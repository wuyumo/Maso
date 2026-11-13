import Foundation

/// One finished session's training contribution.
///
/// Loaded volume is external weight times reps, counted once per completed set.
/// Muscle numbers reuse the recovery split, 1.0 primary and 0.4 synergist, and stay in sets.
/// The result does not decay with time and does not read any other session.
struct SessionMuscleReport: Equatable {
    struct HeartPoint: Equatable {
        let date: Date
        let bpm: Double
    }

    struct HeartSegment: Equatable, Identifiable {
        let id: String
        let points: [HeartPoint]
        var drawsLine: Bool { points.count >= 2 }
    }

    enum Load: Equatable {
        case loaded(sets: Int, weightKg: Double, reps: [Int])
        case mixed(sets: Int, volumeKg: Double)
        case bodyweight(sets: Int, reps: [Int])
        case timed(seconds: Int)
        case counted(sets: Int)
    }

    struct ExerciseFacts: Equatable, Identifiable {
        let id: String
        let name: String
        let variant: String?
        let setCount: Int
        let load: Load
        /// Kilograms times reps for this exercise. Nil when nothing had a positive external load.
        let loadedVolumeKg: Double?
        let workSeconds: Double?
        let timingIncomplete: Bool
        let heart: [HeartSegment]
        let records: [SetRecord]
    }

    struct MuscleRow: Equatable, Identifiable {
        let id: String
        let muscle: MuscleGroup
        let nodes: [String]
        /// Primary 1.0 / synergist 0.4 set contribution. Not kilograms.
        let allocatedSets: Double
        let exercises: [ExerciseFacts]
    }

    static let primaryShare = 1.0
    static let synergistShare = 0.4
    static let heartGap: TimeInterval = 20

    let setCount: Int
    let workSeconds: Double?
    let timingIncomplete: Bool
    /// Nil means no external load was logged. It is not a measured zero.
    let loadedVolumeKg: Double?
    let muscles: [MuscleRow]
    /// Relative to this session's largest muscle contribution. Absent muscles stay unpainted.
    let intensity: [MuscleGroup: Double]

    struct ShareSelection: Equatable {
        var includeDetails = false
        var includeHeart = false
        /// A photo on the page is not part of the image until this is on.
        var includePhoto = false
    }

    struct ShareContent: Equatable {
        var name: String?
        var day: Date?
        var work: String
        var sets: String
        var volume: String
        var muscles: [MuscleShare]
        var includesPhoto: Bool

        struct MuscleShare: Equatable, Identifiable {
            var id: String
            var name: String
            var exercises: [ExerciseShare]
            var heart: String?
        }

        struct ExerciseShare: Equatable, Identifiable {
            var id: String
            var name: String
            var sets: [String]
        }

        /// The words painted on the exported card. Opening a section does not add them.
        var lines: [String] {
            var result: [String] = []
            if let name, !name.isEmpty { result.append(name) }
            if let day { result.append(SessionMuscleReport.dayLabel(day)) }
            result.append(contentsOf: [work, sets, volume])
            for muscle in muscles where !muscle.exercises.isEmpty || muscle.heart != nil {
                result.append(muscle.name)
                for exercise in muscle.exercises {
                    result.append(exercise.name)
                    result.append(contentsOf: exercise.sets)
                }
                if let heart = muscle.heart { result.append(heart) }
            }
            if includesPhoto { result.append("photo") }
            return result
        }
    }

    static func make(
        records: [SetRecord],
        exercises: [String: Exercise],
        regions: [MuscleBodyRegion],
        samples: [String: [HeartPoint]] = [:]
    ) -> SessionMuscleReport {
        let ordered = records.sorted { $0.performedAt < $1.performedAt }
        let loaded = ordered.compactMap(loadedKilograms)
        let measured = ordered.compactMap(\.activeSeconds)
        var buckets = regionBuckets(regions)
        var exerciseOrder: [String] = []
        var seenExercises = Set<String>()
        for record in ordered where countsAsMuscleWork(record.category) {
            guard let exercise = exercises[record.exerciseId] else { continue }
            if seenExercises.insert(record.exerciseId).inserted { exerciseOrder.append(record.exerciseId) }
            let primary = expandAnatomyMuscles(exercise.primaryMuscles)
            let synergist = expandAnatomyMuscles(exercise.muscleGroups).subtracting(primary)
            for key in buckets.keys {
                let area = expandAnatomyMuscles(Array(key))
                let share: Double
                if !primary.isDisjoint(with: area) { share = primaryShare }
                else if !synergist.isDisjoint(with: area) { share = synergistShare }
                else { continue }
                guard var bucket = buckets[key] else { continue }
                bucket.share += share
                bucket.exerciseShare[record.exerciseId, default: 0] += share
                buckets[key] = bucket
            }
        }
        let facts = exerciseFacts(records: ordered, exercises: exercises, samples: samples)
        let built = muscleRows(buckets: buckets, exerciseOrder: exerciseOrder, facts: facts)
        return SessionMuscleReport(
            setCount: ordered.count,
            workSeconds: measured.isEmpty ? nil : measured.reduce(0, +),
            timingIncomplete: ordered.contains { $0.activeIntervals == nil },
            loadedVolumeKg: loaded.isEmpty ? nil : loaded.reduce(0, +),
            muscles: built.rows,
            intensity: built.intensity
        )
    }

