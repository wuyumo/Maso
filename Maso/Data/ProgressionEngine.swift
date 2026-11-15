import Foundation

struct ExerciseLoadPolicy: Codable, Equatable, Sendable {
    var maintain = false
    var limitKg: Double? = nil
}

struct ProgressionNotice: Codable, Equatable, Sendable {
    let evidence: String
    let shownAt: Date
    var declined = false
}

struct LoadProgressionPreferences: Codable, Equatable, Sendable {
    var maintain = false
    var exercises: [String: ExerciseLoadPolicy] = [:]
    var notices: [String: ProgressionNotice] = [:]
}

/// Optional working-load suggestions. Thresholds and cooldowns are product rules,
/// not measurements of effort, a strength ceiling, or a validated prescription.
enum ProgressionEngine {
    struct Suggestion {
        let weightKg: Double
        let deltaKg: Double
        let evidence: String
    }

    static func suggestion(exerciseId: String, targetReps: Int?, sets: [SetRecord], exercise: Exercise?,
                           goal: TrainingGoalKind, currentWeight: Double?, requiredSets: Int = 2,
                           preferences: LoadProgressionPreferences, activeSessionID: String? = nil,
                           now: Date = Date()) -> Suggestion? {
        let policy = preferences.exercises[exerciseId] ?? .init()
        guard !preferences.maintain, !policy.maintain,
              goal != .generalFitness, goal != .endurance,
              let exercise, ExerciseWeightReference.expectsLoad(exercise), exercise.unilateral != true,
              let load = currentWeight, load.isFinite, load > 0, load <= 500,
              let reps = targetReps, (1...12).contains(reps) else { return nil }
        if let limit = policy.limitKg, !limit.isFinite || limit <= 0 || limit > 500 || load >= limit { return nil }
        let needed = goal == .getStronger ? 2 : 3
        let upper = goal == .getStronger ? max(5, reps) + 1 : max(12, reps)
        let records = sets.filter {
            $0.exerciseId == exerciseId && $0.category == .strength
                && $0.workoutSessionID?.isEmpty == false && $0.workoutSessionID != activeSessionID
                && now.timeIntervalSince($0.performedAt) > 1800 && now.timeIntervalSince($0.performedAt) <= 90 * 86400
        }
        let unique = Dictionary(grouping: records, by: \.id).compactMap { $0.value.count == 1 ? $0.value.first : nil }
        guard unique.count == records.count else { return nil }
        let sessions = Dictionary(grouping: unique, by: { $0.workoutSessionID! }).values.sorted {
            ($0.map(\.performedAt).max() ?? .distantPast) > ($1.map(\.performedAt).max() ?? .distantPast)
        }
        guard sessions.count >= needed else { return nil }
        let recent = Array(sessions.prefix(needed))
        let calendar = Calendar.current
        guard Set(recent.compactMap { $0.map(\.performedAt).max().map { calendar.startOfDay(for: $0) } }).count == needed,
              let latest = recent.first?.map(\.performedAt).max(), now.timeIntervalSince(latest) <= 21 * 86400,
              // Do not reuse old success after a new load, incomplete session, or rep regression.
              !sets.contains(where: { $0.exerciseId == exerciseId && $0.workoutSessionID != activeSessionID
                  && $0.performedAt <= now && $0.performedAt > latest }) else { return nil }
        for session in recent {
            let working = session.filter { abs(($0.weight ?? 0) - load) < 0.01 }
            guard working.count >= max(2, requiredSets), Set(session.compactMap(\.setNumber)).count == session.count,
                  session.allSatisfy({ $0.weight?.isFinite == true && ($0.weight ?? 0) > 0 && ($0.weight ?? 0) <= load + 0.01
                      && ($0.reps.map { (1...999).contains($0) } ?? false) && $0.duration == nil
                      && ($0.setNumber.map { (1...999).contains($0) } ?? false) }),
                  let first = session.map(\.performedAt).min(), let last = session.map(\.performedAt).max(),
                  last.timeIntervalSince(first) <= 12 * 3600,
                  working.allSatisfy({ ($0.reps ?? 0) >= upper }) else { return nil }
        }
        let increment: Double
        switch ExerciseWeightReference.equipment(exercise) {
        case .dumbbell, .kettlebell: increment = 1
        case .barbell, .machine, .smith, .cable: increment = 2.5
        default: return nil
        }
        guard increment / load <= 0.10 else { return nil }
        let proposed = load + increment
        guard proposed <= 500 else { return nil }
        if let limit = policy.limitKg, proposed > limit { return nil }
        let evidence = ([goal.rawValue, String(reps), String(requiredSets), String(load)] + recent.flatMap { $0.map(\.id) }.sorted()).joined(separator: "|")
        let baseDays = goal == .getStronger ? 7 : goal == .loseFat ? 28 : 21
        let nearLimit = policy.limitKg.map { load >= 0.9 * $0 } ?? false
        if let notice = preferences.notices[exerciseId] {
            let days = notice.declined || nearLimit ? max(42, baseDays) : baseDays
            guard notice.evidence != evidence, now.timeIntervalSince(notice.shownAt) >= Double(days) * 86400 else { return nil }
            // The same completed sets cannot be recycled as new readiness evidence.
            guard recent.allSatisfy({ ($0.map(\.performedAt).min() ?? .distantPast) > notice.shownAt }) else { return nil }
        }
        let globalDays = goal == .loseFat ? 14 : 7
        guard !preferences.notices.values.contains(where: { now.timeIntervalSince($0.shownAt) < Double(globalDays) * 86400 }) else { return nil }
        return .init(weightKg: proposed, deltaKg: increment, evidence: evidence)
    }
}

