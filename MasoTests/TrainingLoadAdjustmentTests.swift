import XCTest
import CoreImage
@testable import Maso

@MainActor
final class TrainingLoadAdjustmentTests: XCTestCase {
    private func fixture(perSet: Bool = false, extraStep: Bool = false) throws -> (TrainingSessionStore, DataStore, Plan) {
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById.values.first { $0.category == .strength })
        var step = PlanStep(id: "load-step", exerciseId: exercise.id, sets: 3, reps: 10,
                            weight: 20, duration: nil)
        if perSet {
            step.setWeights = [20, 25, 30]
            step.setReps = [13, 10, 8]
        }
        var steps = [step]
        if extraStep {
            steps.append(.init(id: "next-step", exerciseId: exercise.id, sets: 1,
                               reps: 8, weight: 15, duration: nil))
        }
        let plan = Plan(id: "load-adjustment", name: "Workout", steps: steps,
                        createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan,
                    segments: expandPlan(plan, exById: data.exById,
                                         defaultRest: 90, defaultBetweenExerciseRest: 120))
        return (store, data, plan)
    }

    private func weights(in store: TrainingSessionStore, stepId: String = "load-step") -> [Double?] {
        store.segments.compactMap { segment -> Double?? in
            guard segment.stepId == stepId,
                  case .exercise(_, _, _, _, let weight, _, _) = segment.kind else { return nil }
            return .some(weight)
        }
    }

    func testUniformLoadChangesOnlyWeightAndKeepsPlaybackPosition() throws {
        let (store, _, original) = try fixture()
        defer { store.end() }
        store.setIndex(2)
        store.togglePlay()
        let session = try XCTUnwrap(store.session)
        let segmentIDs = store.segments.map(\.id)
        XCTAssertTrue(store.updateStepWeight(stepId: "load-step", weightKg: 22.5))
        let updated = try XCTUnwrap(store.plan?.steps.first)
        XCTAssertEqual(updated.weight, 22.5)
        XCTAssertNil(updated.setWeights)
        XCTAssertEqual(updated.sets, original.steps[0].sets)
        XCTAssertEqual(updated.reps, original.steps[0].reps)
        XCTAssertEqual(updated.setReps, original.steps[0].setReps)
        XCTAssertEqual(updated.duration, original.steps[0].duration)
        XCTAssertEqual(updated.id, original.steps[0].id)
        XCTAssertEqual(store.segments.map(\.id), segmentIDs)
        XCTAssertEqual(weights(in: store), [22.5, 22.5, 22.5])
        XCTAssertEqual(store.session?.segmentIndex, session.segmentIndex)
        XCTAssertEqual(store.session?.startedAt, session.startedAt)
        XCTAssertEqual(store.session?.playing, session.playing)
        XCTAssertEqual(store.session?.endsAt, session.endsAt)
        XCTAssertEqual(store.session?.pausedRemaining, session.pausedRemaining)
        XCTAssertTrue(store.planParamsDirty)
    }

    func testPerSetLoadPreservesCompletedSetAndActualRecord() throws {
        let (store, _, original) = try fixture(perSet: true)
        defer { store.end() }
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        let recorded = records
        let completed = store.session?.completedSets
        XCTAssertTrue(store.updateStepWeight(stepId: "load-step", weightKg: 35))
        let updated = try XCTUnwrap(store.plan?.steps.first)
        XCTAssertEqual(updated.weight, 35)
        XCTAssertEqual(updated.setWeights, [20, 35, 35])
        XCTAssertEqual(updated.setReps, original.steps[0].setReps)
        XCTAssertEqual(weights(in: store), [20, 35, 35])
        XCTAssertEqual(store.session?.completedSets, completed)
        XCTAssertEqual(records, recorded)
        XCTAssertEqual(records.first?.weight, 20)
        XCTAssertEqual(records.first?.reps, 13)
    }

    func testRunningAndPausedRestKeepExactDeadlineAndRemainingTime() throws {
        let (store, _, _) = try fixture()
        defer { store.end() }
        store.advance()
        XCTAssertEqual(store.currentSegment?.isRest, true)
        let running = try XCTUnwrap(store.session)
        let rest = store.currentSegment
        XCTAssertNotNil(running.endsAt)
        XCTAssertTrue(store.updateStepWeight(stepId: "load-step", weightKg: 25))
        XCTAssertEqual(store.currentSegment, rest)
        XCTAssertEqual(store.session?.segmentIndex, running.segmentIndex)
        XCTAssertEqual(store.session?.playing, true)
        XCTAssertEqual(store.session?.endsAt, running.endsAt)
        XCTAssertEqual(store.session?.pausedRemaining, running.pausedRemaining)

        store.togglePlay()
        let paused = try XCTUnwrap(store.session)
        XCTAssertNotNil(paused.pausedRemaining)
        XCTAssertTrue(store.updateStepWeight(stepId: "load-step", weightKg: 30))
        XCTAssertEqual(store.currentSegment, rest)
        XCTAssertEqual(store.session?.segmentIndex, paused.segmentIndex)
        XCTAssertEqual(store.session?.playing, false)
        XCTAssertEqual(store.session?.endsAt, paused.endsAt)
        XCTAssertEqual(store.session?.pausedRemaining, paused.pausedRemaining)
    }

    func testCompletedStepChangesNextWorkoutTargetsWithoutRewritingThisWorkout() throws {
        let (store, data, _) = try fixture(perSet: true, extraStep: true)
        defer { store.end() }
        var records: [SetRecord] = []
        // Complete the three real sets and their intervening rests; next step remains active.
        for _ in 0..<5 { store.advance { records.append($0) } }
        XCTAssertEqual(store.session?.completed, false)
        XCTAssertEqual(store.session?.completedSets.count, 3)
        let previousSession = try XCTUnwrap(store.session)
        let previousSegments = store.segments
        let previousRecords = records
        XCTAssertTrue(store.updateStepWeight(stepId: "load-step", weightKg: 35))
        let plan = try XCTUnwrap(store.plan)
        XCTAssertEqual(plan.steps[0].weight, 35)
        XCTAssertEqual(plan.steps[0].setWeights, [35, 35, 35])
        XCTAssertEqual(weights(in: store), [20, 25, 30])
        XCTAssertEqual(store.segments, previousSegments)
        XCTAssertEqual(store.session?.segmentIndex, previousSession.segmentIndex)
        XCTAssertEqual(store.session?.endsAt, previousSession.endsAt)
        XCTAssertEqual(records, previousRecords)
        let nextWorkout = expandPlan(plan, exById: data.exById)
        for segment in nextWorkout where segment.stepId == "load-step" {
            if case .exercise(_, _, _, _, let weight, _, _) = segment.kind { XCTAssertEqual(weight, 35) }
        }
    }

    func testInvalidInputMissingStepAndCompletedSessionAreRejectedWithoutMutation() throws {
        let (store, _, _) = try fixture()
        defer { store.end() }
        let plan = store.plan, session = store.session, segments = store.segments
        for value in [0, -1, Double.infinity, -Double.infinity, Double.nan, 500.1] {
            XCTAssertFalse(store.updateStepWeight(stepId: "load-step", weightKg: value))
            XCTAssertEqual(store.plan, plan)
            XCTAssertEqual(store.session, session)
            XCTAssertEqual(store.segments, segments)
            XCTAssertFalse(store.planParamsDirty)
        }
        XCTAssertFalse(store.updateStepWeight(stepId: "missing-step", weightKg: 25))
        XCTAssertEqual(store.plan, plan)
        XCTAssertEqual(store.session, session)
        store.finishEarly()
        XCTAssertEqual(store.session?.completed, true)
        let completedPlan = store.plan, completedSession = store.session
        XCTAssertFalse(store.updateStepWeight(stepId: "load-step", weightKg: 25))
        XCTAssertEqual(store.plan, completedPlan)
        XCTAssertEqual(store.session, completedSession)
        store.end()
        XCTAssertFalse(store.updateStepWeight(stepId: "load-step", weightKg: 25))
    }
}

