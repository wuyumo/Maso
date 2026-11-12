import SwiftUI

// ExerciseTagsRow — 全 app exercise 行 / 卡片用的"标签条".
//
// 显示内容:
//   - 前 1-2 个 muscle major (用 MuscleSelector.majorOf 折叠到 UI 暴露的 12 大肌群)
//   - equipment 显示名 (i18n)
//
// 视觉:
//   - muscle chip — 11pt 字, accent 半透底 (淡绿) — 表"训练目标"语义
//   - equipment chip — 11pt 字, surfaceHi 底 (深灰) — 表"工具"语义, 视觉跟 muscle 区分开
//
// 使用场景 (5 处共用):
//   - ExerciseLibraryBrowser 浏览动作行
//   - PlansScreen ExercisePickerSheet 挑动作行
//   - QuickWorkoutScreen Step 2 按肌群挑动作行
//   - PlansScreen PlanDetailSheet 计划 step 行 + grid card
//   - PlanPlayerScreen InlinePlaylist 训练中播放列表
struct ExerciseTagsRow: View {
    let muscleGroups: [MuscleGroup]
    let equipment: String?

    /// 最多显示几个 muscle chip. 默认 2 (节省横向空间, 防 chip 行换行).
    /// 卡片密集排版可传 1; 详情页可传 3; QuickWorkout Step 2 按 muscle 分组的列表可传 0
    /// (muscle 信息已经在 section header, row 内再显示就是冗余).
    var muscleLimit: Int = 2

    /// 是否显示 equipment chip. 默认 true.
    /// 训练中 playlist 已经"在做这个动作", equipment 信息没那么关键, 可传 false 省空间.
    var showEquipment: Bool = true

    /// 整体字号 / 内边距 — compact 用于 grid card 这种宽度受限场景.
    var compact: Bool = false

    /// 折叠到 12 major + dedupe, **保留输入顺序** (= primary muscles 在前, 因为
    /// Exercise.muscleGroups = orderedUnique(primary + secondary)).
    /// 落点用 MuscleSelector.majorOf — 全 app 肌群归一唯一入口.
    ///
    /// ⚠️ 不再按 groupedRows 固定顺序重排: 那会让 RDL (primary 腘绳/臀, secondary 下背/前臂)
    /// 因为 back/forearms 在 groupedRows 里排在 legs 前面 → badge 显示 "Back, Forearms",
    /// 在 Legs 筛选下看起来"标签不是 legs". primary-first 才是动作主目标, 也跟筛选语义一致.
    private var folded: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for m in muscleGroups {
            let major = MuscleSelector.majorOf(m)
            if major == .fullBody { continue }
            if seen.insert(major).inserted { out.append(major) }
        }
        return out
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(folded.prefix(muscleLimit)), id: \.self) { m in
                muscleChip(m.displayName)
            }
            if showEquipment, let eqName = equipmentLabel {
                equipmentChip(eqName)
            }
        }
        .lineLimit(1)
    }

    /// equipment chip 显示文案 — nil / "body only" 都显示 "Body only" 系列 (有信息量),
    /// nil → "Body only" (i18n) 而不是空, 让"徒手"动作也有视觉标记区分.
    private var equipmentLabel: String? {
        if let eq = equipment, !eq.isEmpty {
            return Exercise.equipmentDisplayName(for: eq)
        }
        // equipment 为 nil 的动作罕见 (yuhonas 数据里几乎都有标), 真没标时不显示 chip
        return nil
    }

    private func muscleChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(MasoColor.accent)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 1.5 : 2)
            .background(MasoColor.accent.opacity(0.16))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(MasoColor.accent.opacity(0.28), lineWidth: 0.5)
            )
    }

    private func equipmentChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(MasoColor.textDim)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 1.5 : 2)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
    }
}

