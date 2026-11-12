import SwiftUI
import Charts

enum InsightsTimeRange: String, CaseIterable, Identifiable {
    case thisWeek
    case fourWeeks
    case twelveWeeks
    case sixMonths
    case oneYear
    case allTime

    var id: String { rawValue }

    var title: String {
        let key: String
        switch self {
        case .thisWeek: key = "This week"
        case .fourWeeks: key = "4 weeks"
        case .twelveWeeks: key = "12 weeks"
        case .sixMonths: key = "6 months"
        case .oneYear: key = "1 year"
        case .allTime: key = "All time"
        }
        return NSLocalizedString(key, comment: "insights time range")
    }

    func startDate(calendar: Calendar, now: Date, records: [SetRecord]) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        case .fourWeeks:
            return calendar.date(byAdding: .day, value: -27, to: today) ?? today
        case .twelveWeeks:
            return calendar.date(byAdding: .day, value: -83, to: today) ?? today
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: today) ?? today
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: today) ?? today
        case .allTime:
            return records.map(\.performedAt).min().map(calendar.startOfDay(for:)) ?? today
        }
    }

    func hasData(records: [SetRecord], calendar: Calendar, now: Date) -> Bool {
        let start = startDate(calendar: calendar, now: now, records: records)
        return records.contains { $0.performedAt >= start && $0.performedAt <= now }
    }

    /// Opening Insights matches the current-week workout summary on Home.
    /// Empty weeks stay empty rather than silently switching to older records.
    static func defaultValue(records: [SetRecord], calendar: Calendar, now: Date) -> Self {
        .thisWeek
    }

}

/// Comparable records, training input, and consistency stay separate: none is a muscle-growth score.
struct TrainingInsightsSnapshot {
    enum MuscleScope { case currentWeek, selectedRange }
    struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }
    enum Metric { case weight(reps: Int), reps(weight: Double) }
    struct Lift: Identifiable {
        let id: String
        let name: String
        let metric: Metric?
        let points: [Point]
        let latest: SetRecord
        var change: Double? {
            guard points.count > 1, let first = points.first, let last = points.last else { return nil }
            return last.value - first.value
        }
        var improved: Bool { (change ?? 0) > 0.0001 }
    }
    struct Muscle: Identifiable {
        var id: MuscleGroup { group }
        let group: MuscleGroup
        let sets: Int
        let exercises: [(id: String, sets: Int)]
    }
    let start: Date
    let end: Date
    let lifts: [Lift]
    let muscles: [Muscle]
    let trainingDates: Set<Date>
    let weekDates: [Date]
    let weekTrainingDays: Int
    let unmappedSets: Int

    /// A baseline is a recorded workout, but not yet a comparable progress series.
    var comparableLifts: [Lift] { lifts.filter { $0.metric != nil && $0.points.count > 1 } }

    /// A fixed cohort of comparable lifts; each enters only after a second observation.
    var improvementTrend: [Point] {
        let comparable = lifts.filter { $0.points.count > 1 }
        let dates = Set(comparable.flatMap { $0.points.map(\.date) }).sorted()
        return dates.map { date in
            Point(date: date, value: Double(comparable.filter { lift in
                let observed = lift.points.filter { $0.date <= date }
                return observed.count > 1 && observed.last!.value > observed.first!.value + 0.0001
            }.count))
        }
    }

    static func build(sets: [SetRecord], names: [String: String], primarySections: [String: Set<MuscleGroup>],
                      range: InsightsTimeRange, calendar: Calendar, now: Date, muscleScope: MuscleScope = .currentWeek) -> Self {
        let today = calendar.startOfDay(for: now)
        let start = range.startDate(calendar: calendar, now: now, records: sets)
        let records = sets.filter { $0.performedAt >= start && $0.performedAt <= now }
        let trainingDates = Set(records.map { calendar.startOfDay(for: $0.performedAt) })
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let weekRecords = records.filter { $0.performedAt >= weekStart }
        var counts: [MuscleGroup: [String: Int]] = [:]
        var unmapped = 0
        for record in (muscleScope == .selectedRange ? records : weekRecords) {
            let groups = primarySections[record.exerciseId] ?? []
            if groups.isEmpty { unmapped += 1 }
            for group in groups { counts[group, default: [:]][record.exerciseId, default: 0] += 1 }
        }
        let muscles = [MuscleGroup.chest, .back, .legs, .shoulders, .arms, .core, .fullBody].compactMap { group -> Muscle? in
            let exercises = counts[group] ?? [:]
            if group == .fullBody && exercises.isEmpty { return nil }
            return Muscle(group: group, sets: exercises.values.reduce(0, +),
                          exercises: exercises.map { (id: $0.key, sets: $0.value) }.sorted {
                              $0.sets == $1.sets ? $0.id < $1.id : $0.sets > $1.sets
                          })
        }
        let lifts = Dictionary(grouping: records, by: \.exerciseId).compactMap { id, all -> Lift? in
            // Missing load is not assumed to mean bodyweight for a weighted exercise.
            let valid = all.filter { record in
                guard let reps = record.reps, reps > 0 else { return false }
                if let weight = record.weight { return weight.isFinite && weight >= 0 }
                return record.category == .calisthenics
            }
            guard let latest = valid.max(by: { $0.performedAt < $1.performedAt }) else { return nil }
            var candidates: [(metric: Metric, points: [Point])] = []
            func dailyBest(_ records: [SetRecord], value: (SetRecord) -> Double) -> [Point] {
                var byDay: [Date: Double] = [:]
                for record in records {
                    let day = calendar.startOfDay(for: record.performedAt)
                    byDay[day] = max(byDay[day] ?? -.infinity, value(record))
                }
                return byDay.sorted { $0.key < $1.key }.map { Point(date: $0.key, value: $0.value) }
            }
            for (reps, records) in Dictionary(grouping: valid.filter { ($0.weight ?? 0) > 0 }, by: { $0.reps! }) {
                let points = dailyBest(records, value: { $0.weight! })
                if points.count > 1 { candidates.append((.weight(reps: reps), points)) }
            }
            for (weight, records) in Dictionary(grouping: valid, by: { $0.weight ?? 0 }) {
                let points = dailyBest(records, value: { Double($0.reps!) })
                if points.count > 1 { candidates.append((.reps(weight: weight), points)) }
            }
            // Prefer recently repeated benchmarks, then more observations. Never choose by biggest gain.
            candidates.sort {
                let left = $0.points.last!.date, right = $1.points.last!.date
                if left != right { return left > right }
                if $0.points.count != $1.points.count { return $0.points.count > $1.points.count }
                switch ($0.metric, $1.metric) {
                case (.weight(let a), .weight(let b)): return a < b
                case (.weight, .reps): return true
                case (.reps, .weight): return false
                case (.reps(let a), .reps(let b)): return a < b
                }
            }
            let best = candidates.first
            return Lift(id: id, name: names[id] ?? latest.exerciseName, metric: best?.metric,
                        points: best?.points ?? [], latest: latest)
        }.sorted {
            if $0.improved != $1.improved { return $0.improved }
            if ($0.metric != nil) != ($1.metric != nil) { return $0.metric != nil }
            if $0.latest.performedAt != $1.latest.performedAt { return $0.latest.performedAt > $1.latest.performedAt }
            return $0.id < $1.id
        }
        return Self(start: start, end: now, lifts: lifts, muscles: muscles, trainingDates: trainingDates,
                    weekDates: weekDates, weekTrainingDays: Set(weekRecords.map { calendar.startOfDay(for: $0.performedAt) }).count,
                    unmappedSets: unmapped)
    }
}