/// Exact-exercise evidence only. Recording units alone cannot predict another lift.
enum ExerciseWeightReference {
    struct Reference {
        let kilograms: Double
        let sourceExerciseID: String
        var source: ExerciseParameterSuggestion.Source = .history
        var recordID: String? = nil
        var recordedAt: Date? = nil
        var ruleID: String? = nil
    }

    static func equipment(_ ex: Exercise) -> EquipmentCategory? {
        ([ex.equipment].compactMap { $0 } + (ex.equipmentAll ?? [])).compactMap(EquipmentCategory.category).first
    }

    static func perDumbbell(_ ex: Exercise) -> Bool { equipment(ex) == .dumbbell }

    /// A missing target remains unknown; equipment only controls field visibility.
    static func expectsLoad(_ ex: Exercise) -> Bool {
        guard ex.category == .strength else { return false }
        let supportOnly: Set<String> = ["preacher_bench", "hyperextension_bench", "ghd_machine", "sissy_squat_machine", "rack", "power_rack", "squat_rack", "platform"]
        let items = [ex.equipment].compactMap { $0 } + (ex.equipmentAll ?? [])
        return items.contains { raw in
            guard !supportOnly.contains(raw.lowercased()), let category = EquipmentCategory.category(for: raw) else { return false }
            return [.barbell, .dumbbell, .cable, .machine, .smith, .kettlebell].contains(category)
        }
    }


    static func needsCalibration(_ step: PlanStep, exercise: Exercise?) -> Bool {
        guard let exercise, expectsLoad(exercise), step.duration == nil else { return false }
        return step.weight == nil && step.setWeights?.contains(where: { $0 != nil }) != true
    }

    static func latest(for target: Exercise, records: [SetRecord], library: [String: Exercise]) -> Reference? {
        let valid = records.filter { $0.performedAt <= Date() && ($0.reps ?? 0) > 0 && ($0.reps ?? 0) <= 999
            && ($0.weight.map { $0.isFinite && $0 >= 0 && $0 <= 500 } ?? false) }
        let exact = valid.filter { $0.exerciseId == target.id }.max { $0.performedAt < $1.performedAt }
        if let exact, let weight = exact.weight { return .init(kilograms: weight, sourceExerciseID: target.id, recordID: exact.id, recordedAt: exact.performedAt) }
        // Recording-unit conversion does not establish equivalent working strength.
        // Cross-exercise load prediction needs separately validated personal evidence.
        return nil
    }

}

/// Superseded for product fill by FullBodyLoadEstimate. Kept so older direct checks still describe the previous three-lift table.
/// Product heuristics, not measured maximums or research-backed individual ratios.
/// A completed set is required. Suggestions themselves never enter this evidence input.
enum RoughExerciseLoadReference {
    // Ratios share a flat-barbell-bench reference. Cable stacks differ by pulley setup.
    static let relativeLoads: [String: Double] = [
        "bench_press_barbell": 1, "incline_bench_press_barbell": 0.8,
        "triceps_pushdown_straight_bar": 0.3
    ]

    static func reference(for target: Exercise, targetReps: Int?, records: [SetRecord],
                          now: Date = Date()) -> ExerciseWeightReference.Reference? {
        guard let targetRatio = relativeLoads[target.id], let reps = targetReps,
              (1...20).contains(reps), target.category == .strength else { return nil }
        // Only the two barbell presses anchor estimates; never infer presses from cable stacks.
        let eligible = records.filter {
            ["bench_press_barbell", "incline_bench_press_barbell"].contains($0.exerciseId)
                && $0.exerciseId != target.id && $0.category == .strength && $0.duration == nil
                && ($0.weight.map { $0.isFinite && $0 > 0 && $0 <= 500 } ?? false)
                && (1...20).contains($0.reps ?? 0)
                && now.timeIntervalSince($0.performedAt) >= 0
                && now.timeIntervalSince($0.performedAt) <= 30 * 86400
        }
        guard let record = eligible.max(by: { $0.performedAt < $1.performedAt }),
              let sourceRatio = relativeLoads[record.exerciseId], let load = record.weight,
              let sourceReps = record.reps else { return nil }
        let reference = load * (1 + Double(sourceReps) / 30)
        let estimate = reference / (1 + Double(reps) / 30) * targetRatio / sourceRatio * 0.7
        let rounded = floor(estimate / 2.5) * 2.5
        guard rounded >= 2.5, rounded <= 500 else { return nil }
        return .init(kilograms: rounded, sourceExerciseID: record.exerciseId, source: .roughEstimate,
                     recordID: record.id, recordedAt: record.performedAt, ruleID: "rough-press-v1-\(reps)")
    }
}

