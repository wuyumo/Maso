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
