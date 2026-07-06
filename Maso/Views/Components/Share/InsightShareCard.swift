import SwiftUI
import UIKit
import Charts

// Insights 分享卡 — AI 教练小结 + Progress→Insights 段共用的单张合并卡 (share-out P0 v3).
//
// v3: 跟 UnifiedShareCard 对齐的"真内容"哲学 — 勾选项揭示/隐藏的是真实内容块 (实打实的图表),
// 不再是"标题+一个数字"的 tile 列表. 用户在 preview 里看到什么, 分享出去就是什么.
//
// 信息层级 (Wrapped 式, 每块带小 kicker 标签, 跟 UnifiedShareCard section 同款):
//   - (可选) 用户照片 banner (SharePhotoBanner)
//   - ✨ TRAINING INSIGHTS kicker (accent)
//   - hero: AI 教练 TL;DR 引言 (左侧 accent 竖条引用样式) — 只读缓存, 绝不触发 LLM;
//     没缓存 / 用户关掉 → 整块优雅退化成纯数字标题
//   - This week vs last: 环比 % + 本周容量 tile (数字即内容, tile 形态正确)
//   - Weekly volume: 真·8 周容量柱状图 (InsightsChartsView.volumeCard 的紧凑分享版)
//   - Estimated 1RM (Pro): 头号动作按天最佳 e1RM 真折线图 + 动作名
//   - Consistency (Pro): 坚持度 % tile (数字即内容)
//   - "As of <date>" 溯源行 (仅有 TL;DR 时 — 数字/图表是实时算的, 不需要溯源)
//   - (仅编辑模式) 参数勾选面板 — 镜像 UnifiedShareCard 的 inline toggle 机制, 即点即看
//   - 品牌 footer + App Store QR (增长回路, 跟 UnifiedShareCard 同 payload)
//
// 数字全部来自 DataStore.summaryKeyStats(); 图表序列来自 DataStore.summaryWeeklyVolumeSeries() /
// summaryTopLiftSeries() — 卡片从不自己算数 (AISummary.swift 规则: "LLM 从不自己算/编数字",
// 分享卡同理), 跟 AI 小结 payload 同源同口径.
//
// 图表经 ShareImageRenderer (ImageRenderer, iOS 16+) 离屏渲染 — Swift Charts 是纯 SwiftUI,
// ImageRenderer 原生支持 (跟 UnifiedShareCard 的日历/肌肉图同路径), 无需额外处理.
//
// Pro 规则 (#insights-share-pro): 非 Pro 用户不能分享 app 内看不到的数据.
// app 内分层: 周容量环比 + 周容量柱状图 = 免费图表; 头号动作 e1RM + 坚持度 = Pro 锁图表;
// AI TL;DR = Pro (cachedSummary 只有 Pro 会生成). 强制在两层:
//   ① toggle UI — Pro 项对非 Pro 整行不出现 (optionsPanel);
//   ② 渲染层 — effective = options.resolved(isPro:…), 非 Pro 的 Pro 项即使 state 是 true 也硬拦.

/// Insights 分享卡的参数开关 — customize 步骤里用户逐项勾选 (镜像 ShareSections 之于 UnifiedShareCard).
/// 默认全开; 渲染层永远只认 resolved(isPro:hasQuote:stats:…) 之后的结果 (Pro 锁 / 没数据的项强制 false).
struct InsightShareOptions: Equatable {
    /// AI 教练 TL;DR 引言 (Pro)
    var includeQuote = true
    /// 本周 vs 上周 (环比 % + 本周容量 tile, 免费)
    var includeVolumeDelta = true
    /// 每周容量 8 周柱状图 (免费)
    var includeWeeklyVolume = true
    /// 头号动作 e1RM 折线图 (Pro)
    var includeTopLift = true
    /// 坚持度 % (Pro)
    var includeConsistency = true

    /// 至少勾了一项 — caller 用来 disable Share (跟 ShareSections.anyEnabled 同语义).
    var anyEnabled: Bool {
        includeQuote || includeVolumeDelta || includeWeeklyVolume || includeTopLift || includeConsistency
    }