enum InsightsCategory: String, CaseIterable, Identifiable {
    case workout = "Workout", diet = "Diet", sleep = "Sleep"
    var id: String { rawValue }
    var color: Color {
        switch self { case .workout: MasoColor.accent; case .diet: MasoColor.dietAccent; case .sleep: MasoColor.sleepAccent }
    }
}

struct InsightsChartsView: View {
    let data: DataStore
    var forSharing = false
    var onUnlock: (() -> Void)? = nil
    @Binding var range: InsightsTimeRange
    @State private var detail: Detail?
    @State private var showsAllLifts = false
    @State private var shareProgress = false
    private enum Detail: Identifiable {
        case muscle(TrainingInsightsSnapshot.Muscle)
        var id: String {
            switch self {
            case .muscle(let muscle): return muscle.group.rawValue
            }
        }
    }
    private var snapshot: TrainingInsightsSnapshot {
        var names: [String: String] = [:]
        var sections: [String: Set<MuscleGroup>] = [:]
        for id in Set(data.sets.map(\.exerciseId)) {
            guard let exercise = data.exById[id] else { continue }
            names[id] = exercise.displayName
            sections[id] = Set(exercise.primaryMuscles.compactMap { $0 == .fullBody ? .fullBody : $0.section })
        }
        return TrainingInsightsSnapshot.build(sets: data.sets, names: names, primarySections: sections,
                                              range: range, calendar: data.settings.calendar, now: Date(), muscleScope: .selectedRange)
    }
    private var unit: WeightUnit { data.settings.weightUnit }
    private var shareableProgress: AccomplishmentShare.Progress? {
        let now = Date()
        let calendar = data.settings.calendar
        let start = range.startDate(calendar: calendar, now: now, records: data.sets)
        let records = data.sets.filter { $0.performedAt >= start && $0.performedAt <= now }
        var names: [String: String] = [:]
        var bells: [String: Bool] = [:]
        for id in Set(records.map(\.exerciseId)) {
            guard let exercise = data.exById[id] else { continue }
            names[id] = exercise.displayName
            bells[id] = ExerciseWeightReference.perDumbbell(exercise)
        }
        return AccomplishmentShare.bestProgress(sets: records, names: names, perDumbbell: bells, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
            if !forSharing {
                Menu {
                    ForEach(InsightsTimeRange.allCases) { option in
                        Button {
                            range = option
                        } label: {
                            if range == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                        .disabled(!hasData(in: option))
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("Time range")
                            .foregroundStyle(MasoColor.textDim)
                        Text(range.title)
                            .foregroundStyle(MasoColor.text)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.7))
                }
                .menuOrder(.fixed)
                .accessibilityIdentifier("insights.range")
                .accessibilityLabel(Text("Time range"))
                .accessibilityValue(Text(range.title))
            }
            let summary = snapshot
            Text("\(summary.start.formatted(.dateTime.month(.abbreviated).day())) – \(summary.end.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption).foregroundStyle(MasoColor.textDim)
            ShareSelectableCard(id: "insights-muscles", title: NSLocalizedString("Muscles trained", comment: "")) { muscleCard(summary) }
            if data.settings.isPro {
                ShareSelectableCard(id: "insights-lifts", title: NSLocalizedString("Lift progress", comment: "")) { progressCard(summary) }
            } else if !forSharing {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Lift progress", systemImage: "lock").font(.headline)
                    Text("Compare your lifts over time with Masso Pro")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Try Masso Pro") { onUnlock?() }
                        .buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, alignment: .leading).cardChrome()
            }
        }
        .sheet(item: $detail) { item in
            AppNavigationStack {
                detailContent(item)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { detail = nil } } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }

    private func hasData(in option: InsightsTimeRange) -> Bool {
        option.hasData(records: data.sets, calendar: data.settings.calendar, now: Date())
    }

    private func progressCard(_ summary: TrainingInsightsSnapshot) -> some View {
        let lifts = summary.comparableLifts
        return VStack(alignment: .leading, spacing: 12) {
            let improved = lifts.filter(\.improved).count
            HStack(alignment: .firstTextBaseline) {
                Text("Lift progress")
                    .font(.headline)
                    .foregroundStyle(MasoColor.text)
                Spacer()
                if improved > 0 {
                    Text(String.localizedStringWithFormat(NSLocalizedString("%d improved", comment: "insights improved lift count"), improved))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MasoColor.accent)
                }
            }
            if !forSharing, let progress = shareableProgress {
                Button { shareProgress = true } label: {
                    Label {
                        Text("Share this progress")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("insights.share.progress")
                .sheet(isPresented: $shareProgress) {
                    AccomplishmentShareSheet(title: "Share this progress", model: { _ in
                        .progress(progress, unit: data.settings.weightUnit)
                    }, allowsPhoto: false)
                }
            } else if !forSharing && shareableProgress == nil && !lifts.isEmpty {
                Text("No same-reps weight increase to share yet")
                    .font(.caption)
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("insights.share.progress.unavailable")
            }
            if lifts.isEmpty {
                emptyChartState.accessibilityIdentifier("insights.liftProgress.empty")
            } else {
                let visibleLifts = (showsAllLifts || forSharing) ? lifts : Array(lifts.prefix(3))
                ForEach(Array(visibleLifts.enumerated()), id: \.element.id) { index, lift in
                    if index > 0 { Divider() }
                    liftRow(lift)
                }
                if lifts.count > 3 && !forSharing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllLifts.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showsAllLifts
                                 ? NSLocalizedString("Show fewer", comment: "collapse lift progress rows")
                                 : String.localizedStringWithFormat(NSLocalizedString("Show all %d exercises", comment: "expand lift progress rows"), lifts.count))
                            if showsAllLifts {
                                Image(systemName: "chevron.up").font(.caption.weight(.semibold)).foregroundStyle(MasoColor.accent)
                            } else {
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(MasoColor.accent)
                            }
                        }
                        .foregroundStyle(MasoColor.accent)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }.cardChrome()
    }

    private var emptyChartState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2).foregroundStyle(MasoColor.textFaint)
            Text("Keep logging workouts to see your progress")
                .font(.subheadline).foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }

    private func liftRow(_ lift: TrainingInsightsSnapshot.Lift) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(lift.name).font(.subheadline.weight(.semibold)).foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(comparison(lift)).font(.caption).foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                if lift.points.count > 1 {
                    sparkline(lift).frame(width: 84, height: 34)
                } else {
                    Capsule()
                        .fill(MasoColor.textDim.opacity(0.45))
                        .frame(width: 84, height: 2)
                        .frame(height: 34)
                }
                HStack(spacing: 3) {
                    if lift.improved {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(changeLabel(lift))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(lift.improved ? MasoColor.accent : MasoColor.textDim)
            }
        }
        .padding(.vertical, 8)
    }

    private func sparkline(_ lift: TrainingInsightsSnapshot.Lift) -> some View {
        LiftProgressSparkline(lift: lift)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(comparison(lift)))
    }

    private func muscleCard(_ summary: TrainingInsightsSnapshot) -> some View {
        let hasMuscleData = summary.muscles.contains { $0.sets > 0 }
        let maximum = max(summary.muscles.map(\.sets).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Muscles trained").font(.headline)
            if hasMuscleData {
                Text(range.title + " · " + NSLocalizedString("Recorded sets", comment: ""))
                    .font(.caption).foregroundStyle(MasoColor.textDim)
                    .accessibilityIdentifier("insights.muscles.range")
                ForEach(summary.muscles) { muscle in
                    Button { detail = .muscle(muscle) } label: {
                        HStack(spacing: 10) {
                            Text(muscle.group.displayName).font(.caption).foregroundStyle(MasoColor.text)
                                .frame(width: 72, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(MasoColor.surfaceHi)
                                    .overlay(alignment: .leading) {
                                        if muscle.sets > 0 {
                                            Capsule().fill(MasoColor.accent)
                                                .frame(width: proxy.size.width * Double(muscle.sets) / Double(maximum))
                                        }
                                    }
                            }.frame(height: 7)
                            Text(String.localizedStringWithFormat(NSLocalizedString("%d sets", comment: "recorded sets"), muscle.sets))
                                .font(.caption.monospacedDigit()).foregroundStyle(MasoColor.textDim)
                                .frame(minWidth: 48, alignment: .trailing)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(forSharing)
                        .accessibilityIdentifier("insights.muscle." + muscle.group.rawValue)
                        .accessibilityValue(muscle.sets.formatted(.number.locale(LanguageManager.currentLocale)))
                }
                Text("Primary muscles only · not a growth score")
                    .font(.caption2).foregroundStyle(MasoColor.textDim)
            } else {
                emptyChartState.accessibilityIdentifier("insights.musclesTrained.empty")
            }
            if summary.unmappedSets > 0 {
                Text("Some exercises have no muscle mapping and are excluded.")
                    .font(.caption2).foregroundStyle(MasoColor.textDim)
            }
        }.cardChrome()
    }


    @ViewBuilder private func detailContent(_ item: Detail) -> some View {
        switch item {
        case .muscle(let muscle):
            List {
                Section {
                    LabeledContent("Recorded sets", value: "\(muscle.sets)")
                    ForEach(muscle.exercises, id: \.id) { exercise in
                        LabeledContent(data.exById[exercise.id]?.displayName ?? exercise.id, value: "\(exercise.sets)")
                    }
                }
            }
            .navigationTitle(muscle.group.displayName)
        }
    }

    private func comparison(_ lift: TrainingInsightsSnapshot.Lift) -> String {
        guard let first = lift.points.first, let last = lift.points.last, let metric = lift.metric else {
            let load = lift.latest.weight.flatMap { $0 > 0 ? "\(weight($0)) × " : nil } ?? ""
            return load + String.localizedStringWithFormat(NSLocalizedString("%d reps", comment: "insights reps"), lift.latest.reps ?? 0)
        }
        switch metric {
        case .weight(let reps): return "\(weight(first.value)) × \(reps) → \(weight(last.value)) × \(reps)"
        case .reps(let load):
            let prefix = load > 0 ? "\(weight(load)) · " : ""
            return prefix + String.localizedStringWithFormat(NSLocalizedString("%d → %d reps", comment: "insights reps comparison"), Int(first.value), Int(last.value))
        }
    }
    private func changeLabel(_ lift: TrainingInsightsSnapshot.Lift) -> String {
        guard let change = lift.change else { return NSLocalizedString("Baseline", comment: "new lift benchmark") }
        if abs(change) < 0.0001 { return NSLocalizedString("Unchanged", comment: "unchanged benchmark") }
        let sign = change > 0 ? "+" : "−"
        switch lift.metric {
        case .weight: return sign + weight(abs(change))
        case .reps: return sign + String.localizedStringWithFormat(NSLocalizedString("%d reps", comment: "insights rep delta"), Int(abs(change)))
        case nil: return "—"
        }
    }
    private func weight(_ kg: Double) -> String {
        "\(unit.fromKg(kg).formatted(.number.precision(.fractionLength(0...1)))) \(unit.label)"
    }
}

/// Comparable exercise benchmarks share the Insights calculation; volume is kept separate.
struct HomePerformanceMetric: Identifiable {
    let id: String
    let title: String
    let delta: String
    let values: [Double]

    static func build(sets: [SetRecord], names: [String: String], sections: [String: Set<MuscleGroup>],
                      calendar: Calendar, now: Date, unit: WeightUnit) -> [Self] {
        let snapshot = TrainingInsightsSnapshot.build(sets: sets, names: names, primarySections: sections,
                                                     range: .fourWeeks, calendar: calendar, now: now)
        let comparable = snapshot.lifts.filter { $0.points.count > 1 }
        let improved = comparable.filter(\.improved)
        var result: [Self] = []
        if !improved.isEmpty {
            let values = snapshot.improvementTrend.map(\.value)
            result.append(Self(id: "overview", title: String.localizedStringWithFormat(
                NSLocalizedString("%d/%d lifts improving", comment: "compact homepage progress"), improved.count, comparable.count),
                delta: "+\(improved.count)", values: values))
        }
        for lift in improved {
            guard let metric = lift.metric, let change = lift.change, let last = lift.points.last else { continue }
            let suffix: String
            let value: Double
            let difference: Double
            switch metric {
            case .weight(let reps):
                suffix = "\(unit.label) · \(reps) " + NSLocalizedString("reps", comment: "")
                value = unit.fromKg(last.value); difference = unit.fromKg(change)
            case .reps(let weight):
                suffix = NSLocalizedString("reps", comment: "") + (weight > 0 ? " · \(unit.fromKg(weight).formatted(.number.precision(.fractionLength(0...1)))) \(unit.label)" : "")
                value = last.value; difference = change
            }
            let deltaUnit: String
            switch metric { case .weight: deltaUnit = unit.label; case .reps: deltaUnit = NSLocalizedString("reps", comment: "") }
            result.append(Self(id: "lift-\(lift.id)", title: "\(lift.name) · \(value.formatted(.number.precision(.fractionLength(0...1)))) \(suffix)",
                               delta: "+\(difference.formatted(.number.precision(.fractionLength(0...1)))) \(deltaUnit)", values: lift.points.map(\.value)))
        }
        // Only complete, equally sized periods, with a recorded historical baseline.
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -28, to: end),
              let previous = calendar.date(byAdding: .day, value: -56, to: end),
              let earliest = sets.map(\.performedAt).min(), earliest <= previous else { return result }
        let current = sets.filter { $0.performedAt >= start && $0.performedAt < end }
        let prior = sets.filter { $0.performedAt >= previous && $0.performedAt < start }
        func days(_ records: [SetRecord]) -> Int { Set(records.map { calendar.startOfDay(for: $0.performedAt) }).count }
        func weekly(_ records: [SetRecord], count: ([SetRecord]) -> Int) -> [Double] {
            (0..<4).map { index in
                let a = calendar.date(byAdding: .day, value: index * 7, to: start)!
                let b = calendar.date(byAdding: .day, value: 7, to: a)!
                return Double(count(records.filter { $0.performedAt >= a && $0.performedAt < b }))
            }
        }
        if days(current) > days(prior), days(prior) > 0 {
            result.append(Self(id: "consistency", title: String.localizedStringWithFormat(NSLocalizedString("%d training days", comment: ""), days(current)),
                               delta: "+\(days(current) - days(prior))", values: weekly(current, count: days)))
        }
        for group in [MuscleGroup.chest, .back, .legs, .shoulders, .arms, .core] {
            let a = current.filter { sections[$0.exerciseId]?.contains(group) == true }
            let b = prior.filter { sections[$0.exerciseId]?.contains(group) == true }
            if a.count > b.count, !b.isEmpty {
                result.append(Self(id: "volume-\(group.rawValue)", title: "\(group.displayName) · \(a.count) " + NSLocalizedString("sets", comment: ""),
                                   delta: "+\(a.count - b.count) " + NSLocalizedString("sets", comment: ""), values: weekly(a, count: { $0.count })))
            }
        }
        return result
    }
}