@MainActor
final class RelatedExerciseWeightTests: XCTestCase {
    func testCalibrationDistinguishesUnknownFromZeroManualAndPerSetWeights() throws {
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        var step = PlanStep(id: "new", exerciseId: exercise.id, sets: 3, reps: 8)
        XCTAssertTrue(ExerciseWeightReference.needsCalibration(step, exercise: exercise))
        step.weight = 0
        XCTAssertFalse(ExerciseWeightReference.needsCalibration(step, exercise: exercise))
        step.weight = 60
        XCTAssertFalse(ExerciseWeightReference.needsCalibration(step, exercise: exercise))
        step.weight = nil; step.setWeights = [nil, 20, nil]
        XCTAssertFalse(ExerciseWeightReference.needsCalibration(step, exercise: exercise))
        step.setWeights = [nil, nil]
        XCTAssertTrue(ExerciseWeightReference.needsCalibration(step, exercise: exercise))
        XCTAssertFalse(ExerciseWeightReference.needsCalibration(step, exercise: ExerciseLibrary.byId["push_up"]))
        XCTAssertFalse(ExerciseWeightReference.needsCalibration(step, exercise: nil))
    }

    func testEstimateExplanationFlagIsOptionalAndPersists() throws {
        var settings = UserSettings()
        XCTAssertNil(settings.hasSeenWeightEstimateExplanation)
        settings.hasSeenWeightEstimateExplanation = true
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.hasSeenWeightEstimateExplanation, true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        object.removeValue(forKey: "hasSeenWeightEstimateExplanation")
        let old = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.hasSeenWeightEstimateExplanation)
    }

    private func ex(_ id: String) throws -> Exercise { try XCTUnwrap(ExerciseLibrary.byId[id], id) }

    private func history(_ id: String = "bench_press_barbell", weight: Double = 50, reps: Int = 8,
                         age: TimeInterval = -1) -> SetRecord {
        SetRecord(id: UUID().uuidString, exerciseId: id, exerciseName: id, category: .strength,
                  weight: weight, reps: reps, duration: nil, performedAt: Date().addingTimeInterval(age), planId: nil)
    }

    func testMissingTargetsUseExactHistoryWithPersistedProvenanceWithoutCreatingRecords() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        let record = history()
        data.plans = []; data.sets = [record]; data.settings.exerciseWeightInputs = nil
        let step = data.makeSeededStep(for: exercise, stepId: "new")
        XCTAssertEqual(step.weight, 50); XCTAssertEqual(step.reps, 8)
        data.settings.weightUnit = .lb
        XCTAssertEqual(data.makeSeededStep(for: exercise, stepId: "lb").weight, 50)
        XCTAssertEqual(WeightUnit.lb.toKg(WeightUnit.lb.fromKg(50)), 50, accuracy: 0.000001)
        XCTAssertTrue(step.isSuggested("weight")); XCTAssertTrue(step.isSuggested("reps")); XCTAssertTrue(step.isSuggested("sets"))
        XCTAssertEqual(step.parameterSuggestions?["weight"]?.recordID, record.id)
        XCTAssertEqual(step.parameterSuggestions?["weight"]?.recordedAt, record.performedAt)
        XCTAssertEqual(try JSONDecoder().decode(PlanStep.self, from: JSONEncoder().encode(step)), step)
        XCTAssertEqual(data.sets, [record])
        let plan = Plan(id: "new", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        data.updatePlan(plan)
        XCTAssertNil(data.settings.exerciseWeightInputs?[exercise.id], "Saving a suggestion must not turn it into user evidence")
    }

    func testManualZeroPerSetAndLegacyTargetsNeverGetOverwritten() throws {
        let data = DataStore.makeMock()
        data.sets = [history()]; data.settings.exerciseWeightInputs = nil
        for weight: Double? in [0, 27.5, nil] {
            let step = PlanStep(id: "explicit", exerciseId: "bench_press_barbell", sets: 5, reps: 12,
                                weight: weight, setWeights: weight == nil ? [10, 20, nil] : nil, duration: nil)
            XCTAssertEqual(data.suggestingMissingParameters(for: step), step)
        }
        let legacy = PlanStep(id: "legacy", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 17.5, duration: nil)
        XCTAssertFalse(legacy.isSuggested("weight"))
        let plan = Plan(id: "old", name: "Old", steps: [legacy], createdAt: Date(), updatedAt: Date())
        data.plans = [plan]
        data.recordSet(history(weight: 80))
        XCTAssertEqual(data.plans[0], plan)
    }

    func testRelatedExercisesDoNotReuseUnitsAsPredictedStrength() throws {
        let data = DataStore.makeMock()
        data.plans = []; data.sets = [history()]; data.settings.exerciseWeightInputs = ["bench_press_barbell": 50]
        for id in ["bench_press_dumbbell", "bench_press_machine", "bicep_curl_dumbbell"] {
            let exercise = try ex(id)
            XCTAssertNil(data.referenceWeight(for: exercise))
            let step = data.makeSeededStep(for: exercise, stepId: id)
            XCTAssertNil(step.weight)
            XCTAssertNotNil(step.reps)
            XCTAssertTrue(step.isSuggested("sets"))
        }
    }

    func testLatestZeroAndInvalidOrFutureRecords() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        data.plans = []; data.settings.exerciseWeightInputs = nil
        data.sets = [history(weight: 0), history(weight: 60, age: -30), history(weight: 90, age: 600),
                     history(weight: .nan), history(weight: -1), history(reps: 0)]
        XCTAssertEqual(data.referenceWeight(for: exercise)?.kilograms, 0)
        XCTAssertTrue(data.makeSeededStep(for: exercise, stepId: "zero").isSuggested("weight"))
    }

    func testExactInputFallbackIsClearlySuggestedAndHistoryTakesPriority() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        data.plans = []; data.sets = []; data.settings.exerciseWeightInputs = [exercise.id: 37.5]
        data.settings.confirmedExerciseWeightInputIDs = nil
        XCTAssertNil(data.referenceWeight(for: exercise), "Legacy auto-seeded inputs have unknown origin")
        XCTAssertEqual(data.settings.exerciseWeightInputs?[exercise.id], 37.5, "Preserve legacy data")
        data.rememberWeight(37.5, for: exercise)
        let step = data.makeSeededStep(for: exercise, stepId: "input")
        XCTAssertEqual(step.weight, 37.5)
        XCTAssertEqual(step.parameterSuggestions?["weight"]?.source, .userInput)
        data.sets = [history(weight: 40)]
        XCTAssertEqual(data.referenceWeight(for: exercise)?.kilograms, 40)
    }

    func testGlobalSyncCopiesExplicitTargetsAndDoesNotApplySuggestionsOverManualValues() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        data.settings.globalExerciseParamSyncEnabled = true
        data.settings.exerciseWeightInputs = nil; data.sets = [history()]; data.plans = []
        var source = data.makeSeededStep(for: exercise, stepId: "source")
        source.reps = 11; source.confirmParameter("reps")
        let target = PlanStep(id: "manual", exerciseId: exercise.id, sets: 5, reps: 7, weight: 22.5, duration: nil)
        data.plans = [Plan(id: "manual", name: "Manual", steps: [target], createdAt: Date(), updatedAt: Date())]
        data.syncExerciseParams(from: source)
        XCTAssertEqual(data.plans[0].steps[0].weight, 22.5)
        XCTAssertEqual(data.plans[0].steps[0].sets, 5)
        XCTAssertEqual(data.plans[0].steps[0].reps, 11)
        let copied = data.makeSeededStep(for: exercise, stepId: "copy")
        XCTAssertEqual(copied.weight, 22.5, "Global manual target wins over historical suggestion")
        XCTAssertFalse(copied.isSuggested("weight"))
    }

    func testExplicitConfirmationDoesNotReturnAfterChangingBackToSuggestedNumber() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        data.plans = []; data.sets = [history()]; data.settings.exerciseWeightInputs = nil
        let step = data.makeSeededStep(for: exercise, stepId: "new")
        let plan = Plan(id: "session", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById))
        defer { store.end() }
        store.confirmParameters(stepId: step.id, fields: ["weight"])
        XCTAssertTrue(store.updateStepWeight(stepId: step.id, weightKg: 52.5))
        XCTAssertTrue(store.updateStepWeight(stepId: step.id, weightKg: 50))
        XCTAssertFalse(store.plan!.steps[0].isSuggested("weight"))
        XCTAssertTrue(store.plan!.steps[0].isSuggested("reps"))
        data.plans = [plan]
        data.confirmMatchingSuggestions(from: store.plan!.steps[0], in: plan.id)
        XCTAssertFalse(data.plans[0].steps[0].isSuggested("weight"))
        XCTAssertTrue(data.plans[0].steps[0].isSuggested("reps"))
        XCTAssertEqual(data.plans[0].steps[0].weight, 50)
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records[0].weight, 50)
    }

    func testOldJSONAndTimedDefaultsKeepMissingLoadDistinctFromZero() throws {
        let data = DataStore.makeMock()
        data.plans = []; data.sets = []; data.settings.exerciseWeightInputs = nil
        let oldJSON = Data(#"{"id":"old","exerciseId":"bench_press_barbell","sets":3,"reps":8,"weight":0,"restBetweenSets":90,"rest":0}"#.utf8)
        let old = try JSONDecoder().decode(PlanStep.self, from: oldJSON)
        XCTAssertNil(old.parameterSuggestions); XCTAssertEqual(data.suggestingMissingParameters(for: old).weight, 0)
        let exercise = try XCTUnwrap(data.exById.values.first { $0.category.isStretching })
        let step = data.makeSeededStep(for: exercise, stepId: "timed")
        XCTAssertNil(step.weight); XCTAssertTrue(step.isSuggested("duration")); XCTAssertEqual(step.duration, 30)
    }

    func testUnconfirmedSuggestionRefreshesFromNewHistoryButConfirmedValueStaysPinned() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        data.plans = []; data.sets = [history(weight: 40, age: -100)]
        data.settings.exerciseWeightInputs = nil
        var step = data.makeSeededStep(for: exercise, stepId: "refresh")
        XCTAssertEqual(step.weight, 40)
        data.sets.append(history(weight: 45))
        step = data.suggestingMissingParameters(for: step)
        XCTAssertEqual(step.weight, 45); XCTAssertTrue(step.isSuggested("weight"))
        step.confirmParameter("weight")
        data.sets.append(history(weight: 50, age: -0.5))
        XCTAssertEqual(data.suggestingMissingParameters(for: step).weight, 45)
    }

    func testSharedSuggestionsKeepTheirStatusWithoutPersonalRecordIdentifiers() throws {
        let data = DataStore.makeMock(), exercise = try ex("bench_press_barbell")
        data.plans = []; data.sets = [history()]; data.settings.exerciseWeightInputs = nil
        let step = data.makeSeededStep(for: exercise, stepId: "private")
        let plan = Plan(id: "share", name: "Share", steps: [step], createdAt: Date(), updatedAt: Date())
        let decoded = try XCTUnwrap(PlanShareCodec.decode(try XCTUnwrap(PlanShareCodec.encode(plan))))
        XCTAssertTrue(decoded.steps[0].isSuggested("weight"))
        XCTAssertEqual(decoded.steps[0].weight, step.weight)
        XCTAssertEqual(decoded.steps[0].parameterSuggestions?["weight"]?.source, .shared)
        XCTAssertNil(decoded.steps[0].parameterSuggestions?["weight"]?.recordID)
        XCTAssertNil(decoded.steps[0].parameterSuggestions?["weight"]?.recordedAt)
        data.sets = [history(weight: 80)]
        XCTAssertEqual(data.suggestingMissingParameters(for: decoded.steps[0]).weight, step.weight,
                       "Adopted shared targets preserve the exported parameters")
    }

    func testWorkoutQRUsesHTTPSAndPreservesExactPlan() throws {
        let plan = Plan(id: "share-check", name: "Workout", steps: [PlanStep(id: "s", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 42.5, duration: nil)], createdAt: Date(), updatedAt: Date())
        let record = SetRecord(id: "share-record", exerciseId: "bench_press_barbell", exerciseName: "Bench Press", category: .strength, weight: 42.5, reps: 8, duration: nil, performedAt: Date(), planId: plan.id)
        let built = WorkoutShareBuilder.build(sessionSets: [record], orderHint: plan.steps, exById: ExerciseLibrary.byId, planName: plan.name)
        XCTAssertEqual(built.importPlan.preservesExerciseVariants, true)
        let payload = try XCTUnwrap(PlanShareCodec.appStoreDataLink(for: [plan]))
        XCTAssertTrue(payload.hasPrefix("https://masso-plan-share.vercel.app/workout-plan/#ps="))
        let url = try XCTUnwrap(URL(string: payload))
        let encoded = try XCTUnwrap(PlanShareCodec.encodeMany([plan]))
        XCTAssertNotNil(PlanShareCodec.decodeMany(encoded), "raw array decoding")
        XCTAssertEqual(url.path, "/workout-plan", "Foundation normalizes the trailing slash")
        XCTAssertEqual(url.fragment, "ps=" + encoded, "fragment")
        let imported = try XCTUnwrap(PlanShareCodec.decodePlan(from: url))
        XCTAssertEqual(imported.steps.first?.weight, 42.5)
        XCTAssertEqual(imported.steps.first?.exerciseId, "bench_press_barbell")
        XCTAssertEqual(PlanShareCodec.decodePlans(fromQRPayload: payload)?.count, 1)
        let qr = try XCTUnwrap(ShareQR.image(for: payload)?.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: qr)).compactMap { $0 as? CIQRCodeFeature }
        XCTAssertEqual(features.first?.messageString, payload)
    }

}

