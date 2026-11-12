import SwiftUI
import UIKit

// Section toggle 状态 — UnifiedShareCard 4 个 section 单独开关.
// 默认值由 caller 传入. todayStatus (照片) 默认 true, 是用户可加照片的入口.
struct ShareSections: Equatable {
    var todayStatus: Bool
    var workout: Bool
    var muscleStatus: Bool
    var calendar: Bool

    init(
        todayStatus: Bool = true,
        workout: Bool = false,
        muscleStatus: Bool = false,
        calendar: Bool = false
    ) {
        self.todayStatus = todayStatus
        self.workout = workout
        self.muscleStatus = muscleStatus
        self.calendar = calendar
    }

    var anyEnabled: Bool { todayStatus || workout || muscleStatus || calendar }
}

/// 卡片渲染模式 — UnifiedShareCard 通过 caller 传入的模式决定:
///   - 编辑模式 (.editing): preview 里实时绑定 toggle, 用户在 section 标题右侧切 on/off
///   - 渲染模式 (.rendering): 渲染最终图时按 ShareSections snapshot 过滤可见 section, 不画 toggle
enum ShareCardMode {
    /// preview — UnifiedShareCard.editToggles 接 binding, 每个 section 标题右侧画 inline toggle.
    case editing(Binding<ShareSections>)
    /// final render — UnifiedShareCard.visibleSections 用 snapshot 决定哪些 section 入图, 不画 toggle.
    case rendering(ShareSections)
}

// 通用 share 按钮 — 点击 → 弹 customize sheet (内嵌 preview + 卡内"添加照片"入口 + 卡内
// section toggle) → 渲染图 → 原生 share.
//
// 用法 (闭包根据 mode 二选一构造卡片):
//   ShareImageButton(
//       previewTitle: "My Workout",
//       defaultSections: ShareSections(workout: true)
//   ) { photo, onTapAddPhoto, mode in
//       switch mode {
//       case .editing(let binding):
//           UnifiedShareCard(
//               userPhoto: photo,
//               onTapAddPhoto: onTapAddPhoto,
//               workoutSection: workoutData,
//               muscleStatusSection: muscleData,
//               calendarSection: calendarData,
//               editToggles: binding
//           )
//       case .rendering(let sections):
//           UnifiedShareCard(
//               userPhoto: photo,
//               onTapAddPhoto: onTapAddPhoto,
//               workoutSection: workoutData,
//               muscleStatusSection: muscleData,
//               calendarSection: calendarData,
//               visibleSections: sections
//           )
//       }
//   } onPersistPhoto: { image in
//       data.setSessionPhoto(image, forSessionId: session.id)
//   } label: {
//       Image(systemName: "square.and.arrow.up")
//   }
//
// shareContent 闭包参数:
//   - photo: 当前选的 UIImage. 没选 = nil. card 内根据它决定要不要显示 photo banner.
//   - onTapAddPhoto: card 内"添加照片"占位 tap 时调. preview 模式非 nil; 渲染最终图时 nil
//     (让 banner 在最终图里不渲染占位 UI).
//   - mode: .editing 给 preview, .rendering 给 final 图.
//
// onPersistPhoto: 用户在 sheet 加/换照片时回调, caller 持久化照片到 DataStore.
//   nil = caller 不需要持久化 (e.g. 肌肉状态 / 日历入口没有 sessionId).
struct ShareImageButton<ShareContent: View, Label: View>: View {
    let previewTitle: String
    var sheetTitle: LocalizedStringKey = "Customize"
    let defaultSections: ShareSections
    /// 已存在的照片 (例如这个 session 之前已经存过照片) — 进入 sheet 时预填,
    /// 用户不用每次都重新加.
    var initialPhoto: UIImage? = nil
    @ViewBuilder let shareContent: (UIImage?, (() -> Void)?, ShareCardMode) -> ShareContent
    /// 用户在 sheet 改照片时回调, 把照片持久化到 DataStore.
    /// 传 nil image = 用户点 Remove → caller 应清掉持久化的照片.
    var onPersistPhoto: ((UIImage?) -> Void)? = nil
    /// 分享卡来源 (workout_complete/history/calendar) — 用于 workout_share 事件. 默认 unknown,
    /// 现有 caller 不传不报错 (Phase 0 不改各调用点签名).
    var shareSurface: String = "unknown"
    @ViewBuilder let label: () -> Label

    @State private var showCustomize = false

    var body: some View {
        Button(action: { showCustomize = true }, label: label)
            .tint(MasoColor.text)
            .sheet(isPresented: $showCustomize) {
                ShareCustomizeSheet(
                    previewTitle: previewTitle,
                    sheetTitle: sheetTitle,
                    defaultSections: defaultSections,
                    initialPhoto: initialPhoto,
                    shareSurface: shareSurface,
                    shareContent: shareContent,
                    onPersistPhoto: onPersistPhoto
                )
                .presentationDragIndicator(.visible)
            }
    }
}