/// Only comparable improvements qualify; otherwise the current week's actual primary-muscle sets.
enum WorkoutPreviewContent {
    case lift(TrainingInsightsSnapshot.Lift)
    case muscles([TrainingInsightsSnapshot.Muscle])
    static func select(from summary: TrainingInsightsSnapshot) -> Self {
        if let lift = summary.lifts.first(where: { $0.improved && $0.metric != nil && $0.points.count > 1 }) {
            return .lift(lift)
        }
        // Keep the same anatomical order as the full Muscles trained card.
        let trained = summary.muscles.filter { $0.sets > 0 }
        let padding = summary.muscles.filter { $0.sets == 0 }.prefix(max(0, 3 - trained.count))
        let visibleGroups = Set((trained + Array(padding)).map(\.group))
        let volume = summary.muscles.filter { visibleGroups.contains($0.group) }
        // Unknown mappings do not become a misleading chart of zero training.
        return .muscles(summary.unmappedSets > 0 && volume.allSatisfy { $0.sets == 0 } ? [] : volume)
    }
}

struct LiftProgressSparkline: View {
    let lift: TrainingInsightsSnapshot.Lift
    var body: some View {
        let color = lift.improved ? MasoColor.accent : MasoColor.textDim
        let values = lift.points.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let range = max(high - low, abs(high) * 0.15, 1)
        let middle = (high + low) / 2
        return Chart(lift.points) { point in
            AreaMark(x: .value("Date", point.date), yStart: .value("Baseline", middle - range * 0.65), yEnd: .value("Value", point.value))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if point.id == lift.points.last?.id {
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(color).symbolSize(14)
            }
        }
        .chartYScale(domain: (middle - range * 0.65)...(middle + range * 0.65))
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    }
}