@MainActor
final class CrossExerciseLoadReferenceTests: XCTestCase {
    private func fixture(confirmed: Bool = true, age: TimeInterval = -86400, load: Double = 50, reps: Int = 6) -> DataStore {
        let data = DataStore.makeMock()
        data.plans = []; data.settings.exerciseWeightInputs = nil
        data.settings.confirmedExerciseWeightInputIDs = nil
        data.settings.gender = .male; data.settings.age = 25
        data.settings.globalExerciseParamSyncEnabled = false
        var record = SetRecord(id: "six-rm", exerciseId: "bench_press_barbell", exerciseName: "Bench Press",
                               category: .strength, weight: load, reps: reps, duration: nil,
                               performedAt: Date().addingTimeInterval(age), planId: nil)
        if confirmed { record.sixRMReference = SixRMReference(kilograms: load) }
        data.sets = [record]
        return data
    }
    private func target(_ id: String = "bicep_curl_barbell", reps: Int = 12) -> PlanStep {
        PlanStep(id: "target", exerciseId: id, sets: 3, reps: reps, weight: nil, duration: nil)
    }

    func testPublishedSharedObjectEquationsGiveConservativeStartingTargetsAndProvenance() throws {
        let data = fixture(), originalRecords = data.sets
        for (id, expected, rule) in [("bicep_curl_barbell", 15.0, "wong2013-curl-start-v1"),
                                     ("overhead_extension_dumbbell_two_hand", 10.0, "wong2013-triceps-start-v1")] {
            let step = data.suggestingMissingParameters(for: target(id))
            XCTAssertEqual(step.weight, expected)
            XCTAssertTrue(step.isSuggested("weight"))
            XCTAssertEqual(step.parameterSuggestions?["weight"]?.source, .crossExercise)
            XCTAssertEqual(step.parameterSuggestions?["weight"]?.exerciseID, "bench_press_barbell")
            XCTAssertEqual(step.parameterSuggestions?["weight"]?.recordID, "six-rm")
            XCTAssertEqual(step.parameterSuggestions?["weight"]?.ruleID, rule)
            XCTAssertEqual(try JSONDecoder().decode(PlanStep.self, from: JSONEncoder().encode(step)), step)
        }
        data.settings.weightUnit = .lb
        XCTAssertEqual(data.suggestingMissingParameters(for: target()).weight, 15, "Storage and rounding are canonical kg")
        XCTAssertEqual(data.sets, originalRecords)
        XCTAssertNil(data.settings.exerciseWeightInputs)
    }

