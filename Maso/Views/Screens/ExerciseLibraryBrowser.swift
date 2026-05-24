import SwiftUI

// 浏览全部 873 个动作的 sheet — Settings → Data → Exercise library 入口.
// 跟 ExercisePicker 类似 UI (search + chip + list), 但 tap 一项不是"加进 plan",
// 而是展开/弹出动作详情 (instructions / muscles / category) — 纯浏览模式.
struct ExerciseLibraryBrowser: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var muscleFilter: MuscleGroup? = nil
    @State private var equipmentFilter: String? = nil
    @State private var selected: Exercise? = nil

    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    private var filtered: [Exercise] {
        var arr = data.exercises
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

    /// 当前 equipment / text filter 下还有动作的 muscle section. menu 里 dim disabled.
    private var availableMuscles: Set<MuscleGroup> {
        var out: Set<MuscleGroup> = []
        for ex in data.exercises {
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
        for ex in data.exercises {
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    TextField("Search exercises…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(MasoColor.surface)
                        .clipShape(Capsule())
                        .overlay(
                            HStack {
                                Spacer()
                                if !query.isEmpty {
                                    Button(action: { query = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(MasoColor.textFaint)
                                    }
                                    .padding(.trailing, 8)
                                }
                            }
                        )

                    // Filter menus — 跟 chip 行比节省纵向空间, 视觉简洁.
                    // 单选 + iOS native Menu 拉起列表式选择, 跟系统 Mail 筛选邮件 / Files 排序的交互一致.
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
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // List + 原生 .swipeActions — 替换之前的自制 SwipeableRow.
                // 自制版本跟 ScrollView 的 vertical pan gesture 有冲突 (左滑 OK 但上下滑死掉).
                // 原生 swipeActions 在 List 内是 OS 帮你管手势, 不会跟 List 自己的 scroll 抢.
                List {
                    ForEach(filtered) { ex in
                        let isFav = data.isFavorite(ex.id)
                        Button {
                            selected = ex
                        } label: {
                            HStack(spacing: 14) {
                                ExerciseImage(
                                    category: ex.category,
                                    imageFolder: ex.imageFolder,
                                    cornerRadius: 8,
                                    size: 56,
                                    animated: false
                                )
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(ex.displayName)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(MasoColor.text)
                                        .lineLimit(1)
                                    ExerciseTagsRow(
                                        muscleGroups: ex.muscleGroups,
                                        equipment: ex.equipment,
                                        muscleLimit: 1
                                    )
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if isFav {
                                    // 置顶标识 — 跟动作列表右滑 swipeAction 同图标
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(MasoColor.accent)
                                }
                            }
                            .padding(.horizontal, MasoMetrics.rowPaddingH)
                            .padding(.vertical, 10)
                            .background(MasoColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: MasoMetrics.pagePaddingHorizontal, bottom: 3, trailing: MasoMetrics.pagePaddingHorizontal))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                data.toggleFavorite(ex.id)
                                Haptics.tap()
                            } label: {
                                // pin.slash.fill (取消置顶) vs pin.fill (置顶) — 状态切换图标
                                Image(systemName: isFav ? "pin.slash.fill" : "pin.fill")
                            }
                            .tint(MasoColor.accent)
                            .accessibilityLabel(NSLocalizedString(isFav ? "Unpin" : "Pin to top", comment: ""))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Exercise library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
            .sheet(item: $selected) { ex in
                ExerciseDetailSheet(exercise: ex)
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
                        cornerRadius: 14,
                        size: 220,
                        animated: true
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

                    // Muscles
                    if !exercise.muscleGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target Muscles")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.5)
                                .foregroundStyle(MasoColor.textFaint)
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
                                // Watch demo — YouTube / 视频 link (新 schema 字段).
                                // 只在 video_url 非空时显示. 系统会用默认浏览器 / YouTube app 打开.
                                if let url = exercise.videoURL {
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
