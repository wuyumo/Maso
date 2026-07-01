import Foundation

/// Progress → Insights 段的全部卡片, 拍平成一个有序、可拖拽重排、可持久化的模型.
///
/// 每张卡一个稳定 rawValue (落进 UserSettings.insightCardOrder, 别改已发布的值否则老用户排序丢).
/// isPro 标记免费/Pro (Pro 卡在 UI 里模糊+锁, 但一样能被拖动重排).
/// canonicalOrder = 默认顺序: 4 张免费卡在前, 7 张 Pro 卡沉底 (修掉旧版 1RM Pro 卡混在免费卡中间的问题).
///
/// 数据守卫仍由 InsightsChartsView.hasData(_:) 逐卡把关 — 没数据的卡直接跳过 (不渲染, 不占位).
enum InsightCard: String, CaseIterable, Identifiable {
    // 免费 4 张 (原 ProgressChartsView + TrainingActivityHeatmap)
    case delta          // 本周 vs 上周
    case volume         // 周训练容量
    case muscleBalance  // 本周肌群均衡
    case heatmap        // 训练活跃度热力图

    // Pro 7 张 (原 InsightsChartsView + 1RM 从免费块挪来)
    case oneRM          // 头号动作估算 1RM 趋势 (曾在 ProgressChartsView, 是 Pro)
    case perLift        // 逐动作 e1RM
    case mevMav         // MEV/MAV 落点
    case perMuscleVolume // 逐肌群容量趋势
    case frequency      // 逐肌群训练频率
    case prTimeline     // PR 时间线
    case consistency    // 一致性 + 终身负荷

    var id: String { rawValue }

    /// Pro 专属卡 — UI 模糊+锁 (非 Pro), 但排序不受限.
    var isPro: Bool {
        switch self {
        case .delta, .volume, .muscleBalance, .heatmap:
            return false
        case .oneRM, .perLift, .mevMav, .perMuscleVolume, .frequency, .prTimeline, .consistency:
            return true
        }
    }

    /// 默认顺序 — 免费在前, Pro 沉底. 空持久化 / 新增 case 补位都以它为准.
    static let canonicalOrder: [InsightCard] = [
        // 免费
        .delta, .volume, .muscleBalance, .heatmap,
        // Pro
        .oneRM, .perLift, .mevMav, .perMuscleVolume, .frequency, .prTimeline, .consistency,
    ]
}

extension UserSettings {
    /// 解析出最终渲染顺序:
    ///   1. 持久化 insightCardOrder 里"仍存在的 case"按存的顺序 (丢弃已删除/未知 rawValue).
    ///   2. 任何不在持久化里的 case (= 本版新增卡) 按 canonicalOrder 追加到末尾 → 向前兼容.
    ///   3. 持久化为空 → 直接 canonicalOrder.
    /// 注意: 只决定"顺序", 不管数据有没有 (数据守卫在 InsightsChartsView.hasData 里, 空卡跳过).
    var resolvedInsightOrder: [InsightCard] {
        let saved = insightCardOrder.compactMap { InsightCard(rawValue: $0) }
        let seen = Set(saved)
        let missing = InsightCard.canonicalOrder.filter { !seen.contains($0) }
        let out = saved + missing
        return out.isEmpty ? InsightCard.canonicalOrder : out
    }
}