    func testSixRepetitionsOrTypedInputAloneAreNotSixRMEvidence() {
        let data = fixture(confirmed: false)
        XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
        data.sets = []
        data.settings.exerciseWeightInputs = ["bench_press_barbell": 50]
        data.settings.confirmedExerciseWeightInputIDs = ["bench_press_barbell"]
        XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
    }

    func testUnknownOrUnmatchedProfilesLeaveLoadUnknownWhileOwnHistoryStillWorks() {
        let data = fixture()
        for age: Int? in [nil, 17, 31, 80] {
            data.settings.age = age
            XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
        }
        data.settings.age = 25
        for gender: Gender? in [nil, .female, .other] {
            data.settings.gender = gender
            XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
        }
        var own = data.sets[0]; own.exerciseId = "bicep_curl_barbell"; own.weight = 0
        data.sets.append(own)
        XCTAssertEqual(data.suggestingMissingParameters(for: target()).weight, 0, "Same-exercise references work for everyone")
    }

    func testFutureExpiredOutOfDomainAndChangedSnapshotsCannotAnchorEstimates() {
        for age in [60.0, -31 * 86400.0] {
            XCTAssertNil(fixture(age: age).suggestingMissingParameters(for: target()).weight)
        }
        for load in [0.0, 29.9, 70.1, .infinity, .nan] {
            XCTAssertNil(fixture(load: load).suggestingMissingParameters(for: target()).weight)
        }
        for reps in [5, 7, 12] {
            XCTAssertNil(fixture(reps: reps).suggestingMissingParameters(for: target()).weight)
        }
        let data = fixture(); data.sets[0].weight = 52.5
        XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
        data.sets[0].weight = 50; data.sets[0].sixRMReference = SixRMReference(kilograms: 50, protocolID: "unknown")
        XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
    }

    func testExactActionAndTargetProtocolMatchNoFamilyOrReverseChaining() {
        let data = fixture()
        for id in ["bicep_curl_dumbbell", "hammer_curl", "bench_press_machine", "overhead_extension_dumbbell_single_arm", "squat_barbell"] {
            XCTAssertNil(data.suggestingMissingParameters(for: target(id)).weight, id)
        }
        for reps in [1, 5, 13, 20] {
            XCTAssertNil(data.suggestingMissingParameters(for: target(reps: reps)).weight)
        }
        data.sets[0].exerciseId = "incline_bench_press_barbell"
        XCTAssertNil(data.suggestingMissingParameters(for: target()).weight)
    }

