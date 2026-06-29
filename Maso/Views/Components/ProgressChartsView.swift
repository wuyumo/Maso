import SwiftUI
import Charts

/// 进度图表 — History tab 的"看见自己变强"模块 (day-30 留存回报).
///   - 周训练容量柱状 (最近 8 周, Σ weight×reps): 直观看出"练得越来越多".
///   - 头号动作估算 1RM 折线 (Epley: w×(1+reps/30), 按天取最佳): 直观看出"力量在涨".
/// 数据不足 (各 <2 个点) 的图自动不渲染; 两图都没数据则整块为空 (调用方据 isEmpty 决定显隐).
struct ProgressChartsView: View {
    /// 显式传入 (非 @Environment) — 这样调用方能在视图树外安全调 isEmpty 判断是否整块显隐.
    let data: DataStore
    /// 非 Pro 用户点锁住的 1RM 趋势图 → 调用方拉起付费墙.
    var onUnlock: () -> Void = {}

    private struct VolPoint: Identifiable { let id = UUID(); let week: Date; let volume: Double }
    private struct RMPoint: Identifiable { let id = UUID(); let date: Date; let oneRM: Double }

    /// 整块是否没足够数据 — 调用方用来决定是否整块隐藏.
    /// 周容量 / 1RM / 肌群均衡 / 周对比 任一有数据即显示.
    var isEmpty: Bool {
        weeklyVolume().filter { $0.volume > 0 }.count < 2
            && topLiftSeries().series.count < 2
            && !weeklySetsPerSection().contains { $0.sets > 0 }
            && weekDeltas() == nil
    }

    var body: some View {
        let weekly = weeklyVolume()
        let hasVolume = weekly.filter { $0.volume > 0 }.count >= 2
        let lift = topLiftSeries()
        let deltas = weekDeltas()
        let balance = weeklySetsPerSection()

        VStack(alignment: .leading, spacing: 16) {
            // 本周 vs 上周 = 一眼"我有没有在加量" (verdict), 放最上.
            if let deltas { deltaRow(deltas) }
            if hasVolume {
                volumeCard(weekly)
            }
            if lift.series.count >= 2, let name = lift.name {
                oneRMCard(name: name, series: lift.series)
            }
            // 本周肌群均衡 — 最短的柱 = 老跳过的部位.
            if balance.contains(where: { $0.sets > 0 }) {
                muscleBalanceCard(balance)
            }
        }
    }

    // MARK: - 周容量柱状

    @ViewBuilder
    private func volumeCard(_ points: [VolPoint]) -> some View {
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
                .cornerRadius(3)
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

    // MARK: - 头号动作 1RM 趋势

    @ViewBuilder
    private func oneRMCard(name: String, series: [RMPoint]) -> some View {
        let unit = data.settings.weightUnit
        let isPro = data.settings.isPro
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(icon: "chart.line.uptrend.xyaxis",
                       title: NSLocalizedString("Estimated 1RM", comment: ""),
                       subtitle: name)
            // Pro 专属 (折中: 周容量免费, 逐动作力量趋势属"高级分析"锁 Pro). 非 Pro → 模糊预览 + 锁,
            // 点一下拉付费墙. 真实曲线仍然渲染在底下做"看得见的钩子", 解锁后立刻清晰.
            ZStack {
                oneRMChart(series: series, unit: unit)
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    // MARK: - 数据

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

    // MARK: - 本周 vs 上周

    enum WeekChange { case pct(Int); case isNew; case none }
    private struct WeekDelta { let volume: WeekChange; let sets: WeekChange }

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
        guard setsByWeek.keys.count >= 2 else { return nil }
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

    @ViewBuilder
    private func deltaRow(_ d: WeekDelta) -> some View {
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

    // MARK: - 本周肌群均衡

    private struct SectionSets: Identifiable { let id = UUID(); let label: String; let sets: Int; let isLagging: Bool }

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

    @ViewBuilder
    private func muscleBalanceCard(_ rows: [SectionSets]) -> some View {
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

/// History "Activity" section — GitHub/Duolingo 式 16 周每日训练热力图.
/// 按"组数"着色 (徒手/有氧日也会亮), 4 档 accent 透明度. 调用方据 isEmpty 决定显隐.
struct TrainingActivityHeatmap: View {
    let data: DataStore
    private let weeks = 16
    private let cellSize: CGFloat = 11
    private let gap: CGFloat = 3

    private struct DayCell: Identifiable { let id = UUID(); let date: Date; let count: Int; let future: Bool }

    /// 窗口内有训练的天数 < 2 → 调用方隐藏.
    var isEmpty: Bool { dailyCounts().values.filter { $0 > 0 }.count < 2 }

    var body: some View {
        let cols = columns()
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: gap) {
                        ForEach(col) { c in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(tierColor(c))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
            legend
        }
        .padding(14)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    private var header: some View {
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
    }

    private var legend: some View {
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

    private func tierColor(_ c: DayCell) -> Color {
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
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -(weeks * 7), to: Date()) ?? Date())
        var out: [Date: Int] = [:]
        for s in data.sets where s.performedAt >= cutoff {
            out[cal.startOfDay(for: s.performedAt), default: 0] += 1
        }
        return out
    }

    private func columns() -> [[DayCell]] {
        let cal = data.settings.calendar
        let today = cal.startOfDay(for: Date())
        let counts = dailyCounts()
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        var cols: [[DayCell]] = []
        for back in stride(from: weeks - 1, through: 0, by: -1) {
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
}
