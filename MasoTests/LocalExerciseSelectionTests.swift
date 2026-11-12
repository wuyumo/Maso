import XCTest
@testable import Maso

@MainActor
final class LocalExerciseSelectionTests: XCTestCase {
    private let policy = ExerciseSelectionPolicy.shared

    func testDiscardRestoredHourLongWorkoutRemovesOnlyOwnedHistory() throws {
        let step = PlanStep(id: "discard-step", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60)
        let plan = Plan(id: "discard-plan", name: "Discard", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        let logged = try XCTUnwrap(records.first)
        // Another workout with the SAME plan, exercise and day must survive.
        let earlier = SetRecord(id: "earlier-workout", exerciseId: logged.exerciseId,
                                exerciseName: logged.exerciseName, category: logged.category,
                                weight: 40, reps: 8, performedAt: Date().addingTimeInterval(-7200), planId: plan.id)
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [plan], sets: [earlier, logged], settings: UserSettings())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(store.session))) as? [String: Any])
        json["startedAt"] = Date().addingTimeInterval(-3900).timeIntervalSinceReferenceDate
        json["lastActiveAt"] = Date().addingTimeInterval(-3600).timeIntervalSinceReferenceDate
        // Old installed builds have undo IDs but no recordedSetIDs field.
        json.removeValue(forKey: "recordedSetIDs")
        let legacy = try JSONDecoder().decode(TrainingSessionStore.Session.self, from: JSONSerialization.data(withJSONObject: json))
        store.end()
        SessionPersistence.save(.init(session: legacy, plan: plan, planParamsDirty: false))
        let restored = TrainingSessionStore(completionSound: {})
        restored.restorePersistedSession(exById: ExerciseLibrary.byId, defaultRest: 60, defaultBetweenExerciseRest: 60)
        XCTAssertNotNil(restored.session)
        data.updateWorkoutCompletion(planID: plan.id, startedAt: earlier.performedAt, completed: true)
        data.updateWorkoutCompletion(planID: plan.id, startedAt: try XCTUnwrap(restored.session).startedAt, completed: true)
        restored.discard { data.discardWorkout($0, recordIDs: $1) }
        XCTAssertEqual(data.sets.map(\.id), [earlier.id])
        XCTAssertEqual(data.settings.workoutCompletions?.filter { !$0.sessionID.hasPrefix("legacy-") }.count, 1)
        XCTAssertNil(restored.session)
        XCTAssertTrue(restored.endedExplicitly)
        XCTAssertNil(SessionPersistence.load())
        let reopened = TrainingSessionStore(completionSound: {})
        reopened.restorePersistedSession(exById: ExerciseLibrary.byId, defaultRest: 60, defaultBetweenExerciseRest: 60)
        XCTAssertNil(reopened.session)
    }

    func testDiscardAfterUndoAndRepeatPreservesOtherRecords() throws {
        let step = PlanStep(id: "discard-repeat", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60)
        let plan = Plan(id: "discard-repeat-plan", name: "Repeat", steps: [step], createdAt: Date(), updatedAt: Date())
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [plan], sets: [], settings: UserSettings())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        store.advance { data.recordSet($0) }
        let firstID = try XCTUnwrap(data.sets.first?.id)
        XCTAssertTrue(store.undoPlayback { data.removeSetRecord(id: $0) })
        store.advance { data.recordSet($0) }
        XCTAssertNotEqual(firstID, data.sets.first?.id)
        let decoded = try JSONDecoder().decode(TrainingSessionStore.Session.self,
                                              from: JSONEncoder().encode(try XCTUnwrap(store.session)))
        XCTAssertEqual(decoded.recordedSetIDs?.count, 2)
        store.discard { data.discardWorkout($0, recordIDs: $1) }
        XCTAssertTrue(data.sets.isEmpty)
    }

    func testFinishKeepsHistoryAndEmptyDiscardCreatesNone() {
        let step = PlanStep(id: "keep-step", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60)
        let plan = Plan(id: "keep-plan", name: "Keep", steps: [step], createdAt: Date(), updatedAt: Date())
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [plan], sets: [], settings: UserSettings())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        store.advance { data.recordSet($0) }
        store.finishEarly()
        XCTAssertEqual(store.session?.completed, true)
        store.end()
        XCTAssertEqual(data.sets.count, 1)
        let savedID = data.sets.first?.id
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        store.discard { data.discardWorkout($0, recordIDs: $1) }
        XCTAssertEqual(data.sets.map(\.id), [savedID].compactMap { $0 })
        XCTAssertNil(SessionPersistence.load())
    }

    func testPlayerTitleSplitsLocalizedParenthesesWithoutLosingNames() {
        let english = PlayerExerciseTitleParts("Bench Press (Dumbbell) (Neutral Grip)")
        XCTAssertEqual(english.title, "Bench Press")
        XCTAssertEqual(english.subtitle, "Dumbbell · Neutral Grip")
        let chinese = PlayerExerciseTitleParts("卧推（哑铃）")
        XCTAssertEqual(chinese.title, "卧推")
        XCTAssertEqual(chinese.subtitle, "哑铃")
        XCTAssertNil(PlayerExerciseTitleParts("上斜卧推").subtitle)
        XCTAssertEqual(PlayerExerciseTitleParts("Custom (unfinished").title, "Custom (unfinished")
        XCTAssertEqual(PlayerExerciseTitleParts("(Custom)").title, "(Custom)")
        XCTAssertNil(PlayerExerciseTitleParts("(Custom)").subtitle)
    }

    func testPlaybackUndoRestThenSetRemovesOnlyExactRecordAndSurvivesCoding() throws {
        let step = PlanStep(id: "undo-step", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60)
        let plan = Plan(id: "undo-plan", name: "Undo", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        defer { store.end() }
        var records: [SetRecord] = []
        XCTAssertFalse(store.canUndoPlayback)
        store.advance { records.append($0) }
        XCTAssertEqual(records.count, 1)
        let restEnd = try XCTUnwrap(store.session?.endsAt)
        store.advance() // Skip rest, land on set two.
        let encoded = try JSONEncoder().encode(try XCTUnwrap(store.session))
        let decoded = try JSONDecoder().decode(TrainingSessionStore.Session.self, from: encoded)
        XCTAssertEqual(decoded.playbackUndo?.count, 2)
        var removed: [String] = []
        XCTAssertTrue(store.undoPlayback { removed.append($0) })
        XCTAssertTrue(try XCTUnwrap(store.currentSegment).isRest)
        XCTAssertEqual(store.session?.completedSets.count, 1)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(try XCTUnwrap(store.session?.endsAt).timeIntervalSince(restEnd), 0, accuracy: 1)
        XCTAssertTrue(store.undoPlayback { removed.append($0) })
        XCTAssertEqual(store.session?.segmentIndex, 0)
        XCTAssertEqual(store.session?.completedSets.count, 0)
        XCTAssertEqual(store.session?.completionOrder, [])
        XCTAssertEqual(removed, records.map(\.id))
        XCTAssertFalse(store.canUndoPlayback)
        store.advance { records.append($0) }
        XCTAssertNotEqual(records[0].id, records[1].id)
        XCTAssertEqual(store.session?.completedSets.count, 1)
    }

    func testPlaybackUndoPausedRestRestoresRemainingAndJumpDoesNotUndoASet() throws {
        let step = PlanStep(id: "undo-pause", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: nil)
        let plan = Plan(id: "undo-paused", name: "Undo", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        defer { store.end() }
        store.advance()
        store.togglePlay()
        let remaining = try XCTUnwrap(store.session?.pausedRemaining)
        store.advance()
        XCTAssertTrue(store.undoPlayback { _ in XCTFail("Rest has no record") })
        XCTAssertEqual(store.session?.playing, false)
        XCTAssertEqual(try XCTUnwrap(store.session?.pausedRemaining), remaining, accuracy: 0.1)
        store.setIndex(4)
        XCTAssertTrue(store.undoPlayback { _ in XCTFail("Jump has no record") })
        XCTAssertTrue(try XCTUnwrap(store.currentSegment).isRest)
        XCTAssertEqual(store.session?.completedSets.count, 1)
    }

    func testQuickAdjustmentsPreserveCompletedTargetsRestPositionAndClock() throws {
        let step = PlanStep(id: "quick", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60,
                            setReps: [8, 9, 10], setWeights: [60, 65, 70])
        let plan = Plan(id: "quick-test", name: "Quick", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        defer { store.end() }
        store.advance(); store.advance(); store.advance()
        XCTAssertTrue(store.currentSegment?.isRest == true)
        let before = try XCTUnwrap(store.session)
        store.adjustParameter(.weight, by: 1, stepId: step.id, unit: .kg, exById: ExerciseLibrary.byId,
                              defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.first?.setWeights, [60, 65, 72.5])
        XCTAssertEqual(store.session?.segmentIndex, before.segmentIndex)
        XCTAssertEqual(store.session?.endsAt, before.endsAt)
        XCTAssertEqual(store.session?.completedSets, before.completedSets)
        store.adjustParameter(.reps, by: 1, stepId: step.id, unit: .kg, exById: ExerciseLibrary.byId,
                              defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.first?.setReps, [8, 9, 11])
        store.adjustParameter(.sets, by: -1, stepId: step.id, unit: .kg, exById: ExerciseLibrary.byId,
                              defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.first?.sets, 3, "Do not remove the pending set beneath the active rest")
        XCTAssertEqual(store.session?.endsAt, before.endsAt)
        store.adjustParameter(.weight, by: 1, stepId: step.id, unit: .lb, exById: ExerciseLibrary.byId,
                              defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(try XCTUnwrap(store.plan?.steps.first?.weightForSet(3)), 72.5 + WeightUnit.lb.toKg(5), accuracy: 0.001)
    }

    func testQuickDurationAdjustmentExtendsPausedCountdownWithoutRestarting() throws {
        let exercise = try XCTUnwrap(ExerciseLibrary.all.first { $0.category.normalized == .cardio })
        let step = PlanStep(id: "timed", exerciseId: exercise.id, sets: 1, duration: 60)
        let plan = Plan(id: "timed-test", name: "Timed", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        defer { store.end() }
        store.togglePlay()
        let before = try XCTUnwrap(store.session?.pausedRemaining)
        store.adjustParameter(.duration, by: 1, stepId: step.id, unit: .kg, exById: ExerciseLibrary.byId,
                              defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.first?.durationForSet(1), 75)
        XCTAssertEqual(try XCTUnwrap(store.session?.pausedRemaining), before + 15, accuracy: 0.01)
        XCTAssertNil(store.session?.endsAt)
    }

    func testFreshDefaultLibraryContainsOnlyTheCoreSet() {
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
        let curated = store.curatedExerciseLibrary
        XCTAssertEqual(curated.count, 134)
        XCTAssertEqual(Set(curated.map { policy.displayFamilyID(for: $0) }).count, 64)
        XCTAssertTrue(curated.allSatisfy { policy.tier(for: $0) == .core })
        XCTAssertEqual(store.userLibrary.count, ExerciseLibrary.all.count)
    }

    func testAutomaticSelectionUsesFamiliarEquipmentMatchedGroups() throws {
        var settings = UserSettings()
        settings.availableEquipment = ["dumbbell"]
        let selected = DataStore.suggestedTrainingExercises(
            targetMuscles: [.chest, .back, .shoulders, .arms, .legs],
            library: ExerciseLibrary.all, settings: settings, perMuscleLimit: 2, limit: 8)
        XCTAssertFalse(selected.isEmpty)
        XCTAssertLessThanOrEqual(selected.count, 8)
        XCTAssertTrue(selected.allSatisfy { !policy.tier(for: $0).isSpecialist })
        XCTAssertTrue(selected.allSatisfy { policy.equipmentAllows($0, selected: ["dumbbell"]) })
        XCTAssertEqual(Set(selected.map { policy.programmingGroupID(for: $0) }).count, selected.count)
        let reversed = DataStore.suggestedTrainingExercises(
            targetMuscles: [.chest, .back, .shoulders, .arms, .legs],
            library: Array(ExerciseLibrary.all.reversed()), settings: settings, perMuscleLimit: 2, limit: 8)
        XCTAssertEqual(selected.map(\.id), reversed.map(\.id))
    }

    func testQuickConcreteEquipmentFiltersStayExactThroughSanitization() {
        var settings = UserSettings()
        settings.availableEquipment = ["dumbbell"]
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: settings)
        let cases: [(String, String, MuscleGroup)] = [
            ("smith_machine", "smith", .chest),
            ("pull_up_bar", "pullupBar", .back),
            ("leg_press_machine", "machine", .legs)
        ]
        for (raw, category, muscle) in cases {
            let candidates = store.suggestedTrainingExercises(
                targetMuscles: [muscle], perMuscleLimit: 6, limit: 40, equipmentFilter: raw)
            let effective = DataStore.settingsForTrainingSelection(settings, equipmentFilter: raw)
            XCTAssertEqual(effective.availableEquipment, [category], raw)
            XCTAssertFalse(candidates.isEmpty, raw)
            XCTAssertTrue(candidates.allSatisfy { $0.equipment == raw }, raw)
            let accepted = policy.sanitizedGeneratedExercises(candidates, allowed: candidates, settings: effective)
            XCTAssertEqual(accepted.map(\.id), candidates.map(\.id), raw)
            XCTAssertTrue(accepted.allSatisfy { !policy.tier(for: $0).isSpecialist }, raw)
        }
        XCTAssertEqual(store.settings.availableEquipment, ["dumbbell"])
    }

    func testSpecialistStashUsesTheSameEditorialTiersAsGeneration() throws {
        let specialist = try XCTUnwrap(ExerciseLibrary.byId["arnold_curl"])
        let adopted = try XCTUnwrap(ExerciseLibrary.byId["axle_bar_curl"])
        let core = try XCTUnwrap(ExerciseLibrary.byId["ab_wheel_rollout_kneeling"])
        XCTAssertFalse(specialist.isNiche)
        XCTAssertTrue(core.isNiche)
        var settings = UserSettings()
        settings.adoptedNicheExerciseIds = [adopted.id]
        let store = DataStore(exercises: [specialist, adopted, core], plans: [], sets: [], settings: settings)
        XCTAssertEqual(store.unadoptedNicheExercises.map(\.id), [specialist.id])
    }

    func testLocalPostProcessingRetainsOnlyTheInputSpecialistVariant() throws {
        let specialist = try XCTUnwrap(ExerciseLibrary.byId["arnold_curl"])
        let otherSpecialist = try XCTUnwrap(ExerciseLibrary.byId["axle_bar_curl"])
        let step = PlanStep(id: "requested-specialist", exerciseId: specialist.id, sets: 3, reps: 10,
                            weight: 12, setWeights: [12, 14, 14])
        let plan = Plan(id: "requested-plan", name: "Arms", steps: [step], createdAt: Date(), updatedAt: Date())
        var settings = UserSettings()
        settings.availableEquipment = ["dumbbell"]
        settings.favoriteExerciseIds = [otherSpecialist.id]
        var intent = LocalRoutineRules.Intent()
        intent.focusSections = [.arms]
        let result = try XCTUnwrap(LocalRoutineRules.apply(
            to: [plan], intent: intent, settings: settings, exById: ExerciseLibrary.byId).first)
        XCTAssertEqual(result.steps, [step])
        XCTAssertFalse(result.steps.contains { $0.exerciseId == otherSpecialist.id })

        // Ordinary template normalization still excludes specialist work by default.
        let automatic = DataStore.applyEquipmentPreference([step], settings: settings, exById: ExerciseLibrary.byId)
        XCTAssertFalse(automatic.isEmpty)
        XCTAssertTrue(automatic.allSatisfy { step in
            ExerciseLibrary.byId[step.exerciseId].map { !policy.tier(for: $0).isSpecialist } ?? false
        })

        // Retaining an exact variant cannot override a later explicit equipment restriction.
        intent.equipment = ["barbell"]
        let constrained = try XCTUnwrap(LocalRoutineRules.apply(
            to: [plan], intent: intent, settings: settings, exById: ExerciseLibrary.byId).first)
        XCTAssertFalse(constrained.steps.isEmpty)
        XCTAssertFalse(constrained.steps.contains { $0.exerciseId == specialist.id || $0.exerciseId == otherSpecialist.id })
        XCTAssertTrue(constrained.steps.allSatisfy { step in
            ExerciseLibrary.byId[step.exerciseId].map { policy.equipmentAllows($0, selected: ["barbell"]) } ?? false
        })
    }

    func testNewRoutineNormalizationAndPaddingKeepOneVariantPerGroup() throws {
        let first = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        let sameGroup = try XCTUnwrap(ExerciseLibrary.all.first {
            $0.id != first.id && policy.programmingGroupID(for: $0) == policy.programmingGroupID(for: first)
                && !policy.tier(for: $0).isSpecialist
        })
        let raw = [first, sameGroup, first].enumerated().map { index, exercise in
            PlanStep(id: "generated-\(index)", exerciseId: exercise.id, sets: 3, reps: 10,
                     weight: 60, setWeights: [60, 65, 70])
        }
        var settings = UserSettings()
        settings.availableEquipment = ["dumbbell"]
        let normalized = DataStore.applyEquipmentPreference(raw, settings: settings, exById: ExerciseLibrary.byId)
        let padded = DataStore.padStepsToTarget(normalized, target: 5, settings: settings, exById: ExerciseLibrary.byId)
        let selected = padded.compactMap { ExerciseLibrary.byId[$0.exerciseId] }
        XCTAssertFalse(selected.isEmpty)
        XCTAssertEqual(Set(selected.map { policy.programmingGroupID(for: $0) }).count, selected.count)
        XCTAssertTrue(selected.allSatisfy { !policy.tier(for: $0).isSpecialist })
        XCTAssertTrue(selected.allSatisfy { policy.equipmentAllows($0, selected: ["dumbbell"]) })
        XCTAssertTrue(padded.allSatisfy { $0.weight == nil && $0.setWeights == nil })
        XCTAssertEqual(raw[0].exerciseId, first.id)
        XCTAssertEqual(raw[0].weight, 60)
    }

    func testLegDayKeepsKneeHingeCurlAndCalfRoles() throws {
        let ids = ["squat_barbell", "rdl_barbell", "leg_curl_seated", "calf_raise_seated"]
        let exercises = try ids.map { try XCTUnwrap(ExerciseLibrary.byId[$0]) }
        let steps = exercises.enumerated().map { index, exercise in
            PlanStep(id: "leg-\(index)", exerciseId: exercise.id, sets: 3, reps: 10)
        }
        let normalized = DataStore.applyEquipmentPreference(steps, settings: UserSettings(), exById: ExerciseLibrary.byId)
        let final = DataStore.enforceScience(normalized, exById: ExerciseLibrary.byId)
        XCTAssertEqual(Set(final.map(\.exerciseId)), Set(ids))
        XCTAssertEqual(final.count, 4)
    }

    func testCuratedLibraryRetainsPersonalVariantsWithoutChangingPlansOrRecords() throws {
        let specialist = try XCTUnwrap(ExerciseLibrary.all.first { policy.tier(for: $0).isSpecialist })
        let unused = try XCTUnwrap(ExerciseLibrary.all.first {
            $0.id != specialist.id && policy.tier(for: $0).isSpecialist
        })
        let custom = Exercise(id: "custom-local-review", name: "My exercise", category: .strength,
                              tags: [], primaryMuscles: [.chest], muscleGroups: [.chest], imageFolder: nil, instructions: [])
        var settings = UserSettings()
        settings.customExercises = [custom]
        let plan = Plan(id: "saved", name: "Saved", steps: [
            PlanStep(id: "saved-step", exerciseId: specialist.id, sets: 4, reps: 8, weight: 42)
        ], createdAt: Date(), updatedAt: Date())
        let legacyID = specialist.imageFolder ?? specialist.id
        let record = SetRecord(id: "record", exerciseId: legacyID, exerciseName: specialist.name,
                               category: specialist.category, weight: 42, reps: 8, duration: nil,
                               performedAt: Date(), planId: plan.id)
        let store = DataStore(exercises: [specialist, unused], plans: [plan], sets: [record], settings: settings)
        XCTAssertEqual(Set(store.userLibrary.map(\.id)), [specialist.id, unused.id, custom.id])
        XCTAssertEqual(Set(store.curatedExerciseLibrary.map(\.id)), [specialist.id, custom.id])
        XCTAssertEqual(store.recentExerciseIDs, [specialist.id])
        XCTAssertEqual(store.plans, [plan])
        XCTAssertEqual(store.sets, [record])
        let automatic = store.suggestedTrainingExercises(targetMuscles: [.chest])
        XCTAssertFalse(automatic.contains { $0.id == specialist.id || $0.id == custom.id })
    }

    func testReplacementRetainsCompletedVariantAndRestPositionButClearsFutureLoad() throws {
        let old = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        let replacement = try XCTUnwrap(ExerciseLibrary.byId["bench_press_dumbbell"])
        let step = PlanStep(id: "replace-step", exerciseId: old.id, sets: 3, reps: 10,
                            weight: 60, setWeights: [60, 65, 70])
        let plan = Plan(id: "replacement-qa", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        defer { store.end() }
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        store.advance() // First rest.
        store.advance { records.append($0) }
        let before = try XCTUnwrap(store.session)
        XCTAssertEqual(store.currentSegment?.isRest, true)
        store.replaceStepExercise(step.id, newExerciseId: replacement.id, exById: ExerciseLibrary.byId,
                                  defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertNil(store.plan?.steps.first?.weight)
        XCTAssertNil(store.plan?.steps.first?.setWeights)
        XCTAssertEqual(store.session?.segmentIndex, before.segmentIndex)
        XCTAssertEqual(store.session?.endsAt, before.endsAt)
        XCTAssertEqual(store.session?.completedSets, before.completedSets)
        let variants = store.segments.compactMap { segment -> String? in
            if case .exercise(let exercise, _, _, _, _, _, _) = segment.kind { return exercise.id }
            return nil
        }
        XCTAssertEqual(variants, [old.id, old.id, replacement.id])
        XCTAssertEqual(records.map(\.exerciseId), [old.id, old.id])
        XCTAssertEqual(records.map(\.weight), [60, 65])

        // A later parameter edit re-expands the timeline without relabeling completed sets.
        store.updateStep(step.id, sets: 3, reps: 12, weight: 20, duration: nil,
                         exById: ExerciseLibrary.byId, defaultRest: 90, defaultBetweenExerciseRest: 120)
        let first = try XCTUnwrap(store.segments.first)
        if case .exercise(let exercise, _, _, _, let weight, _, _) = first.kind {
            XCTAssertEqual(exercise.id, old.id)
            XCTAssertEqual(weight, 60)
        } else { XCTFail("Expected completed exercise") }
        let session = try XCTUnwrap(store.session)
        let decoded = try JSONDecoder().decode(TrainingSessionStore.Session.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.completedExerciseSnapshots?.map { $0.exercise.id }, [old.id, old.id])
        var removedID: String?
        XCTAssertTrue(store.undoLastCompletedSet { exerciseID, _, _ in removedID = exerciseID })
        XCTAssertEqual(removedID, old.id)
    }
}

@MainActor
final class WorkoutSignalsTests: XCTestCase {
    func testHeartAutomaticDetectorRequiresContinuousRiseAndRecovery() {
        var settings = UserSettings()
        settings.workoutHeartRateAssistEnabled = true
        XCTAssertNotEqual(settings.workoutHeartRateAutomaticEnabled, true, "The older suggestion opt-in must not enable automatic actions")
        let start = Date()
        func sample(_ second: Double, _ bpm: Double) -> WorkoutHeartSample {
            .init(id: "\(second)", sessionID: "test", date: start.addingTimeInterval(second), bpm: bpm, source: "test")
        }
        var exercise = WorkoutHeartAutomaticDetector()
        for (seconds, bpm) in [(0.0, 130.0), (8, 124), (16, 116)] {
            XCTAssertFalse(exercise.observe(sample(seconds, bpm), phase: .exercise, now: start.addingTimeInterval(seconds)))
        }
        var detector = WorkoutHeartAutomaticDetector()
        for (seconds, bpm) in [(0.0, 116.0), (8, 124), (16, 130), (24, 124)] {
            XCTAssertFalse(detector.observe(sample(seconds, bpm), phase: .exercise, now: start.addingTimeInterval(seconds)))
        }
        XCTAssertTrue(detector.observe(sample(32, 116), phase: .exercise, now: start.addingTimeInterval(32)))
        XCTAssertFalse(detector.observe(sample(40, 110), phase: .exercise, now: start.addingTimeInterval(40)))
        var rest = WorkoutHeartAutomaticDetector()
        XCTAssertFalse(rest.observe(sample(0, 116), phase: .rest, now: start))
        XCTAssertFalse(rest.observe(sample(8, 124), phase: .rest, now: start.addingTimeInterval(8)))
        XCTAssertFalse(rest.observe(sample(8, 130), phase: .rest, now: start.addingTimeInterval(8)))
        XCTAssertTrue(rest.observe(sample(16, 130), phase: .rest, now: start.addingTimeInterval(16)))
        var gap = WorkoutHeartAutomaticDetector()
        XCTAssertFalse(gap.observe(sample(0, 116), phase: .rest, now: start))
        XCTAssertFalse(gap.observe(sample(25, 124), phase: .rest, now: start.addingTimeInterval(25)))
        XCTAssertFalse(gap.observe(sample(33, 130), phase: .rest, now: start.addingTimeInterval(33)))
        XCTAssertFalse(gap.observe(sample(40, 140), phase: .rest, now: start.addingTimeInterval(70)))
    }

    func testWatchLaunchRequiresOptedInSessionAndDoesNotRepeatOnLimitRefresh() async {
        let monitor = WorkoutHeartRateMonitor()
        defer { monitor.stop() }
        WatchSyncManager.shared.resetForNewWorkout()
        var launches = 0
        let launch: () async throws -> Void = { launches += 1 }
        let now = Date()
        monitor.bind(sessionID: "watch-launch-a", start: now, enabled: false, limit: nil)
        await monitor.startWatchWorkoutIfNeeded(launch: launch)
        XCTAssertEqual(launches, 0)
        monitor.bind(sessionID: "watch-launch-a", start: now, enabled: true, limit: nil)
        await monitor.startWatchWorkoutIfNeeded(launch: launch)
        monitor.bind(sessionID: "watch-launch-a", start: now, enabled: true, limit: 180)
        await monitor.startWatchWorkoutIfNeeded(launch: launch)
        XCTAssertEqual(launches, 1)
        monitor.bind(sessionID: "watch-launch-b", start: now, enabled: true, limit: nil)
        await monitor.startWatchWorkoutIfNeeded(launch: launch)
        XCTAssertEqual(launches, 2)
        monitor.stop()
        await monitor.startWatchWorkoutIfNeeded(launch: launch)
        XCTAssertEqual(launches, 2)
    }

    private func fixture(clock: @escaping () -> Date) throws -> (TrainingSessionStore, Plan, DataStore) {
        let data = DataStore.makeMock()
        let exercises = ["bench_press_barbell", "squat_barbell"]
        for id in exercises { _ = try XCTUnwrap(data.exById[id]) }
        let plan = Plan(id: "signals-\(UUID().uuidString)", name: "Signals", steps: exercises.enumerated().map {
            PlanStep(id: "step-\($0.offset)", exerciseId: $0.element, sets: $0.offset == 0 ? 3 : 2, reps: 8, weight: 40)
        }, createdAt: clock(), updatedAt: clock())
        let store = TrainingSessionStore(completionSound: {}, clock: clock)
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120))
        return (store, plan, data)
    }

    func testTrackedTimeExcludesPauseAndPreservesLoggedTargets() throws {
        var now = Date()
        let (store, _, _) = try fixture(clock: { now })
        now.addTimeInterval(10); store.togglePlay()
        now.addTimeInterval(5); store.togglePlay()
        now.addTimeInterval(8)
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.activeSeconds ?? -1, 18, accuracy: 0.01)
        XCTAssertEqual(record.activeIntervals?.count, 2)
        XCTAssertNil(record.duration, "Actual App time must not overwrite planned hold duration")
        XCTAssertEqual(record.weight, 40)
        XCTAssertEqual(record.reps, 8)
        XCTAssertEqual(record.setNumber, 1)
        XCTAssertEqual(record.stepID, "step-0")
        XCTAssertEqual(record.workoutSessionID, store.workoutSessionID)
    }

    func testTimingAccumulatesOnlyVisitsToTheSameConcreteSet() throws {
        var now = Date()
        let (store, _, _) = try fixture(clock: { now })
        now.addTimeInterval(10); XCTAssertTrue(store.jumpToFirstUnfinishedStep(stepId: "step-1"))
        now.addTimeInterval(10); XCTAssertTrue(store.jumpToFirstUnfinishedStep(stepId: "step-0"))
        now.addTimeInterval(5)
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        XCTAssertEqual(records.first?.activeSeconds ?? -1, 15, accuracy: 0.01)
        XCTAssertEqual(records.first?.activeIntervals?.count, 2)
        XCTAssertEqual(store.session?.completedSets.count, 1, "Navigation never marks skipped sets done")
        XCTAssertTrue(store.jumpToFirstUnfinishedStep(stepId: "step-0"))
        if case .exercise(_, let number, _, _, _, _, _) = store.currentSegment?.kind { XCTAssertEqual(number, 2) }
        else { XCTFail("Expected the earliest unfinished set") }
    }

    func testRestPreferencesAlsoApplyIfRestEndedWhileEditing() throws {
        var now = Date()
        let (store, _, _) = try fixture(clock: { now })
        defer { store.end() }
        now.addTimeInterval(10); store.advance { _ in }; store.advance()
        let current = try XCTUnwrap(store.currentSegment)
        XCTAssertTrue(current.isExercise)
        let endsAt = store.session?.endsAt
        store.applyRestPreferences(setRest: 150, switchingRest: 45, exById: ExerciseLibrary.byId, now: now)
        XCTAssertEqual(store.currentSegment, current)
        XCTAssertEqual(store.session?.endsAt, endsAt)
        XCTAssertEqual(store.session?.completedSets.count, 1)
        let future = store.segments.dropFirst(try XCTUnwrap(store.session).segmentIndex + 1)
        XCTAssertTrue(future.contains { $0.kind == .rest(duration: 150) })
        XCTAssertTrue(future.contains { $0.kind == .rest(duration: 45) })
    }

    func testConfirmedRestPreferencesPreserveCurrentProgressAndReplaceFutureRest() throws {
        var now = Date()
        let (store, _, _) = try fixture(clock: { now })
        defer { store.end() }
        now.addTimeInterval(10); store.advance { _ in }
        store.togglePlay()
        let remaining = try XCTUnwrap(store.session?.pausedRemaining)
        let records = store.session?.recordedSetIDs
        store.applyRestPreferences(setRest: 120, switchingRest: 0, exById: ExerciseLibrary.byId, now: now)
        XCTAssertEqual(store.session?.pausedRemaining ?? -1, remaining + 30, accuracy: 0.1)
        XCTAssertEqual(store.session?.playing, false)
        XCTAssertEqual(store.session?.recordedSetIDs, records)
        XCTAssertEqual(store.session?.completedSets.count, 1)
        XCTAssertEqual(Set(store.segments.map(\.id)).count, store.segments.count)
        let future = store.segments.dropFirst(try XCTUnwrap(store.session).segmentIndex + 1)
        for segment in future where segment.isRest {
            if case .rest(let duration) = segment.kind { XCTAssertEqual(duration, 120) }
            let next = future.drop(while: { $0.id != segment.id }).dropFirst().first
            XCTAssertEqual(next?.stepId, segment.stepId, "Zero switching rest must remove future cross-exercise breaks")
        }
    }

    func testRestEditPreservesElapsedTimePauseAndRecordOwnership() throws {
        var now = Date()
        let (store, _, _) = try fixture(clock: { now })
        now.addTimeInterval(10); store.advance { _ in }
        XCTAssertTrue(store.currentSegment?.isRest == true)
        store.togglePlay()
        let oldRemaining = try XCTUnwrap(store.session?.pausedRemaining)
        let recorded = store.session?.recordedSetIDs
        store.updateCurrentRest(seconds: 180)
        XCTAssertEqual(store.session?.pausedRemaining ?? -1, oldRemaining + 90, accuracy: 0.1)
        XCTAssertEqual(store.session?.playing, false)
        XCTAssertNil(store.session?.endsAt)
        XCTAssertEqual(store.session?.recordedSetIDs, recorded)
        XCTAssertEqual(store.session?.completedSets.count, 1)
        XCTAssertEqual(store.session?.currentRestDurationOverride, 180)
        let restored = try JSONDecoder().decode(TrainingSessionStore.Session.self, from: JSONEncoder().encode(try XCTUnwrap(store.session)))
        XCTAssertEqual(restored.currentRestDurationOverride, 180)
        XCTAssertEqual(restored.setTimings?.count, store.session?.setTimings?.count)
    }

    func testUndoDoesNotDuplicateOldTimingWhenTheSetIsDoneAgain() throws {
        var now = Date()
        let (store, _, _) = try fixture(clock: { now })
        var records: [SetRecord] = []
        now.addTimeInterval(10); store.advance { records.append($0) }
        XCTAssertTrue(store.undoPlayback { id in records.removeAll { $0.id == id } })
        XCTAssertTrue(records.isEmpty)
        now.addTimeInterval(7); store.advance { records.append($0) }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.activeSeconds ?? -1, 7, accuracy: 0.01)
    }

    func testOldRecordsKeepUnknownTimingAndSettingsDecode() throws {
        let record = SetRecord(id: "legacy", exerciseId: "plank", exerciseName: "Plank", category: .strength, performedAt: Date())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        for key in ["workoutSessionID", "stepID", "setNumber", "activeIntervals", "restBeforeSeconds"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(SetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.activeSeconds)
        XCTAssertNil(WorkoutTimelineReport(records: [decoded]).activeSeconds)
        XCTAssertNil(WorkoutTimelineReport(records: [decoded]).restSeconds)
        XCTAssertTrue(WorkoutHeartLocalStore.shared.samples(for: decoded).isEmpty)
        var settings = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UserSettings())) as? [String: Any])
        settings.removeValue(forKey: "workoutHeartRateEnabled"); settings.removeValue(forKey: "workoutHeartRateLimit")
        let old = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: settings))
        XCTAssertNil(old.workoutHeartRateEnabled); XCTAssertNil(old.workoutHeartRateLimit)
    }

    func testReportGroupsConsecutiveExercisesAndKeepsMissingTimeUnknown() {
        let now = Date()
        func record(_ id: String, _ exercise: String, _ step: String, _ seconds: Double?, _ at: TimeInterval) -> SetRecord {
            var result = SetRecord(id: id, exerciseId: exercise, exerciseName: exercise, category: .strength, performedAt: now.addingTimeInterval(at))
            result.workoutSessionID = "session"; result.stepID = step
            if let seconds { result.activeIntervals = [.init(start: now.addingTimeInterval(at - seconds), end: now.addingTimeInterval(at))] }
            return result
        }
        let blocks = WorkoutReportExerciseBlock.group([
            record("1", "press", "a", 20, 30), record("2", "press", "a", nil, 60),
            record("3", "row", "b", 25, 90), record("4", "press", "c", 10, 120)
        ])
        XCTAssertEqual(blocks.map(\.exerciseId), ["press", "row", "press"])
        XCTAssertEqual(blocks[0].records.count, 2)
        XCTAssertEqual(blocks[0].trackedSeconds, 20)
        XCTAssertTrue(blocks[0].hasMissingTiming)
        XCTAssertFalse(blocks[1].hasMissingTiming)
        let totals = WorkoutReportExerciseBlock.totalsByExercise(blocks.flatMap(\.records))
        XCTAssertEqual(totals.map(\.exerciseId), ["press", "row"])
        XCTAssertEqual(totals[0].trackedSeconds, 30)
        XCTAssertEqual(totals[0].records.count, 3)
        XCTAssertTrue(totals[0].hasMissingTiming)
    }

    func testReportCountsSustainedHeartEventsWithoutCountingEachSample() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func sample(_ second: Double, _ bpm: Double, _ limit: Int?) -> WorkoutHeartSample {
            var value = WorkoutHeartSample(id: "\(second)", sessionID: "one", date: start.addingTimeInterval(second), bpm: bpm, source: "test")
            value.reminderLimit = limit
            return value
        }
        let values = [sample(0, 160, 150), sample(8, 162, 150), sample(16, 165, 150),
                      sample(24, 170, 150), sample(30, 140, 150),
                      sample(40, 160, 150), sample(48, 161, 150), sample(56, 163, 150),
                      sample(64, 180, nil), sample(80, 180, 150)]
        let events = WorkoutHeartExceedanceDetector.events(in: values)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.peak), [170, 163])
        XCTAssertTrue(WorkoutHeartExceedanceDetector.events(in: [sample(0, 170, nil), sample(8, 170, nil), sample(16, 170, nil)]).isEmpty)
    }

    func testHeartRecommendationUsesPriorSessionsAndPreservesManualChoice() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var samples: [WorkoutHeartSample] = []
        for session in 0..<3 {
            for index in 0..<12 {
                let date = now.addingTimeInterval(-1000.0 - Double(index) * 10.0)
                let bpm = Double(130 + session * 5 + index)
                samples.append(WorkoutHeartSample(id: "\(session)-\(index)", sessionID: "s\(session)", date: date, bpm: bpm, source: "test"))
            }
        }
        XCTAssertEqual(WorkoutHeartRecommendation.calculate(samples: [], age: nil, excluding: nil, now: now).bpm, 150)
        XCTAssertEqual(WorkoutHeartRecommendation.calculate(samples: [], age: 40, excluding: nil, now: now).bpm, 153)
        let recommendation = WorkoutHeartRecommendation.calculate(samples: samples, age: 40, excluding: nil, now: now)
        XCTAssertEqual(recommendation.bpm, 144)
        XCTAssertEqual(recommendation.basis, WorkoutHeartRecommendation.Basis.history)
        XCTAssertEqual(WorkoutHeartRecommendation.calculate(samples: samples, age: 40, excluding: "s0", now: now).basis, WorkoutHeartRecommendation.Basis.age)
        var settings = UserSettings()
        settings.workoutHeartRateLimit = 175
        XCTAssertFalse(WorkoutHeartRecommendation.usesRecommendation(settings))
        XCTAssertEqual(WorkoutHeartRecommendation.effective(settings: settings, samples: samples, excluding: nil), 175)
        settings.workoutHeartRateUseRecommendation = true
        XCTAssertTrue(WorkoutHeartRecommendation.usesRecommendation(settings))
        XCTAssertNotEqual(WorkoutHeartRecommendation.effective(settings: settings, samples: samples, excluding: nil), 175)
    }

    func testHeartRippleUsesFreshHeartRateAndPersonalLimit() {
        XCTAssertEqual(WorkoutHeartLiquid.progress(bpm: 90, limit: 150), 0)
        XCTAssertEqual(WorkoutHeartLiquid.progress(bpm: 150, limit: 150), 1)
        XCTAssertNil(WorkoutHeartLiquid.progress(bpm: nil, limit: 150))
        XCTAssertNil(WorkoutHeartLiquid.progress(bpm: 150, limit: nil))
    }

    func testHeartVisualEscalationRequiresSustainedHighReadingsAndStableRecovery() {
        let start = Date()
        var policy = WorkoutHeartVisualEscalation()
        func observe(_ second: Double, _ bpm: Double, _ limit: Int? = 150) {
            let date = start.addingTimeInterval(second)
            policy.observe(bpm: bpm, date: date, limit: limit, now: date)
        }
        observe(0, 160); observe(8, 160); observe(16, 160)
        XCTAssertFalse(policy.isEscalated, "A normal above-limit reminder must not tint the screen")
        observe(24, 173); observe(32, 173)
        XCTAssertFalse(policy.isEscalated)
        observe(40, 173)
        XCTAssertTrue(policy.isEscalated)
        observe(48, 160); observe(56, 165)
        XCTAssertTrue(policy.isEscalated, "A short dip must not flicker the screen")
        observe(64, 160); observe(72, 160); observe(80, 160)
        XCTAssertFalse(policy.isEscalated)
        observe(88, 180); observe(96, 180); observe(104, 180)
        XCTAssertTrue(policy.isEscalated)
        observe(130, 180)
        XCTAssertFalse(policy.isEscalated, "A sampling gap requires fresh confirmation")
        observe(138, 180); observe(146, 180)
        XCTAssertTrue(policy.isEscalated)
        observe(154, 180, 170)
        XCTAssertFalse(policy.isEscalated, "Changing the personal limit resets escalation")
        var stale = WorkoutHeartVisualEscalation()
        for second in [0.0, 8, 16] {
            let date = start.addingTimeInterval(second)
            stale.observe(bpm: 180, date: date, limit: 150, now: date.addingTimeInterval(30))
        }
        XCTAssertFalse(stale.isEscalated)
    }

    func testHeartWarningRecoveryRequiresFreshSustainedReadings() {
        let now = Date()
        var recovery = WorkoutHeartWarningRecovery()
        XCTAssertFalse(recovery.observe(bpm: 100, date: now, limit: 150, now: now))
        XCTAssertFalse(recovery.observe(bpm: 100, date: now, limit: 150, now: now))
        XCTAssertFalse(recovery.observe(bpm: 110, date: now.addingTimeInterval(8), limit: 150, now: now.addingTimeInterval(8)))
        XCTAssertFalse(recovery.observe(bpm: 100, date: now.addingTimeInterval(16), limit: 150, now: now.addingTimeInterval(16)))
        XCTAssertFalse(recovery.observe(bpm: 100, date: now.addingTimeInterval(24), limit: 150, now: now.addingTimeInterval(24)))
        XCTAssertTrue(recovery.observe(bpm: 100, date: now.addingTimeInterval(32), limit: 150, now: now.addingTimeInterval(32)))
        var stale = WorkoutHeartWarningRecovery()
        XCTAssertFalse(stale.observe(bpm: 100, date: now, limit: 150, now: now.addingTimeInterval(30)))
    }

    func testPersonalHeartReminderNeedsSustainedFreshDistinctSamplesAndCooldown() {
        let start = Date()
        var policy = WorkoutHeartAlertPolicy()
        func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        XCTAssertFalse(policy.observe(bpm: 190, date: date(0), limit: 180, now: date(0)))
        XCTAssertFalse(policy.observe(bpm: 190, date: date(8), limit: 180, now: date(8)))
        XCTAssertFalse(policy.observe(bpm: 190, date: date(8), limit: 180, now: date(8)), "A duplicated sample cannot advance persistence")
        XCTAssertTrue(policy.observe(bpm: 190, date: date(16), limit: 180, now: date(16)))
        XCTAssertFalse(policy.observe(bpm: 195, date: date(24), limit: 180, now: date(24)))
        XCTAssertFalse(policy.observe(bpm: 250, date: date(32), limit: 180, now: date(90)), "Stale samples must not alert")
        XCTAssertFalse(policy.observe(bpm: .nan, date: date(40), limit: 180, now: date(40)))
        XCTAssertFalse(policy.observe(bpm: 190, date: date(200), limit: nil, now: date(200)))
        XCTAssertFalse(policy.observe(bpm: 190, date: date(208), limit: 200, now: date(208)))
    }

    func testMissingSensorGapsAndThresholdChangesCannotCreateAWarning() {
        let start = Date()
        var policy = WorkoutHeartAlertPolicy()
        for second in [0.0, 20, 40, 60] {
            let date = start.addingTimeInterval(second)
            XCTAssertFalse(policy.observe(bpm: 190, date: date, limit: 180, now: date))
        }
        XCTAssertFalse(policy.observe(bpm: 190, date: start.addingTimeInterval(65), limit: 180, now: start.addingTimeInterval(65)))
        XCTAssertFalse(policy.observe(bpm: 230, date: start.addingTimeInterval(70), limit: 220, now: start.addingTimeInterval(70)))
        XCTAssertFalse(policy.observe(bpm: 230, date: start.addingTimeInterval(75), limit: 220, now: start.addingTimeInterval(75)))
        XCTAssertTrue(policy.observe(bpm: 230, date: start.addingTimeInterval(85), limit: 220, now: start.addingTimeInterval(85)))
    }

    func testHeartSamplesUseExactSetIntervalsAndAuthoritativeDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("heart.json")
        let cache = WorkoutHeartLocalStore(url: url)
        let start = Date()
        let sampleTime = start.addingTimeInterval(10)
        cache.append(.init(id: "watch|sample", sessionID: "session", date: sampleTime, bpm: 170, source: "Apple Watch"))
        cache.append(.init(id: "health-uuid", sessionID: "session", date: sampleTime, bpm: 170, source: "Health"))
        XCTAssertEqual(cache.samples.count, 1)
        XCTAssertEqual(cache.samples.first?.id, "health-uuid")
        var first = SetRecord(id: "one", exerciseId: "plank", exerciseName: "Plank", category: .strength, performedAt: start.addingTimeInterval(10))
        first.workoutSessionID = "session"; first.activeIntervals = [.init(start: start, end: sampleTime)]
        var second = first; second.activeIntervals = [.init(start: sampleTime, end: start.addingTimeInterval(20))]
        XCTAssertTrue(cache.samples(for: first).isEmpty)
        XCTAssertEqual(cache.samples(for: second).count, 1)
        cache.flush()
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(WorkoutHeartLocalStore(url: url).samples.count, 1)
        let publicRecord = String(decoding: try JSONEncoder().encode(second), as: UTF8.self)
        XCTAssertFalse(publicRecord.contains("bpm")); XCTAssertFalse(publicRecord.contains("health-uuid"))
        cache.remove(ids: ["health-uuid"])
        XCTAssertTrue(cache.samples.isEmpty)
    }

    func testObservedRestAndRepDropExplainTheRecoveryAdviceWithoutHealthPayload() throws {
        let data = DataStore.makeMock()
        let start = Date().addingTimeInterval(-1200)
        let key = UUID().uuidString
        data.sets = [10, 8, 6].enumerated().map { index, reps in
            var record = SetRecord(id: "evidence-\(index)", exerciseId: "bench_press_barbell", exerciseName: "Bench Press", category: .strength,
                                   weight: 40, reps: reps, performedAt: start.addingTimeInterval(Double(index * 60)), planId: "evidence")
            record.workoutSessionID = key
            record.activeIntervals = [.init(start: record.performedAt.addingTimeInterval(-20), end: record.performedAt)]
            record.restBeforeSeconds = 20
            return record
        }
        let advice = try XCTUnwrap(data.routineSuggestion())
        XCTAssertEqual(advice.reportRecordIDs?.count, 3)
        XCTAssertTrue(advice.focusNote.contains("tracked active seconds 60"))
        XCTAssertFalse(advice.focusNote.contains("bpm"))
        XCTAssertFalse(data.summaryMinDataMet, "Immediate pacing advice must not bypass the weekly AI summary data requirement")
    }
}

