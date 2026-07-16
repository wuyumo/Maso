import SwiftUI

// "肌肉图 + 可选照片" 视觉块 — WorkoutCard (今日训练) + SessionCard (训练记录) + 各种 plan
// 卡片共享.
//
// ⚠️ 维护约定 (2026-05-23 用户拍板):
//   - WorkoutCard 跟 SessionCard 的"相同元素必须代码层面也一致".
//   - 这个 block 是所有卡片"Muscle Map + 用户照片"区域的唯一实现源.
//   - 任何视觉 / 尺寸 / 排布的改动改这里, 不要在某一边单独 hack.
//   - Muscle map 跟照片都锁正方形 (sideLength × sideLength), 视觉一致.
//
// 行为:
//   - 左对齐
//   - Muscle Map 渲染在 sideLength × sideLength 的正方形里, 前后半身紧贴 (panelSpacing 0).
//     人体本身宽高比 ~1.14:1, BodyHint 高 ≈ sideLength×0.88 → 自然宽刚好 = sideLength,
//     在正方形内垂直居中 (上下各留 ~6% 透气). 视觉是个正方形区域.
//   - 有照片 → 照片放在 Muscle Map 右边, 也是 sideLength × sideLength 正方形.
//   - 没照片 → 只 Muscle Map, 右侧自然 Spacer 撑开.
struct MuscleVisualBlock: View {
    let muscles: [MuscleGroup]
    /// 正方形边长 — 同时是 muscle map slot + 照片的宽高. 默认 110.
    var sideLength: CGFloat = 110
    /// 用户该 session 的照片 (SessionCard 用; WorkoutCard 暂时不传).
    var photo: UIImage? = nil
    /// 恢复热图模式 — MuscleStatusOverviewCard 用. 传了之后 BodyHint 走 heatStyleFor 路径 (忽略 muscles 参数).
    var heatStyleFor: ((MuscleGroup) -> (Color, Double)?)? = nil
    /// 粗颗粒模式 — Settings.muscleDetailEnabled 取反时传 true.
    var coarseOnly: Bool = false

    /// 人体 viewBox 自然宽高比 ~0.568, 两 panel + 4pt gap 总宽高比 ~1.18.
    /// BodyHint height × 1.18 = 自然宽. 想让宽 ≈ sideLength → height = sideLength / 1.18.
    /// 取 0.82 给左右各 ~3pt 透气, 不挨方框边. 跟 BodyHint.panelSpacing=4 一致.
    private var bodyHintHeight: CGFloat { sideLength * 0.82 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Muscle Map 正方形 slot — BodyHint 在内部居中, 上下有 ~7% 透气
            BodyHint(
                muscles: muscles,
                height: bodyHintHeight,
                region: .full,
                heatStyleFor: heatStyleFor,
                coarseOnly: coarseOnly,
                panelSpacing: 0
            )
            .frame(width: sideLength, height: sideLength)

            // 用户照片 — 严格正方形, 跟 muscle map slot 等大
            if let img = photo {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: sideLength, height: sideLength)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(MasoColor.borderSoft, lineWidth: 0.5)
                    )
                    .accessibilityLabel("Workout photo")
            }

            // 整体左对齐 (frame .infinity + .leading 显式约束, 不依赖 caller 是否撑全宽)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: sideLength)
    }
}