    /// Statement-level on purpose. One nested `map`/`sorted` chain does not type-check in Xcode 27.1.
    private static func muscleRows(
        buckets: [Set<MuscleGroup>: Bucket],
        exerciseOrder: [String],
        facts: [String: ExerciseFacts]
    ) -> (rows: [MuscleRow], intensity: [MuscleGroup: Double]) {
        var rows: [MuscleRow] = []
        for bucket in buckets.values where bucket.share > 0 {
            var listed: [String] = []
            for exerciseID in exerciseOrder {
                let share = bucket.exerciseShare[exerciseID] ?? 0
                if share > 0 { listed.append(exerciseID) }
            }
            listed.sort { (leftID: String, rightID: String) in
                let leftShare = bucket.exerciseShare[leftID] ?? 0
                let rightShare = bucket.exerciseShare[rightID] ?? 0
                if leftShare != rightShare { return leftShare > rightShare }
                let leftName = facts[leftID]?.name ?? leftID
                let rightName = facts[rightID]?.name ?? rightID
                return leftName < rightName
            }
            var exercises: [ExerciseFacts] = []
            for exerciseID in listed {
                if let fact = facts[exerciseID] { exercises.append(fact) }
            }
            let nodes = bucket.nodes.sorted()
            rows.append(MuscleRow(
                id: nodes.joined(separator: "|"),
                muscle: bucket.muscle,
                nodes: bucket.nodes,
                allocatedSets: bucket.share,
                exercises: exercises
            ))
        }
        rows.sort { (left: MuscleRow, right: MuscleRow) in
            if left.allocatedSets != right.allocatedSets { return left.allocatedSets > right.allocatedSets }
            return left.id < right.id
        }
        var intensity: [MuscleGroup: Double] = [:]
        let peak = rows.reduce(0) { partial, row in max(partial, row.allocatedSets) }
        if peak > 0 {
            for row in rows {
                let value = row.allocatedSets / peak
                for (key, bucket) in buckets where bucket.nodes == row.nodes {
                    for muscle in key { intensity[muscle] = value }
                }
            }
        }
        return (rows, intensity)
    }

    static func countsAsMuscleWork(_ category: ExerciseCategory) -> Bool {
        switch category {
        case .cardio, .stretching, .mobility, .flexibility: return false
        case .strength, .hypertrophyFocus, .plyometric, .calisthenics: return true
        }
    }

    /// Positive external load only. Zero, missing weight, bodyweight, timed work, and cardio stay nil.
    static func loadedKilograms(_ record: SetRecord) -> Double? {
        guard countsAsMuscleWork(record.category),
              let weight = record.weight, weight > 0,
              let reps = record.reps, reps > 0 else { return nil }
        return weight * Double(reps)
    }

    static func heartSegments(for record: SetRecord, samples: [HeartPoint]) -> [HeartSegment] {
        guard let intervals = record.activeIntervals else { return [] }
        var segments: [HeartSegment] = []
        for (index, interval) in intervals.enumerated() {
            let inside = samples
                .filter { $0.date >= interval.start && $0.date < interval.end && $0.bpm.isFinite }
                .sorted { $0.date < $1.date }
            var current: [HeartPoint] = []
            var part = 0
            func flush() {
                if !current.isEmpty {
                    segments.append(HeartSegment(id: "\(record.id)|\(index)|\(part)", points: current))
                    part += 1
                    current = []
                }
            }
            for point in inside {
                if let last = current.last, point.date.timeIntervalSince(last.date) > heartGap { flush() }
                current.append(point)
            }
            flush()
        }
        return segments
    }

    private struct Bucket {
        var muscle: MuscleGroup
        var nodes: [String]
        var share = 0.0
        var exerciseShare: [String: Double] = [:]
    }

    private static func regionBuckets(_ regions: [MuscleBodyRegion]) -> [Set<MuscleGroup>: Bucket] {
        var buckets: [Set<MuscleGroup>: Bucket] = [:]
        for region in regions where region.fatigueEligible && !region.muscles.isEmpty {
            let key = Set(region.muscles)
            var bucket = buckets[key] ?? Bucket(muscle: region.muscles[0], nodes: [])
            bucket.nodes.append(region.node)
            buckets[key] = bucket
        }
        return buckets
    }