/// Retained for old snapshots and direct checks. Empty targets now use FullBodyLoadEstimate.
/// Narrow, auditable population priors. Formula output is 6RM, not a working load.
/// Wong et al. 2013, JSSM 12:38–43, PMID 24149723; Table 2 and Methods.
/// Age/load windows, 30-day expiry, target 6–12, 75% starting margin and rounding
/// are conservative PRODUCT gates, not validated boundaries/prescriptions from the paper.
enum CrossExerciseLoadReference {
    static let studyURL = URL(string: "https://www.jssm.org/jssm-12-38.xml-Fulltext")!
    static let anchorID = "bench_press_barbell"
    static let targetIDs: Set<String> = ["bicep_curl_barbell", "overhead_extension_dumbbell_two_hand"]

    static func clearIfUnsupported(_ step: inout PlanStep) {
        if step.isSuggested("weight"), let suggestion = step.parameterSuggestions?["weight"], suggestion.source == .personalHistory {
            if PersonalExerciseLoadReference.ruleID(reps: step.reps) == nil
                || suggestion.ruleID != PersonalExerciseLoadReference.ruleID(reps: step.reps)
                || step.duration != nil || step.setReps?.contains(where: { $0 != nil }) == true {
                step.weight = nil; step.confirmParameter("weight")
            }
            return
        }
        guard step.isSuggested("weight"), step.parameterSuggestions?["weight"]?.source == .crossExercise else { return }
        let supported = targetIDs.contains(step.exerciseId) && (6...12).contains(step.reps ?? 0)
            && step.duration == nil && step.setReps?.contains(where: { $0 != nil }) != true
        if !supported { step.weight = nil; step.confirmParameter("weight") }
    }

    static func reference(for target: Exercise, targetReps: Int?, records: [SetRecord],
                          settings: UserSettings, library: [String: Exercise], now: Date = Date()) -> ExerciseWeightReference.Reference? {
        guard targetIDs.contains(target.id), target.category == .strength, target.unilateral != true,
              let reps = targetReps, (6...12).contains(reps),
              settings.gender == .male, let age = settings.age, (18...30).contains(age),
              let anchor = library[anchorID], anchor.category == .strength,
              ExerciseWeightReference.equipment(anchor) == .barbell,
              ExerciseWeightReference.equipment(target) == (target.id == "bicep_curl_barbell" ? .barbell : .dumbbell) else { return nil }
        let eligible = records.filter { record in
            guard record.exerciseId == anchorID, record.category == .strength, record.hasConfirmedSixRM,
                  let load = record.weight, load.isFinite, (30...70).contains(load) else { return false }
            let age = now.timeIntervalSince(record.performedAt)
            return age >= 0 && age <= 30 * 86400
        }
        guard let source = eligible.max(by: { $0.performedAt < $1.performedAt }), let load = source.weight else { return nil }
        let intercept = target.id == "bicep_curl_barbell" ? 6.20 : -0.60
        // Both selected formulas use one shared object: total barbell or ONE dumbbell
        // held with BOTH hands. No ambiguous per-hand/pair conversion is performed.
        let predictedSixRM = 0.33 * load + intercept
        let startingLoad = floor(predictedSixRM * 0.75 / 2.5) * 2.5
        guard startingLoad.isFinite, startingLoad > 0 else { return nil }
        return .init(kilograms: startingLoad, sourceExerciseID: anchorID, source: .crossExercise,
                     recordID: source.id, recordedAt: source.performedAt,
                     ruleID: target.id == "bicep_curl_barbell" ? "wong2013-curl-start-v1" : "wong2013-triceps-start-v1")
    }
}

/// Observed working-load relationships, not strength equivalence. All thresholds are
/// product abstention rules; a held-out session is required, not a claim of clinical accuracy.
enum PersonalExerciseLoadReference {
    static func ruleID(reps: Int?) -> String? {
        guard let reps, (6...12).contains(reps) else { return nil }
        return "personal-working-\(reps)-v1"
    }

