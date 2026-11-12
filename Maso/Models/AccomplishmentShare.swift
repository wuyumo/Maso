import Foundation

/// User-initiated share facts for a calendar rhythm, one workout, or a comparable lift.
/// Dates use the caller's calendar (the user's timezone and week start). Sample design
/// numbers are not stored here.
enum AccomplishmentShare {
    /// Lean disclosure. Choosing an audience never turns a private field on.
    struct Privacy: Equatable {
        enum Audience: Equatable { case friend, coach, personal }
        var includePhoto = false
        var includeExactTime = false
        var audience: Audience = .friend

        mutating func select(_ audience: Audience) {
            self.audience = audience
        }

        /// Heart rate, body weight, location, and a display name are not exported.
        var includesHeartRate: Bool { false }
        var includesBodyWeight: Bool { false }
        var includesLocation: Bool { false }
        var includesDisplayName: Bool { false }
    }

    struct Rhythm: Equatable {
        struct Day: Equatable {
            let date: Date
            /// Workouts that logged a set on this calendar day. A future day is 0.
            let sessions: Int
            let isFuture: Bool
            var dietProgress: Double? = nil
            var sleepMinutes: Double? = nil
            var sleepProgress: Double? = nil
        }
        let monthly: Bool
        let firstWeekday: Int
        let timeZoneID: String
        let start: Date
        let end: Date
        /// Set while the selected month or week still contains today.
        let asOf: Date?
        let trainingDays: Int
        let sessions: Int
        let days: [Day]
        var isEmpty: Bool { trainingDays == 0 && sessions == 0 }
        var averageDiet: Double? {
            let values = days.compactMap(\.dietProgress)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        var averageSleep: Double? {
            let values = days.compactMap(\.sleepMinutes)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    enum SessionKind: Equatable {
        /// Every set shares one saved training-session id.
        case single(id: String)
        /// No single session id, or more than one. This is a plan/day record, not one workout.
        case aggregate
    }

    enum DayPart: Equatable { case morning, afternoon, evening, night }

    struct SessionFact: Equatable {
        let kind: SessionKind
        let name: String
        let start: Date
        let end: Date
        let setCount: Int
        /// Minutes from the first set to the last, or a caller-supplied elapsed time.
        /// Missing when the span is under a minute and no elapsed time was supplied.
        let durationMinutes: Int?
        /// Coarse part of day for one session that stays inside a single part. Nil for an aggregate.
        let dayPart: DayPart?
        var isAggregate: Bool {
            if case .aggregate = kind { return true }
            return false
        }
    }

    struct SessionPresentation: Equatable {
        let showsExactTime: Bool
        let showsDayPart: Bool
        let includesPhoto: Bool
        let includesHeartRate: Bool
        let includesBodyWeight: Bool
        let includesLocation: Bool
        let includesDisplayName: Bool
    }

    struct Progress: Equatable {
        let exerciseID: String
        let name: String
        /// True when the stored weight is one dumbbell, matching ExerciseWeightReference.
        let perDumbbell: Bool
        let reps: Int
        let previousKg: Double
        let currentKg: Double
        let previousDate: Date
        let currentDate: Date
        var deltaKg: Double { currentKg - previousKg }
    }

    static func rhythm(sets: [SetRecord], focus: Date, monthly: Bool, calendar: Calendar, now: Date,
                       diet: [Date: Double] = [:], sleep: [Date: Double] = [:], sleepProgress: [Date: Double] = [:]) -> Rhythm {
        let start = DailyRecordCalendar.start(focus, monthly: monthly, calendar: calendar)
        let end: Date = {
            if monthly {
                let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                return calendar.date(byAdding: .day, value: -1, to: next) ?? start
            }
            return calendar.date(byAdding: .day, value: 6, to: start) ?? start
        }()
        let today = calendar.startOfDay(for: now)
        let asOf: Date? = (today >= start && today <= end) ? now : nil
        var trainingDays = Set<Date>()
        var sessionIDs = Set<String>()
        var legacy = Set<String>()
        var perDayIDs: [Date: Set<String>] = [:]
        var perDayLegacy: [Date: Set<String>] = [:]
        for record in sets where record.performedAt <= now {
            let day = calendar.startOfDay(for: record.performedAt)
            guard day >= start, day <= end, day <= today else { continue }
            trainingDays.insert(day)
            if let id = record.workoutSessionID, !id.isEmpty {
                sessionIDs.insert(id)
                perDayIDs[day, default: []].insert(id)
            } else {
                let token = (record.planId ?? "free") + "|" + String(day.timeIntervalSince1970)
                legacy.insert(token)
                perDayLegacy[day, default: []].insert(token)
            }
        }
        var days: [Rhythm.Day] = []
        var cursor = start
        while cursor <= end {
            let future = cursor > today
            let count = future ? 0 : (perDayIDs[cursor]?.count ?? 0) + (perDayLegacy[cursor]?.count ?? 0)
            let dietValue = diet[cursor].flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let sleepValue = sleep[cursor].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            days.append(.init(date: cursor, sessions: count, isFuture: future,
                              dietProgress: future ? nil : dietValue, sleepMinutes: future ? nil : sleepValue,
                              sleepProgress: future ? nil : sleepProgress[cursor]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return Rhythm(monthly: monthly, firstWeekday: calendar.firstWeekday, timeZoneID: calendar.timeZone.identifier, start: start, end: end, asOf: asOf,
                      trainingDays: trainingDays.count, sessions: sessionIDs.count + legacy.count, days: days)
    }

    /// Sets that belong to one saved session id. Other same-day workouts stay out.
    static func records(sessionID: String, in sets: [SetRecord]) -> [SetRecord] {
        sets.filter { $0.workoutSessionID == sessionID && $0.performedAt <= Date() }
            .sorted { $0.performedAt < $1.performedAt }
    }

    static func sessionFact(records: [SetRecord], name: String, calendar: Calendar, durationSeconds: Int? = nil) -> SessionFact {
        let ordered = records.filter { $0.performedAt <= Date() }.sorted { $0.performedAt < $1.performedAt }
        let ids = Set(ordered.compactMap { $0.workoutSessionID }.filter { !$0.isEmpty })
        let hasLegacy = ordered.contains { ($0.workoutSessionID ?? "").isEmpty }
        let kind: SessionKind = (ids.count == 1 && !hasLegacy) ? .single(id: ids.first!) : .aggregate
        let start = ordered.first?.performedAt ?? Date()
        let end = ordered.last?.performedAt ?? start
        let elapsed = durationSeconds.flatMap { $0 >= 60 ? $0 / 60 : nil }
        let span = Int((end.timeIntervalSince(start) / 60).rounded())
        let singleSpan: Int?
        if case .single = kind, span >= 1 {
            singleSpan = span
        } else {
            singleSpan = nil
        }
        // An aggregate has no single workout length. A caller-supplied elapsed time
        // (the completion screen) is still a real measurement.
        let duration = elapsed ?? singleSpan
        let part: DayPart? = {
            guard case .single = kind, let first = ordered.first else { return nil }
            let startPart = DayPart.of(first.performedAt, calendar: calendar)
            let endPart = DayPart.of(end, calendar: calendar)
            return startPart == endPart ? startPart : nil
        }()
        return SessionFact(kind: kind, name: name, start: start, end: end, setCount: ordered.count,
                           durationMinutes: ordered.isEmpty ? nil : duration, dayPart: part)
    }

    static func present(_ fact: SessionFact, privacy: Privacy) -> SessionPresentation {
        SessionPresentation(
            showsExactTime: !fact.isAggregate && privacy.includeExactTime,
            showsDayPart: !fact.isAggregate && !privacy.includeExactTime && fact.dayPart != nil,
            includesPhoto: privacy.includePhoto,
            includesHeartRate: privacy.includesHeartRate,
            includesBodyWeight: privacy.includesBodyWeight,
            includesLocation: privacy.includesLocation,
            includesDisplayName: privacy.includesDisplayName
        )
    }

    /// Same exercise id (same equipment variant), same reps, a later heavier recorded weight.
    /// Dumbbell kilograms stay the stored per-bell value. A heavier set with fewer reps is not a match.
    static func bestProgress(sets: [SetRecord], names: [String: String], perDumbbell: [String: Bool], now: Date = Date()) -> Progress? {
        let valid = sets.filter {
            $0.performedAt <= now && ($0.reps ?? 0) > 0 && ($0.weight ?? 0) > 0 && ($0.weight?.isFinite ?? false)
        }
        var best: Progress?
        for (exerciseID, rows) in Dictionary(grouping: valid, by: \.exerciseId) {
            for (reps, group) in Dictionary(grouping: rows, by: { $0.reps! }) {
                let ordered = group.sorted { $0.performedAt < $1.performedAt }
                guard ordered.count >= 2, let current = ordered.last, let previous = ordered.dropLast().last,
                      current.performedAt > previous.performedAt,
                      let currentKg = current.weight, let previousKg = previous.weight,
                      currentKg > previousKg + 0.05 else { continue }
                let candidate = Progress(exerciseID: exerciseID, name: names[exerciseID] ?? current.exerciseName,
                                         perDumbbell: perDumbbell[exerciseID] == true, reps: reps,
                                         previousKg: previousKg, currentKg: currentKg,
                                         previousDate: previous.performedAt, currentDate: current.performedAt)
                if let existing = best {
                    if candidate.currentDate > existing.currentDate
                        || (candidate.currentDate == existing.currentDate && candidate.deltaKg > existing.deltaKg) {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }
        return best
    }
}

extension AccomplishmentShare.DayPart {
    static func of(_ date: Date, calendar: Calendar) -> Self {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}
