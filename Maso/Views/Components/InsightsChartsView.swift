import SwiftUI
import Charts
import UniformTypeIdentifiers

/// Progress → Insights 段的唯一卡片渲染器 — 把原 ProgressChartsView (免费: delta/周容量/1RM/肌群均衡)
/// + TrainingActivityHeatmap (免费: 活跃度热力图) + 本文件原有 Pro 深度分析 (逐动作 1RM / MEV·MAV /
/// 逐肌群容量 / 频率 / PR 时间线 / 一致性) 全部拍平成一个 InsightCard 枚举驱动的有序列表.
///
/// 用户可长按任意卡拎起、拖动重排 (免费用户也能重排 Pro 模糊卡), 落定即持久化到
/// settings.insightCardOrder. 渲染顺序 = settings.resolvedInsightOrder (免费在前, Pro 沉底; 新卡向前兼容),
/// 每张卡再经 hasData(_:) 守卫 (没数据的卡直接跳过).
///
/// Pro 卡沿用 oneRMCard 的 blur+lock 模式: 真实图表渲染在底下 (看得见的钩子), 非 Pro 叠 .blur(7) +
/// .allowsHitTesting(false) + 中央解锁按钮 → onUnlock 拉付费墙. isEmpty 只看"有没有数据", 不看 isPro.
///
/// 全部指标从 data.sets / data.exById 现算, 零新采集.
struct InsightsChartsView: View {
    /// 显式传入 (非 @Environment) — 让调用方能在视图树外调 isEmpty 判断整块显隐.
    let data: DataStore
    /// 非 Pro 点锁 → 调用方拉付费墙.
    var onUnlock: () -> Void = {}
    /// AI 小结卡"Apply"一条建议 → 调用方 (HistoryScreen) 接管 Pro gate + 路由/写 note + toast.
    var onApplySummary: (AISummaryAction) -> Void = { _ in }

    // MEV/MAV 每周每肌群"硬组"科学落点 (RP / Israetel 派系常用锚): 低于 MEV = 刺激不够,
    // MEV~MAV 之间 = 有效带 (green), 超过 MAV 逼近 MRV = 可能过量. 静态阈值, 无需新数据.
    private static let mevSets = 10   // Minimum Effective Volume
    private static let mavSets = 20   // Maximum Adaptive Volume

    private struct VolPoint: Identifiable { let id = UUID(); let week: Date; let volume: Double }
    private struct RMPoint: Identifiable { let id = UUID(); let date: Date; let oneRM: Double }
    private struct SectionWeekVol: Identifiable { let id = UUID(); let week: Date; let section: String; let volume: Double }
    private struct FreqRow: Identifiable { let id = UUID(); let label: String; let daysPerWeek: Double }
    private struct LandmarkRow: Identifiable { let id = UUID(); let label: String; let sets: Int }
    private struct PRItem: Identifiable { let id: String; let date: Date; let exercise: String; let oneRM: Double }

    /// 逐动作 1RM 卡的动作选择 — 默认头号动作 (weighted set 最多). nil = 用默认.
    @State private var pickedExerciseId: String? = nil
    /// 拖拽重排时被拎起的卡 — 只用来算 move 的 target index (放在 @State 让 drop 时读得到).
    @State private var draggingCard: InsightCard? = nil

    // MARK: - 整块空判断

    /// 整块是否没足够数据 — 任一 InsightCard 有数据即非空. 调用方 (HistoryScreen) 用它决定 Insights 段显隐.
    var isEmpty: Bool {
        !InsightCard.allCases.contains { hasData($0) }
    }

    /// 当前会真正渲染的卡 (已解析顺序 + 数据守卫过滤). body 与 HistoryScreen 的提示判断共用.
    var visibleCards: [InsightCard] {
        data.settings.resolvedInsightOrder.filter { hasData($0) }
    }

    // MARK: - body: 可拖拽重排列表

