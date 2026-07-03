import SwiftUI
import UIKit

// Insights 分享卡 — AI 教练小结 + Progress→Insights 段共用的单张合并卡 (share-out P0 v2).
//
// 信息层级 (Wrapped 式: 一句判读 + 数字):
//   - (可选) 用户照片 banner (SharePhotoBanner, 分享前唯一的 customize 项)
//   - ✨ TRAINING INSIGHTS kicker (accent)
//   - hero: AI 教练 TL;DR 引言 (左侧 accent 竖条引用样式) — 只读缓存, 绝不触发 LLM;
//     没缓存 → 整块优雅退化成纯数字标题 (免费用户 / 从未生成过小结也能分享)
//   - 至多 4 个 stat tile (2×2): 周容量环比 % / 本周容量 kg / 头号动作 e1RM / 坚持度 %
//   - "As of <date>" 溯源行 (仅有 TL;DR 时 — 数字是实时算的, 不需要溯源)
//   - 品牌 footer + App Store QR (增长回路, 跟 UnifiedShareCard 同 payload)
//
// 数字全部来自 DataStore.summaryKeyStats() — 卡片从不自己算数 (AISummary.swift 规则:
// "LLM 从不自己算/编数字", 分享卡同理).
struct InsightShareCard: View {
    /// AI 教练 TL;DR (data.cachedSummary?.tldr). nil = 无缓存 → 纯数字卡, 不画引言块.
    let tldr: String?
    /// 小结缓存生成时间 — "As of <date>" 行. 仅在有 tldr 时显示.
    let generatedAt: Date?
    /// 4 个头条数字 — DataStore.summaryKeyStats(), 跟 AI 小结 payload 同源同口径.
    let stats: SummaryKeyStats
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    var body: some View {
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

                    if let tldr {
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
                        // 无缓存小结 → 纯数字标题 (stats-only 退化态; 绝不为了这张卡触发 LLM).
                        Text(NSLocalizedString("My Progress", comment: "insight share card stats-only headline"))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(MasoColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)

                // 2×2 stat tiles — 复用 ShareStat 视觉单元, 每格 surface 底 tile.
                statGrid

                // 溯源行 — 只跟着 TL;DR 走 (数字是实时算的).
                if tldr != nil, let generatedAt {
                    Text(String(
                        format: NSLocalizedString("As of %@ · based on the last 14 days", comment: "AI summary footer"),
                        Self.asOfFormatter.string(from: generatedAt)
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
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

    /// 至多 4 个 (value, label) — 没数据的 tile 整个不出现 (环比无对比 / 无负重动作时).
    private var tiles: [(value: String, label: String)] {
        var out: [(String, String)] = []
        if let wow = stats.volumeWoWPct {
            out.append((
                "\(wow >= 0 ? "+" : "")\(wow)%",
                NSLocalizedString("vs last week", comment: "insight share stat — volume WoW")
            ))
        }
        if stats.weeklyVolumeKg > 0 {
            out.append((
                "\(stats.weeklyVolumeKg.formatted(.number.grouping(.automatic))) kg",
                NSLocalizedString("Volume this week", comment: "insight share stat — weekly volume")
            ))
        }
        if let name = stats.topLiftName, let e1rm = stats.topLiftE1rmKg {
            out.append((
                "\(e1rm) kg",
                String(format: NSLocalizedString("%@ e1RM", comment: "insight share stat — top lift estimated 1RM"), name)
            ))
        }
        out.append((
            "\(stats.adherencePct)%",
            NSLocalizedString("Consistency", comment: "insight share stat — adherence")
        ))
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

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
