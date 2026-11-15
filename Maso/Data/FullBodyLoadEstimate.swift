import Foundation

/// Approved full-body rough ratios, v0.2. Back squat is 100. Values are percents
/// of that squat for an approximate 8–12 rep working set, not a 1RM and not a
/// measured or safe prescription. Barbell and EZ loads include the bar. Dumbbell
/// loads are per dumbbell, or one dumbbell held in two hands when the movement says so.
struct FullBodyLoadMovement: Equatable, Sendable {
    let id: String
    let malePercent: Double
    let femalePercent: Double
    let exerciseIDs: [String]
}

enum FullBodyLoadProfile: Equatable, Sendable {
    case male, female, unspecified

    static func resolve(_ gender: Gender?) -> FullBodyLoadProfile {
        switch gender {
        case .male: return .male
        case .female: return .female
        case .other, nil: return .unspecified
        }
    }
}

struct FullBodyLoadAnchor: Codable, Equatable, Sendable {
    var exerciseID: String
    var movementID: String
    var sessionID: String
    var kilograms: Double
    var recordedAt: Date
}

enum FullBodyLoadEstimate {
    static let ruleID = "full-body-v0.2"
    /// Working-set caliber the approved table describes.
    static let workingReps = 8...12

    static let movements: [FullBodyLoadMovement] = [
        .init(id: "deadlift", malePercent: 115, femalePercent: 120, exerciseIDs: ["deadlift"]),
        .init(id: "hip-thrust", malePercent: 110, femalePercent: 110, exerciseIDs: ["hip_thrust_barbell"]),
        .init(id: "back-squat", malePercent: 100, femalePercent: 100, exerciseIDs: ["squat_barbell"]),
        .init(id: "rdl", malePercent: 80, femalePercent: 80, exerciseIDs: ["rdl_barbell"]),
        .init(id: "front-squat", malePercent: 75, femalePercent: 75, exerciseIDs: ["squat_front"]),
        .init(id: "bench", malePercent: 70, femalePercent: 60, exerciseIDs: ["bench_press_barbell"]),
        .init(id: "close-grip-bench", malePercent: 60, femalePercent: 50, exerciseIDs: ["bench_press_close_grip"]),
        .init(id: "barbell-row", malePercent: 60, femalePercent: 50, exerciseIDs: ["barbell_row"]),
        .init(id: "incline-bench", malePercent: 55, femalePercent: 48, exerciseIDs: ["incline_bench_press_barbell"]),
        .init(id: "overhead-press", malePercent: 40, femalePercent: 35, exerciseIDs: ["overhead_press_barbell"]),
        .init(id: "dumbbell-row", malePercent: 35, femalePercent: 30, exerciseIDs: ["dumbbell_row_single_arm"]),
        .init(id: "goblet-squat", malePercent: 35, femalePercent: 35, exerciseIDs: ["squat_goblet"]),
        .init(id: "dumbbell-bench", malePercent: 28, femalePercent: 24, exerciseIDs: ["bench_press_dumbbell"]),
        .init(id: "dumbbell-incline", malePercent: 24, femalePercent: 20, exerciseIDs: ["incline_bench_press_dumbbell"]),
        .init(id: "ez-curl", malePercent: 24, femalePercent: 20, exerciseIDs: ["bicep_curl_ez_bar"]),
        .init(id: "dumbbell-pullover", malePercent: 24, femalePercent: 20, exerciseIDs: ["dumbbell_pullover"]),
        .init(id: "dumbbell-calf-raise", malePercent: 24, femalePercent: 24, exerciseIDs: ["calf_raise_standing_dumbbell"]),
        .init(id: "ez-skullcrusher", malePercent: 20, femalePercent: 18, exerciseIDs: ["skullcrusher_ez_bar"]),
        .init(id: "seated-dumbbell-press", malePercent: 18, femalePercent: 15, exerciseIDs: ["overhead_press_dumbbell_seated"]),
        .init(id: "dumbbell-overhead-extension", malePercent: 18, femalePercent: 16, exerciseIDs: [
            "overhead_extension_dumbbell_two_hand", "overhead_extension_dumbbell_seated_two_hand"
        ]),
        .init(id: "reverse-lunge", malePercent: 15, femalePercent: 15, exerciseIDs: ["lunge_reverse_dumbbell"]),
        .init(id: "dumbbell-curl", malePercent: 14, femalePercent: 12, exerciseIDs: ["bicep_curl_dumbbell"]),
        .init(id: "hammer-curl", malePercent: 14, femalePercent: 12, exerciseIDs: ["hammer_curl"]),
        .init(id: "side-bend", malePercent: 14, femalePercent: 14, exerciseIDs: ["side_bend_dumbbell"]),
        .init(id: "dumbbell-fly", malePercent: 10, femalePercent: 8, exerciseIDs: ["dumbbell_fly_flat"]),
        .init(id: "plate-crunch", malePercent: 8, femalePercent: 8, exerciseIDs: ["crunch_weighted"]),
        .init(id: "lateral-raise", malePercent: 7, femalePercent: 6, exerciseIDs: ["lateral_raise_dumbbell"]),
        .init(id: "reverse-fly", malePercent: 7, femalePercent: 6, exerciseIDs: [
            "rear_delt_fly_dumbbell", "rear_delt_fly_dumbbell_seated"
        ]),
    ]