    var body: some View {
        let cards = visibleCards
        VStack(alignment: .leading, spacing: 16) {
            // AI 教练小结 — 固定钉在最顶, 非 reorderable (不进 InsightCard/resolvedInsightOrder,
            // 不碰下方拖拽重排数学). 见 docs/ai-insight-summary-design.md §1.
            AISummaryCard(data: data, onUnlock: onUnlock, onApply: onApplySummary)
            // 一行低调提示 (仅在有 ≥2 张卡时出现, 单卡没得排). 长按拎起 → 拖动重排.
            if cards.count >= 2 {
                Text(NSLocalizedString("Long-press a card to reorder", comment: "insights reorder hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
                    .padding(.horizontal, 4)
            }
            ForEach(cards) { id in
                card(id)
                    // iOS 18 原生 draggable/dropDestination — 在 ScrollView 里长按才拎起 (不劫持垂直滚动).
                    // payload 携带 rawValue; drop 时按目标卡 index 做 move 数学.
                    .draggable(id.rawValue) {
                        // 拖拽预览 — 缩小的卡快照, 拎起瞬间置 draggingCard.
                        card(id)
                            .frame(width: 280)
                            .opacity(0.9)
                            .onAppear { draggingCard = id }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first,
                              let dropped = InsightCard(rawValue: raw) else { return false }
                        moveCard(dropped, before: id)
                        return true
                    } isTargeted: { _ in }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: data.settings.insightCardOrder)
        }
    }

    /// 把 dropped 卡移到 target 卡之前 (拖到某卡上方插到它前面). 落定即持久化.
    private func moveCard(_ dropped: InsightCard, before target: InsightCard) {
        guard dropped != target else { return }
        // 以当前"完整解析顺序"为基准做 move (非仅 visible, 保持隐藏卡相对位置稳定).
        var full = data.settings.resolvedInsightOrder
        guard let from = full.firstIndex(of: dropped),
              let to = full.firstIndex(of: target) else { return }
        full.remove(at: from)
        // 移除后 target 可能位移, 重新定位插到它前面.
        let insertAt = full.firstIndex(of: target) ?? to
        full.insert(dropped, at: insertAt)
        data.settings.insightCardOrder = full.map(\.rawValue)
        data.save()   // 落库 (debounced; scenePhase→background 也有 flushSave 兜底)
        draggingCard = nil
        Haptics.tap()
    }

    // MARK: - 卡分发

    /// 按 id 渲染单张卡 — 各卡自带数据守卫 (无数据返回 EmptyView, 但外层已用 hasData 过滤).
    @ViewBuilder
    func card(_ id: InsightCard) -> some View {
        switch id {
        case .delta:           deltaCardOrEmpty
        case .volume:          volumeCardOrEmpty
        case .muscleBalance:   muscleBalanceCardOrEmpty
        case .heatmap:         heatmapCard
        case .oneRM:           oneRMCardOrEmpty
        case .perLift:         perLiftCard
        case .mevMav:          mevMavCard
        case .perMuscleVolume: perMuscleVolumeCard
        case .frequency:       frequencyCard
        case .prTimeline:      prTimelineCard
        case .consistency:     consistencyCard
        }
    }

    /// 单张卡是否有数据 — 决定渲不渲 (跟各卡内部守卫同口径).
    func hasData(_ id: InsightCard) -> Bool {
        switch id {
        case .delta:           return weekDeltas() != nil
        case .volume:          return weeklyVolume().filter { $0.volume > 0 }.count >= 1
        case .muscleBalance:   return weeklySetsPerSection().contains { $0.sets > 0 }
        case .heatmap:         return dailyCounts().values.filter { $0 > 0 }.count >= 1
        case .oneRM:           return topLiftSeries().series.count >= 1
        case .perLift:         return !weightedLifts().isEmpty
        case .mevMav:          return weeklyLandmarkRows().contains { $0.sets > 0 }
        case .perMuscleVolume: return !perMuscleWeeklyVolume().isEmpty
        case .frequency:       return trainingFrequencyRows().contains { $0.daysPerWeek > 0 }
        case .prTimeline:      return !prTimeline().isEmpty
        case .consistency:     return allTimeTonnage() > 0
        }
    }

    // MARK: - 共享卡壳 (blur + lock)

    /// 通用 Pro 卡壳 — header + 真实内容, 非 Pro 叠模糊 + 中央解锁按钮 (复刻 oneRMCard 模式).
    @ViewBuilder
    private func proCard<Content: View>(
        icon: String, title: String, subtitle: String, height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isPro = data.settings.isPro
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(icon: icon, title: title, subtitle: subtitle)
            ZStack {
                content()
                    .blur(radius: isPro ? 0 : 7)
                    .allowsHitTesting(isPro)
                if !isPro {
                    Button(action: onUnlock) {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold))
                            Text(NSLocalizedString("Unlock deep insights with Pro", comment: "insights paywall"))
                                .font(.system(size: 12, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(MasoColor.text)
                        .padding(.horizontal, 16).padding(.vertical, 12)   // 隐形点击区; 背景去掉, 直接落在模糊图表上
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: height)
        }
        .padding(14)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    private func cardHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MasoColor.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - 免费卡①: 本周 vs 上周 (原 ProgressChartsView.deltaRow)

    enum WeekChange { case pct(Int); case isNew; case none }
    private struct WeekDelta { let volume: WeekChange; let sets: WeekChange }

    @ViewBuilder
    private var deltaCardOrEmpty: some View {
        if let d = weekDeltas() {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(icon: "arrow.up.arrow.down",
                           title: NSLocalizedString("This week vs last", comment: "week-over-week comparison"),
                           subtitle: NSLocalizedString("so far", comment: "current week is incomplete"))
                HStack(spacing: 10) {
                    deltaTile(label: NSLocalizedString("Volume", comment: "training volume"), change: d.volume)
                    deltaTile(label: NSLocalizedString("Sets", comment: "set count"), change: d.sets)
                }
            }
            .padding(14)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
    }

    private func deltaTile(label: String, change: WeekChange) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                switch change {
                case .pct(let p):
                    Image(systemName: p > 0 ? "arrow.up.right" : (p < 0 ? "arrow.down.right" : "minus"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(p > 0 ? MasoColor.accent : MasoColor.textDim)
                    Text("\(abs(p))%")
                        .font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(p > 0 ? MasoColor.accent : MasoColor.text)
                case .isNew:
                    Text(NSLocalizedString("NEW", comment: "first week of data"))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                case .none:
                    Text("—")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(MasoColor.textDim)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(MasoColor.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusSmall))
    }

    // MARK: - 免费卡②: 周训练容量柱状 (原 ProgressChartsView.volumeCard)

    @ViewBuilder
    private var volumeCardOrEmpty: some View {
        let points = weeklyVolume()
        if points.filter({ $0.volume > 0 }).count >= 1 {
            let unit = data.settings.weightUnit
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(icon: "chart.bar.fill",
                           title: NSLocalizedString("Weekly volume", comment: ""),
                           subtitle: String(format: NSLocalizedString("Total %@ lifted per week", comment: ""), unit.label))
                Chart(points) { p in
                    BarMark(
                        x: .value("Week", p.week, unit: .weekOfYear),
                        y: .value("Volume", unit.fromKg(p.volume))
                    )
                    .foregroundStyle(MasoColor.accent.gradient)
                    // clipShape 上下四角全圆 (.cornerRadius 只圆离基线远的一端, 柱底仍是直角).
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 132)
                .chartYAxis { AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                        .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
            }
            .padding(14)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
    }

    // MARK: - Pro 卡: 头号动作 1RM 趋势 (原 ProgressChartsView.oneRMCard — Pro)

    @ViewBuilder
    private var oneRMCardOrEmpty: some View {
        let lift = topLiftSeries()
        if lift.series.count >= 1, let name = lift.name {
            let unit = data.settings.weightUnit
            let isPro = data.settings.isPro
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(icon: "chart.line.uptrend.xyaxis",
                           title: NSLocalizedString("Estimated 1RM", comment: ""),
                           subtitle: name)
                // Pro 专属. 非 Pro → 模糊预览 + 锁, 点一下拉付费墙. 真实曲线仍渲染在底下做钩子.
                ZStack {
                    oneRMChart(series: lift.series, unit: unit)
                        .blur(radius: isPro ? 0 : 7)
                        .allowsHitTesting(isPro)
                    if !isPro {
                        Button(action: onUnlock) {
                            VStack(spacing: 6) {
                                Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold))
                                Text(NSLocalizedString("Unlock strength trends with Pro", comment: ""))
                                    .font(.system(size: 12, weight: .semibold))
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(MasoColor.text)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 132)
            }
            .padding(14)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
    }

    /// 1RM 折线本体 — 抽出来好让 oneRMCard 在非 Pro 时叠模糊 + 锁层.
    private func oneRMChart(series: [RMPoint], unit: WeightUnit) -> some View {
        Chart(series) { p in
            LineMark(
                x: .value("Date", p.date, unit: .day),
                y: .value("1RM", unit.fromKg(p.oneRM))
            )
            .foregroundStyle(MasoColor.accent)
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Date", p.date, unit: .day),
                y: .value("1RM", unit.fromKg(p.oneRM))
            )
            .foregroundStyle(MasoColor.accent)
            .symbolSize(28)
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in
            AxisGridLine().foregroundStyle(MasoColor.borderSoft)
            AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
        } }
        .chartXAxis { AxisMarks { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
        } }
    }

    // MARK: - 免费卡③: 本周肌群均衡 (原 ProgressChartsView.muscleBalanceCard)

    private struct SectionSets: Identifiable { let id = UUID(); let label: String; let sets: Int; let isLagging: Bool }

    @ViewBuilder
    private var muscleBalanceCardOrEmpty: some View {
        let rows = weeklySetsPerSection()
        if rows.contains(where: { $0.sets > 0 }) {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(icon: "figure.strengthtraining.traditional",
                           title: NSLocalizedString("Muscle balance", comment: "sets per muscle group"),
                           subtitle: NSLocalizedString("Sets this week", comment: ""))
                Chart(rows) { r in
                    BarMark(
                        x: .value("Sets", r.sets),
                        y: .value("Region", r.label)
                    )
                    .foregroundStyle(r.isLagging ? MasoColor.accent.opacity(0.4) : MasoColor.accent)
                    .cornerRadius(3)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(r.sets)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                // 保持降序 (最高在上). domain 倒序 → rows[0] 落在顶部.
                .chartYScale(domain: rows.map(\.label).reversed())
                .frame(height: CGFloat(rows.count) * 22 + 6)
            }
            .padding(14)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
    }

    // MARK: - 免费卡④: 训练活跃度热力图 (原 TrainingActivityHeatmap)

    private struct DayCell: Identifiable { let id = UUID(); let date: Date; let count: Int; let future: Bool }
    private let heatmapWeeks = 16
    private let heatmapCellSize: CGFloat = 11
    private let heatmapGap: CGFloat = 3

    @ViewBuilder
    private var heatmapCard: some View {
        let cols = heatmapColumns()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(MasoColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Training activity", comment: "history heatmap title"))
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(MasoColor.text)
                    Text(NSLocalizedString("Last 16 weeks", comment: ""))
                        .font(.system(size: 11)).foregroundStyle(MasoColor.textDim)
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: heatmapGap) {
                ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: heatmapGap) {
                        ForEach(col) { c in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(heatmapTierColor(c))
                                .frame(width: heatmapCellSize, height: heatmapCellSize)
                        }
                    }
                }
            }
            heatmapLegend
        }
        .padding(14)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    private var heatmapLegend: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("Less", comment: "heatmap legend"))
                .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
            ForEach([MasoColor.surfaceHi, MasoColor.accent.opacity(0.3),
                     MasoColor.accent.opacity(0.6), MasoColor.accent], id: \.self) { c in
                RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            }
            Text(NSLocalizedString("More", comment: "heatmap legend"))
                .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
        }
    }

    private func heatmapTierColor(_ c: DayCell) -> Color {
        if c.future { return MasoColor.surfaceHi.opacity(0.35) }
        switch c.count {
        case 0: return MasoColor.surfaceHi
        case 1...5: return MasoColor.accent.opacity(0.3)
        case 6...12: return MasoColor.accent.opacity(0.6)
        default: return MasoColor.accent
        }
    }

    private func dailyCounts() -> [Date: Int] {
        let cal = data.settings.calendar
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -(heatmapWeeks * 7), to: Date()) ?? Date())
        var out: [Date: Int] = [:]
        for s in data.sets where s.performedAt >= cutoff {
            out[cal.startOfDay(for: s.performedAt), default: 0] += 1
        }
        return out
    }

    private func heatmapColumns() -> [[DayCell]] {
        let cal = data.settings.calendar
        let today = cal.startOfDay(for: Date())
        let counts = dailyCounts()
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        var cols: [[DayCell]] = []
        for back in stride(from: heatmapWeeks - 1, through: 0, by: -1) {
            guard let colStart = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeekStart) else { continue }
            var col: [DayCell] = []
            for d in 0..<7 {
                let day = cal.startOfDay(for: cal.date(byAdding: .day, value: d, to: colStart) ?? colStart)
                col.append(DayCell(date: day, count: counts[day] ?? 0, future: day > today))
            }
            cols.append(col)
        }
        return cols
    }

    // MARK: - Pro 领衔①: 逐动作 e1RM

    /// 逐动作 e1RM — 头部一个动作 picker (weighted set 数排序), 选中动作按天最佳 e1RM 折线.
    @ViewBuilder
    private var perLiftCard: some View {
        let unit = data.settings.weightUnit
        let lifts = weightedLifts()
        let selectedId = pickedExerciseId ?? lifts.first?.id
        let series = selectedId.map { e1rmSeries(forExerciseId: $0) } ?? []
        let name = selectedId.flatMap { id in lifts.first { $0.id == id }?.name } ?? ""
        if !lifts.isEmpty {
            let isPro = data.settings.isPro
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(icon: "chart.line.uptrend.xyaxis",
                           title: NSLocalizedString("Strength by lift", comment: "per-lift e1RM title"),
                           subtitle: NSLocalizedString("Estimated 1RM over time", comment: ""))
                // 动作 picker — Pro 可交互切换; 非 Pro 也显示 (被下面模糊层盖住).
                if lifts.count > 1 {
                    Picker(NSLocalizedString("Lift", comment: "exercise picker label"),
                           selection: Binding(get: { selectedId ?? "" }, set: { pickedExerciseId = $0 })) {
                        ForEach(lifts) { lift in Text(lift.name).tag(lift.id) }
                    }
                    .pickerStyle(.menu)
                    .tint(MasoColor.accent)
                    .disabled(!isPro)
                    .font(.system(size: 12, weight: .semibold))
                }
                ZStack {
                    e1rmChart(series: series, unit: unit)
                        .blur(radius: isPro ? 0 : 7)
                        .allowsHitTesting(isPro)
                    if !isPro {
                        Button(action: onUnlock) {
                            VStack(spacing: 6) {
                                Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold))
                                Text(NSLocalizedString("Unlock strength trends with Pro", comment: ""))
                                    .font(.system(size: 12, weight: .semibold))
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundStyle(MasoColor.text)
                            .padding(.horizontal, 16).padding(.vertical, 12)   // 隐形点击区; 背景去掉, 直接落在模糊图表上
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 132)
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
            }
            .padding(14)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
    }

    private func e1rmChart(series: [RMPoint], unit: WeightUnit) -> some View {
        Chart(series) { p in
            LineMark(x: .value("Date", p.date, unit: .day), y: .value("1RM", unit.fromKg(p.oneRM)))
                .foregroundStyle(MasoColor.accent)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", p.date, unit: .day), y: .value("1RM", unit.fromKg(p.oneRM)))
                .foregroundStyle(MasoColor.accent)
                .symbolSize(28)
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in
            AxisGridLine().foregroundStyle(MasoColor.borderSoft)
            AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
        } }
        .chartXAxis { AxisMarks { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
        } }
    }

    // MARK: - Pro 领衔②: MEV/MAV 落点

    /// 本周每大肌群硬组数 vs MEV(~10)/MAV(~20) 有效带 — 绿=有效带内, 暗=不足, 边框=偏高.
    @ViewBuilder
    private var mevMavCard: some View {
        let rows = weeklyLandmarkRows()
        if rows.contains(where: { $0.sets > 0 }) {
            proCard(icon: "target",
                    title: NSLocalizedString("Sets vs targets", comment: "MEV/MAV title"),
                    subtitle: NSLocalizedString("Weekly hard sets per muscle", comment: "MEV/MAV subtitle"),
                    height: CGFloat(rows.count) * 26 + 20) {
                Chart {
                    // MEV / MAV 参考线 (有效带边界).
                    RuleMark(x: .value("MEV", Self.mevSets))
                        .foregroundStyle(MasoColor.textFaint.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .center) {
                            Text(NSLocalizedString("MEV", comment: "min effective volume"))
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(MasoColor.textFaint)
                        }
                    RuleMark(x: .value("MAV", Self.mavSets))
                        .foregroundStyle(MasoColor.textFaint.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .center) {
                            Text(NSLocalizedString("MAV", comment: "max adaptive volume"))
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(MasoColor.textFaint)
                        }
                    ForEach(rows) { r in
                        BarMark(x: .value("Sets", r.sets), y: .value("Region", r.label))
                            .foregroundStyle(landmarkColor(r.sets))
                            .cornerRadius(3)
                            .annotation(position: .trailing, alignment: .leading) {
                                Text("\(r.sets)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(MasoColor.textFaint)
                            }
                    }
                }
                .chartXScale(domain: 0...max(Self.mavSets + 4, (rows.map(\.sets).max() ?? 0) + 2))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(MasoColor.textDim)
                    }
                }
                .chartYScale(domain: rows.map(\.label).reversed())
            }
        }
    }

    /// MEV/MAV 着色: 不足=暗绿, 有效带=亮绿, 偏高=橙.
    private func landmarkColor(_ sets: Int) -> Color {
        if sets < Self.mevSets { return MasoColor.accent.opacity(0.35) }
        if sets <= Self.mavSets { return MasoColor.accent }
        return Color(red: 1.0, green: 0.6, blue: 0.2)
    }

    // MARK: - Pro: 逐肌群容量趋势 (8 周堆叠)

    @ViewBuilder
    private var perMuscleVolumeCard: some View {
        let unit = data.settings.weightUnit
        let points = perMuscleWeeklyVolume()
        if !points.isEmpty {
            proCard(icon: "chart.bar.doc.horizontal",
                    title: NSLocalizedString("Volume by muscle", comment: "per-muscle volume title"),
                    subtitle: String(format: NSLocalizedString("Weekly %@ per muscle", comment: ""), unit.label),
                    height: 150) {
                Chart(points) { p in
                    BarMark(
                        x: .value("Week", p.week, unit: .weekOfYear),
                        y: .value("Volume", unit.fromKg(p.volume))
                    )
                    .foregroundStyle(by: .value("Muscle", p.section))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale(range: sectionPalette())
                .chartLegend(position: .bottom, spacing: 6)
                .chartYAxis { AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
                } }
            }
        }
    }

    // MARK: - Pro: 逐肌群训练频率

    @ViewBuilder
    private var frequencyCard: some View {
        let rows = trainingFrequencyRows()
        if rows.contains(where: { $0.daysPerWeek > 0 }) {
            proCard(icon: "calendar.badge.clock",
                    title: NSLocalizedString("Training frequency", comment: "frequency title"),
                    subtitle: NSLocalizedString("Days per week per muscle", comment: "frequency subtitle"),
                    height: CGFloat(rows.count) * 24 + 10) {
                Chart(rows) { r in
                    BarMark(x: .value("Days", r.daysPerWeek), y: .value("Region", r.label))
                        .foregroundStyle(MasoColor.accent)
                        .cornerRadius(3)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(String(format: "%.1f×", r.daysPerWeek))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MasoColor.textFaint)
                        }
                }
                .chartXScale(domain: 0...max(3.5, (rows.map(\.daysPerWeek).max() ?? 0) + 0.6))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(MasoColor.textDim)
                    }
                }
                .chartYScale(domain: rows.map(\.label).reversed())
            }
        }
    }

    // MARK: - Pro: PR 时间线

    @ViewBuilder
    private var prTimelineCard: some View {
        let prs = prTimeline()
        if !prs.isEmpty {
            proCard(icon: "trophy.fill",
                    title: NSLocalizedString("PR timeline", comment: "PR timeline title"),
                    subtitle: NSLocalizedString("Your personal records", comment: "PR timeline subtitle"),
                    height: CGFloat(min(prs.count, 6)) * 34 + 4) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(prs.prefix(6)) { pr in
                        HStack(spacing: 10) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(MasoColor.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pr.exercise)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(MasoColor.text)
                                    .lineLimit(1)
                                Text(pr.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .font(.system(size: 10))
                                    .foregroundStyle(MasoColor.textDim)
                            }
                            Spacer()
                            Text(weightLabel(pr.oneRM))
                                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                                .foregroundStyle(MasoColor.accent)
                        }
                        .frame(height: 34)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Pro: 一致性 + 终身负荷

    @ViewBuilder
    private var consistencyCard: some View {
        let score = consistencyScore()
        let tonnage = allTimeTonnage()
        if tonnage > 0 {
            proCard(icon: "flame.fill",
                    title: NSLocalizedString("Consistency & load", comment: "consistency title"),
                    subtitle: NSLocalizedString("All-time", comment: "consistency subtitle"),
                    height: 76) {
                HStack(spacing: 10) {
                    bigStatTile(
                        value: "\(score)%",
                        label: NSLocalizedString("Adherence", comment: "adherence stat")
                    )
                    bigStatTile(
                        value: compactWeight(tonnage),
                        label: NSLocalizedString("Total lifted", comment: "lifetime tonnage stat")
                    )
                }
            }
        }
    }

    private func bigStatTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(MasoColor.accent)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label))
                .font(.system(size: 9, weight: .semibold)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MasoColor.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusSmall))
    }

    // MARK: - 数据 (免费卡)

    /// 最近 8 周的训练容量 (Σ weight×reps, kg). 缺的周补 0 → 柱形连续.
    private func weeklyVolume() -> [VolPoint] {
        let cal = data.settings.calendar
        var byWeek: [Date: Double] = [:]
        for s in data.sets {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.performedAt)
            guard let weekStart = cal.date(from: comps) else { continue }
            byWeek[weekStart, default: 0] += w * Double(r)
        }
        let now = Date()
        let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        var out: [VolPoint] = []
        for back in stride(from: 7, through: 0, by: -1) {
            guard let wk = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { continue }
            out.append(VolPoint(week: wk, volume: byWeek[wk] ?? 0))
        }
        return out
    }

    /// 训练 set 数最多的力量动作 + 其按天最佳估算 1RM 序列 (Epley).
    private func topLiftSeries() -> (name: String?, series: [RMPoint]) {
        var countByEx: [String: Int] = [:]
        for s in data.sets where (s.weight ?? 0) > 0 && (s.reps ?? 0) > 0 {
            countByEx[s.exerciseId, default: 0] += 1
        }
        guard let topId = countByEx.max(by: { $0.value < $1.value })?.key else { return (nil, []) }
        let name = data.exById[topId]?.name
            ?? data.sets.first { $0.exerciseId == topId }?.exerciseName
        let cal = Calendar.current
        var bestByDay: [Date: Double] = [:]
        for s in data.sets where s.exerciseId == topId {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            let e1rm = w * (1 + Double(r) / 30)
            let day = cal.startOfDay(for: s.performedAt)
            bestByDay[day] = max(bestByDay[day] ?? 0, e1rm)
        }
        let series = bestByDay.sorted { $0.key < $1.key }.map { RMPoint(date: $0.key, oneRM: $0.value) }
        return (name, series)
    }

    /// 本周 vs 上一完整周的 容量% + 组数% 变化. <2 周有数据 → nil (新用户不显示).
    private func weekDeltas() -> WeekDelta? {
        let cal = data.settings.calendar
        var volByWeek: [Date: Double] = [:]
        var setsByWeek: [Date: Int] = [:]
        for s in data.sets {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.performedAt)
            guard let wk = cal.date(from: comps) else { continue }
            setsByWeek[wk, default: 0] += 1
            if let w = s.weight, let r = s.reps, w > 0, r > 0 { volByWeek[wk, default: 0] += w * Double(r) }
        }
        guard setsByWeek.keys.count >= 1 else { return nil }
        let now = Date()
        guard let thisWk = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let lastWk = cal.date(byAdding: .weekOfYear, value: -1, to: thisWk) else { return nil }
        func change(_ cur: Double, _ prev: Double) -> WeekChange {
            if prev > 0 { return .pct(Int(((cur - prev) / prev * 100).rounded())) }
            if cur > 0 { return .isNew }
            return .none
        }
        return WeekDelta(
            volume: change(volByWeek[thisWk] ?? 0, volByWeek[lastWk] ?? 0),
            sets: change(Double(setsByWeek[thisWk] ?? 0), Double(setsByWeek[lastWk] ?? 0))
        )
    }

    /// 近 7 天各大肌群 (按主肌) 组数, 降序. 含 0 的部位也返回 (让"跳过腿"看得见).
    private func weeklySetsPerSection() -> [SectionSets] {
        let cal = data.settings.calendar
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        var tally: [MuscleGroup: Int] = [:]
        for s in data.sets where s.performedAt >= cutoff {
            guard let ex = data.exById[s.exerciseId],
                  let sec = ex.primaryMuscles.first?.section else { continue }
            tally[sec, default: 0] += 1
        }
        let order: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]
        let counts = order.map { tally[$0] ?? 0 }
        let maxC = counts.max() ?? 0
        let minC = counts.min() ?? 0
        var rows = order.enumerated().map { i, sec in
            SectionSets(label: sec.displayName,
                        sets: counts[i],
                        isLagging: maxC > 0 && counts[i] == minC && minC < maxC)
        }
        rows.sort { $0.sets > $1.sets }
        return rows
    }

    // MARK: - 数据 (Pro 卡)

    private struct Lift: Identifiable { let id: String; let name: String; let count: Int }

    /// 有 weighted set 的动作, 按 set 数降序 (给 picker 用).
    private func weightedLifts() -> [Lift] {
        var countByEx: [String: Int] = [:]
        for s in data.sets where (s.weight ?? 0) > 0 && (s.reps ?? 0) > 0 {
            countByEx[s.exerciseId, default: 0] += 1
        }
        return countByEx
            .sorted { $0.value > $1.value }
            .map { id, c in
                let name = data.exById[id]?.name
                    ?? data.sets.first { $0.exerciseId == id }?.exerciseName
                    ?? id
                return Lift(id: id, name: name, count: c)
            }
    }

    /// 某动作按天最佳估算 1RM (Epley) 序列.
    private func e1rmSeries(forExerciseId id: String) -> [RMPoint] {
        let cal = Calendar.current
        var bestByDay: [Date: Double] = [:]
        for s in data.sets where s.exerciseId == id {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            let e1rm = w * (1 + Double(r) / 30)
            let day = cal.startOfDay(for: s.performedAt)
            bestByDay[day] = max(bestByDay[day] ?? 0, e1rm)
        }
        return bestByDay.sorted { $0.key < $1.key }.map { RMPoint(date: $0.key, oneRM: $0.value) }
    }

    private let sectionOrder: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]

    /// 本周 (近 7 天) 每大肌群硬组数 (weighted set = 一个硬组代理), 按 section 顺序.
    private func weeklyLandmarkRows() -> [LandmarkRow] {
        let cal = data.settings.calendar
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        var tally: [MuscleGroup: Int] = [:]
        for s in data.sets where s.performedAt >= cutoff {
            guard let ex = data.exById[s.exerciseId],
                  let sec = ex.primaryMuscles.first?.section else { continue }
            tally[sec, default: 0] += 1
        }
        return sectionOrder.map { LandmarkRow(label: $0.displayName, sets: tally[$0] ?? 0) }
    }

    /// 最近 8 周逐大肌群周容量 (Σ weight×reps, kg). 缺的 (周,肌群) 不补 → 图表自然跳过.
    private func perMuscleWeeklyVolume() -> [SectionWeekVol] {
        let cal = data.settings.calendar
        let now = Date()
        guard let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return [] }
        guard let cutoff = cal.date(byAdding: .weekOfYear, value: -7, to: thisWeek) else { return [] }
        var byKey: [String: (week: Date, section: MuscleGroup, vol: Double)] = [:]
        for s in data.sets {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            guard s.performedAt >= cutoff else { continue }
            guard let ex = data.exById[s.exerciseId],
                  let sec = ex.primaryMuscles.first?.section else { continue }
            guard let wk = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.performedAt)) else { continue }
            let key = "\(wk.timeIntervalSince1970)-\(sec.rawValue)"
            let prev = byKey[key]?.vol ?? 0
            byKey[key] = (wk, sec, prev + w * Double(r))
        }
        return byKey.values
            .map { SectionWeekVol(week: $0.week, section: $0.section.displayName, volume: $0.vol) }
            .sorted { $0.week < $1.week }
    }

    /// section 调色 — 跟 perMuscleVolumeCard 的 domain (section.displayName) 对齐.
    private func sectionPalette() -> [Color] {
        [
            Color(red: 1.0, green: 0.42, blue: 0.42),   // chest 暖红
            Color(red: 0.42, green: 0.78, blue: 1.0),   // back 蓝
            Color(red: 1.0, green: 0.75, blue: 0.20),   // shoulders 黄橙
            Color(red: 0.78, green: 0.55, blue: 1.0),   // arms 紫
            Color(red: 1.0, green: 0.55, blue: 0.85),   // core 粉
            Color(red: 0.20, green: 0.82, blue: 0.62)   // legs 绿松
        ]
    }

    /// 逐大肌群训练频率 — 最近 4 周平均每周命中天数.
    private func trainingFrequencyRows() -> [FreqRow] {
        let cal = data.settings.calendar
        let weeks = 4.0
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -27, to: Date()) ?? Date())
        // 每 section → 命中的不同日期集合.
        var daysBySection: [MuscleGroup: Set<Date>] = [:]
        for s in data.sets where s.performedAt >= cutoff {
            guard let ex = data.exById[s.exerciseId] else { continue }
            let day = cal.startOfDay(for: s.performedAt)
            var seen = Set<MuscleGroup>()
            for m in ex.muscleGroups {
                guard let sec = m.section, seen.insert(sec).inserted else { continue }
                daysBySection[sec, default: []].insert(day)
            }
        }
        return sectionOrder.map { sec in
            let days = Double(daysBySection[sec]?.count ?? 0)
            return FreqRow(label: sec.displayName, daysPerWeek: (days / weeks * 10).rounded() / 10)
        }
    }

    /// PR 时间线 — 所有 isPR 的记录, 按时间倒序, 每条动作名 + 该次 e1RM.
    private func prTimeline() -> [PRItem] {
        data.sets
            .filter { data.isPR($0) }
            .compactMap { rec -> PRItem? in
                guard let w = rec.weight, w > 0, let r = rec.reps, r > 0 else { return nil }
                let e1rm = w * (1 + Double(r) / 30)
                let name = data.exById[rec.exerciseId]?.displayName ?? rec.exerciseName
                return PRItem(id: rec.id, date: rec.performedAt, exercise: name, oneRM: e1rm)
            }
            .sorted { $0.date > $1.date }
    }

    /// 一致性 / 依从分 — 最近 8 周里"达标周"占比 (每周训练天数 ≥ weeklyTrainingDays goal). 0..100.
    private func consistencyScore() -> Int {
        let cal = data.settings.calendar
        let goal = max(1, data.settings.weeklyTrainingDays)
        var days: Set<Date> = []
        for s in data.sets { days.insert(cal.startOfDay(for: s.performedAt)) }
        guard let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return 0 }
        func trainedDays(inWeekStarting weekStart: Date) -> Int {
            let weekDays: Set<Date> = Set((0..<7).compactMap {
                cal.date(byAdding: .day, value: $0, to: weekStart).map { cal.startOfDay(for: $0) }
            })
            return days.intersection(weekDays).count
        }
        var hit = 0
        var considered = 0
        for back in 0..<8 {
            guard let wkStart = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { continue }
            // 只统计"已经开始训练之后"的周 — 空白的很早周不该拉低分.
            let td = trainedDays(inWeekStarting: wkStart)
            if td > 0 || back == 0 { considered += 1 }
            if td >= goal { hit += 1 }
        }
        guard considered > 0 else { return 0 }
        return Int((Double(hit) / Double(considered) * 100).rounded())
    }

    /// 终身累计负荷 (Σ weight×reps, kg).
    private func allTimeTonnage() -> Double {
        data.sets.reduce(0) { acc, s in
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { return acc }
            return acc + w * Double(r)
        }
    }

    /// 大数字用的紧凑重量 (含单位, k 缩写). 终身负荷动辄几十万 kg, 全展开太长.
    private func compactWeight(_ kg: Double) -> String {
        let unit = data.settings.weightUnit
        let v = unit.fromKg(kg)
        if v >= 1000 {
            return String(format: "%.1fk %@", v / 1000, unit.label)
        }
        return String(format: "%.0f %@", v, unit.label)
    }
}
