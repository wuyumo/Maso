#if MASSO_WIDGET_TESTS
@testable import Maso
#endif
import AppIntents
import SwiftUI
import WidgetKit

// The system owns editing, margins and Home Screen rendering modes; full-color uses Masso's dark palette.
enum WidgetMetric: String, AppEnum, CaseIterable {
    case workout, diet, sleep
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Content"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .workout: "Workout", .diet: "Diet", .sleep: "Sleep"
    ]
    var overviewMetric: OverviewMetric {
        switch self { case .workout: .workout; case .diet: .diet; case .sleep: .sleep }
    }
    var title: String { overviewMetric.title }
    var color: Color { switch self { case .workout: Color(red: 30/255, green: 215/255, blue: 96/255); case .diet: .yellow; case .sleep: .blue } }
    var destination: MassoWidgetDestination { switch self { case .workout: .workout; case .diet: .diet; case .sleep: .sleep } }
}
enum WidgetPanel: String, AppEnum, CaseIterable {
    case workout, diet, sleep, calendar
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Widget panel"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .workout: "Workout", .diet: "Diet", .sleep: "Sleep", .calendar: "Calendar"
    ]
    var metric: WidgetMetric? {
        switch self { case .workout: .workout; case .diet: .diet; case .sleep: .sleep; case .calendar: nil }
    }
    static func distinct(_ panels: [WidgetPanel]) -> [WidgetPanel] {
        var used = Set<WidgetPanel>()
        let reserved = Set(panels)
        return panels.map { panel in
            if used.insert(panel).inserted { return panel }
            let replacement = allCases.first { !used.contains($0) && !reserved.contains($0) }
                ?? allCases.first { !used.contains($0) }!
            used.insert(replacement)
            return replacement
        }
    }
}
enum WidgetMetricPair: String, AppEnum, CaseIterable {
    case workoutDiet, workoutSleep, dietSleep, workoutCalendar, dietCalendar, sleepCalendar, workoutDietSleep
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Two metrics"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .workoutDiet: "Workout and Diet", .workoutSleep: "Workout and Sleep", .dietSleep: "Diet and Sleep",
        .workoutCalendar: "Workout and Calendar", .dietCalendar: "Diet and Calendar", .sleepCalendar: "Sleep and Calendar",
        .workoutDietSleep: "Workout, Diet and Sleep"
    ]
    var panels: [WidgetPanel] {
        switch self {
        case .workoutDiet: [.workout, .diet]; case .workoutSleep: [.workout, .sleep]
        case .dietSleep: [.diet, .sleep]; case .workoutCalendar: [.workout, .calendar]
        case .dietCalendar: [.diet, .calendar]; case .sleepCalendar: [.sleep, .calendar]
        case .workoutDietSleep: [.workout, .diet, .sleep]
        }
    }
}
protocol MassoWidgetIntent: WidgetConfigurationIntent {
    var metricChoice: WidgetMetric { get }
    var pairChoice: WidgetMetricPair { get }
    var panelChoices: [WidgetPanel] { get }
}
struct MetricWidgetIntent: MassoWidgetIntent {
    static var title: LocalizedStringResource = "Daily overview"
    @Parameter(title: "Content", default: .workout) var metric: WidgetMetric
    @Parameter(title: "Widget content", default: .workoutDiet) var pair: WidgetMetricPair
    @Parameter(title: "Top left", default: .workout) var topLeft: WidgetPanel
    @Parameter(title: "Top right", default: .calendar) var topRight: WidgetPanel
    @Parameter(title: "Bottom left", default: .diet) var bottomLeft: WidgetPanel
    @Parameter(title: "Bottom right", default: .sleep) var bottomRight: WidgetPanel
    var metricChoice: WidgetMetric { metric }
    var pairChoice: WidgetMetricPair { pair }
    var panelChoices: [WidgetPanel] { WidgetPanel.distinct([topLeft, topRight, bottomLeft, bottomRight]) }
    static var parameterSummary: some ParameterSummary { Summary { \.$metric; \.$pair; \.$topLeft; \.$topRight; \.$bottomLeft; \.$bottomRight } }
}

