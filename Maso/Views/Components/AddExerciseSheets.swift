import SwiftUI
import PhotosUI

// MARK: - AddExerciseChoiceSheet
//
// Library Browser 顶部 "+" 触发的两路选择 sheet:
//   1. Create your own — 自己定义 name + photo, 用户视角"我自己的动作".
//   2. Browse rare exercises — 从我们收纳的 58 个 niche 动作里采纳 (Foam Roll / Battle Rope /
//      Hip Abduction Machine / Grip Crusher etc.). 不是新建, 而是把已在数据库里但默认隐藏的
//      动作"挪进自己的库".
//
// 两条路径都最终让动作出现在主 picker 里 (创建 plan 时能选到).

struct AddExerciseChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreateCustom: () -> Void
    let onBrowseNiche: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Pick how to add an exercise. Either build your own from scratch, or adopt one from our specialized library.")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { Haptics.tap(); onCreateCustom() }) {
                        choiceCard(
                            icon: "square.and.pencil",
                            title: "Create your own",
                            subtitle: "Add a name, an image, and tag it to a muscle. Best for moves we don't have."
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    Button(action: { Haptics.tap(); onBrowseNiche() }) {
                        choiceCard(
                            icon: "archivebox",
                            title: "Browse rare exercises",
                            subtitle: "Foam rolls, battle ropes, machine isolations and other specialized moves we corralled."
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    Spacer()
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
        .presentationBackground(MasoColor.background)
    }

    private func choiceCard(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MasoColor.accent)
                .frame(width: 32, height: 32)
                .background(MasoColor.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(MasoColor.textFaint)
        }
        .padding(MasoMetrics.cardPadding)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}

// MARK: - CustomExerciseFormSheet
//
// 自创动作表单. 必填 name + primaryMuscle; 可选 image + equipment. Save → DataStore.addCustomExercise.
// 不要求所有字段 — 用户视角"快速给一个动作命个名 + 选条边", 90 秒能加完一个.

struct CustomExerciseFormSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedMuscle: MuscleGroup = .chest
    @State private var selectedEquipment: String = "body_only"
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil
    @State private var showingError: String? = nil
    /// "网上搜图" sheet 开关.
    @State private var webPickerOpen: Bool = false

    /// 创建成功回调 — caller (选动作 picker) 拿到新动作可以直接勾选 / 加入.
    private let onCreated: ((Exercise) -> Void)?

    /// 预填名字 — 从"选动作"页搜索空结果点"Add 'xxx'"进来时, 把搜索词带过来直接填好.
    init(initialName: String = "", onCreated: ((Exercise) -> Void)? = nil) {
        _name = State(initialValue: String(initialName.prefix(Self.maxNameLength)))
        self.onCreated = onCreated
    }
    /// P1-6: 计量方式 — false = Reps & weight (.strength), true = Timed (秒, 非 strength → player 用 duration).
    @State private var isTimed: Bool = false
    /// P2-13: 照片加载/压缩中 — 显 spinner, 防用户以为没反应.
    @State private var photoLoading: Bool = false

    /// 自创动作名字上限 — 防 500 字垃圾名撑爆 share card / history.
    private static let maxNameLength = 60

    /// "primary muscle" 给用户选的几个大肌群 — 跟 ExercisePickerSheet 顶部分类一致.
    private static let muscleOptions: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                Form {
                    // 图片 — 顶部 hero 区. 跟 share card 的 photo placeholder 同款样式:
                    //   - 没图: 虚线描边 + photo.badge.plus icon (light 字重, textDim) + "Add a photo"
                    //          整块都是 PhotosPicker tap 目标 — 一步到位, 不需要额外按钮
                    //   - 有图: 实色描边 (borderSoft) + 右上角小"Change" 胶囊 (灰底,
                    //          不再用 accent 绿) 给用户重新选的入口
                    Section {
                        // 图片预览 / 占位 (展示用). 两个来源按钮在下面.
                        photoArea
                            .padding(.vertical, 4)
                        // 两个图片来源: 网上搜图 (主, 用动作名自动搜) + 从相册选.
                        HStack(spacing: 10) {
                            Button(action: { webPickerOpen = true }) {
                                Label(NSLocalizedString("Search the web", comment: ""), systemImage: "magnifyingglass")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(MasoColor.accent.opacity(0.16))
                                    .foregroundStyle(MasoColor.accent)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(NSLocalizedString("From library", comment: ""), systemImage: "photo.on.rectangle")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(MasoColor.surfaceHi)
                                    .foregroundStyle(MasoColor.text)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(MasoColor.surface)

                    // 名称 — 必填
                    Section {
                        TextField(NSLocalizedString("Exercise name", comment: ""), text: $name)
                            .foregroundStyle(MasoColor.text)
                            .submitLabel(.done)
                            // P2-12: 硬截上限, 防超长名.
                            .onChange(of: name) { _, newVal in
                                if newVal.count > Self.maxNameLength {
                                    name = String(newVal.prefix(Self.maxNameLength))
                                }
                            }
                    } footer: {
                        Text("Required. Shown in plans and history.")
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .listRowBackground(MasoColor.surface)

                    // 主肌群
                    Section {
                        Picker(NSLocalizedString("Primary muscle", comment: ""), selection: $selectedMuscle) {
                            ForEach(Self.muscleOptions, id: \.self) { m in
                                Text(LocalizedStringKey(m.displayName))
                                    .tag(m)
                            }
                        }
                        .foregroundStyle(MasoColor.text)
                    }
                    .listRowBackground(MasoColor.surface)

                    // 器械
                    Section {
                        Picker(NSLocalizedString("Equipment", comment: ""), selection: $selectedEquipment) {
                            ForEach(Exercise.knownEquipments, id: \.self) { eq in
                                Text(Exercise.equipmentDisplayName(for: eq))
                                    .tag(eq)
                            }
                        }
                        .foregroundStyle(MasoColor.text)
                    }
                    .listRowBackground(MasoColor.surface)

                    // P1-6: 计量方式 — Reps & weight vs Timed. 决定 player 显 reps×重量 还是秒倒计时.
                    Section {
                        Picker(NSLocalizedString("Measure by", comment: ""), selection: $isTimed) {
                            Text("Reps & weight").tag(false)
                            Text("Time (seconds)").tag(true)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(isTimed
                             ? NSLocalizedString("For planks, stretches, carries, cardio intervals.", comment: "")
                             : NSLocalizedString("For most strength moves.", comment: ""))
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .listRowBackground(MasoColor.surface)

                    Section {
                        Text("Custom exercises live only on this device. You can use them in plans and they'll appear in all your pickers.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .listRowBackground(MasoColor.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .tint(MasoColor.text)
        }
        .presentationBackground(MasoColor.background)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            photoLoading = true
            Task {
                // P2-13: 降采样到 ≤800px 再 JPEG 0.7 — 48MP HEIC 直存会几 MB 撑爆 maso-data.json.
                // 失败 → 弹错, 不静默无反应.
                guard let raw = try? await newItem.loadTransferable(type: Data.self),
                      let ui = UIImage(data: raw) else {
                    await MainActor.run {
                        photoLoading = false
                        showingError = NSLocalizedString("Couldn't load that image. Try another.", comment: "")
                    }
                    return
                }
                let scaled = Self.downscale(ui, maxDimension: 800)
                let jpeg = scaled.jpegData(compressionQuality: 0.7)
                await MainActor.run {
                    photoLoading = false
                    if let jpeg { imageData = jpeg }
                    else { showingError = NSLocalizedString("Couldn't process that image. Try another.", comment: "") }
                }
            }
        }
        // 网上搜图 — 用当前动作名预填搜索, 选中一张 → 下载降采样后写回 imageData.
        .sheet(isPresented: $webPickerOpen) {
            WebImagePickerSheet(initialQuery: name) { data in imageData = data }
            .presentationDragIndicator(.visible)
        }
        .alert("Couldn't save exercise", isPresented: Binding(
            get: { showingError != nil }, set: { if !$0 { showingError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingError ?? "")
        }
    }

    /// 图片区 — PhotosPicker 的 label. 两态:
    ///   - 没图: 跟 UnifiedShareCard.photoContent 同款 — 虚线 dashed border + photo.badge.plus
    ///     icon (light 字重) + "Add a photo" 文案, surface 0.4 半透底.
    ///   - 有图: 实色细描边 + 右上角灰底胶囊 "Change" (中性, 不再用 accent 绿).
    /// 比例锁在 160pt 高度 (用户保留这个 ratio 不变).
    @ViewBuilder
    private var photoArea: some View {
        Group {
            if let imageData, let ui = UIImage(data: imageData) {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .overlay {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(MasoColor.borderSoft, lineWidth: 1)
                        )

                    // 右上角 "Change" 胶囊 — 黑底半透 + 白字 (跟 accent 绿无关), 不抢戏.
                    // tap 不需要单独绑 action: 整块 photoArea 已经是 PhotosPicker label,
                    // tap 任意位置 (含这个胶囊) 都会拉相册.
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .heavy))
                        Text("Change")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(10)
                    .allowsHitTesting(false)  // 让 tap 直接命中外层 PhotosPicker, 不被胶囊吃
                }
            } else {
                // 没图: 虚线 + photo.badge.plus + "Add a photo" — UnifiedShareCard 同款.
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            MasoColor.borderSoft,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(MasoColor.textDim)
                        Text("Add a photo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                .background(MasoColor.surface.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)  // 用户要求保留这个比例
        .contentShape(Rectangle())
        .overlay {
            if photoLoading {
                ZStack {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// P2-13: 等比降采样到 maxDimension. 大图直接 JPEG 会几 MB; 800px 对缩略图 / 详情够清晰.
    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longSide = max(w, h)
        guard longSide > maxDimension, longSide > 0 else { return image }
        let scale = maxDimension / longSide
        let newSize = CGSize(width: w * scale, height: h * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1  // 不再乘屏幕 scale — 我们已是目标像素尺寸
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // P2-12: 重名检查 (大小写不敏感) — 防 3 个都叫 "Curl" + 触发幽灵变种.
        let dup = data.settings.customExercises.contains {
            $0.displayName.compare(trimmed, options: .caseInsensitive) == .orderedSame
            || $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        if dup {
            showingError = NSLocalizedString("You already have a custom exercise with this name.", comment: "")
            return
        }

        // id 用 "custom-{uuid}" 防跟 bundle ID 冲突. exById lookup 透明命中.
        let newId = "custom-\(UUID().uuidString.lowercased().prefix(8))"
        // P1-6: Timed → 非 strength category (player 走 duration); 否则 .strength (reps×重量).
        let category: ExerciseCategory = isTimed ? .mobility : .strength
        let ex = Exercise(
            id: newId,
            name: trimmed,
            category: category,
            tags: [selectedMuscle.displayName],
            primaryMuscles: [selectedMuscle],
            muscleGroups: [selectedMuscle],
            imageFolder: nil,
            level: nil,
            force: nil,
            equipment: selectedEquipment,
            equipmentAll: [selectedEquipment],
            instructions: [],
            movementPattern: nil,
            mechanic: nil,
            unilateral: nil,
            tempo: nil,
            videoURL: nil,
            caloriesEstimate: nil,
            dangerWarnings: nil,
            localizedInstructions: nil,
            localizedName: ["en": trimmed],
            localizedDangerWarnings: nil,
            isNiche: false,
            customImageData: imageData
        )
        data.addCustomExercise(ex)
        onCreated?(ex)
        Haptics.tap()
        dismiss()
    }
}

// MARK: - NicheLibraryBrowseSheet
//
// 浏览 58 个 niche 动作 (减去用户已采纳的) + 一键采纳. 区别于 ExercisePickerSheet 的 niche 模式:
//   - 这里语义是"加入我的库" (curation), 不是"选进 plan" (pick for use)
//   - 每行右侧有 "Add" 按钮, tap = adoptNicheExercise → 立刻视觉变成 "✓ Added"
//   - 同一 sheet 里能连续采纳多个 — Add 后该项淡出 (从 unadopted 集合移除), 用户继续往下挑

struct NicheLibraryBrowseSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    /// 顶部"部位"筛选 (nil = 全部). 6 个 section, 跟 Exercise Library 完全一致.
    @State private var muscleFilter: MuscleGroup? = nil
    /// 顶部"器械"筛选 (nil = 不限).
    @State private var equipmentFilter: String? = nil
    /// 当前展开的"变种组" key (= ExerciseGroup.id). 一次只展开一组 — 跟主库 / picker 同一收折语义.
    @State private var expandedGroupKey: String? = nil
    /// tap 行 → 弹动作详情 (纯浏览). adopt 走右侧 "Add" 胶囊.
    @State private var selected: Exercise? = nil

    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    private var filtered: [Exercise] {
        // unadoptedNicheExercises 自己排除已采纳的; adopt 后行随集合变化动画移出.
        // 筛选逻辑跟 Exercise Library 一致: primaryMuscles 严格匹配 + equipment + 文本.
        var arr = data.unadoptedNicheExercises
        if let m = muscleFilter {
            arr = arr.filter { ex in
                ex.primaryMuscles.contains(where: { $0.section == m })
            }
        }
        if let eq = equipmentFilter {
            arr = arr.filter { ex in
                if eq == "other" { return ex.equipment == "other" || ex.equipment == nil }
                return ex.equipment == eq
            }
        }
        let words = exerciseSearchWords(query)
        if !words.isEmpty {
            arr = arr.filter { $0.matchesSearch(words) }
        }
        return arr
    }

    /// filtered 折叠成变种组 — 跟主库 / picker 用同一份 ExerciseGrouping.group(...).
    private var filteredGroups: [ExerciseGroup] {
        ExerciseGrouping.group(filtered)
    }

    /// 当前 equipment / text filter 下还有动作的 muscle section (menu 里 dim disabled).
    private var availableMuscles: Set<MuscleGroup> {
        var out: Set<MuscleGroup> = []
        let words = exerciseSearchWords(query)
        for ex in data.unadoptedNicheExercises {
            if let eq = equipmentFilter {
                if eq == "other" {
                    guard ex.equipment == "other" || ex.equipment == nil else { continue }
                } else {
                    guard ex.equipment == eq else { continue }
                }
            }
            if !words.isEmpty {
                guard ex.matchesSearch(words) else { continue }
            }
            for sec in Self.muscleSections {
                if ex.primaryMuscles.contains(where: { $0.section == sec }) { out.insert(sec) }
            }
        }
        return out
    }

    /// 当前 muscle / text filter 下还有动作的 equipment set (menu 里 dim disabled).
    private var availableEquipments: Set<String> {
        var out: Set<String> = []
        let words = exerciseSearchWords(query)
        for ex in data.unadoptedNicheExercises {
            if let m = muscleFilter {
                guard ex.primaryMuscles.contains(where: { $0.section == m }) else { continue }
            }
            if !words.isEmpty {
                guard ex.matchesSearch(words) else { continue }
            }
            out.insert(ex.equipment ?? "other")
        }
        return out
    }

    private var noFiltersActive: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && muscleFilter == nil && equipmentFilter == nil
    }

    var body: some View {
        NavigationStack {
            List {
                // 搜索 + 两个筛选菜单作为列表首行 — 跟 Exercise Library 完全一致.
                filterHeaderRow

                if filteredGroups.isEmpty {
                    emptyState
                } else {
                    // 收折分组 — canonical 行折叠, 展开后变种拆 "Variation"(动作) / "Equipment"(器械)
                    // 两段, 跟主库 / picker 收折逻辑一致.
                    ForEach(filteredGroups) { group in
                        nicheRow(group.canonical, isVariant: false, group: group)
                        if !group.variants.isEmpty, expandedGroupKey == group.id {
                            groupedVariantSections(for: group) { variant in
                                nicheRow(variant, isVariant: true, group: group)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // filter / 搜索变化 → 收起手风琴 (避免残留孤儿展开态).
            .onChange(of: query) { _, _ in expandedGroupKey = nil }
            .onChange(of: muscleFilter) { _, _ in expandedGroupKey = nil }
            .onChange(of: equipmentFilter) { _, _ in expandedGroupKey = nil }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Rare exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
            .sheet(item: $selected) { ex in
                ExerciseDetailSheet(exercise: ex)
                .presentationDragIndicator(.visible)
            }
        }
        .presentationBackground(MasoColor.background)
    }

    // MARK: - 顶部 search + 两个 filter 菜单 (跟 ExerciseLibraryBrowser 同款)

    @ViewBuilder
    private var filterHeaderRow: some View {
        VStack(spacing: 10) {
            SearchBar(query: $query)

            HStack(spacing: 8) {
                let availM = availableMuscles
                FilterMenuButton(
                    title: NSLocalizedString("Muscle", comment: "filter button placeholder"),
                    allLabel: NSLocalizedString("All muscles", comment: ""),
                    selected: $muscleFilter,
                    options: Self.muscleSections.map { m in
                        FilterMenuOption(
                            value: m,
                            label: m.displayName,
                            enabled: availM.contains(m) || muscleFilter == m
                        )
                    }
                )

                let availE = availableEquipments
                FilterMenuButton(
                    title: NSLocalizedString("Equipment", comment: "filter button placeholder"),
                    allLabel: NSLocalizedString("Any equipment", comment: ""),
                    selected: $equipmentFilter,
                    options: Exercise.knownEquipments.map { eq in
                        FilterMenuOption(
                            value: eq,
                            label: Exercise.equipmentDisplayName(for: eq),
                            enabled: availE.contains(eq) || equipmentFilter == eq
                        )
                    }
                )

                Spacer()
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: MasoMetrics.pagePaddingHorizontal,
                                  bottom: 6, trailing: MasoMetrics.pagePaddingHorizontal))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: noFiltersActive ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(MasoColor.textFaint)
            Text(noFiltersActive
                 ? NSLocalizedString("You've adopted everything in the rare library", comment: "")
                 : NSLocalizedString("No rare exercises match", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - 行 — 共用 GroupedExerciseRow, 右侧注入 "Add" 胶囊 (adopt)

    @ViewBuilder
    private func nicheRow(_ ex: Exercise, isVariant: Bool, group: ExerciseGroup) -> some View {
        GroupedExerciseRow(
            exercise: ex,
            isVariant: isVariant,
            group: group,
            isExpanded: expandedGroupKey == group.id,
            showDisclosure: !group.isSingleton,
            showVariantCategoryLabel: false,
            trailing: { addButton(ex) },
            onTap: { selected = ex },
            onTapImage: { selected = ex },
            onToggleExpand: {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedGroupKey = (expandedGroupKey == group.id) ? nil : group.id
                }
            }
        )
    }

    private func addButton(_ ex: Exercise) -> some View {
        Button(action: { adopt(ex) }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .heavy))
                Text(NSLocalizedString("Add", comment: ""))
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(MasoColor.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func adopt(_ ex: Exercise) {
        Haptics.tap()
        // P3: 立即采纳 (数据一致), 行随 unadopted 集合变化动画移出 —— 不再靠 0.5s 定时器,
        // 用户秒点 Done 也不会有悬空的 deferred 闭包. 行滑出本身就是"已添加"反馈.
        withAnimation(.easeOut(duration: 0.25)) {
            data.adoptNicheExercise(ex.id)
        }
    }
}

// MARK: - 内部小组件: 简单 Search Bar (Library 自己也有一份, 这里独立避免依赖)

private struct SearchBar: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MasoColor.textDim)
            TextField(NSLocalizedString("Search", comment: ""), text: $query)
                .foregroundStyle(MasoColor.text)
                .submitLabel(.search)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MasoColor.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MasoColor.surface)
        .clipShape(Capsule())
    }
}

// MARK: - Web image search — 自创动作"网上搜图"
//
// 走 Maso 的 Vercel 代理 (Pexels key 留服务端, app 只拿现成图片 URL, 不碰 key).
// 换搜索源 (Pexels / Google / Bing) 只改服务端, app 不动.

struct ExerciseImagePhoto: Identifiable, Decodable, Hashable {
    let id: String
    let thumb: String   // 列表缩略图
    let full: String    // 选中后下载的大图
    let alt: String
}

enum ExerciseImageSearch {
    /// Vercel 代理 endpoint. ⚠️ 部署后把这里改成实际 production URL.
    static let endpoint = "https://maso-api.vercel.app/api/exercise-image"

    static func search(_ query: String) async -> [ExerciseImagePhoto] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, var comps = URLComponents(string: endpoint) else { return [] }
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = comps.url else { return [] }
        struct Resp: Decodable { let photos: [ExerciseImagePhoto] }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return (try? JSONDecoder().decode(Resp.self, from: data))?.photos ?? []
        } catch { return [] }
    }

    /// 下载选中大图 → 降采样 800px → JPEG 0.7 (跟相册路径同款存储, 不撑爆 maso-data.json).
    static func downloadJPEG(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let ui = UIImage(data: data) else { return nil }
        return downscale(ui, maxDimension: 800).jpegData(compressionQuality: 0.7)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longSide = max(w, h)
        guard longSide > maxDimension, longSide > 0 else { return image }
        let scale = maxDimension / longSide
        let newSize = CGSize(width: w * scale, height: h * scale)
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - WebImagePickerSheet — 输入名字 → 网上搜训练图 → 选一张
struct WebImagePickerSheet: View {
    let onPicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var photos: [ExerciseImagePhoto] = []
    @State private var loading = false
    @State private var searched = false
    @State private var downloadingId: String? = nil

    init(initialQuery: String, onPicked: @escaping (Data) -> Void) {
        self.onPicked = onPicked
        _query = State(initialValue: initialQuery.trimmingCharacters(in: .whitespaces))
    }

    private let cols = [GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)]

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // 搜索条
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13)).foregroundStyle(MasoColor.textFaint)
                            TextField(NSLocalizedString("Search exercise photos", comment: ""), text: $query)
                                .textFieldStyle(.plain).font(.system(size: 14))
                                .submitLabel(.search).onSubmit { runSearch() }
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(MasoColor.surface).clipShape(Capsule())
                        Button(NSLocalizedString("Search", comment: "")) { runSearch() }
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(MasoColor.accent)
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)

                    if loading {
                        Spacer(); ProgressView().tint(MasoColor.accent); Spacer()
                    } else if photos.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: searched ? "photo.on.rectangle.angled" : "magnifyingglass")
                                .font(.system(size: 34, weight: .light)).foregroundStyle(MasoColor.textFaint)
                            Text(searched
                                 ? NSLocalizedString("No photos found. Try a different name.", comment: "")
                                 : NSLocalizedString("Type a name and search the web.", comment: ""))
                                .font(.system(size: 13)).foregroundStyle(MasoColor.textDim)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: 8) {
                                ForEach(photos) { p in thumb(p) }
                            }
                            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
                        }
                        Text(NSLocalizedString("Photos via Pexels. Pick the one that matches your move.", comment: ""))
                            .font(.system(size: 10)).foregroundStyle(MasoColor.textFaint)
                            .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Find a photo", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .tint(MasoColor.text)
            .task { if !query.isEmpty && !searched { runSearch() } }
        }
        .presentationBackground(MasoColor.background)
    }

    @ViewBuilder private func thumb(_ p: ExerciseImagePhoto) -> some View {
        Button {
            guard downloadingId == nil else { return }
            downloadingId = p.id
            Task {
                let data = await ExerciseImageSearch.downloadJPEG(p.full)
                await MainActor.run {
                    downloadingId = nil
                    if let data { onPicked(data); dismiss() }
                }
            }
        } label: {
            ZStack {
                AsyncImage(url: URL(string: p.thumb)) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { MasoColor.surface }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if downloadingId == p.id {
                    ZStack { Color.black.opacity(0.45); ProgressView().tint(.white) }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(downloadingId != nil)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true
        Task {
            let res = await ExerciseImageSearch.search(q)
            await MainActor.run { photos = res; loading = false; searched = true }
        }
    }
}