@MainActor
final class WorkoutSignalsPrivacyTests: XCTestCase {
    func testUnreadableExistingHealthCacheIsNotSilentlyOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("heart.json")
        let original = Data("unreadable protected-cache fixture".utf8)
        try original.write(to: url)
        let cache = WorkoutHeartLocalStore(url: url)
        cache.append(.init(id: "new", sessionID: "test", date: Date(), bpm: 170, source: "Test"))
        XCTAssertFalse(cache.flush())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(cache.clear(), "Explicit deletion may replace corrupt data")
        XCTAssertTrue(WorkoutHeartLocalStore(url: url).samples.isEmpty)
    }

    func testHealthBasedLocalAdviceDoesNotLeakIntoPayloadOrSummaryCache() throws {
        let data = DataStore.makeMock()
        let key = UUID().uuidString
        let start = Date().addingTimeInterval(-1200)
        data.sets = (0..<3).map { index in
            var record = SetRecord(id: UUID().uuidString, exerciseId: "bench_press_barbell", exerciseName: "Bench", category: .strength,
                                   weight: 40, reps: 8, performedAt: start.addingTimeInterval(Double(index * 60 + 30)), planId: "privacy")
            record.workoutSessionID = key
            record.activeIntervals = [.init(start: start.addingTimeInterval(Double(index * 60)), end: record.performedAt)]
            return record
        }
        for second in [0.0, 8, 16] {
            WorkoutHeartLocalStore.shared.append(.init(id: UUID().uuidString, sessionID: key,
                date: start.addingTimeInterval(second), bpm: 193, source: "Private sensor", reminderLimit: 180))
        }
        defer { WorkoutHeartLocalStore.shared.removeSessions([key]) }
        let advice = try XCTUnwrap(data.routineSuggestion())
        XCTAssertTrue(advice.containsHealthEvidence)
        let payload = String(decoding: try JSONEncoder().encode(data.buildSummaryPayload()), as: UTF8.self)
        XCTAssertFalse(payload.contains("193")); XCTAssertFalse(payload.contains("Private sensor"))
        XCTAssertFalse(payload.contains("readings stayed above"))
        XCTAssertFalse(data.localSummaryFallback().tldr.contains("readings stayed above"))
        XCTAssertFalse(advice.focusNote.contains("bpm"))
    }
}

