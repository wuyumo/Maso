import SwiftUI
import Charts

/// 进度图表 — History tab 的"看见自己变强"模块 (day-30 留存回报).
///   - 周训练容量柱状 (最近 8 周, Σ weight×reps): 直观看出"练得越来越多".
///   - 头号动作估算 1RM 折线 (Epley: w×(1+reps/30), 按天取最佳): 直观看出"力量在涨".
/// 数据不足 (各 <2 个点) 的图自动不渲染; 两图都没数据则整块为空 (调用方据 isEmpty 决定显隐).
struct ProgressChartsView: View {
    /// 显式传入 (非 @Environment) — 这样调用方能在视图树外安全调 isEmpty 判断是否整块显隐.
    let data: DataStore

    private struct VolPoint: Identifiable { let id = UUID(); let week: Date; let volume: Double }
    private struct RMPoint: Identifiable { let id = UUID(); let date: Date; let oneRM: Double }

    /// 两图是否都没足够数据 — 调用方用来决定是否整块隐藏.
    var isEmpty: Bool {
        weeklyVolume().filter { $0.volume > 0 }.count < 2 && topLiftSeries().series.count < 2
    }

    var body: some View {
        let weekly = weeklyVolume()
        let hasVolume = weekly.filter { $0.volume > 0 }.count >= 2
        let lift = topLiftSeries()

        VStack(alignment: .leading, spacing: 16) {
            if hasVolume {
                volumeCard(weekly)
            }
            if lift.series.count >= 2, let name = lift.name {
                oneRMCard(name: name, series: lift.series)
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
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(icon: "chart.line.uptrend.xyaxis",
                       title: NSLocalizedString("Estimated 1RM", comment: ""),
                       subtitle: name)
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
            .frame(height: 132)
            .chartYAxis { AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
            } }
            .chartXAxis { AxisMarks { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 9)).foregroundStyle(MasoColor.textFaint)
            } }
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
}
