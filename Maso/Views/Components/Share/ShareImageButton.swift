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
            .buttonStyle(.plain)
            .sheet(isPresented: $showCustomize) {
                ShareCustomizeSheet(
                    previewTitle: previewTitle,
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
    let defaultSections: ShareSections
    let initialPhoto: UIImage?
    let shareSurface: String
    /// caller 侧的额外"不能分享"条件 — e.g. Insights 卡的参数一个都没勾
    /// (那套 toggle state 在 caller 手里, sections.anyEnabled 管不到它).
    let shareDisabled: Bool
    @ViewBuilder let shareContent: (UIImage?, (() -> Void)?, ShareCardMode) -> ShareContent
    var onPersistPhoto: ((UIImage?) -> Void)? = nil

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
        defaultSections: ShareSections,
        initialPhoto: UIImage?,
        shareSurface: String = "unknown",
        shareDisabled: Bool = false,
        @ViewBuilder shareContent: @escaping (UIImage?, (() -> Void)?, ShareCardMode) -> ShareContent,
        onPersistPhoto: ((UIImage?) -> Void)? = nil
    ) {
        self.previewTitle = previewTitle
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Preview — 传 userPhoto + tap callback + .editing(binding).
                    // tap callback 设 showPhotoOptions = true → confirmationDialog 弹
                    // Camera / Photos / Remove 选项. binding 让卡内 inline toggle 双向同步 sections.
                    shareContent(userPhoto, { showPhotoOptions = true }, .editing($sections))
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
            .navigationTitle("Customize")
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
                        .disabled(!sections.anyEnabled || shareDisabled)
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
        let img = ShareImageRenderer.render { shareContent(userPhoto, nil, .rendering(snap)) }
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
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