/// 用户在分享前的 customize sheet:
///   - 顶部直接 preview share card — 卡内每个 section 标题右侧有 inline toggle, 用户能即点即看
///   - tap 卡内"加照片"占位区 / tap 已选照片 → confirmationDialog 选 Camera / Photos / Remove
///   - 最终 Share 按钮 → 渲染最终图 (.rendering 模式 + sections snapshot, banner 不渲染占位 UI,
///     toggle 完全不画) → 弹原生 share sheet
struct ShareCustomizeSheet<ShareContent: View>: View {
    let previewTitle: String
    let sheetTitle: LocalizedStringKey
    let defaultSections: ShareSections
    let initialPhoto: UIImage?
    let shareSurface: String
    /// caller 侧的额外"不能分享"条件 — e.g. Insights 卡的参数一个都没勾
    /// (那套 toggle state 在 caller 手里, sections.anyEnabled 管不到它).
    let shareDisabled: Bool
    @ViewBuilder let shareContent: (UIImage?, (() -> Void)?, ShareCardMode) -> ShareContent
    var onPersistPhoto: ((UIImage?) -> Void)? = nil

    @State private var cardSelection = ShareCardSelection()
    @State private var userPhoto: UIImage? = nil
    @State private var sections: ShareSections
    /// 用 sheet(item:) 模式 — source 自身驱动 sheet, 避免 "set source + set bool" 双 state
    /// 同 event cycle 顺序 bug (会导致第一次点 camera 实际打开 library).
    @State private var activePicker: PhotoPickerSource? = nil
    /// 渲染产物自己驱动 share sheet (派生 binding) — 不再用单独的 bool.
    /// "set value + set bool" 双 state 在同一 event cycle 的顺序 bug 会让 sheet 内容
    /// 捕获到 nil → 空白 share sheet (跟下面 activePicker 注释是同一类坑).
    @State private var renderedImage: UIImage? = nil
    @State private var showPhotoOptions = false
    @State private var isCameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    @Environment(\.dismiss) private var dismiss

    init(
        previewTitle: String,
        sheetTitle: LocalizedStringKey = "Customize",
        defaultSections: ShareSections,
        initialPhoto: UIImage?,
        shareSurface: String = "unknown",
        shareDisabled: Bool = false,
        @ViewBuilder shareContent: @escaping (UIImage?, (() -> Void)?, ShareCardMode) -> ShareContent,
        onPersistPhoto: ((UIImage?) -> Void)? = nil
    ) {
        self.previewTitle = previewTitle
        self.sheetTitle = sheetTitle
        self.defaultSections = defaultSections
        self.initialPhoto = initialPhoto
        self.shareSurface = shareSurface
        self.shareDisabled = shareDisabled
        self.shareContent = shareContent
        self.onPersistPhoto = onPersistPhoto
        _sections = State(initialValue: defaultSections)
        _userPhoto = State(initialValue: initialPhoto)
    }

