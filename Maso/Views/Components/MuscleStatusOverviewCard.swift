import SwiftUI

// "肌肉状态" 横向卡片 — TodayScreen 顶部 hero 用.
//
// 跟 HistoryScreen 上的 muscle status 卡视觉差异:
//   - 横版布局: 左 BodyHint 紧凑(近正方形) + 右 legend 竖排 + 右下两个按钮
//   - 不带 Share 按钮 (Share 入口仍在 Muscle Status tab)
//   - 不带 share card stats 数据 (Workouts / Total Sets / Groups Hit)
//
// Callers 注入 lastMap (muscle → 最近一次训练时间) + 两个 button handler.
// 计算 (lastMap + gap muscles) 都放在 MuscleStatusCompute / DataStore, 不在 view 里.
struct MuscleStatusOverviewCard: View {
    @Environment(DataStore.self) private var data

    let lastMap: [MuscleGroup: Date]
    let gapMuscles: [MuscleGroup]
    /// "Workout calendar" 按钮 — 弹出训练日历 sheet
    let onShowCalendar: () -> Void
    /// "Train the gaps" 按钮 — caller 构造 plan 并启动训练
    let onStartGapWorkout: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // LEFT: BodyHint — front + back 紧凑显示, 视觉接近正方形
            //   - panelSpacing 0  →  前后无缝 (默认 6 太分离)
            //   - height 160      →  两 panel 自然 aspect 0.57 × 2 = 182 宽, 比例 1.14:1
            // 数学上不完美 1:1, 但视觉上 "近正方形" 已经达到 (人体轮廓本身就比 panel 包络小).
            BodyHint(
                muscles: [],
                height: 160,
                opacityFor: { m in MuscleStatusCompute.opacityFor(muscle: m, lastMap: lastMap) },
                coarseOnly: !data.settings.muscleDetailEnabled,
                panelSpacing: 0
            )

            // RIGHT: legend (4 stacked) + 2 buttons
            VStack(alignment: .leading, spacing: 0) {
                // Legend — 竖排 4 行
                VStack(alignment: .leading, spacing: 6) {
                    legendRow(opacity: 1.0, label: "Fatigued")
                    legendRow(opacity: 0.6, label: "Recovering")
                    legendRow(opacity: 0.3, label: "Almost fresh")
                    legendRow(opacity: nil, label: "Ready to train")
                }

                Spacer(minLength: 8)

                // Action buttons — 竖排 2 个 capsule
                VStack(spacing: 6) {
                    Button(action: onShowCalendar) {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Workout calendar")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(MasoColor.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(MasoColor.surfaceHi)
                        .overlay(Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.8))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onStartGapWorkout) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .heavy))
                            Text("Train the gaps")
                                .font(.system(size: 11, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(MasoColor.accent)
                        .clipShape(Capsule())
                        .shadow(color: MasoColor.accent.opacity(0.35), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(gapMuscles.isEmpty)
                    .opacity(gapMuscles.isEmpty ? 0.35 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 跟 BodyHint 等高, 让 legend / buttons 在垂直方向自然撑开
            .frame(height: 160)
        }
        .padding(MasoMetrics.cardPadding - 4)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    /// 单个 legend 行 — 跟 HistoryScreen 的 legendDot 视觉一致, 改成 row layout.
    private func legendRow(opacity: Double?, label: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(opacity == nil
                      ? Color(red: 0.165, green: 0.165, blue: 0.165)
                      : MasoColor.accent.opacity(opacity!))
                .frame(width: 10, height: 10)
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
