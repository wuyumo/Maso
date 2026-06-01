import SwiftUI

// 浏览全部 873 个动作的 sheet — Settings → Data → Exercise library 入口.
// 跟 ExercisePicker 类似 UI (search + chip + list), 但 tap 一项不是"加进 plan",
// 而是展开/弹出动作详情 (instructions / muscles / category) — 纯浏览模式.
struct ExerciseLibraryBrowser: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 作为底部 tab 嵌入时 true — 去掉 "Done"(tab 不需要 dismiss).
    var asTab: Bool = false
    /// 嵌在 Train tab 里时 true — 不自带 NavigationStack / 大标题 / +按钮 (Train 统一导航栏接管).
    var embedded: Bool = false
    /// embedded 时由 Train 的右上角 "+" 触发: 翻 true → 打开"加动作"选择 sheet.
    var addRequested: Binding<Bool>? = nil

    @State private var query: String = ""
    @State private var muscleFilter: MuscleGroup? = nil
    @State private var equipmentFilter: String? = nil
    @State private var selected: Exercise? = nil
    /// 当前展开的"变种组" key (= ExerciseGroup.id). 一次只展开一组 — 跟 picker 同一收折语义.
    @State private var expandedGroupKey: String? = nil
    /// "+ Add exercise" → 两条路径的选择 sheet (Create your own / Browse rare).
    @State private var addChoiceOpen: Bool = false
    /// 路径 1: 自创动作表单 sheet (name + photo + 元数据).
    @State private var customFormOpen: Bool = false
    /// 路径 2: 小众库浏览 sheet (从 niche stash 采纳到自己的库).
    @State private var nicheBrowseOpen: Bool = false
    /// P0-6: 删自创动作的二次确认.
    @State private var pendingDeleteCustom: Exercise? = nil
    /// 自创动作被 plan/历史 引用 → 不能删, 弹说明 alert.
    @State private var deleteBlockedRef: Exercise? = nil
    /// P1-7: 自创动作是 Pro 功能 (付费墙广告语承诺) — 免费用户走这弹 paywall.
    @State private var paywallOpen: Bool = false

    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    private var filtered: [Exercise] {
        // Library 浏览也走 userLibrary — niche 默认不暴露, 但用户自创 + 已采纳的 niche 在.
        // 想看 niche stash 走顶部 toolbar 的 "+ Add" → "Browse rare exercises".
        var arr = data.userLibrary
        if let m = muscleFilter {
            // 严格筛选 — 只看 primaryMuscles (主练肌), 跟 ExercisePickerSheet 同一行为.
            // 不再因为某个动作 secondary 含 m 就出现 (e.g. deadlift secondary 含 core 也不算 core 动作).
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
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            arr = arr.filter { ex in
                // 搜英文 + 本地化名 (双向命中)
                ex.name.lowercased().contains(q) ||
                ex.displayName.lowercased().contains(q) ||
                ex.tags.contains(where: { $0.lowercased().contains(q) })
            }
        }
        // 收藏置顶 — 在 filter 之后排序, 让收藏的动作在当前 filter 结果里排最前
        arr = data.sortByFavorites(arr)
        return Array(arr.prefix(200))
    }

    /// 把 filtered 折叠成变种组 — 跟 ExercisePickerSheet 同一份 ExerciseGrouping.group(...).
    private var filteredGroups: [ExerciseGroup] {
        ExerciseGrouping.group(filtered)
    }

    /// 单行 — 共用 GroupedExerciseRow (跟 picker 同款展示), tap → 详情, 右滑 → 置顶 / 删除 / 移回冷门库.
    @ViewBuilder
    private func libraryRow(_ ex: Exercise, isVariant: Bool, group: ExerciseGroup) -> some View {
        GroupedExerciseRow(
            exercise: ex,
            isVariant: isVariant,
            group: group,
            isExpanded: expandedGroupKey == group.id,
            showDisclosure: !group.isSingleton,
            showVariantCategoryLabel: false,
            trailing: { EmptyView() },
            onTap: { selected = ex },
            onTapImage: { selected = ex },
            onToggleExpand: {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedGroupKey = (expandedGroupKey == group.id) ? nil : group.id
                }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                data.toggleFavorite(ex.id)
                Haptics.tap()
            } label: {
                Image(systemName: data.isFavorite(ex.id) ? "pin.slash.fill" : "pin.fill")
            }
            .tint(MasoColor.accent)
            .accessibilityLabel(NSLocalizedString(data.isFavorite(ex.id) ? "Unpin" : "Pin to top", comment: ""))

            // P0-6: 自创动作 → 删除 (引用检查); 已采纳 niche → 移回冷门库.
            if ex.id.hasPrefix("custom-") {
                Button(role: .destructive) {
                    if data.isExerciseReferenced(ex.id) {
                        deleteBlockedRef = ex
                    } else {
                        pendingDeleteCustom = ex
                    }
                    Haptics.tap()
                } label: {
                    Image(systemName: "trash.fill")
                }
                .tint(MasoColor.negative)
                .accessibilityLabel(NSLocalizedString("Delete", comment: ""))
            } else if data.settings.adoptedNicheExerciseIds.contains(ex.id) {
                Button {
                    data.unadoptNicheExercise(ex.id)
                    Haptics.tap()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .tint(MasoColor.textDim)
                .accessibilityLabel(NSLocalizedString("Remove from library", comment: ""))
            }
        }
    }

    /// 当前 equipment / text filter 下还有动作的 muscle section. menu 里 dim disabled.
    private var availableMuscles: Set<MuscleGroup> {
        var out: Set<MuscleGroup> = []
        for ex in data.userLibrary {
            // equipment filter narrow
            if let eq = equipmentFilter {
                if eq == "other" {
                    guard ex.equipment == "other" || ex.equipment == nil else { continue }
                } else {
                    guard ex.equipment == eq else { continue }
                }
            }
            // text filter narrow
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                guard ex.name.lowercased().contains(q)
                        || ex.displayName.lowercased().contains(q)
                        || ex.tags.contains(where: { $0.lowercased().contains(q) }) else { continue }
            }
            // 跟 filtered 行为一致用 primaryMuscles — 否则 chip "可点", 点了 0 结果.
            for sec in Self.muscleSections {
                if ex.primaryMuscles.contains(where: { $0.section == sec }) {
                    out.insert(sec)
                }
            }
        }
        return out
    }

    /// 当前 muscle / text filter 下还有动作的 equipment set. menu 里 dim disabled.
    private var availableEquipments: Set<String> {
        var out: Set<String> = []
        for ex in data.userLibrary {
            if let m = muscleFilter {
                // 严格用 primary, 跟 filtered 一致
                guard ex.primaryMuscles.contains(where: { $0.section == m }) else { continue }
            }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            if !q.isEmpty {
                guard ex.name.lowercased().contains(q)
                        || ex.displayName.lowercased().contains(q)
                        || ex.tags.contains(where: { $0.lowercased().contains(q) }) else { continue }
            }
            out.insert(ex.equipment ?? "other")
        }
        return out
    }

    /// 常驻筛选条 — Muscle / Equipment 两个下拉. 钉在原生搜索栏与列表之间 (不随列表滚动),
    /// 列表上滑也始终可见; 选中后按钮直接显示当前值 (e.g. "Chest" / "Dumbbell").
    private var filterBar: some View {
        let availM = availableMuscles
        let availE = availableEquipments
        return HStack(spacing: 18) {
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
                },
                style: .systemMenu
            )
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
                },
                style: .systemMenu
            )
            Spacer()
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.vertical, 8)
        .background(MasoColor.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MasoColor.textFaint.opacity(0.15))
                .frame(height: 0.5)
        }
    }

    var body: some View {
        NavStackIf(embedded: embedded) {
            VStack(spacing: 0) {
                // 常驻筛选条 — Muscle / Equipment 下拉钉在原生搜索栏与列表之间, 列表上滑也不消失.
                // (搜索框改用系统原生 .searchable, 见下方 modifier — 同样常驻置顶.)
                filterBar

                List {
                // 收折分组 — 跟"训练中选动作 picker"用同一份 ExerciseGrouping 数据 + GroupedExerciseRow
                // 展示/收折逻辑, 保证两边一致. canonical 行折叠, "+N variants" 胶囊展开同名变种.
                ForEach(filteredGroups) { group in
                    libraryRow(group.canonical, isVariant: false, group: group)
                    // 展开 → 变种拆 "Variation"(动作) / "Equipment"(器械) 两段, 跟 picker / Rare 一致.
                    if !group.variants.isEmpty, expandedGroupKey == group.id {
                        groupedVariantSections(for: group) { variant in
                            libraryRow(variant, isVariant: true, group: group)
                        }
                    }
                }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // filter/搜索变化 → 收起手风琴 (跟 picker 一致, 避免残留孤儿展开态).
                .onChange(of: query) { _, _ in expandedGroupKey = nil }
                .onChange(of: muscleFilter) { _, _ in expandedGroupKey = nil }
                .onChange(of: equipmentFilter) { _, _ in expandedGroupKey = nil }
            }
            .background(MasoColor.background.ignoresSafeArea())
            // 系统原生搜索栏 — 常驻导航栏下方 (displayMode .always → 列表上滑也不收起),
            // 取代原先随列表一起滚走的自定义搜索框. 筛选已移到上方常驻 filterBar.
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(NSLocalizedString("Search exercises…", comment: ""))
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
                // embedded 时跳过自己的大标题 / +按钮 (Train 统一导航栏接管); 非 embedded 保持原样.
                .applyIf(!embedded) { v in
                    v.screenHeader(NSLocalizedString("Exercise library", comment: "")) {
                        HStack(spacing: 18) {
                            Button(action: { addChoiceOpen = true }) {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(NSLocalizedString("Add exercise", comment: ""))
                            // 作为 sheet 用时 (非 tab) 才给关闭入口.
                            if !asTab {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Done")
                            }
                        }
                    }
                }
                // embedded: Train 的右上角 "+" 经 addRequested 触发"加动作"选择 sheet.
                .onChange(of: addRequested?.wrappedValue ?? false) { _, v in
                    if v { addChoiceOpen = true; addRequested?.wrappedValue = false }
                }
            .tint(MasoColor.text)
            .sheet(item: $selected) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            // "+" → 选两条路径
            .sheet(isPresented: $addChoiceOpen) {
                AddExerciseChoiceSheet(
                    onCreateCustom: {
                        addChoiceOpen = false
                        // P1-7: 自创动作是 Pro 功能. 免费用户 → paywall, 不进表单.
                        let pro = data.settings.isPro
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            if pro { customFormOpen = true } else { paywallOpen = true }
                        }
                    },
                    onBrowseNiche: {
                        addChoiceOpen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            nicheBrowseOpen = true
                        }
                    }
                )
                .presentationDetents([.medium])
            }
            // 路径 1: 自创动作 (name + photo + muscle/equipment).
            .sheet(isPresented: $customFormOpen) {
                CustomExerciseFormSheet()
            }
            // P1-7: 免费用户点"自己创建"→ paywall
            .sheet(isPresented: $paywallOpen) {
                PaywallScreen()
            }
            // 路径 2: 浏览 niche stash + 一键采纳.
            .sheet(isPresented: $nicheBrowseOpen) {
                NicheLibraryBrowseSheet()
            }
            // P0-6: 删自创动作二次确认
            .alert(NSLocalizedString("Delete exercise?", comment: ""),
                   isPresented: Binding(get: { pendingDeleteCustom != nil },
                                        set: { if !$0 { pendingDeleteCustom = nil } })) {
                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                    if let ex = pendingDeleteCustom { data.deleteCustomExercise(ex.id) }
                    pendingDeleteCustom = nil
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { pendingDeleteCustom = nil }
            } message: {
                Text(pendingDeleteCustom.map {
                    String(format: NSLocalizedString("“%@” will be permanently removed.", comment: ""), $0.displayName)
                } ?? "")
            }
            // 自创动作被 plan / 历史引用 → 不能删
            .alert(NSLocalizedString("Can't delete — in use", comment: ""),
                   isPresented: Binding(get: { deleteBlockedRef != nil },
                                        set: { if !$0 { deleteBlockedRef = nil } })) {
                Button("OK", role: .cancel) { deleteBlockedRef = nil }
            } message: {
                Text("This exercise is used by a plan or your workout history. Remove it from those first.")
            }
        }
    }
}

