import ActivityKit
import SwiftUI
import WidgetKit

// Maso 训练 Live Activity — 锁屏 banner + Dynamic Island.
// 用户退出 app 后, 训练状态实时显示在锁屏顶部 + Dynamic Island.
//
// 4 个 region (Apple Live Activity 必备):
//   1. Lock Screen banner — 主要展示位, 全宽卡片
//   2. Dynamic Island compact (左) — 一个 SF symbol
//   3. Dynamic Island compact (右) — 倒计时或文字
//   4. Dynamic Island expanded — 用户长按 Dynamic Island 时展开, 4 个 sub-region
//   5. Dynamic Island minimal — 多个 Live Activity 同时存在时 fall back 到这个
struct MasoTrainingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainingActivityAttributes.self) { context in
            // === Lock Screen banner ===
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // === Expanded — 用户长按 island 展开 ===
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isRest ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.green)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(context.attributes.planName)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            Text(context.state.segmentLabel)
                                .font(.system(size: 13, weight: .heavy))
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let endsAt = context.state.endsAt {
                        Text(timerInterval: Date()...endsAt, countsDown: true)
                            .font(.system(size: 22, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.green)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if !context.state.setProgress.isEmpty {
                        Text(context.state.setProgress)
                            .font(.system(size: 22, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.green)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isRest, let next = context.state.nextExerciseName {
                        HStack {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.secondary)
                            Text(next)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isRest ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.green)
            } compactTrailing: {
                if let endsAt = context.state.endsAt {
                    Text(timerInterval: Date()...endsAt, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(Color.green)
                        .frame(maxWidth: 50)
                } else if !context.state.setProgress.isEmpty {
                    Text(context.state.setProgress)
                        .monospacedDigit()
                        .foregroundStyle(Color.green)
                }
            } minimal: {
                Image(systemName: context.state.isRest ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.green)
            }
        }
    }
}

/// Lock Screen banner view — 全宽卡片
private struct LockScreenView: View {
    let context: ActivityViewContext<TrainingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部 kicker — plan name
            HStack(spacing: 6) {
                Image(systemName: context.state.isRest ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.green)
                Text(context.attributes.planName.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MASSO")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }

            // 主行: 当前段标签 + 倒计时 / 组进度
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.segmentLabel)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                    if context.state.isRest, let next = context.state.nextExerciseName {
                        Text("Next: \(next)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !context.state.setProgress.isEmpty {
                        Text(context.state.setProgress)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let endsAt = context.state.endsAt {
                    Text(timerInterval: Date()...endsAt, countsDown: true)
                        .font(.system(size: 28, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(Color.green)
    }
}
