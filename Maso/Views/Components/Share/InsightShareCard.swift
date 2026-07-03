import SwiftUI
import UIKit

// Insights 分享卡 — AI 教练小结 + Progress→Insights 段共用的单张合并卡 (share-out P0 v2).
//
// 信息层级 (Wrapped 式: 一句判读 + 数字):
//   - (可选) 用户照片 banner (SharePhotoBanner)
//   - ✨ TRAINING INSIGHTS kicker (accent)
//   - hero: AI 教练 TL;DR 引言 (左侧 accent 竖条引用样式) — 只读缓存, 绝不触发 LLM;
//     没缓存 / 用户关掉 → 整块优雅退化成纯数字标题
//   - stat tile (2 列): 周容量环比 % / 本周容量 kg / 头号动作 e1RM / 坚持度 % — 逐项可勾选
//   - "As of <date>" 溯源行 (仅有 TL;DR 时 — 数字是实时算的, 不需要溯源)
//   - (仅编辑模式) 参数勾选面板 — 镜像 UnifiedShareCard 的 inline toggle 机制, 即点即看
//   - 品牌 footer + App Store QR (增长回路, 跟 UnifiedShareCard 同 payload)
//
// 数字全部来自 DataStore.summaryKeyStats() — 卡片从不自己算数 (AISummary.swift 规则:
// "LLM 从不自己算/编数字", 分享卡同理).
//
// Pro 规则 (#insights-share-pro): 非 Pro 用户不能分享 app 内看不到的数据.
// app 内分层: 周容量环比 + 本周容量 = 免费图表; 头号动作 e1RM + 坚持度 = Pro 锁图表;
// AI TL;DR = Pro (cachedSummary 只有 Pro 会生成). 强制在两层:
//   ① toggle UI — Pro 项对非 Pro 整行不出现 (optionsPanel);
//   ② 渲染层 — effective = options.resolved(isPro:…), 非 Pro 的 Pro 项即使 state 是 true 也硬拦.

/// Insights 分享卡的参数开关 — customize 步骤里用户逐项勾选 (镜像 ShareSections 之于 UnifiedShareCard).
/// 默认全开; 渲染层永远只认 resolved(isPro:hasQuote:stats:) 之后的结果 (Pro 锁 / 没数据的项强制 false).
struct InsightShareOptions: Equatable {
    /// AI 教练 TL;DR 引言 (Pro)
    var includeQuote = true
    /// 周容量环比 % (免费)
    var includeVolumeDelta = true
    /// 本周容量 kg (免费)
    var includeWeeklyVolume = true
    /// 头号动作 e1RM (Pro)
    var includeTopLift = true
    /// 坚持度 % (Pro)
    var includeConsistency = true

    /// 至少勾了一项 — caller 用来 disable Share (跟 ShareSections.anyEnabled 同语义).
    var anyEnabled: Bool {
        includeQuote || includeVolumeDelta || includeWeeklyVolume || includeTopLift || includeConsistency
    }