    private static func exerciseFacts(
        records: [SetRecord],
        exercises: [String: Exercise],
        samples: [String: [HeartPoint]]
    ) -> [String: ExerciseFacts] {
        var grouped: [String: [SetRecord]] = [:]
        var order: [String] = []
        for record in records {
            if grouped[record.exerciseId] == nil { order.append(record.exerciseId) }
            grouped[record.exerciseId, default: []].append(record)
        }
        var facts: [String: ExerciseFacts] = [:]
        for id in order {
            let sets = grouped[id] ?? []
            let exercise = exercises[id]
            let loadedSets = sets.compactMap { record -> (weight: Double, reps: Int)? in
                guard let kilograms = loadedKilograms(record), let reps = record.reps else { return nil }
                return (kilograms / Double(reps), reps)
            }
            let volume = sets.compactMap(loadedKilograms)
            let bodyweight = sets.filter { loadedKilograms($0) == nil }.compactMap(\.reps)
            let timed = sets.reduce(0) { sum, record in
                guard loadedKilograms(record) == nil, record.reps == nil, let duration = record.duration, duration > 0 else { return sum }
                return sum + duration
            }
            let weights = Set(loadedSets.map(\.weight))
            let load: Load
            if loadedSets.count == sets.count, let weight = weights.first, weights.count == 1 {
                load = .loaded(sets: sets.count, weightKg: weight, reps: loadedSets.map(\.reps))
            } else if !volume.isEmpty {
                load = .mixed(sets: sets.count, volumeKg: volume.reduce(0, +))
            } else if !bodyweight.isEmpty {
                load = .bodyweight(sets: sets.count, reps: bodyweight)
            } else if timed > 0 {
                load = .timed(seconds: timed)
            } else {
                load = .counted(sets: sets.count)
            }
            let measured = sets.compactMap(\.activeSeconds)
            let heart = sets.flatMap { heartSegments(for: $0, samples: samples[$0.id] ?? []) }
            facts[id] = ExerciseFacts(
                id: id,
                name: exercise?.displayName ?? sets[0].exerciseName,
                variant: exercise?.equipmentDisplayName,
                setCount: sets.count,
                load: load,
                loadedVolumeKg: volume.isEmpty ? nil : volume.reduce(0, +),
                workSeconds: measured.isEmpty ? nil : measured.reduce(0, +),
                timingIncomplete: sets.contains { $0.activeIntervals == nil },
                heart: heart,
                records: sets
            )
        }
        return facts
    }

    /// One logged set, using only the weight, reps, or duration that were stored.
    static func setLine(_ record: SetRecord) -> String? {
        if let kilograms = record.weight, kilograms > 0, let reps = record.reps {
            return "\(weightLabel(kilograms)) × \(reps)"
        }
        if let kilograms = record.weight, kilograms > 0 { return weightLabel(kilograms) }
        if let reps = record.reps { return "\(reps)" }
        if let duration = record.duration, duration > 0 { return clock(Double(duration)) }
        return nil
    }

    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// Records for one history card. An empty session id never joins a card that has one.
    static func sets(in records: [SetRecord], planID: String?, day: Date, workoutSessionID: String?, calendar: Calendar, now: Date = Date()) -> [SetRecord] {
        records.filter { record in
            guard record.performedAt <= now, calendar.isDate(record.performedAt, inSameDayAs: day), record.planId == planID else { return false }
            return sessionID(record.workoutSessionID) == workoutSessionID
        }.sorted { $0.performedAt < $1.performedAt }
    }

    /// Peak heart rate for one muscle, using the existing Heart rate and bpm labels.
    static func heartShareLine(_ peak: Double?) -> String {
        guard let peak else { return NSLocalizedString("No heart rate", comment: "") }
        let value = Int(peak.rounded()).formatted(.number.locale(LanguageManager.currentLocale))
        return "\(NSLocalizedString("Heart rate", comment: "")) \(value) \(NSLocalizedString("bpm", comment: ""))"
    }

    static func sessionID(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static func shareContent(report: SessionMuscleReport, workoutName: String?, selection: ShareSelection) -> ShareContent {
        let records = report.muscles.flatMap(\.exercises).flatMap(\.records)
        return ShareContent(
            name: workoutName,
            day: records.map(\.performedAt).min(),
            work: report.workSeconds.map(clock) ?? "—",
            sets: "\(report.setCount)",
            volume: report.loadedVolumeKg.map(weightLabel) ?? "—",
            muscles: report.muscles.map { muscle in
                let peak = muscle.exercises.flatMap(\.heart).flatMap(\.points).map(\.bpm).max()
                return ShareContent.MuscleShare(
                    id: muscle.id,
                    name: muscle.muscle.displayName,
                    exercises: selection.includeDetails ? muscle.exercises.map { exercise in
                        ShareContent.ExerciseShare(id: exercise.id, name: exercise.name, sets: exercise.records.compactMap(setLine))
                    } : [],
                    heart: selection.includeHeart ? Self.heartShareLine(peak) : nil
                )
            },
            includesPhoto: selection.includePhoto
        )
    }
}