    private struct SessionLoad {
        let exerciseID: String
        let sessionID: String
        let weight: Double
        let date: Date
        let recordID: String
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func reference(for target: Exercise, targetReps: Int?, records: [SetRecord],
                          library: [String: Exercise], now: Date = Date()) -> ExerciseWeightReference.Reference? {
        guard let rule = ruleID(reps: targetReps), target.unilateral != true,
              ExerciseWeightReference.expectsLoad(target), target.category == .strength else { return nil }
        // Fresh own records win. This model only refreshes an old, unconfirmed target.
        let latestTarget = records.filter { $0.exerciseId == target.id && $0.performedAt <= now }.map(\.performedAt).max()
        guard let latestTarget, now.timeIntervalSince(latestTarget) > 14 * 86400 else { return nil }
        let eligible = records.filter {
            $0.category == .strength && $0.reps == targetReps && $0.duration == nil
                && ($0.weight.map { $0.isFinite && $0 > 0 && $0 <= 500 } ?? false)
                && $0.performedAt <= now && now.timeIntervalSince($0.performedAt) <= 180 * 86400
                && $0.workoutSessionID?.isEmpty == false && ($0.setNumber.map { (1...999).contains($0) } ?? false)
        }
        let unique = Dictionary(grouping: eligible, by: \.id).compactMap { $0.value.count == 1 ? $0.value.first : nil }
        let sessions = Dictionary(grouping: unique, by: { $0.workoutSessionID! }).values.flatMap { session -> [SessionLoad] in
            guard let start = session.map(\.performedAt).min(), let end = session.map(\.performedAt).max(),
                  end.timeIntervalSince(start) <= 12 * 3600 else { return [] }
            return Dictionary(grouping: session, by: \.exerciseId).compactMap { id, sets in
                guard sets.count >= 2, Set(sets.compactMap(\.setNumber)).count == sets.count,
                      let exercise = library[id], exercise.unilateral != true, ExerciseWeightReference.expectsLoad(exercise),
                      let last = sets.max(by: { $0.performedAt < $1.performedAt }) else { return nil }
                let weights = sets.compactMap(\.weight), load = median(weights)
                guard weights.allSatisfy({ abs($0 / load - 1) <= 0.10 }) else { return nil }
                return SessionLoad(exerciseID: id, sessionID: last.workoutSessionID!, weight: load,
                                   date: last.performedAt, recordID: last.id)
            }
        }
        let targets = Dictionary(uniqueKeysWithValues: sessions.filter { $0.exerciseID == target.id }.map { ($0.sessionID, $0) })
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var candidates: [ExerciseWeightReference.Reference] = []
        for (id, sourceSessions) in Dictionary(grouping: sessions.filter { $0.exerciseID != target.id }, by: \.exerciseID) {
            let pairs = sourceSessions.compactMap { source -> (source: SessionLoad, target: SessionLoad)? in
                guard let target = targets[source.sessionID] else { return nil }
                return (source, target)
            }.sorted { $0.target.date < $1.target.date }
            guard pairs.count >= 5, Set(pairs.map { calendar.startOfDay(for: $0.target.date) }).count >= 5,
                  let first = pairs.first, let holdout = pairs.last,
                  holdout.target.date == latestTarget,
                  holdout.target.date.timeIntervalSince(first.target.date) >= 28 * 86400,
                  let current = sourceSessions.max(by: { $0.date < $1.date }),
                  now.timeIntervalSince(current.date) <= 14 * 86400, current.date > latestTarget,
                  !records.contains(where: { $0.exerciseId == id && $0.performedAt <= now && $0.performedAt > current.date }) else { continue }
            let trainingRatios = pairs.dropLast().map { $0.target.weight / $0.source.weight }
            let ratio = median(trainingRatios)
            guard trainingRatios.allSatisfy({ abs($0 / ratio - 1) <= 0.15 }),
                  abs(holdout.source.weight * ratio / holdout.target.weight - 1) <= 0.10,
                  (0.8...1.2).contains(current.weight / holdout.source.weight) else { continue }
            let estimate = floor(current.weight * ratio * 2) / 2
            guard estimate > 0, estimate <= 500,
                  (0.9...1.1).contains(estimate / holdout.target.weight) else { continue }
            candidates.append(.init(kilograms: estimate, sourceExerciseID: id, source: .personalHistory,
                                    recordID: current.recordID, recordedAt: current.date, ruleID: rule))
        }
        guard !candidates.isEmpty else { return nil }
        let center = median(candidates.map(\.kilograms))
        guard candidates.allSatisfy({ abs($0.kilograms / center - 1) <= 0.10 }) else { return nil }
        return candidates.sorted {
            if $0.recordedAt != $1.recordedAt { return ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
            return $0.sourceExerciseID < $1.sourceExerciseID
        }.first
    }
}