// MARK: - Detail (共用 — ExercisePicker / Library Browser 都用这套展示)

struct ExerciseDetailSheet: View {
    @Environment(DataStore.self) private var data
    let exercise: Exercise
    /// 可选 — 传了就显示底部 "Add to workout" 按钮, tap 时调用并 dismiss.
    /// 没传 → 纯浏览模式 (Library Browser 路径).
    var onAdd: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// 是否展开"完整原文" 说明. 默认折叠 — 只显示简化版.
    @State private var showFullInstructions: Bool = false
    /// SpeechManager 单例 — observable, 当前 source / isSpeaking 切按钮态.
    @State private var speech = SpeechManager.shared

    /// "看示范" 链接 — 优先 curated videoURL (有的动作 schema 自带); 否则回退到 YouTube 搜索
    /// "<英文动作名> exercise how to". 用搜索而不是写死具体视频 → 不会失效 / 张冠李戴, 且覆盖全部动作.
    /// 用英文 name (而非本地化 displayName) 搜 — 健身教程英文资源最全, 命中率高.
    private var watchDemoURL: URL? {
        if let u = exercise.videoURL { return u }
        let query = "\(exercise.name) exercise how to"
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.youtube.com/results?search_query=\(enc)")
    }

    /// 是否值得显示"展开"按钮 — 仅当原 instructions 比简化版有"多余信息" 时.
    /// 多余 = 条目更多 / 任意一条被截断 (字符差).
    private var hasMoreDetail: Bool {
        let simp = exercise.simplifiedInstructions
        if exercise.instructions.count > simp.count { return true }
        // 同步条数下, 简化版任意一行被截断 (含 …) 或长度比原文短 → 有"多余"
        let origJoined = exercise.instructions.joined(separator: "\n")
        let simpJoined = simp.joined(separator: "\n")
        return origJoined.count > simpJoined.count
    }

