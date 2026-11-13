import XCTest
@testable import Maso

@MainActor
final class FullBodyLoadEstimateTests: XCTestCase {
    func testEveryApprovedCoefficientForMaleAndFemale() throws {
        let approved: [String: (Double, Double)] = [
            "deadlift": (115, 120), "hip-thrust": (110, 110), "back-squat": (100, 100),
            "rdl": (80, 80), "front-squat": (75, 75), "bench": (70, 60),
            "close-grip-bench": (60, 50), "barbell-row": (60, 50), "incline-bench": (55, 48),
            "overhead-press": (40, 35), "dumbbell-row": (35, 30), "goblet-squat": (35, 35),
            "dumbbell-bench": (28, 24), "dumbbell-incline": (24, 20), "ez-curl": (24, 20),
            "dumbbell-pullover": (24, 20), "dumbbell-calf-raise": (24, 24), "ez-skullcrusher": (20, 18),
            "seated-dumbbell-press": (18, 15), "dumbbell-overhead-extension": (18, 16),
            "reverse-lunge": (15, 15), "dumbbell-curl": (14, 12), "hammer-curl": (14, 12),
            "side-bend": (14, 14), "dumbbell-fly": (10, 8), "plate-crunch": (8, 8),
            "lateral-raise": (7, 6), "reverse-fly": (7, 6),
        ]
        XCTAssertEqual(Set(FullBodyLoadEstimate.movements.map(\.id)), Set(approved.keys))
        let library = DataStore.makeMock()
        let squat = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "back-squat"))
        for movement in FullBodyLoadEstimate.movements {
            let pair = try! XCTUnwrap(approved[movement.id])
            XCTAssertEqual(movement.malePercent, pair.0)
            XCTAssertEqual(movement.femalePercent, pair.1)
            guard movement.id != squat.id else { continue }
            let exercise = try XCTUnwrap(library.exById[movement.exerciseIDs[0]])
            let plate = try XCTUnwrap(FullBodyLoadEstimate.plate(for: exercise))
            for profile: FullBodyLoadProfile in [.male, .female] {
                let raw = 100.0 * FullBodyLoadEstimate.percent(movement, profile) / 100 * 0.70
                let expected = floor((raw / plate) + 1e-8) * plate
                XCTAssertEqual(FullBodyLoadEstimate.recommendation(source: squat, sourceKilograms: 100,
                                                                   target: movement, profile: profile, plate: plate), expected)
            }
        }
    }

    func testAnyMappedSourceReachesAnyOtherTargetOnce() {
        let deadlift = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "deadlift"))
        let bench = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "bench"))
        let male = FullBodyLoadEstimate.recommendation(source: deadlift, sourceKilograms: 100,
                                                       target: bench, profile: .male, plate: 2.5)
        XCTAssertEqual(male, 42.5)
        let female = FullBodyLoadEstimate.recommendation(source: deadlift, sourceKilograms: 100,
                                                         target: bench, profile: .female, plate: 2.5)
        XCTAssertEqual(female, 35)
        let again = FullBodyLoadEstimate.recommendation(source: deadlift, sourceKilograms: male!,
                                                        target: bench, profile: .male, plate: 2.5)
        XCTAssertNotEqual(again, male, "Applying the factor to the recommendation would shrink it again")
    }

    func testUnknownGenderUsesTheLowerApprovedResultWithoutAThirdTable() {
        let squat = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "back-squat"))
        let bench = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "bench"))
        let male = FullBodyLoadEstimate.recommendation(source: squat, sourceKilograms: 100, target: bench, profile: .male, plate: 2.5)
        let female = FullBodyLoadEstimate.recommendation(source: squat, sourceKilograms: 100, target: bench, profile: .female, plate: 2.5)
        for gender: Gender? in [nil, .other] {
            let data = store(gender: gender)
            data.settings.fullBodyLoadAnchor = anchor(exercise: "squat_barbell", movement: "back-squat", kilograms: 100)
            let step = data.suggestingMissingParameters(for: empty("bench_press_barbell"))
            XCTAssertEqual(step.weight, min(male!, female!))
            XCTAssertEqual(step.parameterSuggestions?["weight"]?.source, .fullBodyRough)
        }
    }

    func testThirdSetTriggersMinimumWeightAndUndoIsIdempotent() {
        let data = store(gender: .male)
        data.plans = [plan(steps: [empty("incline_bench_press_barbell"), empty("triceps_pushdown_straight_bar")])]
        data.recordSet(set(1, weight: 100))
        data.recordSet(set(2, weight: 90))
        XCTAssertNil(data.settings.fullBodyLoadAnchor)
        XCTAssertNil(data.plans[0].steps[0].weight)
        data.recordSet(set(3, weight: 80))
        XCTAssertEqual(data.settings.fullBodyLoadAnchor?.kilograms, 80)
        XCTAssertEqual(data.plans[0].steps[0].weight, 30)
        XCTAssertEqual(data.plans[0].steps[0].parameterSuggestions?["weight"]?.ruleID, FullBodyLoadEstimate.ruleID)
        XCTAssertNil(data.plans[0].steps[1].weight)
        let persisted = data.plans
        data.reconcileFullBodyLoadAnchor()
        XCTAssertEqual(data.plans, persisted)
        data.removeSetRecord(id: "set-3-session")
        XCTAssertNil(data.settings.fullBodyLoadAnchor)
        XCTAssertNil(data.plans[0].steps[0].weight)
    }

    func testRestartKeepsTheAnchorAndDoesNotUseAnEstimateAsTheNextAnchor() throws {
        let data = store(gender: .female)
        data.plans = [plan(steps: [empty("bench_press_barbell")])]
        for number in 1...3 { data.recordSet(set(number, weight: 80, exercise: "squat_barbell")) }
        let encoded = try JSONEncoder().encode(data.settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: encoded)
        let restarted = DataStore(exercises: data.exercises, plans: data.plans, sets: data.sets, settings: decoded)
        restarted.reconcileFullBodyLoadAnchor()
        XCTAssertEqual(restarted.plans[0].steps[0].weight, data.plans[0].steps[0].weight)
        for number in 1...3 {
            restarted.recordSet(SetRecord(id: "est-\(number)", exerciseId: "bench_press_barbell", exerciseName: "Bench",
                                          category: .strength, weight: restarted.plans[0].steps[0].weight, reps: 10, duration: nil,
                                          performedAt: Date(), planId: nil, workoutSessionID: "next", setNumber: number, manualLoad: false))
        }
        XCTAssertEqual(restarted.settings.fullBodyLoadAnchor?.exerciseID, "squat_barbell")
    }

    func testExplicitZeroExistingValueAndHistoryStayPut() {
        let data = store(gender: .male)
        var zero = empty("rdl_barbell"); zero.weight = 0
        var filled = empty("squat_front"); filled.weight = 70
        var perSet = empty("barbell_row"); perSet.setWeights = [40, nil, 50]
        data.plans = [plan(steps: [zero, filled, perSet, empty("bench_press_barbell")])]
        data.sets = [history("bench_press_barbell", 50)]
        for number in 1...3 { data.recordSet(set(number, weight: 100, exercise: "squat_barbell")) }
        XCTAssertEqual(data.plans[0].steps[0].weight, 0)
        XCTAssertEqual(data.plans[0].steps[1].weight, 70)
        XCTAssertEqual(data.plans[0].steps[2].setWeights, [40, nil, 50])
        XCTAssertNil(data.plans[0].steps[3].weight, "Own history is not replaced by a rough fill")
        XCTAssertEqual(data.suggestingMissingParameters(for: data.plans[0].steps[3]).weight, 50)
        XCTAssertEqual(data.sets.filter { $0.exerciseId == "squat_barbell" }.map(\.weight), [100, 100, 100])
    }

    func testDisplayUnitDoesNotChangeTheStoredKilograms() {
        let male = recommendation(gender: .male)
        var settings = male.settings
        settings.weightUnit = .lb
        let data = DataStore(exercises: male.exercises, plans: male.plans, sets: male.sets, settings: settings)
        data.reconcileFullBodyLoadAnchor()
        XCTAssertEqual(data.plans[0].steps[0].weight, male.plans[0].steps[0].weight)
        let shown = settings.weightUnit.fromKg(data.plans[0].steps[0].weight!)
        XCTAssertEqual(settings.weightUnit.toKg(shown), data.plans[0].steps[0].weight!, accuracy: 0.001)
    }

    func testEstimateDoesNotCrossStoresAndNewExercisesUseTheSameValue() {
        let first = store(gender: .male)
        for number in 1...3 { first.recordSet(set(number, weight: 100)) }
        let second = store(gender: .male)
        XCTAssertNil(second.settings.fullBodyLoadAnchor)
        let seeded = first.makeSeededStep(for: first.exById["incline_bench_press_dumbbell"]!, stepId: "new")
        XCTAssertEqual(seeded.weight, first.suggestingMissingParameters(for: empty("incline_bench_press_dumbbell")).weight)
        XCTAssertEqual(seeded.parameterSuggestions?["weight"]?.source, .fullBodyRough)
        XCTAssertNil(first.makeSeededStep(for: first.exById["triceps_pushdown_straight_bar"]!, stepId: "cable").weight)
    }

    func testBodyweightMachineAndUnapprovedNamesAreExcluded() {
        XCTAssertNil(FullBodyLoadEstimate.movement(for: "squat_bodyweight"))
        XCTAssertNil(FullBodyLoadEstimate.movement(for: "rdl_barbell") == nil ? nil : FullBodyLoadEstimate.movement(for: "rdl_smith"))
        XCTAssertNil(FullBodyLoadEstimate.movement(for: "bench_press_machine"))
        XCTAssertNil(FullBodyLoadEstimate.movement(for: "hip_thrust_barbell_paused"))
        XCTAssertNil(FullBodyLoadEstimate.movement(for: "push_press_barbell"))
        XCTAssertEqual(FullBodyLoadEstimate.mappedExerciseIDs.count, 30)
        XCTAssertTrue(FullBodyLoadEstimate.mappedExerciseIDs.isDisjoint(with: [
            "deadlift_sumo", "deadlift_deficit", "squat_goblet_kettlebell", "bicep_curl_cable", "lateral_raise_machine"
        ]))
    }

    func testLightResultIsNotRaisedToAnEmptyBar() {
        let squat = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "back-squat"))
        let raise = try! XCTUnwrap(FullBodyLoadEstimate.movement(id: "lateral-raise"))
        XCTAssertNil(FullBodyLoadEstimate.recommendation(source: squat, sourceKilograms: 20,
                                                         target: raise, profile: .male, plate: 1))
    }

    private func recommendation(gender: Gender) -> DataStore {
        let data = store(gender: gender)
        data.plans = [plan(steps: [empty("bench_press_barbell")])]
        for number in 1...3 { data.recordSet(set(number, weight: 100)) }
        return data
    }

    private func store(gender: Gender?) -> DataStore {
        let data = DataStore.makeMock()
        data.plans = []; data.sets = []
        data.settings.gender = gender
        data.settings.exerciseWeightInputs = nil
        data.settings.confirmedExerciseWeightInputIDs = nil
        data.settings.fullBodyLoadAnchor = nil
        data.settings.globalExerciseParamSyncEnabled = false
        return data
    }

    private func empty(_ id: String) -> PlanStep {
        PlanStep(id: id, exerciseId: id, sets: 3, reps: 10, weight: nil, duration: nil)
    }

    private func plan(steps: [PlanStep]) -> Plan {
        Plan(id: "plan", name: "Workout", steps: steps, createdAt: Date(), updatedAt: Date())
    }

    private func anchor(exercise: String, movement: String, kilograms: Double) -> FullBodyLoadAnchor {
        .init(exerciseID: exercise, movementID: movement, sessionID: "session", kilograms: kilograms, recordedAt: Date())
    }

    private func history(_ id: String, _ weight: Double) -> SetRecord {
        SetRecord(id: "history-\(id)", exerciseId: id, exerciseName: id, category: .strength,
                  weight: weight, reps: 8, duration: nil, performedAt: Date().addingTimeInterval(-3600),
                  planId: nil, workoutSessionID: "old", setNumber: 1, manualLoad: true)
    }

    private func set(_ number: Int, weight: Double, exercise: String = "squat_barbell", session: String = "session") -> SetRecord {
        SetRecord(id: "set-\(number)-\(session)", exerciseId: exercise, exerciseName: exercise, category: .strength,
                  weight: weight, reps: 10, duration: nil, performedAt: Date().addingTimeInterval(Double(number)),
                  planId: "plan", workoutSessionID: session, stepID: exercise, setNumber: number, manualLoad: true)
    }
}
