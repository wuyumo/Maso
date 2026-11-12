import SwiftUI

enum RecordHistoryItem: Identifiable {
    case workout(SessionSummary)
    case external(ExternalWorkout)
    case meal(MealCheckIn, number: Int)
    case sleep(day: Date, minutes: Double)

    var id: String {
        switch self {
        case .workout(let value): "workout-" + value.id
        case .external(let value): "external-" + value.id
        case .meal(let value, _): "meal-" + value.id
        case .sleep(let day, _): "sleep-\(day.timeIntervalSince1970)"
        }
    }
    var date: Date {
        switch self {
        case .workout(let value): value.firstPerformedAt
        case .external(let value): value.startedAt
        case .meal(let value, _): value.day
        case .sleep(let day, _): day
        }
    }
    var sortDate: Date {
        if case .meal(let value, _) = self { return value.mealTime }
        return date
    }
}

extension PerformanceCalendarSnapshot.Kind {
    var historyTitle: LocalizedStringKey {
        switch self {
        case .workout: "Workout History"
        case .diet: "Diet history"
        case .sleep: "Sleep history"
        }
    }

    var allHistoryTitle: LocalizedStringKey {
        switch self {
        case .workout: "All workout history"
        case .diet: "All diet history"
        case .sleep: "All sleep history"
        }
    }
}

@MainActor
extension DataStore {
    func historyItems(kind: PerformanceCalendarSnapshot.Kind, now: Date = Date()) -> [RecordHistoryItem] {
        let calendar = settings.calendar
        let today = calendar.startOfDay(for: now)
        var items: [RecordHistoryItem] = []
        switch kind {
        case .workout:
            items = recordedWorkoutSessions().filter { $0.firstPerformedAt <= now }.map(RecordHistoryItem.workout)
            items += recordedExternalWorkouts(now: now).map(RecordHistoryItem.external)
        case .diet:
            let records = (settings.mealCheckIns ?? []).filter {
                $0.confirmedAt <= now && $0.mealTime <= now && calendar.startOfDay(for: $0.day) <= today
            }
            for records in Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.day) }).values {
                let meals = Self.latestMealRecords(records)
                items += meals.enumerated().map { .meal($0.element, number: $0.offset + 1) }
            }
        case .sleep:
            var nights: [Date: Double] = [:]
            for (key, minutes) in settings.sleepRecords ?? [:] {
                let parts = key.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3,
                      let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                      SleepPreferences.dayKey(day, calendar: calendar) == key else { continue }
                nights[calendar.startOfDay(for: day)] = minutes
            }
            for (day, minutes) in HealthKitService.shared.sleepMinutes {
                nights[calendar.startOfDay(for: day)] = minutes
            }
            items = nights.compactMap { day, minutes in
                guard day <= today, minutes.isFinite, minutes >= 0 else { return nil }
                return .sleep(day: day, minutes: minutes)
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.sortDate == rhs.sortDate ? lhs.id < rhs.id : lhs.sortDate > rhs.sortDate
        }
    }
}

enum RecordHistoryFilter {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let items: [RecordHistoryItem]
    }

    /// The preview limit counts recorded days, so several meals never crowd out earlier dates.
    static func days(_ items: [RecordHistoryItem], calendar: Calendar) -> [Day] {
        Dictionary(grouping: items, by: { calendar.startOfDay(for: $0.date) })
            .map { date, items in
                Day(date: date, items: items.sorted {
                    $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate < $1.sortDate
                })
            }
            .sorted { $0.date > $1.date }
    }

    static func items(_ items: [RecordHistoryItem], range: InsightsTimeRange,
                      calendar: Calendar, now: Date = Date(), excludingDay: Date? = nil) -> [RecordHistoryItem] {
        let start = range == .allTime ? .distantPast : range.startDate(calendar: calendar, now: now, records: [])
        return items.filter {
            guard $0.date >= start && $0.date <= now else { return false }
            if let excludingDay, calendar.isDate($0.date, inSameDayAs: excludingDay) { return false }
            return true
        }
    }
}

/// All three modules use the same recorded-day preview and archive presentation.
struct RecordHistorySection: View {
    @Environment(DataStore.self) private var data
    let kind: PerformanceCalendarSnapshot.Kind
    var excludingDay: Date? = nil
    var range: InsightsTimeRange = .allTime
    var limitsToPreview = true
    var onReplay: (Plan) -> Void = { _ in }
    var sessionSelection: Binding<SessionSummary?>? = nil
    private var items: [RecordHistoryItem] {
        RecordHistoryFilter.items(data.historyItems(kind: kind), range: range,
                                  calendar: data.settings.calendar, excludingDay: excludingDay)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.historyTitle).trainingSectionTitle()
            DailyHistoryCards(items: items, kind: kind, limitsToPreview: limitsToPreview, onReplay: onReplay,
                              sessionSelection: sessionSelection)
        }
    }
}