    func testManualZeroPerSetAndSharedTargetsRemainUntouched() throws {
        let data = fixture()
        for weight in [0.0, 15, 42.5] {
            var step = target(); step.weight = weight
            XCTAssertEqual(data.suggestingMissingParameters(for: step), step)
        }
        var step = target(); step.setWeights = [10, nil, 15]
        XCTAssertEqual(data.suggestingMissingParameters(for: step), step)
        step = data.suggestingMissingParameters(for: target())
        let plan = Plan(id: "estimate", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        data.updatePlan(plan)
        XCTAssertNil(data.settings.exerciseWeightInputs?[step.exerciseId], "An estimate must not become an explicit input")
        let shared = try XCTUnwrap(PlanShareCodec.decode(try XCTUnwrap(PlanShareCodec.encode(plan))))
        XCTAssertEqual(shared.steps[0].parameterSuggestions?["weight"]?.source, .shared)
        XCTAssertNil(shared.steps[0].parameterSuggestions?["weight"]?.ruleID)
        data.settings.age = nil
        XCTAssertEqual(data.suggestingMissingParameters(for: shared.steps[0]).weight, 15)
    }

    func testRevokedOrExpiredEvidenceWithdrawsOnlyUnconfirmedEstimate() {
        let data = fixture()
        var step = data.suggestingMissingParameters(for: target())
        data.sets[0].sixRMReference = nil
        XCTAssertNil(data.suggestingMissingParameters(for: step).weight)
        step.confirmParameter("weight")
        XCTAssertEqual(data.suggestingMissingParameters(for: step).weight, 15)
        let expired = fixture(age: -40 * 86400)
        var old = target(); old.weight = 15
        old.markSuggested("weight", value: 15, source: .crossExercise, exerciseID: "bench_press_barbell")
        XCTAssertNil(expired.suggestingMissingParameters(for: old).weight)
    }

    func testReferenceConfirmationIsExplicitSnapshotBoundAndDoesNotRewriteRecords() {
        let data = fixture(confirmed: false), original = fixture(confirmed: false).sets[0]
        data.updateSetRecord(id: "six-rm", reps: 6, weight: 50, duration: nil, sixRMConfirmed: true)
        XCTAssertTrue(data.sets[0].hasConfirmedSixRM)
        XCTAssertEqual(data.sets.count, 1)
        XCTAssertEqual(data.sets[0].weight, original.weight)
        data.updateSetRecord(id: "six-rm", reps: 6, weight: 52.5, duration: nil)
        XCTAssertNil(data.sets[0].sixRMReference)
        data.updateSetRecord(id: "six-rm", reps: 8, weight: 52.5, duration: nil, sixRMConfirmed: true)
        XCTAssertFalse(data.sets[0].hasConfirmedSixRM)
        data.updateSetRecord(id: "six-rm", reps: 6, weight: 50, duration: nil, sixRMConfirmed: true)
        data.updateSetRecord(id: "six-rm", reps: 6, weight: 50, duration: nil, sixRMConfirmed: false)
        XCTAssertNil(data.sets[0].sixRMReference)
    }

    func testMixedTargetsAndActiveRepetitionEditsRemoveUnsupportedEstimates() throws {
        let data = fixture()
        var step = target(); step.setReps = [6, 20, nil]
        XCTAssertNil(data.suggestingMissingParameters(for: step).weight)
        step = data.suggestingMissingParameters(for: target())
        let plan = Plan(id: "active-cross", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById))
        defer { store.end() }
        store.updateCurrentStep(sets: 3, reps: 20, weight: 15, duration: nil, exById: data.exById,
                                defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertNil(store.plan?.steps[0].weight)
        XCTAssertEqual(store.plan?.steps[0].reps, 20)
        XCTAssertEqual(data.sets.count, 1)
    }
}

@MainActor
final class PersonalExerciseLoadReferenceTests: XCTestCase {
    private let now = Date()
    private let sourceID = "bench_press_barbell"
    private let targetID = "bicep_curl_barbell"
    private func fixture() -> DataStore {
        let data = DataStore.makeMock()
        data.plans = []; data.settings.exerciseWeightInputs = nil
        data.settings.confirmedExerciseWeightInputIDs = nil
        data.settings.globalExerciseParamSyncEnabled = false
        data.settings.gender = nil; data.settings.age = nil
        data.sets = []
        for index in 0..<5 {
            let weight = 50 + Double(index) * 2.5
            data.sets += records(sourceID, weight: weight, day: -70 + index * 7, session: "pair-\(index)")
            data.sets += records(targetID, weight: weight / 2, day: -70 + index * 7, session: "pair-\(index)", offset: 120)
        }
        data.sets += records(sourceID, weight: 63, day: -1, session: "current")
        return data
    }
    private func records(_ id: String, weight: Double, day: Int, session: String, offset: Double = 0) -> [SetRecord] {
        (1...2).map { number in
            SetRecord(id: "\(session)-\(id)-\(number)", exerciseId: id, exerciseName: id, category: .strength,
                      weight: weight, reps: 8, duration: nil,
                      performedAt: now.addingTimeInterval(Double(day) * 86400 + offset + Double(number)),
                      planId: nil, workoutSessionID: session, setNumber: number)
        }
    }
    private func reference(_ data: DataStore, reps: Int = 8) -> ExerciseWeightReference.Reference? {
        PersonalExerciseLoadReference.reference(for: data.exById[targetID]!, targetReps: reps,
                                                records: data.sets, library: data.exById, now: now)
    }
    private var target: PlanStep { .init(id: "personal", exerciseId: targetID, sets: 3, reps: 8, weight: nil, duration: nil) }

    func testLearnedObservedRelationshipHasProvenanceAndNoDemographicOrStorageSideEffects() throws {
        let data = fixture(), original = data.sets
        let ref = try XCTUnwrap(reference(data))
        XCTAssertEqual(ref.kilograms, 31.5)
        XCTAssertEqual(ref.source, .personalHistory)
        XCTAssertEqual(ref.sourceExerciseID, sourceID)
        XCTAssertEqual(ref.ruleID, "personal-working-8-v1")
        let step = data.suggestingMissingParameters(for: target)
        XCTAssertEqual(step.weight, 31.5)
        XCTAssertTrue(step.isSuggested("weight"))
        XCTAssertEqual(try JSONDecoder().decode(PlanStep.self, from: JSONEncoder().encode(step)), step)
        data.settings.weightUnit = .lb
        XCTAssertEqual(data.suggestingMissingParameters(for: target).weight, 31.5)
        XCTAssertEqual(data.sets, original)
        XCTAssertNil(data.settings.exerciseWeightInputs)
        let plan = Plan(id: "personal", name: "Workout", steps: [step], createdAt: now, updatedAt: now)
        let shared = try XCTUnwrap(PlanShareCodec.decode(try XCTUnwrap(PlanShareCodec.encode(plan))))
        XCTAssertEqual(shared.steps[0].parameterSuggestions?["weight"]?.source, .shared)
        XCTAssertNil(shared.steps[0].parameterSuggestions?["weight"]?.recordID)
        XCTAssertNil(shared.steps[0].parameterSuggestions?["weight"]?.ruleID)
    }

    func testFiveIndependentDatesAndTwoDistinctSetsAreRequired() {
        for mode in 0..<6 {
            let data = fixture()
            for index in data.sets.indices {
                switch mode {
                case 0: if data.sets[index].workoutSessionID == "pair-0" { data.sets[index].weight = nil }
                case 1: data.sets[index].workoutSessionID = nil
                case 2: data.sets[index].setNumber = nil
                case 3: data.sets[index].setNumber = 1
                case 4: if data.sets[index].setNumber == 2 { data.sets[index].weight = nil }
                default: data.sets[index].duration = 30
                }
            }
            XCTAssertNil(reference(data), "mode \(mode)")
        }
        let data = fixture(); data.sets += data.sets
        XCTAssertNil(reference(data), "Duplicated records cannot inflate evidence")
    }

