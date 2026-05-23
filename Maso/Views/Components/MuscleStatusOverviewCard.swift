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

    /// Muscle map slot 边长. 卡片整体高度 = 标题行 + slot + padding.
    /// 130 比之前 160 紧凑 ~20%, 同时仍能塞下右侧 4 行 legend + 2 个按钮.
    private let slotSize: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 卡片标题 — 跟其他 hero 卡 (WorkoutCard) 同款层级 / 字号
            Text("Muscle Status")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MasoColor.text)

            HStack(alignment: .top, spacing: 12) {
                // LEFT: 复用共享 MuscleVisualBlock — 正方形 slot, opacityFor 启用衰减热图.
                // ⚠️ 跟其它卡片 (WorkoutCard / SessionCard / PlanRow) 共用一份代码, 改这里同步影响所有.
                MuscleVisualBlock(
                    muscles: [],
                    sideLength: slotSize,
                    opacityFor: { m in MuscleStatusCompute.opacityFor(muscle: m, lastMap: lastMap) },
                    coarseOnly: !data.settings.muscleDetailEnabled
                )
                .frame(width: slotSize)   // 不让它撑全宽, 右侧留给 legend + buttons

                // RIGHT: legend (4 stacked) + 2 capsule buttons
                VStack(alignment: .trailing, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        legendRow(opacity: 1.0, label: "Fatigued")
                        legendRow(opacity: 0.6, label: "Recovering")
                        legendRow(opacity: 0.3, label: "Almost fresh")
                        legendRow(opacity: nil, label: "Ready to train")
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 5) {
                        Button(action: onShowCalendar) {
                            HStack(spacing: 5) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Workout calendar")
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(MasoColor.text)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(MasoColor.surfaceHi)
                            .overlay(Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.8))
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.plain)

                        Button(action: onStartGapWorkout) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .heavy))
                                Text("Train the gaps")
                                    .font(.system(size: 11, weight: .heavy))
                                    .lineLimit(1)
                            }
                            // 透明 accent 绿样式 — accent 文字 + 16% accent 背景 + 40% accent 描边.
                            // 跟 ExerciseDetailSheet 的 "Watch demo" / "Listen" 同款 ghost CTA 风格.
                            .foregroundStyle(MasoColor.accent)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(MasoColor.accent.opacity(0.16))
                            .overlay(Capsule().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.8))
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.plain)
                        .disabled(gapMuscles.isEmpty)
                        .opacity(gapMuscles.isEmpty ? 0.35 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: slotSize)
            }
        }
        .padding(MasoMetrics.cardPadding - 4)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    /// 单个 legend 行 — 跟 HistoryScreen 的 legendDot 视觉一致.
    private func legendRow(opacity: Double?, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(opacity == nil
                      ? Color(red: 0.165, green: 0.165, blue: 0.165)
                      : MasoColor.accent.opacity(opacity!))
                .frame(width: 9, height: 9)
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