@MainActor
final class CatalogIdentityAuditTests: XCTestCase {
    func testRetiredAliasesResolveThroughBothAppLookupsAndNoDuplicateEnglishNames() throws {
        let aliases = ["jackknife": "v_up", "sit_up_v": "v_up", "child_pose": "childs_pose",
            "cable_pullover_straight_arm": "straight_arm_pulldown", "landmine_row": "t_bar_row",
            "bicep_curl_machine_seated": "bicep_curl_machine", "lat_pulldown_v_bar": "lat_pulldown_close_grip"]
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
        for (old, new) in aliases {
            XCTAssertFalse(ExerciseLibrary.all.contains { $0.id == old })
            XCTAssertEqual(ExerciseLibrary.byId[old]?.id, new)
            XCTAssertEqual(store.exById[old]?.id, new)
        }
        XCTAssertEqual(Set(ExerciseLibrary.all.map(\.name)).count, ExerciseLibrary.all.count)
        XCTAssertEqual(ExerciseLibrary.all.count, 917)
    }

    func testAliasNormalizationPreservesEverySetStepAndHistoricalSignal() throws {
        var first = PlanStep(id: "one", exerciseId: "jackknife", sets: 3, reps: 10, weight: 5)
        first.setWeights = [5, 6, 7]; first.setReps = [10, 9, 8]; first.rest = 45
        let second = PlanStep(id: "two", exerciseId: "sit_up_v", sets: 2, reps: 12, weight: 4)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = Plan(id: "identity", name: "Existing", steps: [first, second], createdAt: date, updatedAt: date)
        var record = SetRecord(id: "record", exerciseId: "jackknife", exerciseName: "Historical name", category: .calisthenics,
                               weight: 5, reps: 10, duration: 30, performedAt: date, planId: plan.id)
        record.workoutSessionID = "private-session"; record.stepID = first.id; record.setNumber = 2
        record.activeIntervals = [.init(start: date, end: date.addingTimeInterval(24))]
        record.restBeforeSeconds = 60
        var settings = UserSettings(); settings.favoriteExerciseIds = ["jackknife", "v_up", "sit_up_v"]
        settings.adoptedNicheExerciseIds = ["sit_up_v"]
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [plan], sets: [record], settings: settings)
        var expectedPlan = plan; expectedPlan.steps[0].exerciseId = "v_up"; expectedPlan.steps[1].exerciseId = "v_up"
        var expectedRecord = record; expectedRecord.exerciseId = "v_up"
        XCTAssertEqual(store.plans, [expectedPlan], "Do not delete or combine planned set blocks")
        XCTAssertEqual(store.sets, [expectedRecord], "Do not rewrite historical name, load or sensor linkage")
        XCTAssertEqual(store.settings.favoriteExerciseIds, ["v_up"])
        XCTAssertEqual(store.settings.adoptedNicheExerciseIds, ["v_up"])
        XCTAssertEqual(store.lastSet(forExerciseId: "v_up")?.id, record.id)
        let migratedAgain = DataStore(exercises: ExerciseLibrary.all, plans: store.plans, sets: store.sets, settings: store.settings)
        XCTAssertEqual(migratedAgain.plans, store.plans); XCTAssertEqual(migratedAgain.sets, store.sets)
    }

    func testRealCustomIDsWinAndUnknownReferencesAreNotDropped() throws {
        let custom = Exercise(id: "jackknife", name: "My own move", category: .strength, tags: [],
                              primaryMuscles: [.upperAbs], muscleGroups: [.upperAbs], imageFolder: nil, instructions: [])
        var settings = UserSettings(); settings.customExercises = [custom]; settings.favoriteExerciseIds = [custom.id]
        let plan = Plan(id: "custom-identity", name: "Custom", steps: [PlanStep(id: "custom", exerciseId: custom.id),
            PlanStep(id: "unknown", exerciseId: "future-custom-id"),
            PlanStep(id: "legacy-folder", exerciseId: "Barbell_Bench_Press_-_Medium_Grip")], createdAt: Date(), updatedAt: Date())
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [plan], sets: [], settings: settings)
        XCTAssertEqual(store.plans, [plan]); XCTAssertEqual(store.exById[custom.id]?.name, custom.name)
        XCTAssertEqual(store.settings.favoriteExerciseIds, [custom.id])
    }

    func testDifferentAttachmentsAnglesAndSupportVariantsSurvive() throws {
        let ids = ["military_press", "overhead_press_barbell", "anti_rotation_press_cable", "pallof_press_cable",
                   "landmine_press_kneeling", "landmine_press_half_kneeling", "rdl_single_leg_dumbbell", "single_leg_rdl",
                   "triceps_pushdown_rope", "triceps_pushdown_straight_bar", "triceps_pushdown_v_bar"]
        for id in ids { XCTAssertNotNil(ExerciseLibrary.byId[id], id) }
        let values = try ids.map { try XCTUnwrap(ExerciseLibrary.byId[$0]).name }
        XCTAssertEqual(Set(values).count, ids.count)
        XCTAssertTrue(try XCTUnwrap(ExerciseLibrary.byId["landmine_press_kneeling"]).name.contains("Tall-Kneeling"))
    }

    func testAllLocalizedNamesAreDistinctAndRequiredLoadsAppearInParentheses() throws {
        let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]
        for language in languages {
            let names = try ExerciseLibrary.all.map { try XCTUnwrap($0.localizedName?[language]) }
            XCTAssertEqual(Set(names.map { $0.lowercased() }).count, names.count, language)
        }
        for exercise in ExerciseLibrary.all {
            let eq = exercise.equipmentAll ?? []
            if eq.contains("barbell") { XCTAssertTrue(exercise.name.split(separator: "(").dropFirst().joined().contains("Barbell"), exercise.id) }
            if eq.contains("dumbbell") { XCTAssertTrue(exercise.name.split(separator: "(").dropFirst().joined().contains("Dumbbell"), exercise.id) }
        }
        XCTAssertEqual(ExerciseLibrary.byId["v_up"]?.name, "V-Up")
        XCTAssertFalse(ExerciseLibrary.byId["push_up"]?.name.contains("Bodyweight") ?? true)
    }

    func testMatchingMediaWinsWithoutChangingAdoptedVideos() throws {
        XCTAssertEqual(ExerciseMediaPolicy.legacyOwners["Jackknife_Sit-Up"], "v_up")
        XCTAssertEqual(ExerciseMediaPolicy.legacyOwners["Hyperextensions_Back_Extensions"], "back_extension_45_degree")
        XCTAssertEqual(ExerciseMediaPolicy.legacyOwners["Straight-Arm_Pulldown"], "straight_arm_pulldown")
        XCTAssertEqual(ExerciseMediaPolicy.legacyOwners["Bent_Over_Two-Arm_Long_Bar_Row"], "t_bar_row")
        XCTAssertNil(ExerciseMediaPolicy.legacyOwners["Machine_Bicep_Curl"], "Mislabeled source depicts a shoulder press")
        XCTAssertNil(ExerciseMediaPolicy.legacyOwners["Barbell_Seated_Calf_Raise"], "Barbell footage must not illustrate a machine exercise")
        XCTAssertNil(ExerciseLibrary.byId["bicep_curl_machine"]?.imageFolder)
    }
}