private struct DailyHistoryCards: View {
    @Environment(DataStore.self) private var data
    let items: [RecordHistoryItem]
    let kind: PerformanceCalendarSnapshot.Kind
    var limitsToPreview = true
    var showsAllHistory = true
    var onReplay: (Plan) -> Void = { _ in }
    var sessionSelection: Binding<SessionSummary?>? = nil

    private var days: [RecordHistoryFilter.Day] {
        RecordHistoryFilter.days(items, calendar: data.settings.calendar)
    }
    private var visibleDays: [RecordHistoryFilter.Day] {
        limitsToPreview ? Array(days.prefix(3)) : days
    }
    var body: some View {
        LazyVStack(spacing: MasoMetrics.cardPadding) {
            if days.isEmpty {
                Text("No data").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).cardChrome()
            }
            ForEach(visibleDays) { day in
                VStack(alignment: .leading, spacing: 0) {
                    if kind == .diet || kind == .sleep {
                        HistoryDaySummaryHeader(day: day, kind: kind)
                            .padding(.horizontal, MasoMetrics.cardPadding)
                            .padding(.vertical, MasoMetrics.cardPadding)
                        Divider().overlay(MasoColor.borderSoft)
                            .padding(.horizontal, MasoMetrics.cardPadding)
                            .accessibilityHidden(true)
                    } else if !(kind == .workout && day.items.first.map({ if case .workout = $0 { return true }; return false }) == true) {
                        Text(day.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                            .font(.headline)
                            .padding(.horizontal, MasoMetrics.cardPadding)
                            .padding(.top, MasoMetrics.cardPadding).padding(.bottom, 12)
                    }
                    ForEach(day.items) { item in
                        if item.id != day.items.first?.id { Divider().padding(.horizontal, MasoMetrics.cardPadding) }
                        if kind == .workout, case .workout(let session) = item {
                            WorkoutHistoryRecordRow(session: session, embedded: true, showsDate: false,
                                dayHeader: item.id == day.items.first?.id ? day.date : nil,
                                paddedInDay: true,
                                dayTopPadding: item.id == day.items.first?.id ? 0 : MasoMetrics.cardPadding,
                                onReplay: onReplay,
                                onOpenSession: { sessionSelection?.wrappedValue = $0 })
                        } else {
                            RecordHistoryRow(item: item, showsDate: false, onReplay: onReplay, sessionSelection: sessionSelection)
                                .padding(.horizontal, MasoMetrics.cardPadding)
                                .padding(.bottom, MasoMetrics.cardPadding)
                                .padding(.top, kind == .workout && item.id == day.items.first?.id ? 0 : MasoMetrics.cardPadding)
                        }
                    }
                }
                .contentCardChrome(padding: 0)
                .accessibilityIdentifier("history.day.\(SleepPreferences.dayKey(day.date, calendar: data.settings.calendar))")
            }
            if showsAllHistory { RecordHistoryArchiveLink(kind: kind, onReplay: onReplay, sessionSelection: sessionSelection).contentCardChrome(padding: 0) }
        }
    }
}

