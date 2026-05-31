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

    /// 折叠到 12 major + dedupe + 按 groupedRows 顺序 (chest 永远在 back 前)
    /// 落点用 MuscleSelector.majorOf — 全 app 肌群归一唯一入口.
    private var folded: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for m in muscleGroups {
            let major = MuscleSelector.majorOf(m)
            if major == .fullBody { continue }
            if seen.insert(major).inserted { out.append(major) }
        }
        // 按 groupedRows 顺序稳定输出
        return MuscleSelector.groupedRows
            .map(\.major)
            .filter(seen.contains)
            + out.filter { !MuscleSelector.majorMuscles.contains($0) }  // 兜底: 不在 picker 暴露层级里的尾部
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
                if isVariant {
                    // 缩进竖线 — 器械变种中性灰; 执行方式变种 accent, 更显眼.
                    let isModVar = group.isModifierVariant(ex)
                    Rectangle()
                        .fill(isModVar ? MasoColor.accent.opacity(0.6) : MasoColor.textFaint.opacity(0.35))
                        .frame(width: 2)
                        .padding(.leading, 8)
                }
                // 左侧视觉 — 点它查看详情 (任何模式都能看).
                Button(action: onTapImage) {
                    leadingVisual(ex)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), ex.displayName))

                VStack(alignment: .leading, spacing: 5) {
                    Text(Self.rowTitle(for: ex, isVariant: isVariant, group: group))
                        .font(.system(size: isVariant ? 13 : 15, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                    if !isVariant {
                        ExerciseTagsRow(muscleGroups: ex.muscleGroups, equipment: ex.equipment, muscleLimit: 1)
                    } else if let eqName = ex.equipmentDisplayName {
                        Text(eqName)
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isFav {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                }
                trailing()
                // canonical 末尾 "+N variants" 胶囊.
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
            }
            .padding(.horizontal, MasoMetrics.rowPaddingH)
            .padding(.vertical, isVariant ? 6 : 10)
            .background(highlighted ? MasoColor.accent.opacity(0.15) : MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(
            top: isVariant ? 1 : 3,
            leading: MasoMetrics.pagePaddingHorizontal + (isVariant ? 16 : 0),  // 变种缩进 16pt
            bottom: isVariant ? 1 : 3,
            trailing: MasoMetrics.pagePaddingHorizontal
        ))
    }

    @ViewBuilder
    private func leadingVisual(_ ex: Exercise) -> some View {
        if isVariant {
            if let mod = group.modifierLabel(for: ex) {
                // 执行方式变种 — 修饰词胶囊 (accent 底), 跟器械图标尺寸一致 (36×36).
                Text(mod)
                    .font(.system(size: 9, weight: .heavy))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 4)
                    .frame(width: 36, height: 36)
                    .background(MasoColor.accent.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // 纯器械变种 — SF Symbol (中性灰底).
                Image(systemName: Self.variantSymbol(for: ex))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(width: 36, height: 36)
                    .background(MasoColor.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else {
            ExerciseImage(
                category: ex.category,
                imageFolder: ex.imageFolder,
                customImageData: ex.customImageData,
                cornerRadius: 8,
                size: 56,
                animated: false
            )
        }
    }

    /// 行标题: canonical 显全名; variant 显"差异"部分 (括号内 / 全名).
    static func rowTitle(for ex: Exercise, isVariant: Bool, group: ExerciseGroup) -> String {
        guard isVariant else { return ex.displayName }
        let raw = ex.displayName
        // 执行方式变种: 修饰词已在左侧胶囊 → 标题显括号内器械 (若有), 否则全名.
        // 纯器械变种: 只显括号内内容.
        if let openParen = raw.firstIndex(of: "("),
           let closeParen = raw.lastIndex(of: ")") {
            let after = raw.index(after: openParen)
            if after < closeParen { return String(raw[after..<closeParen]) }
        }
        return raw
    }

    /// 变种行小图标 — 按 equipment 选 SF Symbol, 无器械 fallback dumbbell.
    static func variantSymbol(for ex: Exercise) -> String {
        switch ex.equipment {
        case "barbell", "dumbbell", "kettlebell", "ez_bar", "ez_curl_bar":
            return "dumbbell.fill"
        case "machine", "smith_machine", "leg_press_machine", "calf_raise_machine",
             "lat_pulldown_machine", "hip_thrust_machine", "back_extension_machine":
            return "gearshape.fill"
        case "cable":            return "cable.connector"
        case "body_only":        return "figure.strengthtraining.traditional"
        case "pull_up_bar":      return "figure.gymnastics"
        case "bench_flat", "bench_incline", "bench_decline": return "bed.double.fill"
        case "resistance_band", "band": return "alternatingcurrent"
        case "trx", "rings", "gymnastic_rings": return "figure.gymnastics"
        case "plyo_box":         return "square.stack.3d.up.fill"
        case "medicine_ball", "exercise_ball": return "circle.fill"
        case "foam_roller":      return "cylinder.fill"
        case "jump_rope":        return "figure.jumprope"
        case "treadmill", "stationary_bike", "rowing_machine", "elliptical":
            return "figure.run"
        default:                 return "dumbbell.fill"
        }
    }
}