    static var mappedExerciseIDs: Set<String> { Set(movements.flatMap(\.exerciseIDs)) }

    static func movement(for exerciseID: String) -> FullBodyLoadMovement? {
        movements.first { $0.exerciseIDs.contains(exerciseID) }
    }

    static func movement(id: String) -> FullBodyLoadMovement? {
        movements.first { $0.id == id }
    }

    /// A completed set can anchor only when the lifter entered the load. An unconfirmed
    /// estimate, including one produced by this table, cannot.
    static func recordedLoadIsManual(step: PlanStep?, weight: Double?) -> Bool {
        guard let step, let weight, weight.isFinite, weight > 0, weight <= 500 else { return false }
        if let suggestion = step.parameterSuggestions?["weight"],
           suggestion.isCrossExerciseEstimate || suggestion.source == .shared {
            return false
        }
        return true
    }

    static func plate(for exercise: Exercise) -> Double? {
        switch ExerciseWeightReference.equipment(exercise) {
        case .dumbbell, .kettlebell: return 1
        case .barbell: return 2.5
        default: return nil
        }
    }

    /// `sourceKg * target / source * 0.70`, then round down to the equipment plate.
    /// Below one plate stays unknown. The factor is applied to the real source, never
    /// to a previous recommendation.
    static func recommendation(source: FullBodyLoadMovement, sourceKilograms: Double,
                               target: FullBodyLoadMovement, profile: FullBodyLoadProfile,
                               plate: Double) -> Double? {
        guard sourceKilograms.isFinite, sourceKilograms > 0, plate > 0 else { return nil }
        func once(_ profile: FullBodyLoadProfile) -> Double? {
            let sourcePercent = percent(source, profile)
            let targetPercent = percent(target, profile)
            guard sourcePercent > 0 else { return nil }
            let raw = sourceKilograms * targetPercent / sourcePercent * 0.70
            let rounded = floor((raw / plate) + 1e-8) * plate
            guard rounded.isFinite, rounded + 1e-8 >= plate, rounded <= 500 else { return nil }
            return rounded
        }
        switch profile {
        case .male, .female:
            return once(profile)
        case .unspecified:
            let choices = [once(.male), once(.female)].compactMap { $0 }
            return choices.min()
        }
    }

    static func percent(_ movement: FullBodyLoadMovement, _ profile: FullBodyLoadProfile) -> Double {
        switch profile {
        case .male: return movement.malePercent
        case .female: return movement.femalePercent
        case .unspecified: return min(movement.malePercent, movement.femalePercent)
        }
    }

    /// Latest session and exercise with at least three distinct manual 8–12 rep sets.
    /// The source load is the lightest of those sets, not the heaviest.
    static func anchor(from records: [SetRecord], library: [String: Exercise]) -> FullBodyLoadAnchor? {
        struct Key: Hashable { let session: String; let exercise: String; let step: String; let set: Int }
        var grouped: [String: [SetRecord]] = [:]
        var seen = Set<Key>()
        for record in records.sorted(by: { $0.performedAt < $1.performedAt }) {
            guard record.manualLoad == true,
                  let session = record.workoutSessionID, !session.isEmpty,
                  let setNumber = record.setNumber, (1...999).contains(setNumber),
                  record.category == .strength, record.duration == nil,
                  let reps = record.reps, workingReps.contains(reps),
                  let weight = record.weight, weight.isFinite, weight > 0, weight <= 500,
                  library[record.exerciseId] != nil,
                  movement(for: record.exerciseId) != nil else { continue }
            let identity = Key(session: session, exercise: record.exerciseId, step: record.stepID ?? "", set: setNumber)
            guard seen.insert(identity).inserted else { continue }
            grouped["\(session)|\(record.exerciseId)", default: []].append(record)
        }
        var best: FullBodyLoadAnchor?
        for sets in grouped.values where sets.count >= 3 {
            guard let lightest = sets.compactMap(\.weight).min(),
                  let latest = sets.max(by: { $0.performedAt < $1.performedAt }),
                  let movement = movement(for: latest.exerciseId) else { continue }
            let candidate = FullBodyLoadAnchor(exerciseID: latest.exerciseId, movementID: movement.id,
                                               sessionID: latest.workoutSessionID ?? "", kilograms: lightest,
                                               recordedAt: latest.performedAt)
            if best == nil || candidate.recordedAt > best!.recordedAt
                || (candidate.recordedAt == best!.recordedAt && candidate.exerciseID < best!.exerciseID) {
                best = candidate
            }
        }
        return best
    }

    static func reference(for target: Exercise, anchor: FullBodyLoadAnchor?, settings: UserSettings,
                          library: [String: Exercise]) -> ExerciseWeightReference.Reference? {
        guard let anchor, target.id != anchor.exerciseID,
              let source = movement(id: anchor.movementID),
              let targetMovement = movement(for: target.id),
              let sourceExercise = library[anchor.exerciseID],
              ExerciseWeightReference.expectsLoad(target),
              let plate = plate(for: target) else { return nil }
        let profile = FullBodyLoadProfile.resolve(settings.gender)
        guard let kilograms = recommendation(source: source, sourceKilograms: anchor.kilograms,
                                             target: targetMovement, profile: profile, plate: plate) else { return nil }
        return .init(kilograms: kilograms, sourceExerciseID: sourceExercise.id, source: .fullBodyRough,
                     recordedAt: anchor.recordedAt, ruleID: ruleID)
    }
}