// MARK: - GroupedExerciseRow — 收折分组动作行 (单一来源)
//
// Exercise Library (浏览 tab) 和 训练中选动作 picker 共用这一份, 保证两边的:
//   - 展示框架 (canonical 行 + 缩进变种行 + 左侧图/修饰词胶囊/器械图标 + 标题 + tags/器械副文案)
//   - 收折逻辑 (canonical 末尾 "+N variants" 胶囊 toggle; 器械变种 vs 执行方式变种区分)
// 完全一致. 数据来源都是 ExerciseGrouping.group(...) → [ExerciseGroup] (同一份分组真相).
//
// 行为差异 (tap 进详情 / tap 选中 / 末尾勾选 / 右滑动作) 由调用方通过闭包 + trailing + 链 .swipeActions 注入.
struct GroupedExerciseRow<Trailing: View>: View {
    @Environment(DataStore.self) private var data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let exercise: Exercise
    let isVariant: Bool
    let group: ExerciseGroup
    /// 该组是否处于展开态 (控制 +N 胶囊的 chevron 方向).
    let isExpanded: Bool
    /// 是否显示 canonical 末尾的 "+N variants" 胶囊 (= 有变种 且 调用方没强制全展开).
    let showDisclosure: Bool
    /// 变种行是否显示第二行的分类标签 ("VARIATION" / "EQUIPMENT").
    /// 当调用方把变种拆成两个带标题的 section 时传 false — 分类已由 section header 表达, 行内再显就冗余.
    var showVariantCategoryLabel: Bool = true
    /// 行背景高亮 (multiSelect 选中态用).
    var highlighted: Bool = false
    /// 末尾附加视图 (multiSelect 的勾选圈; 库浏览传 EmptyView).
    var selectionAtLeading = false
    @ViewBuilder var trailing: () -> Trailing
    /// 整行点击.
    let onTap: () -> Void
    /// 选择场景的详情入口独立于选中热区；缩略图始终随名称执行整行操作。
    var onShowDetail: (() -> Void)? = nil
    /// "+N variants" 胶囊点击 (toggle 展开).
    let onToggleExpand: () -> Void

    private var disambiguationText: String? {
        ExerciseGrouping.disambiguationText(for: exercise, among: data.userLibrary)
    }

    var body: some View {
        HStack(spacing: 8) {
            if selectionAtLeading { trailing() }
            Button(action: onTap) {
                HStack(spacing: 8) {
                    ExerciseRowContent(exercise: exercise,
                                       titleOverride: !isVariant && !group.isSingleton ? group.entryTitle : nil,
                                       detailLine: isVariant || group.isSingleton ? disambiguationText : nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityIdentifier("exercise.primary.\(exercise.id)")
            .accessibilityAddTraits(highlighted ? [.isSelected] : [])
            if !selectionAtLeading { trailing() }
            if !isVariant, !group.isSingleton, showDisclosure {
                Button(action: onToggleExpand) {
                    HStack(spacing: 4) {
                        Text("+\((group.count - 1).formatted(.number.locale(LanguageManager.currentLocale)))")
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
                            .scaleEffect(0.5)
                            .frame(width: 8, height: 8)
                    }
                }.nativeGlassButtonStyle().controlSize(.mini).tint(MasoColor.text)
                .accessibilityIdentifier("exercise.family.expand.\(group.id)")
                .accessibilityLabel(isExpanded ? NSLocalizedString("Hide variants", comment: "")
                    : String(format: NSLocalizedString("Show %d variants", comment: ""), group.count - 1))
            }
            if let onShowDetail {
                ExerciseDetailInfoButton(exercise: exercise, action: onShowDetail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
        .listRowSeparator(.visible)
        .listRowBackground(Color.clear)
    }

}

/// Shared accessory for rows whose primary action selects an exercise.
/// Keeping this outside that primary Button avoids nested thumbnail/detail taps.
struct ExerciseDetailInfoButton: View {
    let exercise: Exercise
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(MasoColor.textDim.opacity(0.65))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("exercise.info.\(exercise.id)")
        .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), exercise.displayName))
    }
}

// MARK: - VariantSectionHeader — 展开变种时 "Variation" / "Equipment" 两段的小节头
//
// 收折组展开后, 变种拆成"动作差异"(Variation) 和"器械差异"(Equipment) 两个 section.
// 这个小节头标明每段类别, 视觉色跟变种分类色一致 (accent=动作 / 中性灰=器械).
// 缩进对齐变种卡片 (= pagePaddingHorizontal + 16), 让它正好"盖"在它统领的那几行上方.
struct VariantSectionHeader: View {
    let title: String
    var color: Color = MasoColor.textDim

    var body: some View {
        Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 8,
                leading: MasoMetrics.pagePaddingHorizontal,
                bottom: 4,
                trailing: MasoMetrics.pagePaddingHorizontal
            ))
    }
}