extension CatalogIdentityAuditTests {
    func testSnapshotImportAndReplayPreserveLoadsWhenOnlyAnAliasChanges() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let old = Plan(id: "qw-old-alias", name: "Old", steps: [PlanStep(id: "exact-step", exerciseId: "jackknife", sets: 2, reps: 10, weight: 5)], createdAt: date, updatedAt: date)
        let set = SetRecord(id: "exact-record", exerciseId: "sit_up_v", exerciseName: "Old snapshot name", category: .calisthenics, weight: 5, reps: 10, performedAt: date)
        var settings = UserSettings(); settings.favoriteExerciseIds = ["jackknife", "sit_up_v"]
        let snapshot = PersistenceController.Snapshot(version: PersistenceController.schemaVersion, plans: [old], sets: [set], settings: settings, aiTodayPlan: old, updatedAt: date)
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
        store.replaceFromSnapshot(snapshot)
        XCTAssertEqual(store.plans.first?.steps.first?.exerciseId, "v_up")
        XCTAssertEqual(store.aiTodayPlan?.steps.first?.exerciseId, "v_up")
        XCTAssertEqual(store.sets.first?.id, set.id); XCTAssertEqual(store.sets.first?.exerciseName, set.exerciseName)
        XCTAssertEqual(store.settings.favoriteExerciseIds, ["v_up"])
        let replay = store.routinePlanDefaults(old)
        XCTAssertEqual(replay.steps.first?.exerciseId, "v_up"); XCTAssertEqual(replay.steps.first?.weight, 5)
        XCTAssertEqual(replay.steps.first?.id, "exact-step")
    }

    func testRestoringAnActiveOldIDKeepsSegmentAndSetIdentity() throws {
        let plan = Plan(id: "restore-identity", name: "Old active workout", steps: [PlanStep(id: "same-step", exerciseId: "jackknife", sets: 2, reps: 10, weight: 5)], createdAt: Date(), updatedAt: Date())
        let player = TrainingSessionStore(completionSound: {})
        player.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        let session = try XCTUnwrap(player.session)
        player.end()
        SessionPersistence.save(.init(session: session, plan: plan, planParamsDirty: false))
        let restored = TrainingSessionStore(completionSound: {})
        defer { restored.end() }
        restored.restorePersistedSession(exById: ExerciseLibrary.byId, defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(restored.session?.segmentIndex, session.segmentIndex)
        XCTAssertEqual(restored.plan?.steps.first?.id, "same-step")
        XCTAssertEqual(restored.plan?.steps.first?.exerciseId, "v_up")
        XCTAssertEqual(restored.plan?.steps.first?.weight, 5)
        XCTAssertEqual(restored.plan?.steps.first?.sets, 2)
        guard case .exercise(let exercise, _, _, _, _, _, _)? = restored.currentSegment?.kind else { return XCTFail("Missing restored exercise") }
        XCTAssertEqual(exercise.id, "v_up")
    }
}