struct WorkoutInsightsPreview: View {
    let data: DataStore
    let now: Date
    var body: some View {
        let names = data.exById.mapValues(\.displayName)
        let sections = data.exById.mapValues { Set($0.primaryMuscles.compactMap { $0.section }) }
        let summary = TrainingInsightsSnapshot.build(sets: data.sets, names: names, primarySections: sections,
                                                     range: .fourWeeks, calendar: data.settings.calendar, now: now)
        Group {
            switch WorkoutPreviewContent.select(from: summary) {
            case .lift(let lift):
                VStack(alignment: .leading, spacing: 4) {
                    Text(lift.name).font(.caption2).foregroundStyle(MasoColor.textDim)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(delta(lift)).font(.subheadline.weight(.semibold)).foregroundStyle(MasoColor.accent)
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    LiftProgressSparkline(lift: lift).frame(height: 28).accessibilityHidden(true)
                    HStack(spacing: 4) {
                        Text(benchmark(lift)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Text("4 weeks").lineLimit(1).minimumScaleFactor(0.8)
                    }.font(.caption2).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            case .muscles(let muscles):
                if muscles.isEmpty {
                    Text("No data").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(muscles.prefix(5).enumerated()), id: \.element.id) { index, muscle in
                            HStack(spacing: 5) {
                                Text(muscle.group.displayName).font(.caption2).foregroundStyle(MasoColor.textDim)
                                    .lineLimit(1).minimumScaleFactor(0.65)
                                    .frame(width: 42, alignment: .leading)
                                OverviewProgressTrack(
                                    fraction: Double(muscle.sets) / Double(max(muscles.map(\.sets).max() ?? 0, 1)),
                                    accent: MasoColor.accent)
                                Text(muscle.sets.formatted(.number.locale(LanguageManager.currentLocale)))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(MasoColor.text)
                                    .frame(minWidth: 14, alignment: .trailing)
                            }
                            .opacity(muscles.count > 3 ? [1.0, 0.94, 0.78, 0.48, 0.20][index] : 1)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(muscle.group.displayName))
                            .accessibilityValue(Text(verbatim: String.localizedStringWithFormat(NSLocalizedString("%d sets", comment: ""), muscle.sets)))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: muscles.map {
                        $0.group.displayName + " " + String.localizedStringWithFormat(NSLocalizedString("%d sets", comment: ""), $0.sets)
                    }.joined(separator: ", ")))
                }
            }
        }.frame(width: 116, alignment: .leading).frame(minHeight: 76)
    }
    private func weight(_ value: Double) -> String {
        data.settings.weightUnit.fromKg(value).formatted(.number.precision(.fractionLength(0...1)).locale(LanguageManager.currentLocale)) + " " + data.settings.weightUnit.label
    }
    private func delta(_ lift: TrainingInsightsSnapshot.Lift) -> String {
        guard let change = lift.change else { return "—" }
        switch lift.metric {
        case .weight: return "+" + weight(change)
        case .reps: return "+" + String.localizedStringWithFormat(NSLocalizedString("%d reps", comment: ""), Int(change))
        case nil: return "—"
        }
    }
    private func benchmark(_ lift: TrainingInsightsSnapshot.Lift) -> String {
        switch lift.metric {
        case .weight(let reps): return String.localizedStringWithFormat(NSLocalizedString("%d reps", comment: ""), reps)
        case .reps(let load): return load > 0 ? weight(load) : NSLocalizedString("Bodyweight only", comment: "")
        case nil: return "—"
        }
    }
}

