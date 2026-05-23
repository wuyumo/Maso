import SwiftUI

// "肌肉图 + 可选照片" 视觉块 — WorkoutCard (今日训练) + SessionCard (训练记录) 共享.
//
// ⚠️ 维护约定 (2026-05-23 用户拍板):
//   - WorkoutCard 跟 SessionCard 的"相同元素必须代码层面也一致".
//   - 这个 block 是两个卡片"Muscle Map + 用户照片"区域的唯一实现源.
//   - 任何视觉 / 尺寸 / 排布的改动改这里, 不要在某一边单独 hack.
//
// 行为:
//   - 左对齐
//   - Muscle Map 前后半身紧贴 (panelSpacing 0), 接近 1.14:1 的近正方形
//   - 有照片 → 照片放在 Muscle Map 右边, 尺寸跟 Muscle Map 的"高"一致 (照片是严格正方形)
//   - 没照片 → 只 Muscle Map, 右侧自然 Spacer 撑开 (caller 仍要 left-align frame)
struct MuscleVisualBlock: View {
    let muscles: [MuscleGroup]
    /// 块整体高度, 同时决定照片正方形边长. 默认 110.
    var height: CGFloat = 110
    /// 用户该 session 的照片 (SessionCard 用; WorkoutCard 暂时不传).
    var photo: UIImage? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Muscle Map — 前后半身紧贴, region=.full, 跟 MuscleStatusOverviewCard 同一套参数
            BodyHint(
                muscles: muscles,
                height: height,
                region: .full,
                panelSpacing: 0
            )

            // 用户照片 — 跟 muscle map 等高的严格正方形
            if let img = photo {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: height, height: height)
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
        .frame(height: height)
    }
}