    /// 当前 sheet 是不是正在朗读 — speech.currentSource == 我的 exercise.id && isSpeaking.
    /// 多 sheet 共存 (e.g. 用户从 Library 打开一个详情, 又长按弹了另一个) 各自按钮态正确.
    private var isSpeakingThis: Bool {
        speech.isSpeaking && speech.currentSource == exercise.id
    }

    /// 顶部 metadata chip row — level / mechanic / movement / tempo / unilateral / equipment.
    /// 每条都 nil-skip, 没有的字段不渲染 (老 schema 数据可能缺很多).
    @ViewBuilder
    private var metadataChipsRow: some View {
        let chips = exerciseMetadataChips()
        if !chips.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(MasoColor.surfaceHi)
                        .clipShape(Capsule())
                }
            }
        }
    }

    /// 把 Exercise 的 metadata 字段转成 localized chip 文案数组.
    /// 顺序固定: level → mechanic → movement → tempo → unilateral → equipment.
    private func exerciseMetadataChips() -> [String] {
        var out: [String] = []
        // Level
        if let lvl = exercise.level {
            let key: String = {
                switch lvl {
                case .beginner: return "Beginner"
                case .intermediate: return "Intermediate"
                case .expert, .advanced: return "Advanced"
                }
            }()
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Mechanic
        if let mech = exercise.mechanic {
            let key = mech == .compound ? "Compound" : "Isolation"
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Movement pattern
        if let mp = exercise.movementPattern {
            let key: String = {
                switch mp {
                case .pushHorizontal: return "Horizontal push"
                case .pushVertical:   return "Vertical push"
                case .pullHorizontal: return "Horizontal pull"
                case .pullVertical:   return "Vertical pull"
                case .hinge:          return "Hinge"
                case .squat:          return "Squat"
                case .lunge:          return "Lunge"
                case .rotation:       return "Rotation"
                }
            }()
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Tempo
        if let t = exercise.tempo {
            let key: String = {
                switch t {
                case .strength:    return "Strength tempo"
                case .hypertrophy: return "Hypertrophy tempo"
                case .endurance:   return "Endurance tempo"
                case .explosive:   return "Explosive tempo"
                case .isometric:   return "Isometric hold"
                }
            }()
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Unilateral
        if exercise.unilateral == true {
            out.append(NSLocalizedString("Unilateral", comment: ""))
        }
        // Equipment — 仅显示首选 (Library 已经有 equipment filter, 详情页这里只补一个 chip)
        if let eq = exercise.equipment {
            out.append(Exercise.equipmentDisplayName(for: eq))
        }
        return out
    }

    /// 语音播报按钮 — speaking 时显 stop, idle 时显 play. tap toggle.
    /// 朗读内容跟着 showFullInstructions 走 — 展开了就读全文, 没展开就读简化版.
    @ViewBuilder
    private var speakButton: some View {
        Button(action: toggleSpeak) {
            HStack(spacing: 4) {
                Image(systemName: isSpeakingThis ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text(isSpeakingThis
                     ? NSLocalizedString("Stop", comment: "")
                     : NSLocalizedString("Listen", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isSpeakingThis ? MasoColor.text : MasoColor.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSpeakingThis ? MasoColor.accent : MasoColor.accent.opacity(0.16))
            .overlay(
                Capsule().stroke(MasoColor.accent.opacity(isSpeakingThis ? 0 : 0.4), lineWidth: 0.6)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeakingThis
                            ? NSLocalizedString("Stop reading", comment: "")
                            : NSLocalizedString("Read instructions aloud", comment: ""))
    }

    /// 切换朗读 / 停止. 朗读时用当前 effectiveLanguage 的 locale, 让 Chinese 用户听到中文 TTS,
    /// English 用户听到英文 TTS — 跟 displayName / instructions 的 i18n 一致.
    private func toggleSpeak() {
        if isSpeakingThis {
            speech.stop()
        } else {
            let lines = showFullInstructions
                ? exercise.instructions
                : exercise.simplifiedInstructions
            // 在动作名前缀朗读 — 让用户先听到"是哪个动作", 上下文更清楚
            let intro = exercise.displayName
            let allLines = [intro] + lines
            speech.speak(
                steps: allLines,
                locale: LanguageManager.shared.effectiveLanguage.rawValue,
                source: exercise.id
            )
            Haptics.tap()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExerciseImage(
                        category: exercise.category,
                        imageFolder: exercise.imageFolder,
                        photoURL: exercise.photoURL,
                        customImageData: exercise.customImageData,
                        cornerRadius: 14,
                        size: 220,
                        animated: true,
                        fitCustomImage: true   // P3: 详情大图不裁竖图
                    )
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.displayName)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(MasoColor.text)
                        if let first = exercise.tags.first {
                            Text(first)
                                .font(.system(size: 13))
                                .foregroundStyle(MasoColor.textDim)
                        }
                    }

                    // Metadata chips — level / mechanic / movement / tempo / unilateral / equipment
                    // 全部走 nil-skip, 只展示存在的字段, 避免空 chip 占位.
                    metadataChipsRow

                    // Muscles — section title + 人体分区图 (target 肌肉高亮) + chip 列表.
                    // MuscleVisualBlock 前后身分别画, ex.muscleGroups 命中位置上色, 一眼能看出
                    // "这个动作主要顶哪里".
                    if !exercise.muscleGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Target Muscles")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.5)
                                .foregroundStyle(MasoColor.textFaint)
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                MuscleVisualBlock(muscles: exercise.muscleGroups, sideLength: 160)
                                    .fixedSize()
                                Spacer(minLength: 0)
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(exercise.muscleGroups, id: \.self) { m in
                                    Text(m.displayName)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(MasoColor.accent)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(MasoColor.accent.opacity(0.12))
                                        .overlay(
                                            Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5)
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Safety / form cues — 来自 danger_warnings 字段 (新 schema).
                    // 高难度动作 (deadlift / squat / OHP / etc.) 才会有, isolation 通常空.
                    let warnings = exercise.localizedDangers
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Form cues")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.5)
                                .foregroundStyle(MasoColor.textFaint)
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(MasoColor.accent)
                                        .padding(.top, 3)
                                    Text(line)
                                        .font(.system(size: 13))
                                        .foregroundStyle(MasoColor.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MasoColor.accent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(MasoColor.accent.opacity(0.25), lineWidth: 0.6)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Instructions — 默认显示简化版 (LLM 提取的 2-3 个关键要点 / fallback 截断).
                    // 用户想看完整原文 → 点 "Show full instructions" 展开.
                    if !exercise.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("How to do it")
                                    .font(.system(size: 10, weight: .heavy))
                                    .tracking(1.5)
                                    .foregroundStyle(MasoColor.textFaint)
                                Spacer()
                                // Watch demo — 优先 curated video_url; 没有就回退到 YouTube 搜索该动作的教程,
                                // 所以现在每个动作都有"看示范"入口. 系统会用默认浏览器 / YouTube app 打开.
                                if let url = watchDemoURL {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "play.rectangle.fill")
                                                .font(.system(size: 11, weight: .heavy))
                                            Text("Watch demo")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .foregroundStyle(MasoColor.accent)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(MasoColor.accent.opacity(0.16))
                                        .overlay(
                                            Capsule().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.6)
                                        )
                                        .clipShape(Capsule())
                                    }
                                }
                                // 语音播报按钮 — iOS AVSpeechSynthesizer 朗读 instructions
                                // (跟 i18n / 系统语言对齐, Siri Voice 高质量自动用上).
                                speakButton
                            }

                            // 展示数据源: 折叠状态 = simplified; 展开 = 原 instructions
                            let lines = showFullInstructions
                                ? exercise.instructions
                                : exercise.simplifiedInstructions
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                                        .foregroundStyle(MasoColor.accent)
                                        .frame(width: 20, alignment: .leading)
                                    Text(line)
                                        .font(.system(size: 13))
                                        .foregroundStyle(MasoColor.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            // 仅当原文比简化版有"多余" (条目数更多 / 单条更长被截断) 时显示折叠按钮
                            if hasMoreDetail {
                                Button(action: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showFullInstructions.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: showFullInstructions ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9, weight: .heavy))
                                        Text(showFullInstructions
                                             ? NSLocalizedString("Show less", comment: "")
                                             : NSLocalizedString("Show full instructions", comment: ""))
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(MasoColor.textDim)
                                    .padding(.top, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 选择训练 CTA (ExercisePicker 路径传 onAdd 时显示)
                    if let onAdd {
                        Button(action: {
                            onAdd()
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .heavy))
                                Text("Add to workout")
                                    .font(.system(size: 14, weight: .heavy))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MasoColor.accent)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 置顶按钮 — pin toggle (语义从"收藏"改成"置顶到列表顶部")
                ToolbarItem(placement: .topBarLeading) {
                    let favorited = data.isFavorite(exercise.id)
                    Button {
                        data.toggleFavorite(exercise.id)
                        Haptics.tap()
                    } label: {
                        Image(systemName: favorited ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(favorited
                                        ? NSLocalizedString("Unpin", comment: "")
                                        : NSLocalizedString("Pin to top", comment: ""))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
        .presentationDetents([.medium, .large])
        // sheet 关闭时停掉朗读 — 不让用户切走 sheet 后还在念
        .onDisappear {
            if isSpeakingThis { speech.stop() }
        }
    }
}