struct WellnessScoreCard: View {
    @Environment(DataStore.self) private var data
    @State private var goalSheet = false
    var body: some View {
        let score = data.wellnessScore(on: Date())
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(score.total.map(String.init) ?? "—").font(.largeTitle.weight(.semibold)).monospacedDigit()
                Text("/ 100").foregroundStyle(.secondary)
                Spacer()
                Text("Daily score").font(.headline)
            }
            Text(score.total == nil ? "Complete your records to see your score" : "Today · updating")
                .font(.subheadline).foregroundStyle(.secondary)
            scoreRow("Training", value: score.training, maximum: 40, color: MasoColor.accent)
            scoreRow("Diet", value: score.nutrition, maximum: 35, color: MasoColor.dietAccent)
            scoreRow("Sleep", value: score.sleep, maximum: 25, color: MasoColor.sleepAccent)
            Button { goalSheet = true } label: { Label("Today's training goal", systemImage: "slider.horizontal.3") }
                .buttonStyle(.bordered).controlSize(.small)
            let days = (0..<7).reversed().compactMap { data.settings.calendar.date(byAdding: .day, value: -$0, to: Date()) }
            Chart {
                ForEach(days, id: \.self) { date in
                    if let total = data.wellnessScore(on: date).total {
                        PointMark(x: .value("Day", date), y: .value("Score", total)).foregroundStyle(MasoColor.accent)
                    }
                }
            }.chartYScale(domain: 0...100).frame(height: 90)
            Text("Plan adherence, not a health or muscle-growth measurement. Training 40 · protein 20 · carbs 10 · fat 5 · sleep 25. Extra training or food earns no bonus.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(MasoMetrics.cardPadding).glassCardBackground()
        .task { data.captureWellnessGoal() }
        .sheet(isPresented: $goalSheet) { DailyTrainingGoalSheet() }
    }
    private func scoreRow(_ title: LocalizedStringKey, value: Double?, maximum: Int, color: Color) -> some View {
        HStack { Text(title).foregroundStyle(color); Spacer(); ProgressFractionText(numerator: value.map { String(Int($0.rounded())) } ?? "—", denominator: value == nil ? nil : String(maximum), numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim) }
    }
}

