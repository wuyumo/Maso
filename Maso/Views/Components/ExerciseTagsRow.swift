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
    @ViewBuilder var trailing: () -> Trailing
    /// 整行点击.
    let onTap: () -> Void
    /// 左侧图/图标点击 (一般 = 查看详情, 优先于整行).
    let onTapImage: () -> Void
    /// "+N variants" 胶囊点击 (toggle 展开).
    let onToggleExpand: () -> Void

    var body: some View {
        let ex = exercise
        let isFav = data.isFavorite(ex.id)
        Button(action: onTap) {
            HStack(spacing: 14) {
                // 左侧视觉 — 真实动作图 (变种用小尺寸). 缩进靠 listRowInsets, 不再用竖线.
                Button(action: onTapImage) {
                    leadingVisual(ex)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), ex.displayName))

                VStack(alignment: .leading, spacing: isVariant ? 3 : 5) {
                    if isVariant {
                        // 变种: 主文案 = 具体差异 (器械名 / 执行方式), 下方 = 分类标签 (彩色, 区分两类).
                        let diff = variantDiff(ex)
                        Text(diff.text)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(1)
                        if showVariantCategoryLabel {
                            Text(diff.category)
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.6)
                                .textCase(.uppercase)
                                .foregroundStyle(diff.color)
                        }
                    } else {
                        Text(ex.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(1)
                        ExerciseTagsRow(muscleGroups: ex.muscleGroups, equipment: ex.equipment, muscleLimit: 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isFav {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                }
                // canonical 末尾 "+N variants" 胶囊 — 放在 radio 勾选圈左边.
                if !isVariant, !group.isSingleton, showDisclosure {
                    Button(action: onToggleExpand) {
                        HStack(spacing: 4) {
                            Text("+\(group.variants.count)")
                                .font(.system(size: 11, weight: .heavy))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(MasoColor.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MasoColor.accent.opacity(0.14))
                        .overlay(Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isExpanded
                        ? NSLocalizedString("Hide variants", comment: "")
                        : String(format: NSLocalizedString("Show %d variants", comment: ""), group.variants.count)
                    )
                }
                // radio 勾选圈 (多选模式) — 永远在行最右边, "+N variants" 胶囊在它左边.
                trailing()
            }
            .padding(.horizontal, MasoMetrics.rowPaddingH)
            .padding(.vertical, isVariant ? 6 : 10)
            .background(highlighted ? MasoColor.accent.opacity(0.15) : MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        // 标题 (canonical) 上下都收紧 (3→2), 让母动作贴近自己的变种; 变种行 1pt 内聚.
        // 组与组之间的"呼吸" 由 groupedVariantSections 末尾的 spacer 负责 (展开态才加).
        .listRowInsets(EdgeInsets(
            top: isVariant ? 1 : 2,
            leading: MasoMetrics.pagePaddingHorizontal + (isVariant ? 16 : 0),  // 变种缩进 16pt
            bottom: isVariant ? 1 : 2,
            trailing: MasoMetrics.pagePaddingHorizontal
        ))
    }

    @ViewBuilder
    private func leadingVisual(_ ex: Exercise) -> some View {
        // canonical + variant 都用真实动作图; 变种用小尺寸 (40) 体现层级 (不再用文字胶囊 / SF 图标).
        ExerciseImage(
            category: ex.category,
            imageFolder: ex.imageFolder,
            photoURL: ex.photoURL,
            customImageData: ex.customImageData,
            cornerRadius: 8,
            size: isVariant ? 40 : 56,
            animated: false
        )
    }

    /// 变种的"差异"描述 — 明确分两类: 器械差异 / 动作差异 (执行方式).
    /// 返回 (主文案=具体差异, 分类标签, 分类色). accent=动作差异, 中性灰=器械差异.
    private func variantDiff(_ ex: Exercise) -> (text: String, category: String, color: Color) {
        if group.isModifierVariant(ex) {
            // 动作差异 (Seated / Single-Leg / Lean-Forward / 括号内动作细节 …).
            var text = group.variationLabel(for: ex)
            // 器械跟 canonical 不同 → 附器械名消歧 (主库 "Close-Grip · Dumbbell"); 相同 → 不附 (niche, 冗余).
            if !ExerciseGrouping.sameEquipment(ex, group.canonical),
               let eq = ex.equipmentDisplayName, !eq.isEmpty {
                text += " · \(eq)"
            }
            return (text,
                    NSLocalizedString("Variation", comment: "movement/form variant category"),
                    MasoColor.accent)
        }
        // 器械差异 (Dumbbell / Machine / Swiss Ball …) — 优先括号内全文, 退器械名.
        let raw = ex.displayName
        var diff = ex.equipmentDisplayName ?? ""
        if let o = raw.firstIndex(of: "("), let c = raw.lastIndex(of: ")"), raw.index(after: o) < c {
            diff = String(raw[raw.index(after: o)..<c])
        }
        if diff.isEmpty { diff = raw }
        return (diff, NSLocalizedString("Equipment", comment: "equipment variant category"), MasoColor.textDim)
    }
}

// MARK: - VariantSectionHeader — 展开变种时 "Variation" / "Equipment" 两段的小节头
//
// 收折组展开后, 变种拆成"动作差异"(Variation) 和"器械差异"(Equipment) 两个 section.
// 这个小节头标明每段类别, 视觉色跟变种分类色一致 (accent=动作 / 中性灰=器械).
// 缩进对齐变种卡片 (= pagePaddingHorizontal + 16), 让它正好"盖"在它统领的那几行上方.
struct VariantSectionHeader: View {
    let title: String
    var color: Color = MasoColor.textFaint

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: 3,   // 收紧 (7→3) — 小节头贴近上面的母动作 / 上一段变种.
                leading: MasoMetrics.pagePaddingHorizontal + 16 + MasoMetrics.rowPaddingH,
                bottom: 2,
                trailing: MasoMetrics.pagePaddingHorizontal
            ))
    }
}

// 展开收折组时, 把变种拆成 "Variation"(动作) + "Equipment"(器械) 两个带标题的 section.
// 三处共用 (Exercise Library / 训练中选动作 picker / Rare exercises 浏览), 保证收折展开布局一致.
// row 闭包由调用方注入 (各自的 tap / trailing / swipeActions 不同), 但 section 结构 + 标题完全统一.
@ViewBuilder
func groupedVariantSections<RowView: View>(
    for group: ExerciseGroup,
    @ViewBuilder row: @escaping (Exercise) -> RowView
) -> some View {
    let movementVars = group.movementVariants
    let equipmentVars = group.equipmentVariants
    if !movementVars.isEmpty {
        VariantSectionHeader(
            title: NSLocalizedString("Variation", comment: "movement/form variant section"),
            color: MasoColor.accent
        )
        ForEach(movementVars, id: \.id) { row($0) }
    }
    if !equipmentVars.isEmpty {
        VariantSectionHeader(
            title: NSLocalizedString("Equipment", comment: "equipment variant section"),
            color: MasoColor.textDim
        )
        ForEach(equipmentVars, id: \.id) { row($0) }
    }
    // 组尾留白 — 让本组最后一个变种跟下一个母动作之间有"呼吸", 跟组内紧凑形成对比.
    Color.clear
        .frame(height: 5)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
}
