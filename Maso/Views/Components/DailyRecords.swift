import SwiftUI

/// All calendar navigation uses calendar days (including DST and the user's week start).
enum DailyRecordCalendar {
    static func start(_ date: Date, monthly: Bool, calendar: Calendar) -> Date {
        calendar.dateInterval(of: monthly ? .month : .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
    static func days(_ date: Date, monthly: Bool, calendar: Calendar) -> [Date] {
        let period = start(date, monthly: monthly, calendar: calendar)
        let first = monthly ? start(period, monthly: false, calendar: calendar) : period
        let count = monthly ? 42 : 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }
    /// Preserve weekday columns and page height, but never expose adjacent-month dates.
    static func cells(_ date: Date, monthly: Bool, calendar: Calendar) -> [Date?] {
        return days(date, monthly: monthly, calendar: calendar).map { day in
            !monthly || calendar.isDate(day, equalTo: date, toGranularity: .month) ? day : nil
        }
    }
    static func shifted(_ date: Date, by value: Int, monthly: Bool, calendar: Calendar) -> Date {
        calendar.date(byAdding: monthly ? .month : .weekOfYear, value: value,
                      to: start(date, monthly: monthly, calendar: calendar)) ?? date
    }
}

/// A page keeps its identity when its week expands into a month. Browsing focus
/// is independent from today's data refresh and is never reset by sheet dismissal.
struct DailyCalendarNavigation {
    struct Page: Identifiable, Equatable {
        let id: UUID
        var focus: Date
    }
    private(set) var expanded = false
    private(set) var pages: [Page]
    private(set) var visibleID: UUID
    private(set) var revision = 0
    var focus: Date { pages.first { $0.id == visibleID }!.focus }

    init(now: Date, calendar: Calendar) {
        pages = (0..<13).reversed().map { offset in
            Page(id: UUID(), focus: calendar.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now)
        }
        visibleID = pages.last!.id
    }
    mutating func toggle(calendar: Calendar, now: Date) {
        let selectedIndex = pages.firstIndex { $0.id == visibleID }!
        let selectedFocus = focus
        expanded.toggle()
        revision += 1
        let latest = DailyRecordCalendar.start(now, monthly: expanded, calendar: calendar)
        pages = pages.enumerated().compactMap { index, page in
            let candidate = calendar.date(byAdding: expanded ? .month : .weekOfYear,
                                          value: index - selectedIndex, to: selectedFocus) ?? selectedFocus
            guard DailyRecordCalendar.start(candidate, monthly: expanded, calendar: calendar) <= latest else { return nil }
            return Page(id: page.id, focus: min(candidate, now))
        }
        appendThroughToday(calendar: calendar, now: now)
        loadOlderIfNeeded(calendar: calendar)
    }
    mutating func select(_ id: UUID, calendar: Calendar) {
        guard pages.contains(where: { $0.id == id }) else { return }
        visibleID = id
        loadOlderIfNeeded(calendar: calendar)
    }
    mutating func move(_ offset: Int, calendar: Calendar) {
        guard let index = pages.firstIndex(where: { $0.id == visibleID }),
              pages.indices.contains(index + offset) else { return }
        revision += 1
        select(pages[index + offset].id, calendar: calendar)
    }
    mutating func showToday(calendar: Calendar, now: Date) {
        let current = DailyRecordCalendar.start(now, monthly: expanded, calendar: calendar)
        appendThroughToday(calendar: calendar, now: now)
        guard let index = pages.firstIndex(where: {
            DailyRecordCalendar.start($0.focus, monthly: expanded, calendar: calendar) == current
        }) else { return }
        pages[index].focus = now
        visibleID = pages[index].id
        revision += 1
    }
    private mutating func appendThroughToday(calendar: Calendar, now: Date) {
        let current = DailyRecordCalendar.start(now, monthly: expanded, calendar: calendar)
        while let last = pages.last, DailyRecordCalendar.start(last.focus, monthly: expanded, calendar: calendar) < current {
            guard let next = calendar.date(byAdding: expanded ? .month : .weekOfYear, value: 1, to: last.focus) else { break }
            pages.append(Page(id: UUID(), focus: min(next, now)))
        }
    }
    private mutating func loadOlderIfNeeded(calendar: Calendar) {
        guard let index = pages.firstIndex(where: { $0.id == visibleID }), index < 2, let first = pages.first else { return }
        let older = (1...12).reversed().compactMap { offset -> Page? in
            guard let date = calendar.date(byAdding: expanded ? .month : .weekOfYear, value: -offset, to: first.focus) else { return nil }
            return Page(id: UUID(), focus: date)
        }
        pages.insert(contentsOf: older, at: 0)
    }
}

struct RecordDate: Identifiable {
    let date: Date
    var id: Date { date }
}

extension DataStore {
    var recordedSleepStages: [Date: SleepStagesRecord] {
        var result: [Date: SleepStagesRecord] = [:]
        for (key, value) in settings.sleepStageRecords ?? [:] {
            if let date = WellnessInsightsSnapshot.date(key, calendar: settings.calendar) {
                result[settings.calendar.startOfDay(for: date)] = value
            }
        }
        for (date, value) in HealthKitService.shared.sleepStages {
            result[settings.calendar.startOfDay(for: date)] = value
        }
        return result
    }

    func savedWellnessGoal(on day: Date) -> DailyWellnessGoal? {
        settings.wellnessGoals?[SleepPreferences.dayKey(day, calendar: settings.calendar)]
    }
    func savedSleepTarget(on day: Date) -> Int? {
        let key = SleepPreferences.dayKey(day, calendar: settings.calendar)
        let target = settings.sleepPreferences?.recordedGoals[key] ?? savedWellnessGoal(on: day)?.sleepMinutes
        return target.flatMap { $0 > 0 ? $0 : nil }
    }
    func dailyRecordSnapshots(now: Date = Date(), usesSavedTargetOnly: Bool = false) -> [PerformanceCalendarSnapshot] {
        var recordedSettings = settings
        recordedSettings.mealCheckIns = settings.mealCheckIns?.filter { $0.day <= now && $0.confirmedAt <= now && $0.mealTime <= now }
        var snapshots: [PerformanceCalendarSnapshot] = [
            .workout(recordedWorkoutDates(now: now), calendar: settings.calendar),
            .lifestyle(kind: .diet, settings: recordedSettings),
            .lifestyle(kind: .sleep, settings: recordedSettings, healthSleep: HealthKitService.shared.sleepMinutes)
        ]
        if let index = snapshots.firstIndex(where: { $0.kind == .diet }) {
            let days = Dictionary(grouping: recordedSettings.mealCheckIns ?? []) { settings.calendar.startOfDay(for: $0.day) }
            snapshots[index].dietCalorieFractions = days.reduce(into: [:]) { values, item in
                let goal = usesSavedTargetOnly ? savedWellnessGoal(on: item.key) : wellnessGoal(on: item.key)
                values[item.key] = DietEnergyProgress.calculate(goal: goal, meals: item.value).fraction
            }
        }
        guard usesSavedTargetOnly else { return snapshots }
        return snapshots.map { snapshot in
            guard snapshot.kind != .workout else { return snapshot }
            return .init(kind: snapshot.kind,
                         progress: snapshot.progress.filter { snapshot.savedTargetDays.contains($0.key) },
                         savedTargetDays: snapshot.savedTargetDays,
                         dietCalorieFractions: snapshot.dietCalorieFractions.filter { snapshot.savedTargetDays.contains($0.key) })
        }
    }
}

struct DailyOverviewCard: View {
    @Environment(DataStore.self) private var data
    @Environment(\.scenePhase) private var scenePhase
    let onReplay: (Plan) -> Void
    @State private var calendarNavigation = DailyCalendarNavigation(now: Date(), calendar: .current)
    @State private var mealToRecord: DietMeal?
    @State private var selectedDay: DayRoute?
    @State private var rules = false
    @State private var shareRhythm = false
    @State private var now = Date()
    private var calendar: Calendar { data.settings.calendar }
    private var today: Date { calendar.startOfDay(for: now) }

    var body: some View {
        // `now` anchors calendar browsing; it must not exclude meals saved after this card appeared.
        let snapshots = data.dailyRecordSnapshots()
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                entrance(.workout, color: MasoColor.accent, destination: .insights, value: weeklyProgress, percent: nil)
                if data.settings.dietEnabled != false || data.settings.sleepEnabled != false {
                    Divider()
                    HStack(alignment: .top, spacing: 16) {
                        if data.settings.dietEnabled != false {
                            entrance(.diet, color: MasoColor.dietAccent, destination: .diet, value: calorieProgress, percent: dietEnergy.fraction)
                        }
                        if data.settings.dietEnabled != false && data.settings.sleepEnabled != false {
                            Rectangle().fill(MasoColor.borderSoft).frame(width: 1)
                        }
                        if data.settings.sleepEnabled != false {
                            entrance(.sleep, color: MasoColor.sleepAccent, destination: .sleep, value: lastNightMinutes.map { compactSleepDuration($0) } ?? "—", percent: snapshots.first { $0.kind == .sleep }?.progress[today])
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            DailyRecordCalendarView(navigation: $calendarNavigation, calendar: calendar, now: now, snapshots: snapshots,
                                    onSelect: { selectedDay = DayRoute(day: calendar.startOfDay(for: $0)) },
                                    onShowRules: { rules = true },
                                    onShareRhythm: { shareRhythm = true })
        }
        .padding(MasoMetrics.cardPadding)
        .contentCardChrome(padding: 0)
        .navigationDestination(item: $selectedDay) { route in
            DailyRecordSheet(day: route.day, onReplay: { plan in
                selectedDay = nil
                onReplay(plan)
            }, pushed: true)
        }
        .sheet(isPresented: $rules) { DailyCalendarRulesSheet() }
        .sheet(isPresented: $shareRhythm) {
            let savedSnapshots = data.dailyRecordSnapshots(now: now, usesSavedTargetOnly: true)
            let models: [AccomplishmentCard.Model] = [false, true].map { monthly in
                let base = AccomplishmentShare.rhythm(sets: data.sets, focus: calendarNavigation.focus,
                    monthly: monthly, calendar: calendar, now: now)
                let sleep = base.days.reduce(into: [Date: Double]()) { values, day in
                    values[day.date] = HealthKitService.shared.sleepMinutes[day.date]
                        ?? data.settings.sleepRecords?[SleepPreferences.dayKey(day.date, calendar: calendar)]
                }
                return .rhythm(AccomplishmentShare.rhythm(sets: data.sets, focus: calendarNavigation.focus,
                    monthly: monthly, calendar: calendar, now: now,
                    diet: savedSnapshots.first { $0.kind == .diet }?.dietCalorieFractions ?? [:],
                    sleep: sleep, sleepProgress: savedSnapshots.first { $0.kind == .sleep }?.progress ?? [:]))
            }
            AccomplishmentShareSheet(title: "Share", model: { _ in models[calendarNavigation.expanded ? 1 : 0] },
                allowsPhoto: false, rhythmModels: models, initialMonthly: calendarNavigation.expanded)
        }
        .sheet(item: $mealToRecord) { meal in
            MealEditorSheet(meal: meal, image: nil)
        }
        .task {
            now = Date()
            data.captureWellnessGoal()
            try? await data.refreshSleepSummary()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task { data.captureWellnessGoal(); try? await data.refreshSleepSummary() }
        }
    }

    private var weeklyProgress: String {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let count = data.recordedWorkoutDates(now: now).filter { day in
            week.map { day >= $0.start && day < $0.end } ?? false
        }.count
        return "\(count)/\(max(1, min(7, data.settings.weeklyTrainingDays)))"
    }
    private var dietEnergy: DietEnergyProgress {
        let current = Date()
        let meals = data.wellnessMeals(on: current).filter { $0.confirmedAt <= current && $0.mealTime <= current }
        return DietEnergyProgress.calculate(goal: data.wellnessGoal(on: current), meals: meals)
    }
    private var calorieProgress: String {
        let energy = dietEnergy
        let actual = CalorieEstimateText.number(energy.actual)
        return actual + (energy.target.map { " / " + CalorieEstimateText.number($0) } ?? "") + " kcal"
    }
    private var lastNightMinutes: Double? {
        HealthKitService.shared.sleepMinutes[today] ?? data.settings.sleepRecords?[SleepPreferences.dayKey(today, calendar: calendar)]
    }
    private var singleWellnessMetric: Bool {
        (data.settings.dietEnabled != false) != (data.settings.sleepEnabled != false)
    }
    @ViewBuilder private func entrance(_ metric: OverviewMetric, color: Color, destination: AppDestination,
                          value: String, percent: Double?) -> some View {
        if metric == .workout {
            NavigationLink(value: destination) {
                entranceContent(metric, color: color, destination: destination, value: value, percent: percent)
            }.buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
                NavigationLink(value: destination) {
                    HStack(spacing: 6) {
                        OverviewMetricIcon(metric: metric, color: color, glyphScale: 0.9)
                        Text(LocalizedStringKey(metric.title)).foregroundStyle(MasoColor.text)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.font(.headline).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(value: destination) {
                            VStack(alignment: .leading, spacing: 4) {
                                Group {
                                    if singleWellnessMetric {
                                        ProgressFractionText(
                                            numerator: metric == .diet ? CalorieEstimateText.number(dietEnergy.actual) : value,
                                            denominator: metric == .diet
                                                ? dietEnergy.target.map { CalorieEstimateText.number($0) }
                                                : data.savedSleepTarget(on: today).map { compactSleepDuration(Double($0)) },
                                            suffix: metric == .diet ? " kcal" : "",
                                            numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim
                                        )
                                        .font(.title2.weight(.semibold))
                                    } else if metric == .diet {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: CalorieEstimateText.number(dietEnergy.actual))
                                                .foregroundStyle(dietEnergy.actual == nil ? MasoColor.textDim : MasoColor.text)
                                            Text(verbatim: (dietEnergy.target.map { "/ " + CalorieEstimateText.number($0) } ?? "—") + " kcal")
                                                .font(.caption.weight(.regular)).foregroundStyle(MasoColor.textDim)
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(Text(verbatim: calorieProgress))
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: value)
                                            Text(verbatim: "0 kcal")
                                                .font(.caption.weight(.regular))
                                                .hidden().accessibilityHidden(true)
                                        }
                                    }
                                }.font(.title3.weight(.semibold)).foregroundStyle(MasoColor.text)
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                    .accessibilityIdentifier(metric == .diet ? "home.diet.calories" : "home.sleep.value")
                                Text(LocalizedStringKey(metric == .diet ? "Today" : "Last night"))
                                    .font(.caption2).foregroundStyle(MasoColor.textDim)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if metric == .diet {
                        Button { mealToRecord = DietMeal(id: UUID().uuidString, title: "Meal", portions: []) } label: {
                            OverviewCompletionRing(fraction: percent, accent: DietProgressColor.color(for: percent), showsAdd: true)
                                .accessibilityIdentifier("home.diet.progress")
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Add meal")
                        .accessibilityValue(Text(verbatim: percent.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }.map {
                            $0.formatted(.percent.precision(.fractionLength(0)).locale(LanguageManager.currentLocale))
                        } ?? "—"))
                        .accessibilityIdentifier("home.add-meal")
                    } else {
                        NavigationLink(value: destination) {
                            OverviewCompletionRing(fraction: percent, accent: color)
                                .accessibilityIdentifier("home.sleep.progress")
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.vertical, 4)
        }
    }

    private func entranceContent(_ metric: OverviewMetric, color: Color, destination: AppDestination,
                                 value: String, percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
            HStack(spacing: 6) {
                OverviewMetricIcon(metric: metric, color: color, glyphScale: 0.9)
                Text(LocalizedStringKey(metric.title)).foregroundStyle(MasoColor.text)
                Spacer(minLength: 4)
            }.font(.headline)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    TargetValueLabel(value: value, unit: "")
                    Text("This week").font(.subheadline).foregroundStyle(MasoColor.textDim)
                }
                Spacer(minLength: 8)
                WorkoutInsightsPreview(data: data, now: now)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 4).contentShape(Rectangle())
    }

}

/// Same thickness token as the Home and Widget calendar rings.
struct OverviewProgressTrack: View {
    let fraction: Double?
    let accent: Color
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(MasoColor.surfaceHi)
                .overlay(alignment: .leading) {
                    if let fraction, fraction.isFinite, fraction > 0 {
                        Capsule().fill(accent).frame(width: proxy.size.width * min(1, fraction))
                    }
                }
        }.frame(height: OverviewProgressMetrics.thickness).accessibilityHidden(true)
    }
}

/// The ring is capped at one revolution; the label preserves the actual percentage.
private struct OverviewCompletionRing: View {
    let fraction: Double?
    let accent: Color
    var showsAdd = false
    private var validFraction: Double? { fraction.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
    private var percentage: String {
        validFraction.map { ($0 * 100).formatted(.number.precision(.fractionLength(0)).locale(LanguageManager.currentLocale)) } ?? "—"
    }
    var body: some View {
        ZStack {
            Circle().stroke(MasoColor.surfaceHi, lineWidth: OverviewProgressMetrics.thickness)
            if let fraction = validFraction, fraction > 0 {
                Circle().trim(from: 0, to: min(1, fraction))
                    .stroke(accent, style: StrokeStyle(lineWidth: OverviewProgressMetrics.thickness, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                if showsAdd {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(accent)
                }
                Text(verbatim: percentage)
                    .font(.system(size: showsAdd ? 9 : 11, weight: .semibold))
                    .foregroundStyle(MasoColor.text).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }.padding(4)
        }
        .frame(width: 40, height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: validFraction.map {
            $0.formatted(.percent.precision(.fractionLength(0)).locale(LanguageManager.currentLocale))
        } ?? "—"))
    }
}

/// One native pager and one row hierarchy in both modes. Only additional week
/// rows are inserted/removed; the displayed week and viewport IDs remain stable.
struct DailyRecordCalendarView: View {
    @Binding var navigation: DailyCalendarNavigation
    let calendar: Calendar
    let now: Date
    let snapshots: [PerformanceCalendarSnapshot]
    let onSelect: (Date) -> Void
    let onShowRules: () -> Void
    var onShareRhythm: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragRevision: Int?
    @ScaledMetric(relativeTo: .callout) private var dateNumberSize: CGFloat = 14
    private var today: Date { calendar.startOfDay(for: now) }
    private var start: Date { DailyRecordCalendar.start(navigation.focus, monthly: navigation.expanded, calendar: calendar) }
    private var title: String {
        if navigation.expanded { return navigation.focus.formatted(.dateTime.year().month(.wide).locale(LanguageManager.currentLocale)) }
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return start.formatted(.dateTime.month(.abbreviated).day().locale(LanguageManager.currentLocale)) + " – " + end.formatted(.dateTime.month(.abbreviated).day().locale(LanguageManager.currentLocale))
    }
    private var pagePosition: Binding<UUID?> {
        Binding(get: { navigation.visibleID }, set: { id in
            // Layout changes must not masquerade as a user changing the date range.
            guard dragRevision == navigation.revision, let id else { return }
            navigation.select(id, calendar: calendar)
        })
    }
    var body: some View {
        VStack(spacing: 16) {
            header
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(navigation.pages) { page in
                        calendarPage(page.focus)
                            .containerRelativeFrame(.horizontal)
                            .id(page.id)
                    }
                }.scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .scrollPosition(id: pagePosition)
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { dragRevision = navigation.revision }
            }
            .frame(height: navigation.expanded ? 402 : 82)
            .clipped()
            .onAppear { dragRevision = nil }
            .onDisappear { dragRevision = nil }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1), value: navigation.expanded)
    }
    private func calendarPage(_ focus: Date) -> some View {
        let pageDays = DailyRecordCalendar.days(focus, monthly: navigation.expanded, calendar: calendar)
        let weeks = stride(from: 0, to: pageDays.count, by: 7).map { Array(pageDays[$0..<($0 + 7)]) }
        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(pageDays[index].formatted(.dateTime.weekday(.abbreviated).locale(LanguageManager.currentLocale)))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 12) {
                ForEach(weeks, id: \.first!) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            Group {
                                if !navigation.expanded || calendar.isDate(day, equalTo: focus, toGranularity: .month) {
                                    dateCell(day, snapshots: snapshots)
                                } else { Color.clear.frame(height: 52).accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity)
                        }
                    }.transition(.opacity)
                }
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }
    private func animate(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1)) { action() }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { animate { navigation.toggle(calendar: calendar, now: now) } } label: {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Image(systemName: navigation.expanded ? "chevron.up" : "chevron.down").font(.caption)
                }
            }.tint(MasoColor.text)
                .accessibilityIdentifier("home.calendar.toggle")
                .accessibilityLabel(Text(LocalizedStringKey(navigation.expanded ? "Week" : "Month")))
                .accessibilityValue(title)
            Spacer(minLength: 0)
            if !calendar.isDate(navigation.focus, equalTo: now, toGranularity: navigation.expanded ? .month : .weekOfYear) {
                Button("Today") { animate { navigation.showToday(calendar: calendar, now: now) } }
                    .font(.caption).tint(MasoColor.text)
            }
            Menu {
                Button { dragRevision = nil; onShowRules() } label: {
                    Label("Goal & color rules", systemImage: "info.circle")
                }
                Button { dragRevision = nil; onShareRhythm() } label: {
                    Label(LocalizedStringKey(navigation.expanded ? "Share this month" : "Share this week"), systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("calendar.share.rhythm")
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .tint(MasoColor.textDim.opacity(0.7))
            .accessibilityLabel("More")
            .accessibilityIdentifier("home.calendar.more")
        }.buttonStyle(.borderless)
            .accessibilityAction(named: Text("Previous")) { animate { navigation.move(-1, calendar: calendar) } }
            .accessibilityAction(named: Text("Next")) { animate { navigation.move(1, calendar: calendar) } }
    }
    private func dateCell(_ day: Date, snapshots: [PerformanceCalendarSnapshot]) -> some View {
        let future = day > today
        let isToday = calendar.isDate(day, inSameDayAs: today)
        return Button { dragRevision = nil; onSelect(day) } label: {
            ZStack {
                DailyDateProgressRing(progress: [PerformanceCalendarSnapshot.Kind.workout, .diet, .sleep].map { kind in
                    future ? nil : snapshots.first { $0.kind == kind }?.progress[calendar.startOfDay(for: day)]
                }, dietCalorieFraction: future ? nil : snapshots.first { $0.kind == .diet }?.dietCalorieFractions[calendar.startOfDay(for: day)])
                .padding(2)
                Text(calendar.component(.day, from: day).formatted(.number.locale(LanguageManager.currentLocale)))
                    .font(.system(size: dateNumberSize, weight: isToday ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(future ? MasoColor.textFaint : MasoColor.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 7)
            }.frame(maxWidth: 44).frame(height: 44)
                .background {
                    if isToday { Circle().fill(OverviewPalette.calendarToday) }
                }
            .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(future)
        .accessibilityIdentifier(isToday ? "home.calendar.today" : "home.calendar.day")
        .foregroundStyle(future ? MasoColor.textFaint : MasoColor.text)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(LanguageManager.currentLocale)))
        .accessibilityValue(snapshots.map { snapshot in
            let name = NSLocalizedString(snapshot.kind == .workout ? "Workout" : snapshot.kind == .diet ? "Diet" : "Sleep", comment: "")
            let value = snapshot.progress[calendar.startOfDay(for: day)]
            return name + ": " + (value.map { "\(Int($0 * 100))%" } ?? NSLocalizedString("No data", comment: ""))
        }.joined(separator: ", "))
    }


}


/// Workout at top, Diet lower-left, Sleep lower-right. Missing data has only a track.
private struct DailyDateProgressRing: View {
    let progress: [Double?]
    let dietCalorieFraction: Double?
    private let accents = [MasoColor.accent, MasoColor.dietAccent, MasoColor.sleepAccent]
    var body: some View {
        DailyProgressRing(progress: progress, colors: accents, dietCalorieFraction: dietCalorieFraction)
    }
}

private struct DayRoute: Hashable, Identifiable {
    let day: Date
    var id: Date { day }
}

private struct DaySessionRoute: Hashable, Identifiable {
    let session: SessionSummary
    var id: String { session.id }
}

struct DailyRecordSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var training
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let onReplay: (Plan) -> Void
    /// Pushed onto the app navigation stack. Standalone hosts keep their own stack.
    var pushed = false
    @State private var showsShare = false
    @State private var selectedSession: DaySessionRoute?
    @State private var selectedExercise: Exercise?
    private var calendar: Calendar { data.settings.calendar }
    var body: some View {
        if pushed { page } else { AppNavigationStack { page } }
    }

    private var page: some View {
        ScrollView {
            DailyRecordCards(day: day, training: training,
                onShowSession: { selectedSession = DaySessionRoute(session: $0) }, onShowExercise: { selectedExercise = $0 })
                .padding(MasoMetrics.pagePaddingHorizontal)
        }.background(AppBackground())
        .navigationTitle(day.formatted(.dateTime.month(.wide).day().year().locale(LanguageManager.currentLocale)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !pushed {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) }
            }
            ToolbarItem(placement: pushed ? .topBarTrailing : .topBarLeading) {
                Button { showsShare = true } label: { ShareIcon() }
                    .tint(MasoColor.text).accessibilityLabel("Share")
            }
        }
        .navigationDestination(item: $selectedSession) { route in
            RecordedSessionReport(session: route.session, onReplay: { plan in
                selectedSession = nil
                onReplay(plan)
            })
        }
        .sheet(isPresented: $showsShare) {
            FullPageShareSheet(title: NSLocalizedString("Share day", comment: ""), surface: "daily_record", imageOnly: true) {
                DailyRecordShareCard(day: day).environment(data).environment(training)
            }
        }
        .sheet(item: $selectedExercise) { exercise in
            ExerciseDetailSheet(exercise: exercise).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

}

/// Detail and single-day exports share actual records, saved targets and card contents.
struct DailyRecordCards: View {
    @Environment(DataStore.self) private var data
    let day: Date
    var sharing = false
    var training: TrainingSessionStore? = nil
    var onShowSession: (SessionSummary) -> Void = { _ in }
    var onShowExercise: (Exercise) -> Void = { _ in }
    private var calendar: Calendar { data.settings.calendar }
    private var meals: [MealCheckIn] { data.wellnessMeals(on: day) }
    private var sessions: [SessionSummary] { data.recordedWorkoutSessions(on: day).sorted { $0.firstPerformedAt < $1.firstPerformedAt } }
    private var normalizedDay: Date { calendar.startOfDay(for: day) }
    private var sleepMinutes: Double? {
        HealthKitService.shared.sleepMinutes[normalizedDay]
        ?? data.settings.sleepRecords?[SleepPreferences.dayKey(day, calendar: calendar)]
    }
    var body: some View {
        VStack(spacing: MasoMetrics.cardPadding) {
            ShareSelectableCard(id: "daily-workout", title: NSLocalizedString("Workout", comment: "")) { workoutCard }
            ShareSelectableCard(id: "daily-diet", title: NSLocalizedString("Diet", comment: "")) { dietCard }
            ShareSelectableCard(id: "daily-sleep", title: NSLocalizedString("Sleep", comment: "")) { sleepCard }
        }
    }
    private func recordStatus(_ session: SessionSummary) -> String {
        if let active = training?.session, !active.completed,
           calendar.isDate(active.startedAt, inSameDayAs: day),
           active.planId == session.planId || (session.planId == nil && training?.isOpenWorkout == true) {
            return "Training in progress"
        }
        let completed = (data.settings.workoutCompletions ?? []).contains {
            $0.finishedAt <= Date() && $0.planID == session.planId && calendar.isDate($0.finishedAt, inSameDayAs: day)
        }
        return completed ? "Completed" : "Workout recorded"
    }
    private var workoutCard: some View {
        DailySummaryCard(title: "Workout", icon: "dumbbell", accent: MasoColor.accent, exportStyle: sharing) {
            VStack(spacing: 20) {
                if sessions.isEmpty && data.recordedExternalWorkouts(on: day).isEmpty { emptyRecord("No workout") }
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider() }
                    if let plan = data.recordedWorkoutPlan(for: session) {
                        WorkoutCard(plan: plan, exById: data.recordedWorkoutLibrary(for: session),
                                    kicker: recordStatus(session), onStart: {}, onShowDetail: sharing ? nil : { onShowSession(session) },
                                    showStart: false, denseLayout: true, showsExercisePills: true,
                                    embedded: true, showsSourceBadge: false, onExercisePillTap: { onShowExercise($0) })
                            .applyIf(!sharing) { $0.workoutRecordDeletion(session: session) }
                    }
                }
                ForEach(data.recordedExternalWorkouts(on: day)) { workout in
                    if !sessions.isEmpty || workout.id != data.recordedExternalWorkouts(on: day).first?.id { Divider() }
                    ExternalWorkoutRecordCard(workout: workout, embedded: true, allowsDeletion: !sharing)
                }
            }.padding(MasoMetrics.cardPadding)
        }
    }
    private var dietCard: some View {
        let goal = data.savedWellnessGoal(on: day)
        let targets = goal.map { MealNutrition(protein: Double($0.protein), carbs: Double($0.carbsMinimum), fat: Double($0.fatMinimum)) }
        let intake = meals.reduce(MealNutrition()) { $0 + $1.nutrition }
        return DailySummaryCard(title: "Diet", icon: "fork.knife", accent: MasoColor.dietAccent, exportStyle: sharing) {
            if meals.isEmpty && !sharing { emptyRecord("No data").padding(MasoMetrics.cardPadding) }
            else {
                DietNutritionSummaryContent(targets: targets, actual: intake,
                    progress: DietIntakeProgress.calculate(goal: goal, meals: meals), hasRecords: !meals.isEmpty, exportStyle: sharing)
                if !sharing {
                    Divider()
                    VStack(spacing: 20) {
                        ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                            if index > 0 { Divider() }
                            RecordedMealCard(record: meal, number: index + 1, embedded: true, usesSavedTargetOnly: true)
                        }
                    }.padding(MasoMetrics.cardPadding)
                }
            }
        }
    }
    private var sleepCard: some View {
        DailySummaryCard(title: "Sleep", icon: "moon", accent: MasoColor.sleepAccent, exportStyle: sharing) {
            VStack(alignment: .leading, spacing: 20) {
                if let sleepMinutes {
                    SleepTargetSummaryContent(targetMinutes: data.savedSleepTarget(on: day), actualMinutes: sleepMinutes,
                                              actualLabel: "Total sleep", exportStyle: sharing, day: day)
                    Divider()
                    SleepNightChart(day: normalizedDay, intervals: HealthKitService.shared.sleepTimelines[normalizedDay] ?? [],
                                    minutes: sleepMinutes, embedded: true, usesSavedTargetOnly: true, showsStandaloneSummary: false, showsDetailsControl: !sharing)
                } else { emptyRecord("No data") }
            }.padding(MasoMetrics.cardPadding)
        }
    }
    private func emptyRecord(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Each dimension owns one outer surface; existing card contents avoid extra nested backgrounds.
private struct DailySummaryCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let accent: Color
    var exportStyle = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label { Text(title).foregroundStyle(MasoColor.text) } icon: { Image(systemName: icon).foregroundStyle(accent) }
                .font(.headline).padding(MasoMetrics.cardPadding)
            Divider()
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
            .applyIf(exportStyle) { $0.flatCardBackground().clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)) }
            .applyIf(!exportStyle) { $0.contentCardChrome(padding: 0) }
    }
}