private struct DailyTrainingGoalSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @State private var rest = false
    @State private var count = 12
    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Toggle("Planned rest day", isOn: $rest)
                        .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    if !rest { Stepper("\(count) working sets", value: $count, in: 1...100) }
                } footer: { Text("Choose your plan before training. Rest days count as completed only when explicitly planned.") }
            }.navigationTitle("Today's training goal").navigationBarTitleDisplayMode(.inline)
                .onAppear { if let goal = data.wellnessGoal(on: Date()) { rest = goal.trainingSets == 0; count = max(1, goal.trainingSets ?? 12) } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            data.captureWellnessGoal()
                            let key = SleepPreferences.dayKey(Date(), calendar: data.settings.calendar)
                            var goals = data.settings.wellnessGoals ?? [:]
                            goals[key]?.trainingSets = rest ? 0 : count; goals[key]?.planID = nil
                            data.settings.wellnessGoals = goals; data.save(); dismiss()
                        }.disabled(DietNutritionTargets.build(settings: data.settings) == nil)
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}

struct WellnessDayCard: View {
    @Environment(DataStore.self) private var data
    let day: Date
    var body: some View {
        let score = data.wellnessScore(on: day)
        let meals = data.wellnessMeals(on: day)
        let total = meals.reduce(MealNutrition()) { $0 + $1.nutrition }
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        let sleep = HealthKitService.shared.sleepMinutes[data.settings.calendar.startOfDay(for: day)] ?? data.settings.sleepRecords?[key]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                Spacer()
                ProgressFractionText(numerator: score.total.map(String.init) ?? "—", denominator: score.total == nil ? nil : "100",
                                     numeratorColor: score.allMet ? MasoColor.accent : MasoColor.text, denominatorColor: MasoColor.textDim).font(.headline)
            }
            Text("Training: \(score.training.map { "\(Int($0.rounded())) / 40" } ?? "—")").font(.subheadline)
            Text(meals.isEmpty ? "Diet: —" : "Diet: P \(Int(total.protein)) g · C \(Int(total.carbs)) g · F \(Int(total.fat)) g").font(.subheadline)
            Text(sleep.map { "Sleep: \(Int($0) / 60)h \(Int($0) % 60)m" } ?? "Sleep: —").font(.subheadline)
            if !meals.isEmpty {
                DisclosureGroup("Meals") {
                    ForEach(meals) { meal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(meal.title)).font(.subheadline.weight(.semibold))
                            Text(meal.foods).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
        }.padding(MasoMetrics.cardPadding).glassCardBackground()
    }
}