    /// 按 Pro 身份 + 数据可得性过滤后的有效开关 — 不可见/没数据的参数强制 false.
    /// 非 Pro: quote / e1RM / 坚持度一律关 (app 内这三样是 Pro 锁, 不能分享看不到的数据).
    /// 图表块 (周容量柱状 / e1RM 折线) 看真实序列有没有可画的点, 不再只看"本周"单值 —
    /// 周一还没练但过去 7 周有数据时, 柱状图照样成立.
    func resolved(
        isPro: Bool,
        hasQuote: Bool,
        stats: SummaryKeyStats,
        hasVolumeChart: Bool,
        hasTopLiftChart: Bool
    ) -> InsightShareOptions {
        var out = self
        out.includeQuote = includeQuote && isPro && hasQuote
        out.includeVolumeDelta = includeVolumeDelta && stats.volumeWoWPct != nil
        out.includeWeeklyVolume = includeWeeklyVolume && hasVolumeChart
        out.includeTopLift = includeTopLift && isPro && stats.topLiftName != nil && hasTopLiftChart
        out.includeConsistency = includeConsistency && isPro
        return out
    }
}

struct InsightShareCard: View {
    /// AI 教练 TL;DR (data.cachedSummary?.tldr). nil = 无缓存 → 纯数字卡, 不画引言块.
    let tldr: String?
    /// 小结缓存生成时间 — "As of <date>" 行. 仅在有 tldr 时显示.
    let generatedAt: Date?
    /// 头条数字 — DataStore.summaryKeyStats(), 跟 AI 小结 payload 同源同口径.
    let stats: SummaryKeyStats
    /// 渲染层 Pro 闸 (无默认值, 强迫 caller 表态) — 非 Pro 时 quote/e1RM/坚持度永远不入卡,
    /// 不管 options 里勾没勾 (belt & braces, 跟 toggle 不显示双保险).
    let isPro: Bool
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil
    /// 近 8 周容量序列 — DataStore.summaryWeeklyVolumeSeries() 直投, 柱状图数据.
    var volumeSeries: [(week: Date, kg: Double)] = []
    /// 头号动作按天最佳 e1RM 序列 — DataStore.summaryTopLiftSeries().series 直投, 折线图数据
    /// (动作名走 stats.topLiftName, 同源).
    var topLiftSeries: [(date: Date, e1rmKg: Double)] = []
    /// 图表纵轴单位 — 跟 app 内 InsightsChartsView 一致 (settings.weightUnit).
    var unit: WeightUnit = .kg
    /// 参数勾选 (用户 state 原样传入) — 渲染前经 resolved() 过滤, 见 effective.
    var options: InsightShareOptions = InsightShareOptions()
    /// 非 nil = 编辑模式 (ShareCustomizeSheet preview): 卡底部渲染逐参数 toggle 行,
    /// 即点即看 (镜像 UnifiedShareCard 的 editToggles). nil = 渲染最终图, 不画任何 toggle.
    var editOptions: Binding<InsightShareOptions>? = nil

    /// 有效开关 = 用户勾选 ∧ Pro 权限 ∧ 数据可得性 — body 只认这个.
    private var effective: InsightShareOptions {
        options.resolved(
            isPro: isPro,
            hasQuote: tldr != nil,
            stats: stats,
            hasVolumeChart: hasVolumeChart,
            hasTopLiftChart: hasTopLiftChart
        )
    }

    // MARK: - 参数可用性 (toggle 行显隐跟 resolved() 同口径)

    /// 柱状图可画 — 8 周里至少一周有容量.
    private var hasVolumeChart: Bool { volumeSeries.contains { $0.kg > 0 } }
    /// 折线图可画 — 至少一个按天 e1RM 点 (跟 app 内 oneRM 卡的 count >= 1 守卫一致).
    private var hasTopLiftChart: Bool { !topLiftSeries.isEmpty }

    private var quoteAvailable: Bool { isPro && tldr != nil }
    private var volumeDeltaAvailable: Bool { stats.volumeWoWPct != nil }
    private var weeklyVolumeAvailable: Bool { hasVolumeChart }
    private var topLiftAvailable: Bool { isPro && stats.topLiftName != nil && hasTopLiftChart }
    private var consistencyAvailable: Bool { isPro }