    func testUnstableTrainingAndFailedTemporalHoldoutAbstain() {
        for session in ["pair-1", "pair-4"] {
            let data = fixture()
            for i in data.sets.indices where data.sets[i].exerciseId == targetID && data.sets[i].workoutSessionID == session {
                data.sets[i].weight! *= 1.4
            }
            XCTAssertNil(reference(data), session)
        }
        let data = fixture(); data.sets[0].weight = 100
        XCTAssertNil(reference(data), "Mixed warmup/work sets must not create a stable pair")
    }

    func testRecentOwnHistoryAndRememberedExplicitInputHavePriority() {
        let data = fixture()
        data.sets += records(targetID, weight: 29, day: -3, session: "recent-own")
        XCTAssertNil(reference(data))
        XCTAssertEqual(data.suggestingMissingParameters(for: target).weight, 29)
        let other = fixture()
        other.settings.exerciseWeightInputs = [targetID: 40]
        other.settings.confirmedExerciseWeightInputIDs = [targetID]
        XCTAssertEqual(other.suggestingMissingParameters(for: target).weight, 30, "Existing exact-history precedence is retained")
        other.settings.exerciseWeightInputs = [targetID: 30]
        XCTAssertEqual(other.suggestingMissingParameters(for: target).weight, 31.5, "A cache of the old recorded load must not disable learning forever")
        XCTAssertEqual(other.settings.exerciseWeightInputs?[targetID], 30, "The remembered manual input itself is preserved")
    }

    func testFreshnessRepDomainAndExtrapolationGuards() {
        for load in [30.0, 69, 100] {
            let data = fixture()
            for i in data.sets.indices where data.sets[i].workoutSessionID == "current" { data.sets[i].weight = load }
            XCTAssertNil(reference(data))
        }
        let data = fixture()
        for reps in [5, 6, 9, 13] { XCTAssertNil(reference(data, reps: reps)) }
        data.sets += records(sourceID, weight: 65, day: -1, session: "different-reps", offset: 3600).map {
            var record = $0; record.reps = 10; return record
        }
        XCTAssertNil(reference(data), "A newer unmatched rep record must not reuse an older anchor")
        // Rebuild at a past time would also ignore all future observations.
        XCTAssertNil(PersonalExerciseLoadReference.reference(for: data.exById[targetID]!, targetReps: 8,
            records: data.sets, library: data.exById, now: now.addingTimeInterval(-20 * 86400)))
        let stale = fixture(); stale.sets.removeAll { $0.workoutSessionID == "current" }
        XCTAssertNil(reference(stale))
    }

    func testNoEvidenceNoCrossEstimateAndDeletedEvidenceWithdrawsSuggestion() {
        let data = fixture()
        var step = data.suggestingMissingParameters(for: target)
        data.sets = []; data.settings.exerciseWeightInputs = [sourceID: 63]
        data.settings.confirmedExerciseWeightInputIDs = [sourceID]
        XCTAssertNil(data.suggestingMissingParameters(for: target).weight)
        step = data.suggestingMissingParameters(for: step)
        XCTAssertNil(step.weight)
        XCTAssertNil(step.parameterSuggestions?["weight"])
        data.plans = [Plan(id: "typed-only", name: "Workout", steps: [.init(id: "manual", exerciseId: sourceID, sets: 3, reps: 8, weight: 63, duration: nil)], createdAt: now, updatedAt: now)]
        XCTAssertNil(data.suggestingMissingParameters(for: target).weight)
    }

    func testManualZeroPerSetSharedAndChangedRepsRemainProtected() throws {
        let data = fixture()
        for weight in [0.0, 20, 50] {
            var step = target; step.weight = weight
            XCTAssertEqual(data.suggestingMissingParameters(for: step), step)
        }
        var step = target; step.setWeights = [20, nil, 25]
        XCTAssertEqual(data.suggestingMissingParameters(for: step), step)
        step = target; step.setReps = [8, 10, 12]
        XCTAssertNil(data.suggestingMissingParameters(for: step).weight)
        step = data.suggestingMissingParameters(for: target)
        step.reps = 9; step.confirmParameter("reps")
        CrossExerciseLoadReference.clearIfUnsupported(&step)
        XCTAssertNil(step.weight, "Even an in-range rep change invalidates a same-rep relationship")
        step = data.suggestingMissingParameters(for: target)
        step.confirmParameter("weight"); step.reps = 9
        CrossExerciseLoadReference.clearIfUnsupported(&step)
        XCTAssertEqual(step.weight, 31.5, "Manual confirmation protects weight")
    }

    func testIndependentDatesAndFourWeekSpanCannotBeReplacedByExtraSets() {
        for sameDay in [true, false] {
            let data = fixture(); data.sets = []
            for index in 0..<5 {
                let day = sameDay ? -42 : -42 + index
                data.sets += records(sourceID, weight: 60, day: day, session: "dense-\(index)", offset: Double(index) * 3600)
                data.sets += records(targetID, weight: 30, day: day, session: "dense-\(index)", offset: Double(index) * 3600 + 120)
            }
            data.sets += records(sourceID, weight: 63, day: -1, session: "current")
            XCTAssertNil(reference(data))
        }
    }

    func testSeparateHoldoutEvaluatesUnseenPairsAndRespondsToEdits() throws {
        let data = fixture()
        // 30 kg in the fifth pair is not used to fit the 0.5 ratio.
        // 26 kg would be a >10% holdout miss even though the four training pairs fit exactly.
        for i in data.sets.indices where data.sets[i].exerciseId == targetID && data.sets[i].workoutSessionID == "pair-4" {
            data.sets[i].weight = 26
        }
        XCTAssertNil(reference(data))
        for i in data.sets.indices where data.sets[i].exerciseId == targetID && data.sets[i].workoutSessionID == "pair-4" {
            data.sets[i].weight = 30
        }
        XCTAssertEqual(try XCTUnwrap(reference(data)).kilograms, 31.5)
    }

