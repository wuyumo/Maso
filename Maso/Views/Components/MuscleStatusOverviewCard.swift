import SwiftUI

// "肌肉恢复" hero 区 — TodayScreen 顶部用.
//
// 2026-07-06 v4 (去卡片化):
//   - 卡片壳整个拿掉 (无 surface 底 / 无圆角 / 无描边) — 内容直接坐在页面背景上, 读作开放 section
//   - 内容随之摊开: kicker→map 间距 10→18, map↔legend 间距 16→20, map 130→145 (不再吃 cardPadding,
//     左右各多出 ~20pt, 让图呼吸); 横向对齐交给 TodayScreen 的页边距 (跟其它 section 内容同一条线)
// 2026-05-23 v3:
//   - 顶部加 RECOVERY kicker (跟 Plans tab 的 "FOR YOU" 同款 visual style — accent color + tracking)
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
    /// 非 Pro 点"解锁逐肌群恢复" → caller 拉付费墙 (跟 HistoryScreen 的 onUnlock 同款).
    var onUnlock: () -> Void = {}

    /// Muscle map 正方形 slot 边长 — 去卡片化后不再吃 cardPadding, 放大到 145 让图呼吸
    /// (145 + 20 间距 + 右列 ≤150 = ~315pt, SE 375 − 页边距 32 也放得下).
    private let slotSize: CGFloat = 145

    var body: some View {
        // tease-free / precision-Pro: 免费用户看到 body-map 热图 (漂亮 + 卖产品) 但强制 coarseOnly
        // (粗颗粒), 逐肌群精度 + 4 档图例 + train-the-gaps 定向留给 Pro. 直接建模 Fitbod/WHOOP 的
        // "恢复即高级" 模式, 又保持品牌友好 (视觉钩子免费, 只锁可执行的精度).
        let isPro = data.settings.isPro
        // spacing 18 (原卡片版 10) — 无卡片壳后 header→map 拉开一档, 内容摊开呼吸.
        return VStack(alignment: .leading, spacing: 18) {
            // (原 "MUSCLE STATUS" kicker 整行删除 — 贴心提示 + 分享按钮移进右侧图例列顶部.)

            // 居中内容区: 左 Spacer + (map + 间距 + legend/CTA) + 右 Spacer.
            // 内层 HStack 用 fixedSize, 让整组按自然宽度居中, 不再撑满.
            // map↔legend 间距 20 (原 16) — 跟去卡片化一起摊开.
            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 20) {
                    // LEFT: 复用共享 MuscleVisualBlock — 正方形 slot, heatStyleFor 启用恢复热图 (绿=可练/蓝=疲劳).
                    // ⚠️ 跟其它卡片 (WorkoutCard / SessionCard / PlanRow) 共用一份代码, 改这里同步影响所有.
                    // 免费 → 强制 coarseOnly (粗颗粒热图), 无论用户 muscleDetailEnabled 设置;
                    // Pro → 走用户设置 (精细逐肌群).
                    MuscleVisualBlock(
                        muscles: [],
                        sideLength: slotSize,
                        heatStyleFor: { m in MasoColor.recoveryHeatStyle(muscle: m, fatigueMap: fatigueMap) },
                        coarseOnly: isPro ? !data.settings.muscleDetailEnabled : true
                    )
                    .frame(width: slotSize, height: slotSize)

                    // RIGHT: legend 4 行 + Train the gaps 按钮.
                    // legend group → button 之间走 14pt — 之前 8pt 太挤, 用户反馈 button 跟最后一行
                    // legend 贴在一起没有视觉呼吸. 14pt 让 button 明显是"另一组"操作元素.
                    VStack(alignment: .leading, spacing: 14) {
                        // 贴心提示 — 原 kicker 行的文字, 在图例列顶部可折行.
                        // 分享入口移到底部动作行 (补练按钮右侧圆钮, owner 指定), 不再挂在这里.
                        if let tipLine, !tipLine.isEmpty {
                            Text(tipLine)
                                .font(.system(size: 12))
                                .foregroundStyle(MasoColor.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 150, alignment: .leading)
                        }
                        if fatigueMap.isEmpty {
                            // 零历史首日: 不显示空图例 + 误导性"已全部跟上"(其实从没练过), 改给一句引导.
                            Text("Finish a workout to see which muscles need recovery.")
                                .font(.system(size: 12))
                                .foregroundStyle(MasoColor.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 150, alignment: .leading)
                        } else if isPro {
                            // Pro: 4 档精度图例 + train-the-gaps 定向 CTA (完整可执行价值).
                            VStack(alignment: .leading, spacing: 4) {
                                // 4 档恢复, 跟 MasoColor.recoveryHeatStyle 配色逐一对齐 (绿=练过点亮/灰=没点亮).
                                legendRow(swatch: MasoColor.accent.opacity(1.00), label: "Heavy fatigue")
                                legendRow(swatch: MasoColor.accent.opacity(0.60), label: "Recovering")
                                legendRow(swatch: MasoColor.accent.opacity(0.30), label: "Mostly recovered")
                                legendRow(swatch: Color(red: 0.165, green: 0.165, blue: 0.165), label: "Fresh")
                            }
                            // 有 gap → "Train the gaps" CTA; 没 gap (健康状态) → 正向"全部跟上"标签.
                            // (分享圆钮已移到整个区域右上角 overlay, 不在这一行.)
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
                                    // 次级胶囊钮 → accent 低浓度玻璃 (映射表②), 旧系统保留半透明底.
                                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                                  fallback: MasoColor.accent.opacity(0.16))
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            // 免费: 图例模糊 (看得见有 4 档精度但读不清) + 解锁按钮. 视觉钩子留着,
                            // 逐肌群精度是要解锁的东西.
                            VStack(alignment: .leading, spacing: 4) {
                                legendRow(swatch: MasoColor.accent.opacity(1.00), label: "Heavy fatigue")
                                legendRow(swatch: MasoColor.accent.opacity(0.60), label: "Recovering")
                                legendRow(swatch: MasoColor.accent.opacity(0.30), label: "Mostly recovered")
                                legendRow(swatch: Color(red: 0.165, green: 0.165, blue: 0.165), label: "Fresh")
                            }
                            .blur(radius: 4.5)
                            .allowsHitTesting(false)
                            Button(action: onUnlock) {
                                HStack(spacing: 5) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .heavy))
                                    Text("Unlock per-muscle recovery with Pro")
                                        .font(.system(size: 11, weight: .heavy))
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(MasoColor.accent)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                // 次级钮玻璃 (映射表②); 形状保持圆角矩形 — 多行文案撑不成胶囊.
                                .glassButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                       fallback: MasoColor.accent.opacity(0.16),
                                                       in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 150, alignment: .leading)
                        }
                    }
                    // P2-15: 不再 fixedSize 整个右列宽度 — SE / 长中文 legend 会被裁; 让它能压缩.
                    .frame(height: slotSize, alignment: .center)
                }
                Spacer(minLength: 0)
            }
        }
        // 去卡片化 (v4): 无 surface 底 / 无圆角 / 无内边距 — 内容直接坐在页面背景上,
        // 横向对齐 = TodayScreen 的 pagePaddingHorizontal (跟其它 section 内容同一条线).
        .frame(maxWidth: .infinity, alignment: .leading)
        // 分享圆钮钉整个区域右上角 (owner 指定; 三轮定稿: 提示行→补练行→区域右上角).
        .overlay(alignment: .topTrailing) {
            if !fatigueMap.isEmpty {
                shareButton
            }
        }
        .padding(.vertical, 6)
    }

    /// 分享入口 — 复用现成的 MuscleStatusShareCard (卡早就存在, 之前只是没有入口).
    /// 分享图遵循当前 tier 的显示精度: 免费 = 强制粗颗粒热图 (跟卡上看到的一致,
    /// 不把 Pro 的逐肌群精度泄进免费用户的分享图); Pro = 走用户 muscleDetailEnabled 设置.
    /// 本周统计跟 HistoryScreen.historyMuscleSection 同口径.
    private var shareButton: some View {
        let isPro = data.settings.isPro
        let coarse = isPro ? !data.settings.muscleDetailEnabled : true
        let fatigue = fatigueMap
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let weekSets = data.sets.filter { $0.performedAt >= cutoff }
        let days = Set(weekSets.map { cal.startOfDay(for: $0.performedAt) }).count
        var sections = Set<MuscleGroup>()
        for set in weekSets {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let sec = m.section { sections.insert(sec) }
            }
        }
        let sectionsHit = sections.count
        return ShareImageButton(
            previewTitle: NSLocalizedString("Muscle Status", comment: ""),
            defaultSections: ShareSections(),
            shareContent: { photo, onTapAdd, _ in
                MuscleStatusShareCard(
                    muscleStyle: { m in MasoColor.recoveryHeatStyle(muscle: m, fatigueMap: fatigue) },
                    workoutsThisWeek: days,
                    totalSetsThisWeek: weekSets.count,
                    muscleSectionsHit: sectionsHit,
                    coarseOnly: coarse,
                    userPhoto: photo,
                    onTapAddPhoto: onTapAdd
                )
            },
            shareSurface: "muscle_status",
            label: {
                // 圆形素玻璃小钮 (owner 指定形态) — 高度跟旁边的补练胶囊 (~26pt) 对齐.
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(width: 27, height: 27)
                    .glassCircleButtonBackground()
            }
        )
        .accessibilityLabel("Share")
    }

    /// 单个 legend 行 — 跟 HistoryScreen 的 legendDot 视觉一致.
    private func legendRow(swatch: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(swatch)
                .frame(width: 9, height: 9)
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