private struct DailyCalendarRulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Text("Fuller arcs mean more progress")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Workout") {
                    progressExamples(.workout)
                    Text("Training fills green; rest days aren't failures")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diet") {
                    progressExamples(.diet)
                    Text("Recorded calories vs daily calorie target")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sleep") {
                    progressExamples(.sleep)
                }
            }.navigationTitle("Goal & color rules").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func progressExamples(_ kind: PerformanceCalendarSnapshot.Kind) -> some View {
        let index = kind == .workout ? 0 : kind == .diet ? 1 : 2
        let values: [Double] = kind == .workout ? [0, 1] : kind == .diet ? [0, 0.5, 1, 1.3, 1.6, 1.9] : [0, 0.5, 1]
        return ForEach(values, id: \.self) { value in
            HStack(spacing: 12) {
                DailyDateProgressRing(progress: (0..<3).map { $0 == index && value > 0 ? value : nil },
                                      dietCalorieFraction: kind == .diet ? value : nil)
                    .frame(width: 40, height: 40)
                if kind == .diet && value > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value, format: .percent.precision(.fractionLength(0)))
                        Text(LocalizedStringKey(value < 1 ? "Below calorie target" : value == 1 ? "Goal met" : value < 1.6 ? "Above calorie target" : value < 1.9 ? "Well above calorie target" : "Far above calorie target"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                else if value == 0 { Text(LocalizedStringKey(kind == .workout ? "No workout" : "No data")) }
                else if value == 1 { Text(LocalizedStringKey(kind == .workout ? "Workout recorded" : "Goal met")) }
                else { Text(value, format: .percent.precision(.fractionLength(0))) }
            }
        }
    }

}