    var body: some View {
        let visible = effective
        VStack(spacing: 0) {
            SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
            VStack(alignment: .leading, spacing: 16) {
                // 头部 — kicker + hero (引言 或 纯数字标题)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.accent)
                        Text(NSLocalizedString("Training Insights", comment: "insight share card kicker").uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                    }

                    if visible.includeQuote, let tldr {
                        // hero 引言 — 教练的一句判读. 左侧 accent 竖条 (locale 中立,
                        // 不用弯引号 — 中文排版应是「」, 竖条两边通吃).
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MasoColor.accent)
                                .frame(width: 3)
                            Text(tldr)
                                .font(.system(size: 19, weight: .heavy))
                                .foregroundStyle(MasoColor.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // 无缓存小结 / 用户关掉引言 / 非 Pro → 纯数字标题
                        // (stats-only 退化态; 绝不为了这张卡触发 LLM).
                        Text(NSLocalizedString("My Progress", comment: "insight share card stats-only headline"))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(MasoColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)

                // 内容块 — 勾选项逐块揭示/隐藏真实内容 (没数据的块经 resolved() 各自消失).
                if visible.includeVolumeDelta {
                    deltaBlock
                }
                if visible.includeWeeklyVolume {
                    volumeChartBlock
                }
                if visible.includeTopLift {
                    topLiftChartBlock
                }
                if visible.includeConsistency {
                    consistencyBlock
                }

                // 溯源行 — 只跟着 TL;DR 走 (数字/图表是实时算的).
                if visible.includeQuote, tldr != nil, let generatedAt {
                    Text(String(
                        format: NSLocalizedString("As of %@ · based on the last 14 days", comment: "AI summary footer"),
                        Self.asOfFormatter.string(from: generatedAt)
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
                }

                // 参数勾选面板 — 仅编辑模式 (preview) 出现, 渲染最终图时 editOptions == nil 整块不画.
                if let editOptions {
                    optionsPanel(editOptions)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            ShareCardFooter(qrPayload: MasoLinks.appStore)
        }
        .background(MasoColor.background)
    }

    // MARK: - 内容块

    /// 块 kicker — 全大写 + spaced accent 小标签 (跟 UnifiedShareCard.SectionKicker 同规格).
    private func blockKicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(2)
            .foregroundStyle(MasoColor.accent)
    }

    /// kicker 行右侧的小注解 (时间窗 / 动作名 / 单位) — textFaint 不抢焦点.
    private func blockCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MasoColor.textFaint)
            .lineLimit(1)
    }

    /// 本周 vs 上周 — 环比 % + 本周容量两个 tile. 数字即内容, tile 形态正确.
    private var deltaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockKicker(NSLocalizedString("This week vs last", comment: "insight share block — weekly delta"))
            HStack(spacing: 10) {
                if let wow = stats.volumeWoWPct {
                    statTile(
                        value: "\(wow >= 0 ? "+" : "")\(wow)%",
                        label: NSLocalizedString("vs last week", comment: "insight share stat — volume WoW")
                    )
                }
                if stats.weeklyVolumeKg > 0 {
                    statTile(
                        value: "\(stats.weeklyVolumeKg.formatted(.number.grouping(.automatic))) kg",
                        label: NSLocalizedString("Volume this week", comment: "insight share stat — weekly volume")
                    )
                } else {
                    // 本周还没容量 → 右格留空占位, 保持左格宽度一致 (跟旧 statGrid 同做法).
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
    }

    /// 每周容量 — 真·8 周柱状图, InsightsChartsView.volumeCard 的紧凑分享版 (110pt).
    private var volumeChartBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                blockKicker(NSLocalizedString("Weekly volume", comment: ""))
                Spacer()
                blockCaption("\(NSLocalizedString("Last 8 weeks", comment: "insight share chart caption")) · \(unit.label)")
            }
            chartTile {
                Chart {
                    ForEach(volumeSeries, id: \.week) { p in
                        BarMark(
                            x: .value("Week", p.week, unit: .weekOfYear),
                            y: .value("Volume", unit.fromKg(p.kg))
                        )
                        .foregroundStyle(MasoColor.accent.gradient)
                        // 上下四角全圆, 跟 Insights 页的周容量图一致.
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .frame(height: 110)
                .chartYAxis { AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                        .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
            }
        }
    }

    /// 头号动作 e1RM — 真·按天最佳估算 1RM 折线图 (LineMark+PointMark),
    /// InsightsChartsView.oneRMChart 的紧凑分享版 (110pt); 动作名在 kicker 行右侧.
    private var topLiftChartBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                blockKicker(NSLocalizedString("Estimated 1RM", comment: ""))
                Spacer()
                if let name = stats.topLiftName {
                    blockCaption(name)
                }
            }
            chartTile {
                Chart {
                    ForEach(topLiftSeries, id: \.date) { p in
                        LineMark(
                            x: .value("Date", p.date, unit: .day),
                            y: .value("1RM", unit.fromKg(p.e1rmKg))
                        )
                        .foregroundStyle(MasoColor.accent)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Date", p.date, unit: .day),
                            y: .value("1RM", unit.fromKg(p.e1rmKg))
                        )
                        .foregroundStyle(MasoColor.accent)
                        .symbolSize(28)
                    }
                }
                .frame(height: 110)
                .chartYAxis { AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
                .chartXAxis { AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
            }
        }
    }

    /// 坚持度 — % tile (数字即内容). kicker 右侧标时间窗.
    private var consistencyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                blockKicker(NSLocalizedString("Consistency", comment: "insight share stat — adherence"))
                Spacer()
                blockCaption(NSLocalizedString("Last 8 weeks", comment: "insight share chart caption"))
            }
            statTile(
                value: "\(stats.adherencePct)%",
                label: NSLocalizedString("Adherence", comment: "adherence stat")
            )
        }
    }

    /// 单 tile — ShareStat (大数字 + 小 label) 套 surface 圆角底.
    private func statTile(value: String, label: String) -> some View {
        ShareStat(value: value, label: label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 图表 tile — 跟 statTile 同款 surface 圆角底, 图表内容内缩 12pt.
    private func chartTile<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 参数勾选面板 (仅编辑模式)

    /// 每个"可用"参数一行 label + toggle — Pro 锁 (非 Pro) / 没数据的参数整行不出现
    /// (跟 UnifiedShareCard "sectionData == nil 就整节不画" 同哲学). 行 label 复用块 kicker 的
    /// 本地化 key, 用户勾的和卡上看到的是同一个词.
    private func optionsPanel(_ binding: Binding<InsightShareOptions>) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MasoColor.borderSoft)
                .frame(height: 1)
                .padding(.bottom, 6)
            if quoteAvailable {
                optionRow(
                    NSLocalizedString("AI coach quote", comment: "insight share toggle — TL;DR"),
                    isOn: binding.includeQuote
                )
            }
            if volumeDeltaAvailable {
                optionRow(
                    NSLocalizedString("This week vs last", comment: ""),
                    isOn: binding.includeVolumeDelta
                )
            }
            if weeklyVolumeAvailable {
                optionRow(
                    NSLocalizedString("Weekly volume", comment: ""),
                    isOn: binding.includeWeeklyVolume
                )
            }
            if topLiftAvailable, let name = stats.topLiftName {
                optionRow(
                    String(format: NSLocalizedString("%@ e1RM", comment: ""), name),
                    isOn: binding.includeTopLift
                )
            }
            if consistencyAvailable {
                optionRow(
                    NSLocalizedString("Consistency", comment: ""),
                    isOn: binding.includeConsistency
                )
            }
        }
    }

    /// 单行参数 toggle — label + accent 缩放 Toggle (跟 UnifiedShareCard.InlineSectionToggle 同规格).
    private func optionRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MasoColor.text)
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(MasoColor.accent)
                .scaleEffect(0.78)
                .frame(width: 40)
        }
        .frame(minHeight: 36)
    }

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