struct WellnessHistorySection: View {
    @Environment(DataStore.self) private var data
    @State private var expanded = false
    private var days: [Date] {
        let calendar = data.settings.calendar
        let mealDates = (data.settings.mealCheckIns ?? []).map { calendar.startOfDay(for: $0.day) }
        let sleepDates = (data.settings.sleepRecords ?? [:]).keys.compactMap { key -> Date? in
            let components = key.split(separator: "-").compactMap { Int($0) }
            guard components.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2]))
        }
        return Array(Set(mealDates + sleepDates)).sorted(by: >)
    }
    var body: some View {
        if !days.isEmpty {
            Text("Daily records").font(.headline)
            ForEach(expanded ? days : Array(days.prefix(7)), id: \.self) { day in WellnessDayCard(day: day) }
            if days.count > 7 { Button(expanded ? "Show less" : "Show earlier days") { expanded.toggle() } }
        }
    }
}


/// Confirmed meal records and actual sleep samples only; unrecorded days are absent.
struct WellnessInsightsSnapshot {
    struct NutritionDay: Identifiable {
        var id: Date { day }
        let day: Date
        let nutrition: MealNutrition
        let goal: DailyWellnessGoal?
        let complete: Bool
        var met: Bool {
            guard complete, let goal else { return false }
            return nutrition.protein >= Double(goal.protein) && nutrition.carbs >= Double(goal.carbsMinimum) && nutrition.fat >= Double(goal.fatMinimum)
        }
    }
    struct SleepDay: Identifiable {
        var id: Date { day }
        let day: Date
        let minutes: Double
        let goal: Int?
        var met: Bool { goal.map { minutes >= Double($0) } ?? false }
    }
    let nutrition: [NutritionDay]
    let sleep: [SleepDay]
    static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func recordDates(settings: UserSettings, healthSleep: [Date: Double], calendar: Calendar, category: InsightsCategory) -> [Date] {
        if category == .diet { return (settings.mealCheckIns ?? []).map { calendar.startOfDay(for: $0.day) } }
        return (settings.sleepRecords ?? [:]).keys.compactMap { date($0, calendar: calendar) } + healthSleep.keys.map { calendar.startOfDay(for: $0) }
    }
    static func build(settings: UserSettings, healthSleep: [Date: Double], calendar: Calendar, start: Date, end: Date) -> Self {
        let records = (settings.mealCheckIns ?? []).filter { $0.day >= start && $0.day <= end && $0.nutrition.valid }
        let nutrition = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.day) }).map { day, records in
            let meals = Dictionary(grouping: records, by: \.mealID).compactMap { $0.value.max(by: { $0.confirmedAt < $1.confirmedAt }) }
            let goal = settings.wellnessGoals?[SleepPreferences.dayKey(day, calendar: calendar)]
            let complete = goal.map { $0.mealsComplete(meals) } ?? false
            return NutritionDay(day: day, nutrition: meals.reduce(MealNutrition()) { $0 + $1.nutrition }, goal: goal, complete: complete)
        }.sorted { $0.day < $1.day }
        var sleepRecords: [Date: Double] = [:]
        for (key, minutes) in settings.sleepRecords ?? [:] {
            if let day = date(key, calendar: calendar) { sleepRecords[day] = minutes }
        }
        for (day, minutes) in healthSleep { sleepRecords[calendar.startOfDay(for: day)] = minutes }
        let sleep = sleepRecords.compactMap { day, minutes -> SleepDay? in
            guard day >= start, day <= end, minutes.isFinite, minutes >= 0 else { return nil }
            let key = SleepPreferences.dayKey(day, calendar: calendar)
            let goal = settings.sleepPreferences?.recordedGoals[key] ?? settings.wellnessGoals?[key]?.sleepMinutes
            return SleepDay(day: day, minutes: minutes, goal: goal.flatMap { $0 > 0 ? $0 : nil })
        }.sorted { $0.day < $1.day }
        return .init(nutrition: nutrition, sleep: sleep)
    }
}

