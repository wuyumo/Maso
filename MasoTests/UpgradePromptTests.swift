import XCTest
@testable import Maso

@MainActor
final class UpgradePromptTests: XCTestCase {
    func testSemanticPolicyCannotBeBypassedByDismissingTheOldReminder() {
        let prompt = UpgradePrompt()
        var calls = 0
        prompt.requestAI(isPro: false, source: "coach") { calls += 1 }
        XCTAssertFalse(prompt.isPresented)
        XCTAssertEqual(calls, 1, "The shared runtime policy, not a dismissible offer, admits actual work")
        prompt.didDismiss(); prompt.didDismiss()
        XCTAssertEqual(calls, 1)
    }

    func testSubscriberRunsImmediatelyAndWelcomeOnlyAppliesToNewFreeInstallations() {
        let prompt = UpgradePrompt()
        var calls = 0
        prompt.requestAI(isPro: true, source: "coach") { calls += 1 }
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(prompt.isPresented)
        XCTAssertTrue(WelcomePaywallPolicy.shouldPresent(hasSeen: nil, onboardingCompleted: false, isPro: false))
        XCTAssertFalse(WelcomePaywallPolicy.shouldPresent(hasSeen: true, onboardingCompleted: false, isPro: false))
        XCTAssertFalse(WelcomePaywallPolicy.shouldPresent(hasSeen: nil, onboardingCompleted: true, isPro: false))
        XCTAssertFalse(WelcomePaywallPolicy.shouldPresent(hasSeen: nil, onboardingCompleted: false, isPro: true))
    }

    func testSharedPlanImportKeepsExactParametersAndDeduplicatesOnlyIdenticalContent() throws {
        let now = Date()
        let step = PlanStep(id: "bench", exerciseId: "bench_press_barbell", sets: 1, reps: nil, weight: nil,
                            setReps: [8], setWeights: [60], duration: nil)
        let source = Plan(id: "legacy-source", name: "Push", steps: [step], createdAt: now, updatedAt: now)
        var different = Plan(id: "existing", name: source.name, steps: source.steps,
                             createdAt: now, updatedAt: now, preservesExerciseVariants: true)
        different.steps[0].setWeights = [70]
        var settings = UserSettings()
        settings.availableEquipment = ["dumbbell"]
        let store = DataStore(exercises: ExerciseLibrary.all, plans: [different], sets: [], settings: settings)
        let code = try XCTUnwrap(PlanShareCodec.encode(source))
        let received = try XCTUnwrap(PlanShareCodec.decode(code))
        XCTAssertEqual(received.preservesExerciseVariants, true)
        XCTAssertTrue(store.saveImportedPlans([received]))
        XCTAssertEqual(store.plans.count, 2, "Same name and movements with different loads must not be dropped")
        let saved = try XCTUnwrap(store.plans.last)
        XCTAssertEqual(saved.steps[0].exerciseId, "bench_press_barbell")
        XCTAssertEqual(saved.steps[0].weightForSet(1), 60)
        XCTAssertEqual(saved.steps[0].repsForSet(1), 8)
        let segment = try XCTUnwrap(expandPlan(saved, exById: store.exById).first)
        guard case let .exercise(_, setNumber, totalSets, reps, weight, _, _) = segment.kind else {
            return XCTFail("Expected the imported exercise")
        }
        XCTAssertEqual(setNumber, 1)
        XCTAssertEqual(totalSets, 1)
        XCTAssertEqual(reps, 8)
        XCTAssertEqual(weight, 60)
        let rescan = try XCTUnwrap(PlanShareCodec.decode(code))
        XCTAssertTrue(store.saveImportedPlans([rescan]))
        XCTAssertEqual(store.plans.count, 2, "Rescanning the identical plan remains idempotent")

        var unknownStep = step
        unknownStep.setWeights = [nil]; unknownStep.setReps = [nil]
        let unknown = Plan(id: "legacy-unknown", name: "Unknown", steps: [unknownStep], createdAt: now, updatedAt: now)
        let unknownReceived = try XCTUnwrap(PlanShareCodec.decode(try XCTUnwrap(PlanShareCodec.encode(unknown))))
        XCTAssertTrue(store.saveImportedPlans([unknownReceived]))
        let savedUnknown = try XCTUnwrap(store.plans.last?.steps.first)
        XCTAssertNil(savedUnknown.weightForSet(1))
        XCTAssertNil(savedUnknown.repsForSet(1))
    }

    func testImportLimitIsAtomicAndDoesNotDeleteExistingRoutinesAfterDowngrade() throws {
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
        func plan(_ index: Int) -> Plan {
            Plan(id: "import-\(index)", name: "Routine \(index)", steps: [], createdAt: .now, updatedAt: .now)
        }
        XCTAssertTrue(data.saveImportedPlans((0..<4).map(plan)))
        XCTAssertFalse(data.saveImportedPlans([plan(4), plan(5)]))
        XCTAssertEqual(data.plans.count, 4)
        XCTAssertTrue(data.saveImportedPlans([plan(4)]))
        XCTAssertTrue(data.saveImportedPlans([plan(4)]), "Importing an existing signature remains idempotent")
        XCTAssertEqual(data.plans.count, 5)
        data.settings.proSubscription = .init(tier: .lifetime, startedAt: .now, renewsAt: nil)
        XCTAssertTrue(data.saveImportedPlans([plan(5), plan(6)]))
        data.settings.proSubscription = nil
        XCTAssertFalse(data.saveImportedPlans([plan(7)]))
        XCTAssertEqual(data.plans.count, 7, "Downgrading preserves all previously saved work")
    }

    func testThreeFreeCustomExercisesFourthRequiresProAndExpiryPreservesExisting() throws {
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
        let original = try XCTUnwrap(ExerciseLibrary.all.first)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var created: [Exercise] = []
        for index in 0..<4 {
            payload["id"] = "custom-test-\(index)"
            let exercise = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: payload))
            XCTAssertEqual(data.addCustomExercise(exercise), index < 3)
            created.append(exercise)
        }
        XCTAssertEqual(data.settings.customExercises.count, 3)
        XCTAssertFalse(data.canCreateCustomExercise)
        XCTAssertTrue(data.addCustomExercise(created[0]), "Idempotent save must not consume an extra slot")
        XCTAssertEqual(data.settings.customExercises.count, 3)
        data.settings.proSubscription = .init(tier: .lifetime, startedAt: .now, renewsAt: nil)
        XCTAssertTrue(data.addCustomExercise(created[3]))
        data.settings.proSubscription = nil
        XCTAssertEqual(data.settings.customExercises.count, 4)
        XCTAssertFalse(data.canCreateCustomExercise)
        payload["id"] = created[0].id
        payload["name"] = "My updated exercise"
        let updated = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: payload))
        data.updateCustomExercise(updated)
        XCTAssertEqual(data.settings.customExercises.first?.name, updated.name)
    }
}