    var body: some View {
        AppNavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Preview — 传 userPhoto + tap callback + .editing(binding).
                    // tap callback 设 showPhotoOptions = true → confirmationDialog 弹
                    // Camera / Photos / Remove 选项. binding 让卡内 inline toggle 双向同步 sections.
                    shareContent(userPhoto, { showPhotoOptions = true }, .editing($sections))
                        .shareSelection(cardSelection, editing: true)
                        // 卡片撑满 sheet 宽度 — 卡片底色与 sheet 底色同为 #121212, 满宽后左右无留白、
                        // 无投影暗边, 预览跟 sheet 融为一体 (也更贴近导出图的 390 宽). 去掉之前的
                        // .frame(width:360)+圆角裁剪+投影+横向 padding (那套"浮空卡片"留出的左右 sheet
                        // 底色 + 投影暗边正是看着像"异色 margin"的来源).
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(MasoColor.text)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { renderAndShare() }
                        .fontWeight(.bold)
                        .tint(MasoColor.text)
                        .disabled(!sections.anyEnabled || shareDisabled || !cardSelection.canShare)
                }
            }
            // 系统 confirmationDialog — iOS 原生 bottom action sheet 风格, 跟 Mail / Photos
            // 加附件 / 加图片选项交互一致. 比 custom 底栏 native + 清爽.
            .confirmationDialog(
                NSLocalizedString("Add photo", comment: ""),
                isPresented: $showPhotoOptions,
                titleVisibility: .visible
            ) {
                if isCameraAvailable {
                    Button(NSLocalizedString("Take Photo", comment: "")) {
                        activePicker = .camera
                    }
                }
                Button(NSLocalizedString("Choose from Library", comment: "")) {
                    activePicker = .photoLibrary
                }
                if userPhoto != nil {
                    Button(NSLocalizedString("Remove Photo", comment: ""), role: .destructive) {
                        userPhoto = nil
                        onPersistPhoto?(nil)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activePicker) { source in
                PhotoPicker(image: $userPhoto, source: source)
                    .ignoresSafeArea()
                .presentationDragIndicator(.visible)
            }
            .onChange(of: userPhoto) { _, newPhoto in
                // 用户加/换照片 → caller 持久化. 用 isCameraAvailable 防止 init 触发
                // (init 传 initialPhoto 时不应该回调持久化).
                if let img = newPhoto {
                    onPersistPhoto?(img)
                }
            }
            .sheet(isPresented: Binding(
                get: { renderedImage != nil },
                set: { if !$0 { renderedImage = nil } }
            )) {
                if let img = renderedImage {
                    // 分享真的完成 (选了某个 activity) → 收掉系统 sheet 后, 整个 customize 卡
                    // 也自动关 — 用户分享完回来不该还停在卡片上. 取消分享则留在卡上可重试.
                    // 0.35s 延迟串接两层 dismiss — sheet-from-sheet 同 tick 双关会 race
                    // (跟 replacingStepId 的 0.32s 延迟是同一类坑).
                    ActivityViewController(activityItems: [img]) { completed in
                        renderedImage = nil
                        if completed {
                            // workout_share — 用户真的完成了分享 (选了某 activity). 无 PII: 只报 surface.
                            Analytics.shared.track("workout_share", ["surface": .string(shareSurface)])
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                        }
                    }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func renderAndShare() {
        // 渲染时传 .rendering(sections snapshot) — 卡内不画 toggle, 只渲染 on 的 section.
        // 同时 callback 传 nil — banner 在没 photo 时返回 EmptyView, 最终图不含占位 UI.
        let snap = sections
        let img = ShareImageRenderer.render { shareContent(userPhoto, nil, .rendering(snap)).shareSelection(cardSelection, editing: false) }
        guard let img else { return }
        // PNG 往返规整化 — ImageRenderer 的输出偶发带奇异 colorspace/scale 元数据,
        // UIActivityViewController 的预览进程会拒渲染 (空白 sheet). 转标准 PNG 再回 UIImage 兜底.
        if let data = img.pngData(), let normalized = UIImage(data: data) {
            renderedImage = normalized
        } else {
            renderedImage = img
        }
    }
}

/// UIActivityViewController wrapper — 弹原生 share sheet, 用户选 AirDrop / Messages / Instagram 等.
/// onComplete: 系统分享收起时回调, completed = 用户真的执行了某个 activity (分享/存图/拷贝),
/// false = 直接取消. caller 用它做"分享完成后自动关掉整个分享卡".
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        anchorPopover(vc, context: context)
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        anchorPopover(uiViewController, context: context)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// iPad requires a source view. The anchor is a 1pt view, not a private filename or field.
    private func anchorPopover(_ controller: UIActivityViewController, context: Context) {
        guard let popover = controller.popoverPresentationController else { return }
        let anchor = context.coordinator.anchor
        if anchor.superview == nil {
            controller.view.addSubview(anchor)
        }
        anchor.center = CGPoint(x: controller.view.bounds.midX, y: controller.view.bounds.midY)
        popover.sourceView = anchor
        popover.sourceRect = anchor.bounds
        popover.permittedArrowDirections = []
    }
}

/// Preview and export the complete selected progress page, including offscreen records.
struct FullPageShareSheet<Content: View>: View {
    let title: String
    let surface: String
    let imageOnly: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var cardSelection = ShareCardSelection()
    @State private var exported: FullPageExport?
    @State private var isExporting = false
    @State private var exportFailed = false

    init(title: String, surface: String, imageOnly: Bool = false, selection: ShareCardSelection = ShareCardSelection(),
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.surface = surface
        self.imageOnly = imageOnly
        self.content = content
        _cardSelection = State(initialValue: selection)
    }

    var body: some View {
        AppNavigationStack {
            ScrollView {
                content().frame(maxWidth: .infinity).shareSelection(cardSelection, editing: true)
            }
            .background(MasoColor.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        isExporting = true
                        Task { @MainActor in
                            await Task.yield()
                            do {
                                let selected = content().shareSelection(cardSelection, editing: false)
                                if imageOnly {
                                    guard let image = ShareImageRenderer.render({ selected }) else { throw CocoaError(.fileWriteUnknown) }
                                    exported = FullPageExport(items: [image])
                                } else {
                                    exported = try FullPageExporter.export(content: selected)
                                }
                            } catch {
                                exportFailed = true
                            }
                            isExporting = false
                        }
                    }
                    .disabled(isExporting || !cardSelection.canShare)
                }
            }
            .overlay { if isExporting { ProgressView().controlSize(.large) } }
            .sheet(item: $exported) { result in
                ActivityViewController(activityItems: result.items) { completed in
                    if completed {
                        Analytics.shared.track("workout_share", ["surface": .string(surface)])
                    }
                }
            }
            .alert("Couldn’t prepare share", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
        .tint(MasoColor.text)
        .presentationDragIndicator(.visible)
        .presentationBackground(MasoColor.background)
    }
}

struct FullPageExport: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
enum FullPageExporter {
    static func export<Content: View>(content: Content) throws -> FullPageExport {
        let width: CGFloat = 390
        let renderer = ImageRenderer(content: content.frame(width: width)
            .background(MasoColor.background).environment(\.colorScheme, .dark))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 2
        renderer.isOpaque = true
        var size = CGSize.zero
        renderer.render { measured, _ in size = measured }
        guard size.height.isFinite, size.height > 0 else { throw CocoaError(.fileWriteUnknown) }
        if size.height <= 6000, let image = renderer.uiImage {
            return FullPageExport(items: [image])
        }
        // Long archives are paginated as vector PDF, avoiding a huge bitmap or truncated records.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Masso-\(UUID().uuidString).pdf")
        let page = CGRect(x: 0, y: 0, width: width, height: 780)
        var failure: Error?
        renderer.render { measured, draw in
            do {
                try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { pdf in
                    for index in 0..<Int(ceil(measured.height / page.height)) {
                        pdf.beginPage()
                        let context = pdf.cgContext
                        UIColor(MasoColor.background).setFill()
                        context.fill(page)
                        context.saveGState()
                        context.clip(to: page)
                        context.translateBy(x: 0, y: measured.height - CGFloat(index) * page.height)
                        context.scaleBy(x: 1, y: -1)
                        draw(context)
                        context.restoreGState()
                    }
                }
            } catch { failure = error }
        }
        if let failure { throw failure }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteUnknown) }
        return FullPageExport(items: [url])
    }
}

