import SwiftUI
import Charts

/// Insights tab 的 Pro 深度分析模块 — 都从 data.sets / data.exById 现算, 零新采集.
///
/// 定位: 免费的 ProgressChartsView 给"能不能看到自己的训练"(周容量柱/本周肌群均衡/本周 delta),
/// 这里给"纵向 & 跨肌群的智能层"(逐动作 1RM / 逐肌群容量趋势 / 训练频率 / MEV·MAV 落点 /
/// PR 时间线 / 一致性 + 终身负荷) —— MARKET 里唯一"安全可收费"的部分 (智能层叠在免费数据之上).
///
/// 全部卡片沿用 ProgressChartsView.oneRMCard 的 blur+lock 模式: 真实图表渲染在底下 (看得见的钩子),
/// 非 Pro 叠 .blur(7) + .allowsHitTesting(false) + 中央解锁按钮 → onUnlock 拉付费墙.
/// isEmpty 只看"有没有数据", 不看 isPro —— 免费用户也要看到模糊卡才有升级动机.
struct InsightsChartsView: View {
    /// 显式传入 (非 @Environment) — 让调用方能在视图树外调 isEmpty 判断整块显隐.
    let data: DataStore
    /// 非 Pro 点锁 → 调用方拉付费墙.
    var onUnlock: () -> Void = {}

    // MEV/MAV 每周每肌群"硬组"科学落点 (RP / Israetel 派系常用锚): 低于 MEV = 刺激不够,
    // MEV~MAV 之间 = 有效带 (green), 超过 MAV 逼近 MRV = 可能过量. 静态阈值, 无需新数据.
    private static let mevSets = 10   // Minimum Effective Volume
    private static let mavSets = 20   // Maximum Adaptive Volume

    private struct RMPoint: Identifiable { let id = UUID(); let date: Date; let oneRM: Double }
    private struct SectionWeekVol: Identifiable { let id = UUID(); let week: Date; let section: String; let volume: Double }
    private struct FreqRow: Identifiable { let id = UUID(); let label: String; let daysPerWeek: Double }
    private struct LandmarkRow: Identifiable { let id = UUID(); let label: String; let sets: Int }
    private struct PRItem: Identifiable { let id: String; let date: Date; let exercise: String; let oneRM: Double }

    /// 整块是否没足够数据 — 有任意 weighted set 就渲染 (逐动作 1RM / 容量 / PR 都靠它).
    var isEmpty: Bool {
        !data.sets.contains { ($0.weight ?? 0) > 0 && ($0.reps ?? 0) > 0 }
            && !data.sets.contains { data.exById[$0.exerciseId]?.primaryMuscles.first?.section != nil }
    }

    /// 逐动作 1RM 卡的动作选择 — 默认头号动作 (weighted set 最多). nil = 用默认.
    @State private var pickedExerciseId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 领衔 1 — 逐动作 e1RM (泛化 Maso 已有的头号 1RM 图, 加动作 picker): 便宜 + 高感知价值.
            perLiftCard
            // 领衔 2 — MEV/MAV 落点: 市场空白, 循证人群会为它付费.
            mevMavCard
            // 逐肌群容量趋势 (最近 8 周堆叠面积).
            perMuscleVolumeCard
            // 逐肌群训练频率 (每周命中天数).
            frequencyCard
            // PR 时间线.
            prTimelineCard
            // 一致性 / 终身负荷 (两个大数字).
            consistencyCard
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

    // MARK: - 领衔 1: 逐动作 e1RM

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

    // MARK: - 领衔 2: MEV/MAV 落点

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

    // MARK: - 逐肌群容量趋势 (8 周堆叠)

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

    // MARK: - 逐肌群训练频率

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

    // MARK: - PR 时间线

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

    // MARK: - 一致性 + 终身负荷

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

    // MARK: - 数据

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
