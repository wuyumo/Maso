import SwiftUI

// 训练日历 — 从 History 顶部"训练日志"入口拉起的 sheet.
// 一个月的 grid 视图, 有训练的日期用绿色实心圆背景 + 黑色数字标出.
// 顶部左右切换月份, 当月数据回滚成一个 "5×7 grid" (最多 6 行).
//
// 接受预先 startOfDay-normalize 过的 Set<Date> — caller (HistoryScreen) 从 data.sets 直接 derive.
struct WorkoutCalendarScreen: View {
    let sessionDates: Set<Date>
    /// 给 share card 用的本周总组数 (caller 算后传入). 0 = 不算.
    var totalSetsThisWeek: Int = 0
    /// 连续训练天数 (相对今天). 0 = 没连击. 由 caller 算好传入, share card 用.
    var streakDaysCount: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var data
    @State private var monthAnchor: Date = Calendar.current.startOfMonth(for: Date())

    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                weekdayHeader
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.bottom, 4)

                monthGrid
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                Spacer()

                statsRow
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.bottom, 28)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Workout calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 分享本周训练频率 — 生成 UnifiedShareCard (calendar section default on).
                    // 三个 section data 始终算好传入; toggle 状态由卡内 inline toggle / ShareCardMode 控制.
                    let workoutData = mostRecentWorkoutSection()
                    let muscleData = muscleStatusSection()
                    let calendarData = CalendarSectionData(
                        sessionDates: sessionDates,
                        totalSets: totalSetsThisWeek,
                        streakDays: streakDaysCount
                    )
                    ShareImageButton(
                        previewTitle: NSLocalizedString("My Week", comment: ""),
                        defaultSections: ShareSections(calendar: true),
                        shareContent: { photo, onTapAdd, mode in
                            switch mode {
                            case .editing(let binding):
                                UnifiedShareCard(
                                    userPhoto: photo,
                                    onTapAddPhoto: onTapAdd,
                                    workoutSection: workoutData,
                                    muscleStatusSection: muscleData,
                                    calendarSection: calendarData,
                                    editToggles: binding
                                )
                            case .rendering(let visible):
                                UnifiedShareCard(
                                    userPhoto: photo,
                                    onTapAddPhoto: onTapAdd,
                                    workoutSection: workoutData,
                                    muscleStatusSection: muscleData,
                                    calendarSection: calendarData,
                                    visibleSections: visible
                                )
                            }
                        },
                        label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MasoColor.text)
                                .frame(width: 30, height: 30)
                                .background(MasoColor.surfaceHi)
                                .clipShape(Circle())
                        }
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
    }

    // MARK: - 月份切换 header

    @ViewBuilder
    private var monthHeader: some View {
        HStack {
            Button(action: { shiftMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 36, height: 36)
                    .background(MasoColor.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthLabel)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(MasoColor.text)

            Spacer()

            Button(action: { shiftMonth(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isFutureMonth ? MasoColor.textFaint : MasoColor.text)
                    .frame(width: 36, height: 36)
                    .background(MasoColor.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFutureMonth)
            .accessibilityLabel("Next month")
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: monthAnchor)
    }

    private var isFutureMonth: Bool {
        // 不允许翻到比当月还未来的月份 (没意义, 没数据)
        let curMonth = calendar.startOfMonth(for: Date())
        return monthAnchor >= curMonth
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = calendar.startOfMonth(for: next)
        }
    }

    // MARK: - 星期表头 ("Mon Tue Wed ...", 跟系统 locale 走)

    @ViewBuilder
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdaySymbol(i))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(MasoColor.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 按 calendar.firstWeekday 渲染表头 ("Mon Tue..." 或 "Sun Mon..." 跟系统 locale)
    private func weekdaySymbol(_ i: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        let veryShort = f.veryShortStandaloneWeekdaySymbols ?? f.veryShortWeekdaySymbols ?? []
        // veryShort 是 Sun..Sat 顺序; 旋转到 calendar.firstWeekday
        let idx = (calendar.firstWeekday - 1 + i) % 7
        return idx < veryShort.count ? veryShort[idx] : ""
    }

    // MARK: - Grid (7 列 × N 行)

    @ViewBuilder
    private var monthGrid: some View {
        let cells = makeMonthCells()
        VStack(spacing: 6) {
            ForEach(0..<cells.count/7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let cell = cells[row*7 + col]
                        dayCell(cell)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCell) -> some View {
        switch cell {
        case .empty:
            Color.clear.frame(height: 44)
        case .day(let date, let inMonth):
            let isWorkout = sessionDates.contains(date)
            let isToday = date == today
            ZStack {
                if isWorkout {
                    Circle().fill(MasoColor.accent)
                } else if isToday {
                    Circle().stroke(MasoColor.accent.opacity(0.5), lineWidth: 0.5)
                }
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isWorkout ? .heavy : .semibold))
                    .foregroundStyle(
                        isWorkout ? .black
                        : (!inMonth ? MasoColor.textFaint
                           : (isToday ? MasoColor.accent : MasoColor.text))
                    )
            }
            .frame(width: 34, height: 34)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
    }

    private enum DayCell {
        case empty
        case day(Date, inMonth: Bool)
    }

    /// 生成 6 行 × 7 列 = 42 cell, 包含前缀 padding + 月内日期 + 后缀 padding
    private func makeMonthCells() -> [DayCell] {
        let first = monthAnchor
        let weekdayOfFirst = calendar.component(.weekday, from: first)
        // 前缀 padding: first 是该周第几个 (0..6)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let range = calendar.range(of: .day, in: .month, for: first) ?? 1..<2
        let dayCount = range.count
        var cells: [DayCell] = Array(repeating: .empty, count: leading)
        for d in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: d, to: first) {
                cells.append(.day(calendar.startOfDay(for: date), inMonth: true))
            }
        }
        // 后缀 — 填到 42
        while cells.count < 42 {
            cells.append(.empty)
        }
        // 如果最后一行全是 empty, 砍掉这一行 (避免空 5 行视觉浪费)
        if cells.count >= 42, cells[35..<42].allSatisfy({ if case .empty = $0 { return true } else { return false } }) {
            cells = Array(cells[0..<35])
        }
        if cells.count >= 35, cells[28..<35].allSatisfy({ if case .empty = $0 { return true } else { return false } }) {
            cells = Array(cells[0..<28])
        }
        return cells
    }

    // MARK: - 月底 stats — 本月训练几天 + 当前连续天数

    @ViewBuilder
    private var statsRow: some View {
        let monthDates = sessionDates.filter { calendar.isDate($0, equalTo: monthAnchor, toGranularity: .month) }
        let streak = currentStreak()
        HStack(spacing: 24) {
            statColumn(value: "\(monthDates.count)", label: "Days this month")
            Rectangle().fill(MasoColor.borderSoft).frame(width: 0.5, height: 32)
            statColumn(value: "\(streak)", label: "Current streak")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            // value 是 "12" / "3 days" 这类纯数据, 不走 i18n.
            // label 是 "Days this month" / "Current streak" — 走 LocalizedStringKey 查表.
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(MasoColor.accent)
            Text(LocalizedStringKey(label))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
        }
    }

    /// 当前连续训练天数 — 从今天往回数, 直到中断
    private func currentStreak() -> Int {
        var n = 0
        var cursor = today
        while sessionDates.contains(cursor) {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: prev)
        }
        return n
    }

    // MARK: - Share section data (UnifiedShareCard)

    /// 最近一次 session 的 WorkoutSectionData — 让 calendar 入口可以也启用 workout section.
    /// 没有任何 session → 返回 nil.
    fileprivate func mostRecentWorkoutSection() -> WorkoutSectionData? {
        let cal = calendar
        // 把 sets 聚合成 (planId, day) → 取最近的一组
        struct Key: Hashable { let planId: String; let day: Date }
        var bucket: [Key: [SetRecord]] = [:]
        for rec in data.sets {
            let day = cal.startOfDay(for: rec.performedAt)
            let key = Key(planId: rec.planId ?? "free", day: day)
            bucket[key, default: []].append(rec)
        }
        guard let (key, recs) = bucket.max(by: {
            let a = $0.value.map { $0.performedAt }.max() ?? Date.distantPast
            let b = $1.value.map { $0.performedAt }.max() ?? Date.distantPast
            return a < b
        }) else { return nil }

        let planName: String = {
            if key.planId == "free" { return NSLocalizedString("Free workout", comment: "") }
            return data.plans.first(where: { $0.id == key.planId })?.name
                ?? NSLocalizedString("Free workout", comment: "")
        }()
        var seenMuscles = Set<MuscleGroup>()
        var muscles: [MuscleGroup] = []
        var seenIds = Set<String>()
        var names: [String] = []
        for r in recs {
            guard let ex = data.exById[r.exerciseId] else { continue }
            if seenIds.insert(ex.id).inserted { names.append(ex.displayName) }
            for m in ex.muscleGroups where seenMuscles.insert(m).inserted {
                muscles.append(m)
            }
        }
        let prCount = recs.reduce(0) { $0 + (data.isPR($1) ? 1 : 0) }
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return WorkoutSectionData(
            dateLabel: df.string(from: key.day),
            planName: planName,
            durationLabel: "~\(max(5, recs.count * 2))m",
            setCount: recs.count,
            exerciseCount: seenIds.count,
            prCount: prCount,
            muscles: muscles,
            exerciseNames: names
        )
    }

    /// 本周肌肉状态 — 用 DataStore 全局衰减 mapping.
    fileprivate func muscleStatusSection() -> MuscleStatusSectionData {
        let lastMap = muscleLastTrainedMap()
        let cal = calendar
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)

        let workoutsThisWeek = Set(data.sets.filter { $0.performedAt >= cutoff }
            .map { cal.startOfDay(for: $0.performedAt) }).count
        let totalSets = data.sets.filter { $0.performedAt >= cutoff }.count
        var sections = Set<MuscleGroup>()
        for set in data.sets where set.performedAt >= cutoff {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let s = m.section { sections.insert(s) }
            }
        }
        return MuscleStatusSectionData(
            muscleOpacity: { m in shareOpacityFor(muscle: m, lastMap: lastMap) },
            coarseOnly: !data.settings.muscleDetailEnabled,
            workoutsThisWeek: workoutsThisWeek,
            totalSetsThisWeek: totalSets,
            muscleSectionsHit: sections.count
        )
    }

    private func muscleLastTrainedMap() -> [MuscleGroup: Date] {
        var map: [MuscleGroup: Date] = [:]
        for s in data.sets {
            guard let ex = data.exById[s.exerciseId] else { continue }
            let expanded = expandAnatomyMuscles(ex.muscleGroups)
            for m in expanded {
                if let prev = map[m], prev > s.performedAt { continue }
                map[m] = s.performedAt
            }
        }
        return map
    }

    private func shareOpacityFor(muscle m: MuscleGroup, lastMap: [MuscleGroup: Date]) -> Double? {
        guard let last = lastMap[m] else { return nil }
        let days = Date().timeIntervalSince(last) / 86400
        if days < 1 { return 1.0 }
        if days < 2 { return 0.6 }
        if days < 3 { return 0.3 }
        return nil
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

#Preview {
    WorkoutCalendarScreen(sessionDates: [
        Calendar.current.startOfDay(for: Date()),
        Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400)),
        Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400 * 3)),
        Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400 * 6)),
    ])
    .environment(DataStore.makeMock())
}