/// The same imported-record presentation in current and historical workout summaries.
struct ExternalWorkoutRecordCard: View {
    @Environment(DataStore.self) private var data
    let workout: ExternalWorkout
    var embedded = false
    var allowsDeletion = true
    @State private var confirmingDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(LocalizedStringKey(workout.activity.title), systemImage: workout.activity.icon).font(.headline)
                Spacer()
                Text(workout.startedAt.formatted(.dateTime.hour().minute().locale(LanguageManager.currentLocale)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("External workout").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Label(Duration.seconds(workout.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(LanguageManager.currentLocale)), systemImage: "clock")
                if let distance = workout.distanceMeters {
                    Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road).locale(LanguageManager.currentLocale)))
                }
                if let energy = workout.kilocalories { Text(energy.formatted(.number.precision(.fractionLength(0))) + " kcal") }
            }.font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text("Apple Health").font(.caption).foregroundStyle(.secondary)
            Text(verbatim: workout.sourceName).font(.caption).foregroundStyle(.secondary)
            if allowsDeletion {
                Button("Delete workout", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .font(.footnote)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).applyIf(!embedded) { $0.cardChrome() }
        .contextMenu {
            if allowsDeletion {
                Button("Delete workout", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .alert("Delete workout?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { data.deleteExternalWorkout(id: workout.id) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the record from Masso only. Apple Health keeps the original.") }
    }
}
