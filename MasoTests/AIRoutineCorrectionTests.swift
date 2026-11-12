import XCTest
@testable import Maso

@MainActor
final class AIRoutineCorrectionTests: XCTestCase {
    private var service: AIWorkoutService { .shared }
    func testPromptMatchesCurrentCatalog() throws {
        let payload = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings()).buildAIPayload()
        let prompt = service.routineContractProbe(payload: payload, count: 3, maxExercises: 4)
        XCTAssertTrue(prompt.contains("exercise_id"))
    }

    func testPromptCapacityUsesDistinctFilteredGroups() throws {
        XCTAssertEqual(service.routineStepCount(try candidates(), requested: 8), 2)
        XCTAssertEqual(service.routineStepCount([], requested: 8), 0)
    }

    func testEveryCurrentCandidateRoundTripsThroughTheActualPlanBuilder() throws {
        let payload = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings()).buildAIPayload()
        let pool = service.routineCandidates(payload: payload, library: ExerciseLibrary.all)
        for exercise in pool {
            let raw = routine([exercise.id])
            let plan = try XCTUnwrap(service.validatedPlan(fromJSON: raw, candidates: pool, maxExercises: 1), exercise.id)
            XCTAssertEqual(plan.steps.count, 1)
            XCTAssertTrue(pool.contains { $0.id == plan.steps[0].exerciseId })
            XCTAssertEqual(ExerciseSelectionPolicy.shared.programmingGroupID(for: exercise),
                ExerciseSelectionPolicy.shared.programmingGroupID(for: try XCTUnwrap(ExerciseLibrary.byId[plan.steps[0].exerciseId])))
        }
        XCTAssertNil(try service.validatedPlan(fromJSON: routine(["hanging_leg_raise"]), candidates: pool, maxExercises: 1),
                     "Real production hallucination must never be guessed into a different action")
    }

    private func candidates() throws -> [Exercise] {
        try ["bench_press_barbell", "bench_press_dumbbell", "dumbbell_row_single_arm"].map {
            try XCTUnwrap(ExerciseLibrary.byId[$0])
        }
    }
    private func routine(_ ids: [String]) -> String {
        let steps = ids.map { ["exercise_id": $0, "sets": 3, "reps": 10] as [String: Any] }
        let data = try! JSONSerialization.data(withJSONObject: ["name": "Diagnostic", "steps": steps])
        return String(data: data, encoding: .utf8)!
    }
    private func batch(_ routines: [String]) -> String { "{\"routines\":[" + routines.joined(separator: ",") + "]}" }

    func testUnknownIDGetsOneCorrectionUsingTheSameAllowedPool() async throws {
        let pool = try candidates()
        var calls = 0
        let plans = try await service.requestValidatedPlans(candidates: pool, expectedCount: 1, maxExercises: 2) { feedback in
            calls += 1
            if calls == 1 {
                XCTAssertNil(feedback)
                return self.batch([self.routine(["bench_press_barbell", "invented_exercise"])])
            }
            XCTAssertTrue(feedback?.contains("invented_exercise") == true)
            XCTAssertTrue(feedback?.contains("exactly 2") == true)
            return self.batch([self.routine(["bench_press_barbell", "dumbbell_row_single_arm"])])
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(plans.first?.steps.map(\.exerciseId), ["bench_press_barbell", "dumbbell_row_single_arm"])
        XCTAssertEqual(plans.first?.source, .ai)
    }

    func testRepeatedEquipmentVersionsRemainRejectedAfterBoundedCorrection() async throws {
        var calls = 0
        do {
            _ = try await service.requestValidatedPlans(candidates: candidates(), expectedCount: 1, maxExercises: 2) { feedback in
                calls += 1
                if calls == 2 { XCTAssertTrue(feedback?.contains("repeated_groups") == true) }
                return self.batch([self.routine(["bench_press_barbell", "bench_press_dumbbell"])])
            }
            XCTFail("Two equipment versions must not become two workout slots")
        } catch { XCTAssertEqual(calls, 2, "No third attempt or silent weakening of validation") }
    }

    func testWrongWeeklyCountIsCorrectedInsteadOfAcceptingAnIncompleteWeek() async throws {
        var calls = 0
        let valid = routine(["bench_press_barbell", "dumbbell_row_single_arm"])
        let plans = try await service.requestValidatedPlans(candidates: candidates(), expectedCount: 3, maxExercises: 2) { feedback in
            calls += 1
            if calls == 1 { return self.batch([valid]) }
            XCTAssertTrue(feedback?.contains("exactly 3") == true)
            return self.batch([valid, valid, valid])
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(plans.count, 3)
    }

    func testMalformedJSONCanBeCorrectedAndValidSingleResponseDoesNotRetry() async throws {
        var calls = 0
        let valid = routine(["bench_press_barbell", "dumbbell_row_single_arm"])
        _ = try await service.requestValidatedPlans(candidates: candidates(), expectedCount: 1, maxExercises: 2, single: true) { feedback in
            calls += 1
            if calls == 1 { return "{\"name\":" }
            XCTAssertTrue(feedback?.contains("JSON schema") == true)
            return valid
        }
        XCTAssertEqual(calls, 2)
        calls = 0
        _ = try await service.requestValidatedPlans(candidates: candidates(), expectedCount: 1, maxExercises: 2, single: true) { feedback in
            calls += 1
            XCTAssertNil(feedback)
            return valid
        }
        XCTAssertEqual(calls, 1)
    }

    func testTransportFailureAndCancellationDoNotTriggerOutputCorrection() async throws {
        for cancelled in [false, true] {
            var calls = 0
            do {
                _ = try await service.requestValidatedPlans(candidates: candidates(), expectedCount: 1, maxExercises: 2) { _ in
                    calls += 1
                    if cancelled { throw CancellationError() }
                    throw URLError(.timedOut)
                }
                XCTFail("Failure must propagate")
            } catch { XCTAssertEqual(calls, 1) }
        }
    }

    func testRevisionMayReturnOnlyTheChangedDay() async throws {
        let plans = try await service.requestValidatedPlans(candidates: candidates(), expectedCount: nil, maxExercises: 2) { _ in
            self.batch([self.routine(["bench_press_barbell", "dumbbell_row_single_arm"])])
        }
        XCTAssertEqual(plans.count, 1)
    }
}

@MainActor
final class AIMealCorrectionTests: XCTestCase {
    private let valid = #"{"isFood":true,"foods":"Rice 200g","items":[{"name":"Rice","grams":200,"consumedFraction":1,"foodID":"white_rice_cooked","portionEstimated":true}]}"#

    func testValidExtractionUsesOneRequestAndDatabaseArithmetic() async throws {
        var calls = 0
        let value = try await AIWorkoutService.shared.requestValidatedMeal(photo: false) { feedback in
            calls += 1
            XCTAssertNil(feedback)
            return self.valid
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(value.nutrition.carbs, MealFoodCatalog.byID["white_rice_cooked"]!.per100g.carbs * 2, accuracy: 0.0001)
    }

    func testMalformedJSONAndUnknownFoodIDReceiveOneTargetedCorrection() async throws {
        for (bad, expected) in [("{", "JSON"), (valid.replacingOccurrences(of: "white_rice_cooked", with: "invented_rice"), "foodID")] {
            var calls = 0
            let value = try await AIWorkoutService.shared.requestValidatedMeal(photo: true) { feedback in
                calls += 1
                if calls == 1 { return bad }
                XCTAssertTrue(feedback?.contains(expected) == true)
                return self.valid
            }
            XCTAssertEqual(calls, 2)
            XCTAssertTrue(value.analysis?.hasEstimatedPortions == true)
        }
    }

    func testInvalidAmountsRemainRejectedAfterTwoRequests() async {
        var calls = 0
        do {
            _ = try await AIWorkoutService.shared.requestValidatedMeal(photo: false) { feedback in
                calls += 1
                if calls == 2 { XCTAssertTrue(feedback?.contains("amount") == true) }
                return self.valid.replacingOccurrences(of: "\"grams\":200", with: "\"grams\":-200")
            }
            XCTFail("Invalid amounts must not be accepted")
        } catch { XCTAssertEqual(calls, 2) }
    }

    func testNonFoodIsNotRetriedOrInvented() async {
        var calls = 0
        do {
            _ = try await AIWorkoutService.shared.requestValidatedMeal(photo: true) { _ in
                calls += 1
                return #"{"isFood":false,"foods":"","items":[]}"#
            }
            XCTFail("Non-food cannot be saved")
        } catch { XCTAssertEqual(calls, 1) }
    }

    func testTransportFailureAndCancellationDoNotRetry() async {
        for cancelled in [false, true] {
            var calls = 0
            do {
                _ = try await AIWorkoutService.shared.requestValidatedMeal(photo: false) { _ in
                    calls += 1
                    if cancelled { throw CancellationError() }
                    throw URLError(.timedOut)
                }
                XCTFail("Transport errors must propagate")
            } catch { XCTAssertEqual(calls, 1) }
        }
    }

    func testRawWeightConflictUsesOneCorrectionAndPreservesConsumedFraction() async throws {
        var calls = 0
        let corrected = valid.replacingOccurrences(of: "white_rice_cooked", with: "white_rice_dry")
            .replacingOccurrences(of: "\"consumedFraction\":1", with: "\"consumedFraction\":0.5")
        let value = try await AIWorkoutService.shared.requestValidatedMeal(photo: false, description: "200g dry rice, half eaten") { feedback in
            calls += 1
            if calls == 1 { return self.valid }
            XCTAssertTrue(feedback?.contains("RAW/DRY") == true)
            return corrected
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(value.analysis?.items.first?.grams, 100)
        XCTAssertEqual(value.nutrition.carbs, MealFoodCatalog.byID["white_rice_dry"]!.per100g.carbs, accuracy: 0.0001)
    }
}