struct MassoWidgetEntry: TimelineEntry {
    let date: Date
    var snapshot: MassoWidgetSnapshot?
    var metric: WidgetMetric = .workout
    var pair: WidgetMetricPair = .workoutDiet
    var panels: [WidgetPanel] = [.workout, .calendar, .diet, .sleep]
    var moment: MassoWidgetSnapshot.Moment? { snapshot?.moment(at: date) }
    var language: String { snapshot?.language ?? Locale.current.identifier }
    var locale: Locale { Locale(identifier: language) }
    func text(_ key: String) -> String {
        let code = snapshot?.language ?? Bundle.main.preferredLocalizations.first ?? "en"
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        return (bundle ?? Bundle.main).localizedString(forKey: key, value: key, table: nil)
    }
    func enabled(_ metric: WidgetMetric) -> Bool {
        switch metric { case .workout: true; case .diet: snapshot?.dietEnabled ?? true; case .sleep: snapshot?.sleepEnabled ?? true }
    }
    func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0)).locale(locale)) }
    func percent(_ value: Double?) -> String {
        value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }.map { $0.formatted(.percent.precision(.fractionLength(0)).locale(locale)) } ?? "—"
    }
    func progress(_ metric: WidgetMetric) -> Double? {
        guard enabled(metric), let moment else { return nil }
        switch metric {
        case .workout: return Double(moment.workoutDays) / Double(max(1, moment.workoutTarget))
        case .diet: return moment.calorieProgress
        case .sleep: return moment.sleepProgress
        }
    }
    static var preview: Self {
        let now = Date()
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let days = (0..<7).map { index in
            MassoWidgetSnapshot.CalendarDay(date: calendar.date(byAdding: .day, value: index, to: week)!,
                workout: index % 2 == 0 ? 1 : nil, diet: index % 3 == 0 ? 0.75 : nil, sleep: 0.93)
        }
        return .init(date: now, snapshot: .init(generatedAt: now, language: "en", timeZone: TimeZone.current.identifier,
            dietEnabled: true, sleepEnabled: true, moments: [.init(date: now, workoutDays: 2, workoutTarget: 3,
                protein: 90, proteinTarget: 120, dietProgress: 1413.0/1980,
                sleepMinutes: 448, sleepTarget: 480, sleepProgress: 448/480,
                musclesTrained: [.init(id: "chest", name: "Chest", sets: 8), .init(id: "back", name: "Back", sets: 6),
                    .init(id: "legs", name: "Legs", sets: 6), .init(id: "shoulders", name: "Shoulders", sets: 4),
                    .init(id: "arms", name: "Arms", sets: 3)], calendarDays: days, calories: 1413, calorieTarget: 1980)]))
    }
}

struct MassoWidgetProvider<Intent: MassoWidgetIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MassoWidgetEntry {
        var entry = MassoWidgetEntry.preview
        entry.snapshot?.language = MassoWidgetStore.read()?.language ?? Bundle.main.preferredLocalizations.first ?? "en"
        return entry
    }
    func snapshot(for configuration: Intent, in context: Context) async -> MassoWidgetEntry {
        let value = MassoWidgetStore.read()
        var entry = context.isPreview && value == nil ? MassoWidgetEntry.preview : .init(date: Date(), snapshot: value)
        if context.isPreview && value == nil { entry.snapshot?.language = Bundle.main.preferredLocalizations.first ?? "en" }
        entry.metric = configuration.metricChoice
        entry.pair = configuration.pairChoice
        entry.panels = configuration.panelChoices
        return entry
    }
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<MassoWidgetEntry> {
        MassoWidgetEntry.timeline(snapshot: MassoWidgetStore.read(), metric: configuration.metricChoice, pair: configuration.pairChoice, panels: configuration.panelChoices)
    }
}

/// Preserve the installed small widget's kind and configuration when resizing.
struct MassoDailyOverviewWidget: Widget {
    let kind = "MassoSingleMetric"
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MetricWidgetIntent.self, provider: MassoWidgetProvider<MetricWidgetIntent>()) { entry in
            MassoResizableWidgetView(entry: entry)
        }.configurationDisplayName("Daily overview")
            .description("Your day at a glance")
            .supportedFamilies(Self.families)
    }
}