/// One SF Symbols label shared by all share entry points; toolbar supplies its native glass chrome.
struct ShareIcon: View {
    var body: some View { Image(systemName: "square.and.arrow.up").font(.body).foregroundStyle(MasoColor.text) }
}

/// One selection state drives both the editable preview and the final export.
@Observable
final class ShareCardSelection {
    var excluded: Set<String> = []
    var available: Set<String> = []
    var canShare: Bool { available.isEmpty || !available.subtracting(excluded).isEmpty }
    func includes(_ id: String) -> Bool { !excluded.contains(id) }
    func setIncluded(_ included: Bool, id: String) {
        if included { excluded.remove(id) } else { excluded.insert(id) }
    }
}

private struct ShareCardSelectionKey: EnvironmentKey {
    static let defaultValue: ShareCardSelection? = nil
}
private struct ShareCardEditingKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var shareCardSelection: ShareCardSelection? {
        get { self[ShareCardSelectionKey.self] }
        set { self[ShareCardSelectionKey.self] = newValue }
    }
    var shareCardEditing: Bool {
        get { self[ShareCardEditingKey.self] }
        set { self[ShareCardEditingKey.self] = newValue }
    }
}
private struct ShareCardIDsPreferenceKey: PreferenceKey {
    static var defaultValue: Set<String> = []
    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) { value.formUnion(nextValue()) }
}
extension View {
    func shareSelection(_ selection: ShareCardSelection, editing: Bool) -> some View {
        environment(\.shareCardSelection, selection)
            .environment(\.shareCardEditing, editing)
            .onPreferenceChange(ShareCardIDsPreferenceKey.self) { ids in
                if editing { selection.available = ids }
            }
    }
}

/// Off cards retain their switch in preview; exported images contain neither switches nor placeholders.
struct ShareSelectableCard<Content: View>: View {
    let id: String
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.shareCardSelection) private var selection
    @Environment(\.shareCardEditing) private var editing
    var body: some View {
        if let selection {
            VStack(alignment: .leading, spacing: 12) {
                if editing {
                    Toggle(isOn: Binding(get: { selection.includes(id) }, set: { selection.setIncluded($0, id: id) })) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MasoColor.text)
                    }
                    .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    .accessibilityIdentifier("share.card.\(id)")
                }
                if selection.includes(id) { content() }
            }
            .preference(key: ShareCardIDsPreferenceKey.self, value: editing ? [id] : [])
        } else { content() }
    }
}