/// One hierarchy for recorded-day nutrition and sleep, including their archives.
/// Saved targets only: a missing historical goal must never become today's goal.
struct HistoryDaySummaryHeader: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let day: RecordHistoryFilter.Day
    let kind: PerformanceCalendarSnapshot.Kind

    private var energy: DietEnergyProgress {
        let meals = day.items.compactMap { item -> MealCheckIn? in
            if case .meal(let meal, _) = item { return meal }; return nil
        }
        return .calculate(goal: data.savedWellnessGoal(on: day.date), meals: meals)
    }
    private var sleepMinutes: Double? {
        day.items.compactMap { item -> Double? in
            if case .sleep(_, let minutes) = item { return minutes }; return nil
        }.first
    }
    private var fraction: Double? {
        if kind == .diet { return energy.fraction }
        guard let minutes = sleepMinutes, minutes.isFinite, minutes >= 0,
              let target = data.savedSleepTarget(on: day.date), target > 0 else { return nil }
        return Double(sleepScorePercent(minutes, target: target)) / 100
    }
    private var identifier: String { kind == .diet ? "diet" : "sleep" }
    private var accent: Color { kind == .diet ? DietProgressColor.color(for: fraction) : MasoColor.sleepAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text(day.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: fraction.map { $0.formatted(.percent.precision(.fractionLength(0)).locale(LanguageManager.currentLocale)) } ?? "—")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(fraction == nil ? MasoColor.textDim : MasoColor.text)
                        .layoutPriority(1)
                        .accessibilityIdentifier("history.\(identifier).percent")
                    Text(kind == .diet ? LocalizedStringKey("Calories") : LocalizedStringKey("Sleep score"))
                        .font(.caption).foregroundStyle(MasoColor.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Group {
                if kind == .diet {
                    ProgressFractionText(numerator: CalorieEstimateText.number(energy.actual),
                                         denominator: energy.target.map { CalorieEstimateText.number($0) }, suffix: " kcal",
                                         numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim)
                } else {
                    ProgressFractionText(numerator: sleepMinutes.map(compactSleepDuration) ?? "—",
                                         denominator: data.savedSleepTarget(on: day.date).map { compactSleepDuration(Double($0)) },
                                         numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim)
                }
            }
            .font(.headline).monospacedDigit()
            .accessibilityIdentifier("history.\(identifier).actual-target")
            if let fraction {
                ProgressView(value: min(1, max(0, fraction))).tint(accent)
                    .accessibilityHidden(true)
            } else {
                let hasTarget = kind == .diet ? energy.target != nil : (data.savedSleepTarget(on: day.date) ?? 0) > 0
                Text(hasTarget ? LocalizedStringKey("No data") : LocalizedStringKey("Historical target unavailable"))
                    .font(.caption).foregroundStyle(MasoColor.textDim)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.\(identifier).summary")
    }
}

private struct RecordHistoryArchiveLink: View {
    @Environment(DataStore.self) private var data
    let kind: PerformanceCalendarSnapshot.Kind
    var onReplay: (Plan) -> Void = { _ in }
    var sessionSelection: Binding<SessionSummary?>? = nil
    var body: some View {
        NavigationLink {
            RecordHistoryArchiveScreen(kind: kind, onReplay: onReplay, sessionSelection: sessionSelection)
        } label: {
            HStack {
                Text(kind.allHistoryTitle).font(.body)
                Spacer()
                // Count the complete archive, including dates omitted from the preview.
                // Meals and workouts count individual records, not grouped calendar days.
                Text(data.historyItems(kind: kind).count, format: .number.locale(LanguageManager.currentLocale))
                    .font(.body).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityIdentifier("history.totalCount")
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary).padding(MasoMetrics.cardPadding).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("history.all")
    }
}

private struct RecordHistoryRangePicker: View {
    @Binding var range: InsightsTimeRange
    var body: some View {
        Picker("Time range", selection: $range) {
            ForEach(InsightsTimeRange.allCases) { value in Text(value.title).tag(value) }
        }
        .pickerStyle(.menu).controlSize(.small).tint(MasoColor.text)
        .accessibilityIdentifier("history.timeRange")
    }
}

struct RecordHistoryArchiveScreen: View {
    @Environment(DataStore.self) private var data
    let kind: PerformanceCalendarSnapshot.Kind
    var onReplay: (Plan) -> Void = { _ in }
    var sessionSelection: Binding<SessionSummary?>? = nil
    @State private var ownedSession: SessionSummary?
    @State private var range: InsightsTimeRange = .allTime
    private var items: [RecordHistoryItem] {
        RecordHistoryFilter.items(data.historyItems(kind: kind), range: range, calendar: data.settings.calendar)
    }
    private var months: [(date: Date, items: [RecordHistoryItem])] {
        let calendar = data.settings.calendar
        return Dictionary(grouping: items) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
            .map { (date: $0.key, items: $0.value) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
                HStack { Spacer(); RecordHistoryRangePicker(range: $range) }
                if items.isEmpty { ContentUnavailableView("No data", systemImage: "clock") }
                ForEach(months, id: \.date) { month in
                    Text(month.date, format: .dateTime.year().month(.wide)).font(.headline)
                    DailyHistoryCards(items: month.items, kind: kind, limitsToPreview: false,
                                      showsAllHistory: false, onReplay: onReplay,
                                      sessionSelection: sessionSelection ?? $ownedSession)
                }
            }.padding(MasoMetrics.pagePaddingHorizontal)
        }
        .background(AppBackground())
        .navigationTitle(kind.historyTitle)
        .navigationBarTitleDisplayMode(.large)
        .applyIf(sessionSelection == nil) { view in
            view.navigationDestination(item: $ownedSession) { session in
                SessionDetailSheet(session: session, exerciseStats: data.recordedExerciseStats(for: session),
                                   replayPlan: data.recordedReplayPlan(for: session), onReplay: { plan in
                    ownedSession = nil
                    DispatchQueue.main.async { onReplay(plan) }
                }, pushed: true)
            }
        }
    }
}

private struct RecordHistoryRow: View {
    let item: RecordHistoryItem
    var showsDate = true
    let onReplay: (Plan) -> Void
    var sessionSelection: Binding<SessionSummary?>? = nil
    var body: some View {
        switch item {
        case .workout(let session):
            WorkoutHistoryRecordRow(session: session, embedded: true, showsDate: showsDate, onReplay: onReplay,
                                    onOpenSession: { sessionSelection?.wrappedValue = $0 })
        case .external(let workout):
            VStack(alignment: .leading, spacing: 8) {
                if showsDate { Text(workout.startedAt, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary) }
                ExternalWorkoutRecordCard(workout: workout, embedded: true)
            }
        case .meal(let meal, let number):
            RecordedMealCard(record: meal, number: number, embedded: true, usesSavedTargetOnly: true, showsDate: showsDate)
        case .sleep(let day, let minutes):
            SleepNightChart(day: day, intervals: HealthKitService.shared.sleepTimelines[day] ?? [],
                            minutes: minutes, embedded: true, usesSavedTargetOnly: true, showsStandaloneSummary: false)
        }
    }
}