struct MassoResizableWidgetView: View {
    let entry: MassoWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        MassoHomeWidgetView(entry: entry, layout: family == .systemSmall ? .single : family == .systemMedium ? .overview : .largeOverview)
    }
}

struct MassoHomeWidgetView: View {
    enum Layout { case overview, largeOverview, single }
    let entry: MassoWidgetEntry
    let layout: Layout
    @Environment(\.widgetRenderingMode) private var renderingMode
    var tapURL: URL { layout == .single ? entry.metric.destination.url : MassoWidgetDestination.home.url }
    var body: some View {
        Group {
            switch layout {
            case .overview: overview
            case .largeOverview: largeOverview
            case .single: single
            }
        }
        .environment(\.locale, entry.locale)
        .environment(\.layoutDirection, entry.language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
        .containerBackground(for: .widget) { OverviewPalette.surface }
        .environment(\.colorScheme, .dark)
        .widgetURL(tapURL)
        .privacySensitive()
    }
    private var overview: some View {
        let panels = entry.pair.panels
        let threeColumns = panels.count == 3
        return HStack(spacing: threeColumns ? 5 : 16) {
            ForEach(Array(panels.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                if threeColumns, let metric = item.metric {
                    unifiedMetricPanel(metric, compactThree: true).frame(maxWidth: .infinity)
                } else {
                    panel(item).frame(maxWidth: .infinity)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var wellnessPanel: some View {
        VStack(spacing: 8) {
            if entry.enabled(.diet) {
                metric(.diet, compact: true)
            }
            if entry.enabled(.diet) && entry.enabled(.sleep) { Divider() }
            if entry.enabled(.sleep) {
                metric(.sleep, compact: true)
            }
            if !entry.enabled(.diet) && !entry.enabled(.sleep) {
                Text(entry.text("Open Masso to update")).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var largeOverview: some View {
        GeometryReader { geometry in
            let halfHeight = max(0, (geometry.size.height - 33) / 2)
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    panel(entry.panels[0]).frame(maxWidth: .infinity)
                    Divider()
                    panel(entry.panels[1]).frame(maxWidth: .infinity)
                }.environment(\.layoutDirection, .leftToRight).frame(height: halfHeight)
                Divider()
                HStack(spacing: 16) {
                    panel(entry.panels[2]).frame(maxWidth: .infinity)
                    Divider()
                    panel(entry.panels[3]).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.environment(\.layoutDirection, .leftToRight).frame(height: halfHeight)
            }
        }
    }
    @ViewBuilder private func panel(_ value: WidgetPanel) -> some View {
        Group {
            if let metric = value.metric { unifiedMetricPanel(metric) }
            else { foldedWeeklyCalendar }
        }.environment(\.layoutDirection, entry.language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
    }
    private var displayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: entry.snapshot?.timeZone ?? "") ?? .current
        return calendar
    }
    private func formatted(_ date: Date, weekday: Bool = false) -> String {
        var style = weekday ? Date.FormatStyle.dateTime.weekday(.abbreviated) : Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.locale = entry.locale; style.timeZone = displayCalendar.timeZone
        return date.formatted(style)
    }
    /// The same chronological week, folded into three rows inside the lower quarter.
    private var foldedWeeklyCalendar: some View {
        let days = entry.moment?.calendarDays ?? []
        return GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Group {
                if days.isEmpty {
                    Link(destination: MassoWidgetDestination.home.url) {
                        Text(entry.text("Open Masso to update")).font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                } else {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { column in
                                    let index = row * 3 + column
                                    if index < days.count {
                                        calendarDayLink(days[index], compact: true)
                                            .frame(width: side / 3, height: side / 3)
                                    } else {
                                        Color.clear.frame(width: side / 3, height: side / 3)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    @ViewBuilder private func calendarDayLink(_ day: MassoWidgetSnapshot.CalendarDay, compact: Bool) -> some View {
        let future = day.date > displayCalendar.startOfDay(for: entry.date)
        if future { calendarCell(day, future: true, compact: compact) }
        else {
            Link(destination: MassoWidgetDayLink.url(for: day.date)) {
                calendarCell(day, future: false, compact: compact)
            }.buttonStyle(.plain)
        }
    }
    private func calendarCell(_ day: MassoWidgetSnapshot.CalendarDay, future: Bool, compact: Bool) -> some View {
        let today = displayCalendar.isDate(day.date, inSameDayAs: entry.date)
        let values = [day.workout, day.diet, day.sleep]
        return VStack(spacing: compact ? 2 : 6) {
            Text(formatted(day.date, weekday: true)).font(compact ? .system(size: 8) : .caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.65)
            ZStack {
                DailyProgressRing(progress: future ? [nil, nil, nil] : values,
                                  colors: [WidgetMetric.workout, .diet, .sleep].map(accent),
                                  dietCalorieFraction: renderingMode == .fullColor && !future ? day.dietCalorieFraction : nil)
                    .frame(width: compact ? 30 : 40, height: compact ? 30 : 40)
                Text(entry.number(Double(displayCalendar.component(.day, from: day.date))))
                    .font(.system(size: compact ? 11 : 14, weight: today ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(future ? .secondary : .primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }.frame(width: compact ? 34 : 44, height: compact ? 34 : 44)
                .background { if today { Circle().fill(OverviewPalette.calendarToday) } }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(formatted(day.date))
            .accessibilityValue(zip([WidgetMetric.workout, .diet, .sleep], values).map {
                entry.text($0.0.title) + " " + entry.percent($0.1)
            }.joined(separator: ", "))
    }
    private var single: some View {
        unifiedMetricPanel(entry.metric)
    }
    private func unifiedMetricPanel(_ value: WidgetMetric, compactThree: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Link(destination: value.destination.url) { metricLabel(value, compact: compactThree) }.buttonStyle(.plain)
                Spacer(minLength: 0)
                if value == .diet, entry.enabled(.diet) { addMealLink }
                if value == .workout {
                    Link(destination: MassoWidgetDestination.playWorkout.url) {
                        OverviewActionIcon(symbol: "play.fill", accent: WidgetMetric.workout.color,
                                           monochrome: renderingMode != .fullColor, symbolScale: .small, glyphScale: 0.85)
                    }.buttonStyle(.plain).accessibilityLabel(entry.text("Start workout"))
                        .accessibilityIdentifier("widget.play-workout")
                }
            }
            Link(destination: value.destination.url) {
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if value == .workout {
                            Text(verbatim: entry.moment.map { entry.number(Double($0.workoutDays)) } ?? "—")
                                .foregroundStyle(entry.moment == nil ? Color.secondary : Color.primary)
                            Text(verbatim: entry.moment.map { "/ " + entry.number(Double($0.workoutTarget)) } ?? "—")
                                .font(.caption.weight(.regular)).foregroundStyle(.secondary)
                        } else if value == .diet {
                            let actual = entry.enabled(.diet) ? entry.moment?.calories.map(entry.number) ?? "—" : "—"
                            let target = entry.enabled(.diet) ? entry.moment?.calorieTarget.map(entry.number) : nil
                            Text(verbatim: actual).foregroundStyle(actual == "—" ? Color.secondary : Color.primary)
                            Text(verbatim: (target.map { "/ " + $0 } ?? "—") + " kcal")
                                .font(.caption.weight(.regular)).foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: entry.enabled(.sleep) ? entry.moment?.sleepMinutes.map(duration) ?? "—" : "—")
                            Text(verbatim: "0 kcal").font(.caption.weight(.regular)).hidden().accessibilityHidden(true)
                        }
                    }.font((compactThree ? Font.title3 : Font.title).weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(entry.text(value == .workout ? "This week" : value == .diet ? "Today" : "Last night"))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        wellnessRing(value, size: compactThree ? 30 : 40)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(entry.percent(entry.progress(value)))
            }.buttonStyle(.plain)

        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    /// Exactly the same panel in small and on the left of medium.
    private var workoutHeader: some View {
        HStack(spacing: 4) {
            Link(destination: MassoWidgetDestination.workout.url) { metricLabel(.workout, compact: false) }
                .buttonStyle(.plain)
            Spacer(minLength: 0)
            Link(destination: MassoWidgetDestination.playWorkout.url) {
                OverviewActionIcon(symbol: "play.fill", accent: WidgetMetric.workout.color,
                                   monochrome: renderingMode != .fullColor, symbolScale: .small, glyphScale: 0.85)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.text("Start workout"))
            .accessibilityIdentifier("widget.play-workout")
        }
    }
    private var workoutPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            workoutHeader
            Link(destination: MassoWidgetDestination.workout.url) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            workoutFraction.font(.title3).minimumScaleFactor(0.7).lineLimit(1)
                            Text(entry.text("This week")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        wellnessRing(.workout)
                    }
                    muscleRows()
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
            }.buttonStyle(.plain)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func muscleName(_ muscle: MassoWidgetSnapshot.TrainedMuscle) -> String {
        let keys = ["chest": "Chest", "back": "Back muscle", "legs": "Legs", "shoulders": "Shoulders",
                    "arms": "Arms", "core": "Core", "fullBody": "Full body"]
        return keys[muscle.id].map(entry.text) ?? muscle.name
    }
    private func muscleRows(expanded: Bool = false) -> some View {
        let muscles = entry.moment?.musclesTrained ?? []
        let largest = max(muscles.map(\.sets).max() ?? 0, 1)
        return GeometryReader { geometry in
            let expandedSpacing = max(0, (geometry.size.height - CGFloat(muscles.count) * 16) / CGFloat(max(1, muscles.count - 1)))
            if muscles.isEmpty {
                Text(entry.text("No data")).font(.caption2).foregroundStyle(.secondary)
            } else {
                VStack(spacing: expanded ? expandedSpacing : 3) {
                    ForEach(Array(expanded ? muscles : Array(muscles.prefix(5))), id: \.id) { muscle in
                        HStack(alignment: .center, spacing: 5) {
                            Text(muscleName(muscle)).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity, alignment: .leading)
                            track(Double(muscle.sets) / Double(largest), color: accent(.workout)).frame(width: 24)
                            Text(entry.number(Double(muscle.sets))).font(.caption2.monospacedDigit())
                                .frame(minWidth: 12, alignment: .trailing)
                                .frame(width: expanded ? 24 : nil, alignment: .trailing)
                        }
                        .frame(height: expanded ? 16 : nil)
                    }
                }
            }
        }.clipped()
        .mask {
            if muscles.isEmpty { Color.white }
            else {
                LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: expanded ? 0.55 : 0.30),
                    .init(color: .white.opacity(0.65), location: expanded ? 0.80 : 0.65), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.text("Muscles trained"))
        .accessibilityValue(muscles.map { muscleName($0) + " " + entry.number(Double($0.sets)) + " " + entry.text("sets") }.joined(separator: ", "))
    }
    private func accent(_ metric: WidgetMetric) -> Color {
        renderingMode == .fullColor ? metric.color : .primary
    }
    private var workoutFraction: some View {
        ProgressFractionText(numerator: entry.moment.map { entry.number(Double($0.workoutDays)) } ?? "—",
                             denominator: entry.moment.map { entry.number(Double($0.workoutTarget)) })
    }
    private func metricLabel(_ metric: WidgetMetric, compact: Bool) -> some View {
        Label {
            Text(entry.text(metric.title)).foregroundStyle(accent(metric))
        } icon: {
            OverviewMetricIcon(metric: metric.overviewMetric, color: accent(metric), glyphScale: 0.78)
        }
        .font(compact ? .system(size: 10, weight: .semibold) : .footnote.weight(.semibold))
        .foregroundStyle(accent(metric)).lineLimit(1).minimumScaleFactor(0.8)
    }
    @ViewBuilder private func metric(_ value: WidgetMetric, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            HStack(spacing: 4) {
                Link(destination: value.destination.url) { metricLabel(value, compact: compact) }
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
                if value == .diet, entry.enabled(.diet) { addMealLink }
            }
            Link(destination: value.destination.url) {
                metricDetails(value, compact: compact)
            }.buttonStyle(.plain)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var addMealLink: some View {
        Link(destination: MassoWidgetDestination.addMeal.url) {
            MealAddIcon(monochrome: renderingMode != .fullColor, glyphScale: 0.85)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.text("Add meal"))
        .accessibilityIdentifier("widget.add-meal")
    }
    @ViewBuilder private func metricDetails(_ value: WidgetMetric, compact: Bool) -> some View {
        if value == .workout {
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    workoutFraction.font(compact ? .title3 : .title).lineLimit(1).minimumScaleFactor(0.65)
                    Text(verbatim: "0 kcal").font(.caption2.weight(.regular)).hidden().accessibilityHidden(true)
                    Text(entry.text("This week")).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                }.frame(maxWidth: .infinity, alignment: .leading)
                wellnessRing(.workout)
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                .accessibilityValue(entry.percent(entry.progress(.workout)))
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if value == .diet {
                            let actual = entry.enabled(.diet) ? entry.moment?.calories.map(entry.number) ?? "—" : "—"
                            let target = entry.enabled(.diet) ? entry.moment?.calorieTarget.map(entry.number) : nil
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: actual).foregroundStyle(actual == "—" ? Color.secondary : Color.primary)
                                Text(verbatim: (target.map { "/ " + $0 } ?? "—") + " kcal")
                                    .font(.caption2.weight(.regular)).foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.enabled(.sleep) ? entry.moment?.sleepMinutes.map(duration) ?? "—" : "—")
                                Text(verbatim: "0 kcal").font(.caption2.weight(.regular)).hidden().accessibilityHidden(true)
                            }
                        }
                    }.font(compact ? .title3.weight(.semibold) : .title.weight(.semibold))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Text(entry.text(value == .diet ? "Calories" : "Last night"))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                }.frame(maxWidth: .infinity, alignment: .leading)
                wellnessRing(value)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityValue(entry.percent(entry.progress(value)))
        }
    }
    private func wellnessRing(_ metric: WidgetMetric, size: CGFloat = 40) -> some View {
        let progress = entry.progress(metric).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let color = metric == .diet && renderingMode == .fullColor
            ? DietProgressColor.color(for: progress) : accent(metric)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.16), lineWidth: OverviewProgressMetrics.thickness)
            if let progress, progress > 0 {
                Circle().trim(from: 0, to: min(1, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: OverviewProgressMetrics.thickness, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(verbatim: progress.map { entry.number($0 * 100) } ?? "—")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).padding(4)
        }.frame(width: size, height: size)
        .accessibilityLabel(Text(verbatim: entry.percent(progress)))
    }
    private func duration(_ minutes: Double) -> String {
        MassoDurationFormatter.sleep(minutes, locale: entry.locale)
    }
    private func track(_ value: Double?, color: Color) -> some View {
        GeometryReader { proxy in
            Capsule().fill(.secondary.opacity(0.16))
                .overlay(alignment: .leading) {
                    if let value, value.isFinite, value > 0 {
                        Capsule().fill(color).frame(width: proxy.size.width * min(1, value))
                    }
                }
        }.frame(height: OverviewProgressMetrics.thickness).accessibilityHidden(true)
    }
}

#Preview(as: .systemMedium) { MassoDailyOverviewWidget() } timeline: { MassoWidgetEntry.preview }
#Preview(as: .systemLarge) { MassoDailyOverviewWidget() } timeline: { MassoWidgetEntry.preview }
#Preview(as: .systemSmall) { MassoDailyOverviewWidget() } timeline: { MassoWidgetEntry.preview }


extension MassoWidgetEntry {
    var dayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
        calendar.locale = locale
        return calendar
    }
    var todayProgress: [Double?] {
        guard let day = moment?.calendarDays?.first(where: { dayCalendar.isDate($0.date, inSameDayAs: date) }) else {
            return [nil, nil, nil]
        }
        return [day.workout, enabled(.diet) ? day.diet : nil, enabled(.sleep) ? day.sleep : nil]
    }
    static func timeline(snapshot: MassoWidgetSnapshot?, metric: WidgetMetric = .workout, pair: WidgetMetricPair = .workoutDiet, panels: [WidgetPanel] = [.workout, .calendar, .diet, .sleep], now: Date = Date()) -> Timeline<Self> {
        let future = snapshot?.moments.map(\.date).filter { $0 > now } ?? []
        let expiry = snapshot.map { $0.generatedAt.addingTimeInterval(25 * 3600) }
        let dates = Array(Set([now] + future + (expiry.map { $0 > now ? [$0] : [] } ?? []))).sorted()
        return Timeline(entries: dates.map { .init(date: $0, snapshot: snapshot, metric: metric, pair: pair, panels: panels) },
                        policy: .after(now.addingTimeInterval(3600)))
    }
}

struct MassoDailyRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> MassoWidgetEntry {
        var entry = MassoWidgetEntry.preview
        entry.snapshot?.language = MassoWidgetStore.read()?.language ?? Bundle.main.preferredLocalizations.first ?? "en"
        return entry
    }
    func getSnapshot(in context: Context, completion: @escaping (MassoWidgetEntry) -> Void) {
        let snapshot = MassoWidgetStore.read()
        var entry: MassoWidgetEntry = context.isPreview && snapshot == nil ? .preview : .init(date: Date(), snapshot: snapshot)
        if context.isPreview && snapshot == nil { entry.snapshot?.language = Bundle.main.preferredLocalizations.first ?? "en" }
        completion(entry)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MassoWidgetEntry>) -> Void) {
        completion(MassoWidgetEntry.timeline(snapshot: MassoWidgetStore.read()))
    }
}

/// One Lock Screen slot contains all three daily calendar metrics, never the weekly workout count.
struct MassoDailyRingWidget: Widget {
    let kind = "MassoDailyRings"
    static let families: [WidgetFamily] = [.accessoryCircular]
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MassoDailyRingProvider()) { entry in
            MassoDailyRingView(entry: entry)
        }
        .configurationDisplayName("Daily rings")
        .description("Workout, diet and sleep in one ring")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}

struct MassoDailyRingView: View {
    let entry: MassoWidgetEntry
    private var ring: DailyProgressRing {
        DailyProgressRing(progress: entry.todayProgress,
                          colors: [Color.primary, Color.primary, Color.primary],
                          lineWidth: OverviewProgressMetrics.lockScreenThickness)
    }
    var body: some View {
        ZStack {
            ring
            Text(entry.number(Double(entry.dayCalendar.component(.day, from: entry.date))))
                .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
        .widgetURL(MassoWidgetDayLink.url(for: entry.dayCalendar.startOfDay(for: entry.date)))
        .privacySensitive()
        .environment(\.locale, entry.locale)
        .environment(\.layoutDirection, entry.language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: entry.locale, timeZone: entry.dayCalendar.timeZone)))
        .accessibilityValue(zip([WidgetMetric.workout, .diet, .sleep], entry.todayProgress).map {
            entry.text($0.0.title) + ": " + ($0.1 == nil ? entry.text("No data") : entry.percent($0.1))
        }.joined(separator: ", "))
    }
}

/// Native open circular gauge for a single Lock Screen slot.
struct MassoDietProgressWidget: Widget {
    let kind = "MassoDietProgress"
    static let families: [WidgetFamily] = [.accessoryCircular]
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MassoDailyRingProvider()) { entry in
            MassoDietProgressView(entry: entry)
        }
        .configurationDisplayName("Diet progress")
        .description("Today's calorie progress")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}

struct MassoDietProgressView: View {
    let entry: MassoWidgetEntry
    var body: some View { MassoAccessoryProgressView(entry: entry, metric: .diet) }
}

/// Diet and Sleep use one native gauge, including sizing, missing values and system tint.
struct MassoAccessoryProgressView: View {
    let entry: MassoWidgetEntry
    let metric: WidgetMetric
    var body: some View {
        Gauge(value: min(1, max(0, entry.progress(metric) ?? 0))) {
            Image(systemName: metric.overviewMetric.symbol)
                .scaleEffect(0.85)
                .accessibilityHidden(true)
        } currentValueLabel: {
            Text(entry.percent(entry.progress(metric)))
                .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
        .widgetURL(metric.destination.url)
        .privacySensitive()
        .environment(\.locale, entry.locale)
        .environment(\.layoutDirection, entry.language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.text(metric.title))
        .accessibilityValue(entry.progress(metric) == nil ? entry.text("No data") : entry.percent(entry.progress(metric)))
    }
}


struct MassoSleepProgressWidget: Widget {
    let kind = "MassoSleepProgress"
    static let families: [WidgetFamily] = [.accessoryCircular]
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MassoDailyRingProvider()) { entry in
            MassoAccessoryProgressView(entry: entry, metric: .sleep)
        }
        .configurationDisplayName("Sleep progress")
        .description("Progress toward your sleep goal")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}