private struct LifestyleInsightsView: View {
    let data: DataStore
    let range: InsightsTimeRange
    let category: InsightsCategory
    private var start: Date {
        let dates = WellnessInsightsSnapshot.recordDates(settings: data.settings, healthSleep: HealthKitService.shared.sleepMinutes, calendar: data.settings.calendar, category: category)
        return range == .allTime ? (dates.min() ?? data.settings.calendar.startOfDay(for: Date())) : range.startDate(calendar: data.settings.calendar, now: Date(), records: [])
    }
    private var snapshot: WellnessInsightsSnapshot {
        WellnessInsightsSnapshot.build(settings: data.settings, healthSleep: HealthKitService.shared.sleepMinutes, calendar: data.settings.calendar, start: start, end: Date())
    }
    var body: some View {
        let records = snapshot
        VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
            Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(Date().formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption).foregroundStyle(.secondary)
            if category == .diet {
                if records.nutrition.isEmpty { emptyState } else { dietCards(records.nutrition) }
            } else {
                if records.sleep.isEmpty { emptyState } else { sleepCards(records.sleep) }
            }
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(category == .diet ? "No meal records in this period" : "No sleep records in this period")).font(.headline)
            Text(LocalizedStringKey(category == .diet ? "Confirm meal photos to see nutrition trends." : "Connect Apple Health to see your sleep trends.")).font(.subheadline).foregroundStyle(.secondary)
            NavigationLink(value: category == .diet ? AppDestination.diet : .sleep) {
                Label(LocalizedStringKey(category == .diet ? "Open Diet" : "Open Sleep"), systemImage: "chevron.right")
            }.buttonStyle(.bordered).controlSize(.small).tint(category.color)
        }.padding(MasoMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading).glassCardBackground()
    }
    private func dietCards(_ days: [WellnessInsightsSnapshot.NutritionDay]) -> some View {
        let average = days.reduce(MealNutrition()) { $0 + $1.nutrition }
        let divisor = Double(days.count)
        return VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recorded nutrition").font(.headline)
                Text("Daily average · logged days only").font(.caption).foregroundStyle(.secondary)
                HStack {
                    metric("Protein", value: "\(Int((average.protein / divisor).rounded())) g")
                    Spacer()
                    metric("Carbs", value: "\(Int((average.carbs / divisor).rounded())) g")
                    Spacer()
                    metric("Fat", value: "\(Int((average.fat / divisor).rounded())) g")
                }
                Text("\(days.filter(\.complete).count) / \(days.count) days fully logged").font(.subheadline).foregroundStyle(.secondary)
            }.padding(MasoMetrics.cardPadding).glassCardBackground()
            VStack(alignment: .leading, spacing: 12) {
                Text("Protein intake").font(.headline)
                Chart(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Protein (g)", day.nutrition.protein)).foregroundStyle(MasoColor.dietAccent)
                    if let goal = day.goal {
                        PointMark(x: .value("Day", day.day), y: .value("Target (g)", goal.protein)).foregroundStyle(.secondary).symbol(.diamond)
                    }
                }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.frame(height: 160)
                Text("Yellow: recorded protein · diamond: daily target").font(.caption).foregroundStyle(.secondary)
                Text("Partial meals count as recorded intake, not a complete day's total.").font(.caption).foregroundStyle(.secondary)
            }.padding(MasoMetrics.cardPadding).glassCardBackground()
            goalCard(met: days.filter(\.met).count, known: days.filter { $0.complete && $0.goal != nil }.count)
        }
    }
    private func sleepCards(_ days: [WellnessInsightsSnapshot.SleepDay]) -> some View {
        let average = days.reduce(0) { $0 + $1.minutes } / Double(days.count)
        return VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Average sleep").font(.headline)
                Text(Duration.seconds(average * 60), format: .time(pattern: .hourMinute)).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(MasoColor.sleepAccent)
                Text("\(days.count) nights recorded").font(.subheadline).foregroundStyle(.secondary)
            }.padding(MasoMetrics.cardPadding).glassCardBackground()
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep duration").font(.headline)
                Chart(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Hours", day.minutes / 60)).foregroundStyle(MasoColor.sleepAccent)
                    if let goal = day.goal {
                        PointMark(x: .value("Day", day.day), y: .value("Target", Double(goal) / 60)).foregroundStyle(.secondary).symbol(.diamond)
                    }
                }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.frame(height: 160)
                Text("Blue: recorded sleep · diamond: nightly target").font(.caption).foregroundStyle(.secondary)
            }.padding(MasoMetrics.cardPadding).glassCardBackground()
            goalCard(met: days.filter(\.met).count, known: days.filter { $0.goal != nil }.count)
        }
    }
    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(category.color) }
    }
    private func goalCard(met: Int, known: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goal met").font(.headline)
            ProgressFractionText(numerator: known > 0 ? String(met) : "—", denominator: known > 0 ? String(known) : nil,
                                 numeratorColor: category.color, denominatorColor: MasoColor.textDim).font(.largeTitle.weight(.semibold))
            Text(LocalizedStringKey(category == .diet ? "Complete days with saved nutrition targets" : "Nights with saved sleep targets")).font(.caption).foregroundStyle(.secondary)
        }.padding(MasoMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading).glassCardBackground()
    }
}