    /// 按 Pro 身份 + 数据可得性过滤后的有效开关 — 不可见/没数据的参数强制 false.
    /// 非 Pro: quote / e1RM / 坚持度一律关 (app 内这三样是 Pro 锁, 不能分享看不到的数据).
    func resolved(isPro: Bool, hasQuote: Bool, stats: SummaryKeyStats) -> InsightShareOptions {
        var out = self
        out.includeQuote = includeQuote && isPro && hasQuote
        out.includeVolumeDelta = includeVolumeDelta && stats.volumeWoWPct != nil
        out.includeWeeklyVolume = includeWeeklyVolume && stats.weeklyVolumeKg > 0
        out.includeTopLift = includeTopLift && isPro && stats.topLiftName != nil && stats.topLiftE1rmKg != nil
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
    /// 参数勾选 (用户 state 原样传入) — 渲染前经 resolved() 过滤, 见 effective.
    var options: InsightShareOptions = InsightShareOptions()
    /// 非 nil = 编辑模式 (ShareCustomizeSheet preview): 卡底部渲染逐参数 toggle 行,
    /// 即点即看 (镜像 UnifiedShareCard 的 editToggles). nil = 渲染最终图, 不画任何 toggle.
    var editOptions: Binding<InsightShareOptions>? = nil

    /// 有效开关 = 用户勾选 ∧ Pro 权限 ∧ 数据可得性 — body 只认这个.
    private var effective: InsightShareOptions {
        options.resolved(isPro: isPro, hasQuote: tldr != nil, stats: stats)
    }

    // MARK: - 参数可用性 (toggle 行显隐跟 resolved() 同口径)

    private var quoteAvailable: Bool { isPro && tldr != nil }
    private var volumeDeltaAvailable: Bool { stats.volumeWoWPct != nil }
    private var weeklyVolumeAvailable: Bool { stats.weeklyVolumeKg > 0 }
    private var topLiftAvailable: Bool { isPro && stats.topLiftName != nil && stats.topLiftE1rmKg != nil }
    private var consistencyAvailable: Bool { isPro }

    var body: some View {
        let visible = effective
        VStack(spacing: 0) {
            SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
            VStack(alignment: .leading, spacing: 18) {
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

                // 2 列 stat tiles — 复用 ShareStat 视觉单元, 每格 surface 底 tile.
                statGrid

                // 溯源行 — 只跟着 TL;DR 走 (数字是实时算的).
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

    // MARK: - Stat tiles

    /// 已勾选且有数据的 (value, label) — effective 已把 Pro 锁 / 没数据的项滤掉.
    private var tiles: [(value: String, label: String)] {
        let opt = effective
        var out: [(String, String)] = []
        if opt.includeVolumeDelta, let wow = stats.volumeWoWPct {
            out.append((
                "\(wow >= 0 ? "+" : "")\(wow)%",
                NSLocalizedString("vs last week", comment: "insight share stat — volume WoW")
            ))
        }
        if opt.includeWeeklyVolume, stats.weeklyVolumeKg > 0 {
            out.append((
                "\(stats.weeklyVolumeKg.formatted(.number.grouping(.automatic))) kg",
                NSLocalizedString("Volume this week", comment: "insight share stat — weekly volume")
            ))
        }
        if opt.includeTopLift, let name = stats.topLiftName, let e1rm = stats.topLiftE1rmKg {
            out.append((
                "\(e1rm) kg",
                String(format: NSLocalizedString("%@ e1RM", comment: "insight share stat — top lift estimated 1RM"), name)
            ))
        }
        if opt.includeConsistency {
            out.append((
                "\(stats.adherencePct)%",
                NSLocalizedString("Consistency", comment: "insight share stat — adherence")
            ))
        }
        return out
    }

    /// 2 列网格 — 奇数个 tile 时最后一行右格留空占位, 保持左格宽度一致.
    private var statGrid: some View {
        let t = tiles
        return VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: t.count, by: 2)), id: \.self) { i in
                HStack(spacing: 10) {
                    statTile(value: t[i].value, label: t[i].label)
                    if i + 1 < t.count {
                        statTile(value: t[i + 1].value, label: t[i + 1].label)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
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

    // MARK: - 参数勾选面板 (仅编辑模式)

    /// 每个"可用"参数一行 label + toggle — Pro 锁 (非 Pro) / 没数据的参数整行不出现
    /// (跟 UnifiedShareCard "sectionData == nil 就整节不画" 同哲学). 行 label 复用 tile 的
    /// 本地化 stat-label key, 用户勾的和卡上看到的是同一个词.
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
                    NSLocalizedString("vs last week", comment: ""),
                    isOn: binding.includeVolumeDelta
                )
            }
            if weeklyVolumeAvailable {
                optionRow(
                    NSLocalizedString("Volume this week", comment: ""),
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