private actor AnalyticsConsentProbeSink: AnalyticsSink {
    private var batches: [[AnalyticsEvent]] = []
    func send(_ batch: [AnalyticsEvent], envelope: AnalyticsEnvelope) async -> Bool {
        batches.append(batch); return true
    }
    func count() -> Int { batches.reduce(0) { $0 + $1.count } }
}

@MainActor
final class AnalyticsSharingConsentTests: XCTestCase {
    func testNoTransmissionUntilExplicitOptInAndWithdrawalStopsIt() async throws {
        let key = "masso.analyticsSharingConsent.v1"
        let previous = UserDefaults.standard.object(forKey: key)
        let analytics = Analytics.shared
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("maso-analytics.json")
        let previousFile = try? Data(contentsOf: file)
        defer {
            analytics.setSharingEnabled(previous as? Bool ?? false)
            analytics.configure(sink: NoOpSink(), context: { .init(anonymousId: "", optOut: true) })
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            if let previousFile { try? previousFile.write(to: file, options: .atomic) }
        }
        let sink = AnalyticsConsentProbeSink()
        analytics.setSharingEnabled(false)
        analytics.configure(sink: sink, context: { .init(anonymousId: "synthetic-consent-test", optOut: false) })
        analytics.track("release_privacy_probe")
        try await Task.sleep(for: .milliseconds(50))
        await analytics.flush()
        let before = await sink.count(); XCTAssertEqual(before, 0)
        XCTAssertTrue(analytics.buffer.isEmpty)
        analytics.setSharingEnabled(true)
        analytics.track("release_privacy_probe")
        try await Task.sleep(for: .milliseconds(50))
        await analytics.flush()
        let allowed = await sink.count(); XCTAssertEqual(allowed, 1)
        analytics.setSharingEnabled(false)
        analytics.track("release_privacy_probe")
        try await Task.sleep(for: .milliseconds(50))
        await analytics.flush()
        let withdrawn = await sink.count(); XCTAssertEqual(withdrawn, 1)
        XCTAssertTrue(analytics.buffer.isEmpty)
    }
}
