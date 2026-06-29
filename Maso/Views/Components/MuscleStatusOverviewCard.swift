import SwiftUI

// "肌肉恢复" hero 卡 — TodayScreen 顶部用.
//
// 2026-05-23 v3:
//   - 顶部加 RECOVERY kicker (跟 Plans tab 的 "FOR YOU" 同款 visual style — accent color + tracking)
//   - 卡片样式跟 PlanRationaleCard 完全对齐: 1pt accent stroke 40% + accent shadow (无底色)
//   - 居中布局: 左 muscle map + 右 legend / CTA
//
// Callers 注入 lastMap (muscle → 最近一次训练时间) + gap workout handler.
// 计算 (lastMap + gap muscles) 都放在 MuscleStatusCompute / DataStore, 不在 view 里.
struct MuscleStatusOverviewCard: View {
    @Environment(DataStore.self) private var data

    /// 累计 volume + 时间衰减的 fatigue map — caller (TodayScreen) 用
    /// MuscleStatusCompute.muscleFatigueMap 算好传进来.
    let fatigueMap: [MuscleGroup: Double]
    let gapMuscles: [MuscleGroup]
    /// "Train the gaps" 按钮 — caller 构造 plan 并启动训练
    let onStartGapWorkout: () -> Void
    /// Today 标题区移来的一句贴心提示 (距上次训练多久) — 显示在 "MUSCLE STATUS" kicker 行右侧,
    /// 短就靠右、放不下自动向下折行. nil = 不显示.
    var tipLine: String? = nil

    /// Muscle map 正方形 slot 边长 — 跟 MuscleVisualBlock 昨天版本对齐 (正方形, 不放大).
    private let slotSize: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部 kicker — 跟 WorkoutCard "FROM YOUR PLAN" 完全同款字号 (10pt heavy + tracking 1.5)
            // + 跟 FOR YOU 卡同款 icon + 文字 visual family.
            // kicker 跟 Settings section header / "Today's Workout" 同款 textDim 灰,
            // 不再 accent 绿. accent 留给真正的 CTA / 高亮状态, 不给 section 标签用.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(MasoColor.textDim)
                    Text("MUSCLE STATUS")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(MasoColor.textDim)
                }
                Spacer(minLength: 12)
                // Today 标题区移来的贴心提示 — 靠右; 一行放不下自动向下折行 (右对齐).
                if let tipLine, !tipLine.isEmpty {
                    Text(tipLine)
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 居中内容区: 左 Spacer + (map + 间距 + legend/CTA) + 右 Spacer.
            // 内层 HStack 用 fixedSize, 让整组按自然宽度居中, 不再撑满.
            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 16) {
                    // LEFT: 复用共享 MuscleVisualBlock — 正方形 slot, opacityFor 启用衰减热图.
                    // ⚠️ 跟其它卡片 (WorkoutCard / SessionCard / PlanRow) 共用一份代码, 改这里同步影响所有.
                    MuscleVisualBlock(
                        muscles: [],
                        sideLength: slotSize,
                        opacityFor: { m in MuscleStatusCompute.opacityFor(muscle: m, fatigueMap: fatigueMap) },
                        coarseOnly: !data.settings.muscleDetailEnabled
                    )
                    .frame(width: slotSize, height: slotSize)

                    // RIGHT: legend 4 行 + Train the gaps 按钮.
                    // legend group → button 之间走 14pt — 之前 8pt 太挤, 用户反馈 button 跟最后一行
                    // legend 贴在一起没有视觉呼吸. 14pt 让 button 明显是"另一组"操作元素.
                    VStack(alignment: .leading, spacing: 14) {
                        if fatigueMap.isEmpty {
                            // 零历史首日: 不显示空图例 + 误导性"已全部跟上"(其实从没练过), 改给一句引导.
                            Text("Finish a workout to see which muscles need recovery.")
                                .font(.system(size: 12))
                                .foregroundStyle(MasoColor.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 150, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                // 4 档 fatigue, 跟 MuscleStatusCompute.opacityFor 阈值对齐.
                                legendRow(opacity: 1.0, label: "Heavy fatigue")
                                legendRow(opacity: 0.6, label: "Recovering")
                                legendRow(opacity: 0.3, label: "Mostly recovered")
                                legendRow(opacity: nil, label: "Fresh")
                            }
                            // 有 gap → "Train the gaps" CTA; 没 gap (健康状态) → 正向"全部跟上"标签.
                            if gapMuscles.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10, weight: .heavy))
                                    Text("All caught up")
                                        .font(.system(size: 11, weight: .heavy))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(MasoColor.textDim)
                                .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Button(action: onStartGapWorkout) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10, weight: .heavy))
                                        Text("Train the gaps")
                                            .font(.system(size: 11, weight: .heavy))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(MasoColor.accent)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(MasoColor.accent.opacity(0.16))
                                    .clipShape(Capsule())
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    // P2-15: 不再 fixedSize 整个右列宽度 — SE / 长中文 legend 会被裁; 让它能压缩.
                    .frame(height: slotSize, alignment: .center)
                }
                Spacer(minLength: 0)
            }
        }
        // 卡片内边距 — 跟 PlanRationaleCard ("FOR YOU" 卡) 完全对齐.
        .padding(.horizontal, MasoMetrics.cardPadding)
        .padding(.vertical, MasoMetrics.cardPadding - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 无边框 + 背景色 — 跟第二个 tab 的 WorkoutCard 一致 (surface 填充 + 圆角, 不描边).
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