    func testInputOrderDoesNotChangeTheRelationship() {
        let data = fixture(), expected = reference(data)
        data.sets.reverse()
        XCTAssertEqual(reference(data)?.kilograms, expected?.kilograms)
        XCTAssertEqual(reference(data)?.sourceExerciseID, expected?.sourceExerciseID)
    }
}

@MainActor
final class QuietProgressionTests: XCTestCase {
    private let now = Date()
    private let id = "bench_press_barbell"
    private func records(count: Int = 3, reps: Int = 12, load: Double = 50, exerciseID: String = "bench_press_barbell") -> [SetRecord] {
        (0..<count).flatMap { day in
            (1...3).map { n in
                SetRecord(id: "progress-\(day)-\(n)", exerciseId: exerciseID, exerciseName: exerciseID,
                          category: .strength, weight: load, reps: reps, duration: nil,
                          performedAt: now.addingTimeInterval(-Double(2 + day * 2) * 86400 + Double(n)),
                          planId: nil, workoutSessionID: "progress-\(day)", setNumber: n)
            }
        }
    }
    private func suggestion(_ records: [SetRecord]? = nil, goal: TrainingGoalKind = .buildMuscle,
                            load: Double = 50, reps: Int = 8, prefs: LoadProgressionPreferences = .init(),
                            active: String? = nil, exerciseID: String = "bench_press_barbell") -> ProgressionEngine.Suggestion? {
        let library = DataStore.makeMock().exById
        return ProgressionEngine.suggestion(exerciseId: exerciseID, targetReps: reps, sets: records ?? self.records(),
            exercise: library[exerciseID], goal: goal, currentWeight: load, requiredSets: 3,
            preferences: prefs, activeSessionID: active, now: now)
    }
    func testGoalSpecificRepeatedWorkoutsAndRepRangeInsteadOfOneSuccess() {
        XCTAssertNil(suggestion(records(count: 1)))
        XCTAssertNil(suggestion(records(count: 2)))
        XCTAssertEqual(suggestion()?.weightKg, 52.5)
        XCTAssertNotNil(suggestion(records(count: 2, reps: 6), goal: .getStronger, reps: 5))
        XCTAssertNil(suggestion(records(count: 2, reps: 5), goal: .getStronger, reps: 5))
        XCTAssertNil(suggestion(records(reps: 8)))
        XCTAssertNil(suggestion(goal: .generalFitness))
        XCTAssertNil(suggestion(goal: .endurance))
        XCTAssertNotNil(suggestion(goal: .loseFat))
    }
    func testMaintenanceAndStageLimitNeverRewriteTargetsOrRecords() {
        let data = DataStore.makeMock(), original = data.plans, actual = data.sets
        var prefs = LoadProgressionPreferences(); prefs.maintain = true
        XCTAssertNil(suggestion(prefs: prefs))
        prefs.maintain = false; prefs.exercises[id] = .init(maintain: true)
        XCTAssertNil(suggestion(prefs: prefs))
        for limit in [0.0, 49, 50, 51, .infinity, .nan] {
            prefs.exercises[id] = .init(limitKg: limit); XCTAssertNil(suggestion(prefs: prefs))
        }
        prefs.exercises[id] = .init(limitKg: 52.5)
        XCTAssertEqual(suggestion(prefs: prefs)?.weightKg, 52.5)
        data.settings.loadProgression = prefs
        XCTAssertEqual(data.plans, original); XCTAssertEqual(data.sets, actual)
    }
    func testSameEvidenceNeverRepeatsEvenAfterCooldownAndPersists() throws {
        let s = try XCTUnwrap(suggestion())
        var prefs = LoadProgressionPreferences()
        prefs.notices[id] = .init(evidence: s.evidence, shownAt: now.addingTimeInterval(-60 * 86400))
        XCTAssertNil(suggestion(prefs: prefs))
        let decoded = try JSONDecoder().decode(LoadProgressionPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded, prefs); XCTAssertNil(suggestion(prefs: decoded))
    }
    func testCooldownGoalBudgetDeclineAndNearLimit() {
        var prefs = LoadProgressionPreferences()
        prefs.notices[id] = .init(evidence: "old", shownAt: now.addingTimeInterval(-14 * 86400))
        XCTAssertNotNil(suggestion(goal: .getStronger, prefs: prefs))
        XCTAssertNil(suggestion(prefs: prefs))
        prefs.notices[id] = .init(evidence: "old", shownAt: now.addingTimeInterval(-30 * 86400))
        XCTAssertNotNil(suggestion(prefs: prefs))
        prefs.notices[id]?.declined = true; XCTAssertNil(suggestion(prefs: prefs))
        prefs.notices[id] = .init(evidence: "old", shownAt: now.addingTimeInterval(-43 * 86400), declined: true)
        XCTAssertNotNil(suggestion(prefs: prefs))
        prefs.notices[id] = .init(evidence: "old", shownAt: now.addingTimeInterval(-30 * 86400))
        prefs.exercises[id] = .init(limitKg: 55); XCTAssertNil(suggestion(prefs: prefs))
        prefs.exercises = [:]; prefs.notices = ["other": .init(evidence: "x", shownAt: now.addingTimeInterval(-6 * 86400))]
        XCTAssertNil(suggestion(prefs: prefs))
        prefs.notices["other"] = .init(evidence: "x", shownAt: now.addingTimeInterval(-8 * 86400))
        XCTAssertNotNil(suggestion(prefs: prefs)); XCTAssertNil(suggestion(goal: .loseFat, prefs: prefs))
    }
    func testNewEvidenceMustFollowLastSuggestionAndNewLoadRequiresAdaptation() {
        var prefs = LoadProgressionPreferences()
        prefs.notices[id] = .init(evidence: "different", shownAt: now.addingTimeInterval(-3 * 86400))
        XCTAssertNil(suggestion(prefs: prefs))
        XCTAssertNil(suggestion(load: 52.5))
        var changed = records(); changed[0].weight = 52.5
        XCTAssertNil(suggestion(changed))
        changed = records(); changed[0].reps = 7; XCTAssertNil(suggestion(changed))
        XCTAssertNil(suggestion(active: "progress-0"))
    }
    func testMissingDuplicateNonFiniteIncompleteAndFutureEvidenceAbstain() {
        for mode in 0..<6 {
            var r = records()
            switch mode {
            case 0: r[0].weight = .nan
            case 1: r[0].workoutSessionID = nil
            case 2: r[0].setNumber = 2
            case 3: r.removeFirst()
            case 4: r[0].duration = 30
            default: r[0].reps = nil
            }
            XCTAssertNil(suggestion(r), "mode \(mode)")
        }
        let r = records(); XCTAssertNil(suggestion(r + [r[0]]))
        XCTAssertNil(ProgressionEngine.suggestion(exerciseId: id, targetReps: 8, sets: r, exercise: DataStore.makeMock().exById[id],
            goal: .buildMuscle, currentWeight: 50, preferences: .init(), now: now.addingTimeInterval(-30 * 86400)))
        XCTAssertNil(ProgressionEngine.suggestion(exerciseId: id, targetReps: 8, sets: r, exercise: DataStore.makeMock().exById[id],
            goal: .buildMuscle, currentWeight: 50, preferences: .init(), now: now.addingTimeInterval(25 * 86400)))
    }
    func testExcessiveRelativeJumpAndNumericMaximumAreRejected() {
        XCTAssertNil(suggestion(records(load: 5), load: 5))
        XCTAssertNil(suggestion(records(load: 500), load: 500))
        XCTAssertNil(suggestion(load: .nan))
    }
    func testTrainingPreferenceSavePreservesPoliciesReceiptsAndDoesNotRegenerateRoutines() throws {
        var settings = UserSettings()
        settings.loadProgression = .init(exercises: [id: .init(limitKg: 60)], notices: [id: .init(evidence: "x", shownAt: now)])
        let original = TrainingPreferenceDraft(settings: settings)
        var draft = original; draft.maintainWeights = true
        XCTAssertNotEqual(draft, original); XCTAssertFalse(draft.affectsRoutine(comparedTo: original))
        draft.apply(to: &settings)
        XCTAssertEqual(settings.loadProgression?.maintain, true)
        XCTAssertEqual(settings.loadProgression?.exercises[id]?.limitKg, 60)
        XCTAssertEqual(settings.loadProgression?.notices[id]?.evidence, "x")
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.loadProgression, settings.loadProgression)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "loadProgression")
        let old = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.loadProgression)
    }
}

