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