/// Shared inline expansion in Exercises, Choose/Replace and rare adoption.
@ViewBuilder
func groupedVariantSections<RowView: View>(
    for group: ExerciseGroup,
    showAll: Bool = false,
    onCollapse: (() -> Void)? = nil,
    @ViewBuilder row: @escaping (Exercise) -> RowView
) -> some View {
    ExerciseFamilyPreview(group: group, showAll: showAll, onCollapse: onCollapse, row: row)
}

struct ExerciseFamilyPreview<RowView: View>: View {
    let group: ExerciseGroup
    var showAll: Bool = false
    var onCollapse: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let row: (Exercise) -> RowView
    @State private var showsLessCommon = false

    private var equipmentSections: [(key: String, title: String, exercises: [Exercise])] {
        let buckets = Dictionary(grouping: group.variants) { $0.equipment ?? "other" }
        return buckets.map { key, exercises in
            (key: key, title: Exercise.equipmentDisplayName(for: key), exercises: exercises)
        }.sorted { ExerciseNameSort.precedes($0.title, $1.title) }
    }

    var body: some View {
        if showAll {
            ForEach(equipmentSections, id: \.key) { section in
                VariantSectionHeader(title: section.title)
                ForEach(section.exercises, id: \.id) { row($0) }
            }
        } else {
            ForEach(group.commonVariants, id: \.id) { row($0) }
        }
        if !showAll && !group.lessCommonVariants.isEmpty {
            Button {
                Haptics.tap()
                // Keep existing rows anchored; insert the remaining versions below
                // the disclosure instead of navigating or re-sorting the whole list.
                showsLessCommon.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(showsLessCommon ? NSLocalizedString("Fewer versions", comment: "exercise family fold")
                         : String(format: NSLocalizedString("%@ more versions", comment: "exercise family fold"),
                                  group.lessCommonVariants.count.formatted(.number.locale(LanguageManager.currentLocale))))
                    Image(systemName: showsLessCommon ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(MasoColor.textDim)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("exercise.family.more.\(group.id)")
            .listRowBackground(Color.clear)
            if showsLessCommon {
                ForEach(group.lessCommonVariants, id: \.id) { row($0) }
            }
        }
        if let onCollapse {
            Button {
                Haptics.tap()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { onCollapse() }
            } label: {
                Label("Hide variants", systemImage: "chevron.up")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(MasoColor.textDim)
            .accessibilityIdentifier("exercise.family.collapse.\(group.id)")
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        // A stable tail protects List insertions/removals.
        Color.clear.frame(height: 1).listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}

struct ExerciseFamilyVersionsPage<RowView: View>: View {
    let title: String
    let exercises: [Exercise]
    @ViewBuilder let row: (Exercise) -> RowView
    @State private var query = ""

    private var filtered: [Exercise] {
        let words = exerciseSearchWords(query)
        return exercises.filter { $0.matchesSearch(words) }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.id) { row($0) }
            if filtered.isEmpty {
                Text("No exercises match your search").foregroundStyle(MasoColor.textDim)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search"))
        .autocorrectionDisabled().textInputAutocapitalization(.never)
        .accessibilityIdentifier("exercise.family.versions")
    }
}