@MainActor
final class RoughLoadEstimateTests: XCTestCase {
    private func fixture() -> (DataStore, TrainingSessionStore) {
        let data = DataStore.makeMock()
        data.sets = []; data.settings.exerciseWeightInputs = nil
        data.settings.confirmedExerciseWeightInputIDs = nil
        let plan = Plan(id: "rough-live", name: "Workout", steps: [
            .init(id: "bench", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60, duration: nil),
            .init(id: "incline", exerciseId: "incline_bench_press_barbell", sets: 3, reps: 8, duration: nil),
            .init(id: "pushdown", exerciseId: "triceps_pushdown_straight_bar", sets: 3, reps: 8, duration: nil)
        ], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById,
            defaultRest: 90, defaultBetweenExerciseRest: 120))
        return (data, store)
    }

    func testCompletionEditAndUndoRefreshWithoutRewritingHistoryOrPlayback() throws {
        let (data, store) = fixture(); defer { store.end() }
        store.refreshLoadSuggestions(using: data)
        XCTAssertNil(store.plan?.steps[1].weight, "Input alone is not completion evidence")
        store.advance { data.recordSet($0) }
        let records = data.sets
        let ids = store.segments.map(\.id)
        let state = store.session
        store.refreshLoadSuggestions(using: data)
        XCTAssertEqual(store.plan?.steps[1].weight, 32.5)
        XCTAssertEqual(store.plan?.steps[2].weight, 12.5)
        XCTAssertEqual(store.plan?.steps[1].parameterSuggestions?["weight"]?.source, .roughEstimate)
        XCTAssertTrue(store.updateStepWeight(stepId: "bench", weightKg: 50))
        store.refreshLoadSuggestions(using: data)
        XCTAssertEqual(store.plan?.steps[1].weight, 27.5)
        XCTAssertEqual(store.plan?.steps[2].weight, 10)
        XCTAssertEqual(data.sets, records)
        XCTAssertEqual(store.segments.map(\.id), ids)
        XCTAssertEqual(store.session?.endsAt, state?.endsAt)
        XCTAssertEqual(store.session?.segmentIndex, state?.segmentIndex)
        XCTAssertEqual(store.session?.completedSets, state?.completedSets)
        XCTAssertTrue(store.undoPlayback { data.removeSetRecord(id: $0) })
        store.refreshLoadSuggestions(using: data)
        XCTAssertTrue(data.sets.isEmpty)
        XCTAssertNil(store.plan?.steps[1].weight)
        XCTAssertNil(store.plan?.steps[2].weight)
    }

    func testManualZeroPerSetSharedAndCompletedTargetsAreProtected() throws {
        for mode in ["manual", "zero", "perSet", "shared", "completed"] {
            let (data, store) = fixture()
            store.advance { data.recordSet($0) }
            store.refreshLoadSuggestions(using: data)
            var step = try XCTUnwrap(store.plan?.steps[1])
            if mode == "completed" {
                store.jumpToStep(stepId: step.id)
                store.advance { data.recordSet($0) }
            } else {
                if mode == "perSet" { step.setWeights = [nil, 20, nil] }
                else if mode == "shared" { step.markSuggested("weight", value: step.weight!, source: .shared) }
                else { step.weight = mode == "zero" ? 0 : 45; step.confirmParameter("weight") }
                store.plan?.steps[1] = step
            }
            let protected = store.plan?.steps[1]
            let records = data.sets
            XCTAssertTrue(store.updateStepWeight(stepId: "bench", weightKg: 50))
            store.refreshLoadSuggestions(using: data)
            XCTAssertEqual(store.plan?.steps[1], protected, mode)
            XCTAssertEqual(data.sets, records, mode)
            store.end()
        }
    }

    func testWatchCompletionAndUndoRefreshWithoutAVisiblePlayer() throws {
        let (data, store) = fixture(); defer { store.end() }
        func command(_ kind: WatchCommand.Kind) throws -> WatchCommand {
            let state = store.makeWatchState()
            return WatchCommand(sessionID: try XCTUnwrap(state.workoutSessionID),
                                context: try XCTUnwrap(state.context), kind: kind)
        }
        XCTAssertTrue(store.applyWatchCommand(try command(.advance), data: data))
        XCTAssertEqual(store.plan?.steps[1].weight, 32.5)
        XCTAssertEqual(store.plan?.steps[2].weight, 12.5)
        XCTAssertTrue(store.applyWatchCommand(try command(.undo), data: data))
        XCTAssertNil(store.plan?.steps[1].weight)
        XCTAssertNil(store.plan?.steps[2].weight)
    }

    func testRepConversionExpiryAndNoCableToPressInference() throws {
        let data = DataStore.makeMock()
        let incline = try XCTUnwrap(data.exById["incline_bench_press_barbell"])
        var record = SetRecord(id: "rough", exerciseId: "bench_press_barbell", exerciseName: "Bench",
            category: .strength, weight: 60, reps: 8, duration: nil, performedAt: Date(), planId: nil)
        let result = RoughExerciseLoadReference.reference(for: incline, targetReps: 12, records: [record])
        XCTAssertEqual(result?.kilograms, 30)
        XCTAssertNil(RoughExerciseLoadReference.reference(for: incline, targetReps: 0, records: [record]))
        XCTAssertNil(RoughExerciseLoadReference.reference(for: incline, targetReps: 8, records: [record], now: Date().addingTimeInterval(31 * 86400)))
        record.exerciseId = "triceps_pushdown_straight_bar"
        XCTAssertNil(RoughExerciseLoadReference.reference(for: incline, targetReps: 8, records: [record]))
        record.exerciseId = "bench_press_barbell"; record.reps = 6
        record.sixRMReference = SixRMReference(kilograms: 60)
        let roundTrip = try JSONDecoder().decode(SetRecord.self, from: JSONEncoder().encode(record))
        XCTAssertTrue(roundTrip.hasConfirmedSixRM)
    }
}
