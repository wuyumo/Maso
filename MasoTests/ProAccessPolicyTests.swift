import XCTest
@testable import Maso

@MainActor
final class ProAccessPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_480_000)
    private func context(_ period: String = "2026-11", pro: Bool = false) -> CoachAccessContext {
        .init(now: now, period: period, isPro: pro)
    }
    private func request(_ id: String, kind: CoachTaskKind = .focus) -> CoachTaskRequest {
        .init(id: id, kind: kind, goalID: "goal")
    }
    private func complete(_ ledger: CoachAccessLedger, _ id: String) async throws {
        _ = try await ledger.succeed(id, validatedContent: "Validated executable plan fixture", at: now)
    }

    func testBundledPolicyHasHonestReleaseGateAndPreservesPaidRights() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "pro-access-policy", withExtension: "json"))
        let p = try JSONDecoder().decode(ProAccessPolicy.self, from: Data(contentsOf: url))
        XCTAssertTrue(p.productionAIEnforcementEnabled)
        XCTAssertFalse(p.requiresVerifiedSharedAuthority)
        XCTAssertEqual(p.freeSavedPlans, 5)
        XCTAssertEqual(p.freeSavedPlans, FreeLimit.maxPlans)
        XCTAssertEqual(p.freeCustomExercises, 3)
        XCTAssertEqual(p.freeMonthlyTextTasks, 2)
        XCTAssertNil(p.proActiveTaskLimit)
        XCTAssertNil(p.proImageTaskLimit)
    }

    func testEveryExplicitTaskGetsOneSuccessfulExperienceAndImagesThenRequirePro() async throws {
        let ledger = try CoachAccessLedger()
        for kind in CoachTaskKind.allCases {
            let id = "first-" + kind.rawValue
            let first = try await ledger.reserve(request(id, kind: kind), context: context())
            XCTAssertEqual(first, .firstExperience)
            try await complete(ledger, id)
            var second = request("second-" + kind.rawValue, kind: kind)
            second.usesImage = true
            let admission = try await ledger.reserve(second, context: context())
            XCTAssertEqual(admission, .upgrade)
        }
    }

    func testFailureClarificationAndUnchangedResultReleaseExperience() async throws {
        let ledger = try CoachAccessLedger()
        for id in ["failed", "cancelled", "unchanged"] {
            let a = try await ledger.reserve(request(id), context: context())
            XCTAssertEqual(a, .firstExperience)
            try await ledger.release(id)
        }
        let a = try await ledger.reserve(request("valid"), context: context())
        XCTAssertEqual(a, .firstExperience)
        do { _ = try await ledger.succeed("valid", validatedContent: " ", at: now); XCTFail("Empty output is not success") }
        catch CoachLedgerError.invalidResult { }
        try await ledger.release("valid")
        let b = try await ledger.reserve(request("next"), context: context())
        XCTAssertEqual(b, .firstExperience)
    }

    func testTwoEntrancesShareOperationAndCompletedReadbackNeverDebitsAgain() async throws {
        let ledger = try CoachAccessLedger()
        let same = request("same-request-from-two-entrances")
        let a = try await ledger.reserve(same, context: context())
        let b = try await ledger.reserve(same, context: context())
        XCTAssertEqual(a, .firstExperience); XCTAssertEqual(b, .pending)
        try await complete(ledger, same.id)
        let c = try await ledger.reserve(same, context: context())
        XCTAssertEqual(c, .savedResult)
        let used = await ledger.monthlyUsed("2026-11")
        XCTAssertEqual(used, 0)
        do { _ = try await ledger.reserve(request(same.id, kind: .equipment), context: context()); XCTFail("An ID cannot change operation") }
        catch CoachLedgerError.operationConflict { }
    }

    func testMonthlyResetAndConcurrentReservationsCannotOverdrawTwoTextTasks() async throws {
        let ledger = try CoachAccessLedger()
        _ = try await ledger.reserve(request("initial"), context: context())
        try await complete(ledger, "initial")
        let c = context()
        let admissions = try await withThrowingTaskGroup(of: (String, CoachAdmission).self) { group in
            for i in 0..<25 {
                group.addTask {
                    let id = "parallel-\(i)"
                    let a = try await ledger.reserve(.init(id: id, kind: .focus, goalID: "goal"), context: c)
                    return (id, a)
                }
            }
            var values: [(String, CoachAdmission)] = []
            for try await value in group { values.append(value) }
            return values
        }
        let allowed = admissions.filter { $0.1 == .monthlyText }
        XCTAssertEqual(allowed.count, 2)
        for (id, _) in allowed { try await complete(ledger, id) }
        let used = await ledger.monthlyUsed("2026-11")
        XCTAssertEqual(used, 2)
        let reset = try await ledger.reserve(request("new-period"), context: context("2026-12"))
        XCTAssertEqual(reset, .monthlyText)
    }

    func testTwoRevisionsWithin24HoursFailureRefundAndNoGoalSwitching() async throws {
        let ledger = try CoachAccessLedger()
        _ = try await ledger.reserve(request("parent"), context: context()); try await complete(ledger, "parent")
        for i in 0..<2 {
            var child = request("revision-\(i)"); child.parentID = "parent"
            let a = try await ledger.reserve(child, context: context()); XCTAssertEqual(a, .revision)
            if i == 1 {
                try await ledger.release(child.id)
                let retry = try await ledger.reserve(child, context: context()); XCTAssertEqual(retry, .revision)
            }
            try await complete(ledger, child.id)
        }
        var third = request("third"); third.parentID = "parent"
        let denied = try await ledger.reserve(third, context: context()); XCTAssertEqual(denied, .upgrade)
        var otherGoal = CoachTaskRequest(id: "other", kind: .focus, goalID: "different")
        otherGoal.parentID = "parent"
        do { _ = try await ledger.reserve(otherGoal, context: context()); XCTFail("Different goal is not a micro edit") }
        catch CoachLedgerError.operationConflict { }
        let nextDay = CoachAccessContext(now: now.addingTimeInterval(24 * 3600 + 1), period: "2026-11")
        let expired = try await ledger.reserve(third, context: nextDay); XCTAssertEqual(expired, .upgrade)
    }

    func testReadbackSurvivesRecreationExpiryAndOfflineWithoutEntitlement() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("derived-results.json")
        let ledger = try CoachAccessLedger(fileURL: file)
        _ = try await ledger.reserve(request("stored"), context: context(pro: true)); try await complete(ledger, "stored")
        let recreated = try CoachAccessLedger(fileURL: file)
        let result = await recreated.result("stored")
        XCTAssertEqual(result?.content, "Validated executable plan fixture")
        let admission = try await recreated.reserve(request("stored"), context: context())
        XCTAssertEqual(admission, .savedResult, "Expiry must not lock acquired results")
    }

    func testTransitionDoesNotRetroactivelyConsumeAndProIsNotCappedAt30() async throws {
        let ledger = try CoachAccessLedger()
        let legacy = CoachAccessContext(now: now, period: "2026-11", legacyNoticeAt: now.addingTimeInterval(-86400))
        let old = request("old", kind: .physiqueGoal)
        let a = try await ledger.reserve(old, context: legacy); XCTAssertEqual(a, .transition)
        try await complete(ledger, "old")
        let after = CoachAccessContext(now: now.addingTimeInterval(31 * 86400), period: "2026-12", legacyNoticeAt: legacy.legacyNoticeAt)
        let b = try await ledger.reserve(request("first-after", kind: .physiqueGoal), context: after)
        XCTAssertEqual(b, .firstExperience)
        for i in 0..<40 {
            let a = try await ledger.reserve(request("paid-\(i)", kind: .physiqueGoal), context: context(pro: true))
            XCTAssertEqual(a, .existingSubscriber)
        }
    }

    func testAutomaticLocalClarificationStorageAndDataGatesNeverSpendActiveQuota() async throws {
        let ledger = try CoachAccessLedger()
        for (purpose, expected) in [(CoachTaskRequest.Purpose.automatic, CoachAdmission.automaticRecommendation), (.localTool, .noCharge), (.clarification, .noCharge)] {
            var r = request(purpose.rawValue); r.purpose = purpose
            let a = try await ledger.reserve(r, context: context()); XCTAssertEqual(a, expected)
        }
        var noStorage = request("no-storage"); noStorage.canStoreResult = false
        let a = try await ledger.reserve(noStorage, context: context()); XCTAssertEqual(a, .saveConflict)
        var noData = request("no-data", kind: .trainingReview); noData.hasEnoughData = false
        let b = try await ledger.reserve(noData, context: context()); XCTAssertEqual(b, .insufficientData)
        let c = try await ledger.reserve(request("valid-review", kind: .trainingReview), context: context())
        XCTAssertEqual(c, .firstExperience)
    }

    func testStaleReservationsReleaseAndCorruptPersistenceDoesNotResetSilently() async throws {
        let ledger = try CoachAccessLedger()
        _ = try await ledger.reserve(request("stale"), context: context())
        let later = CoachAccessContext(now: now.addingTimeInterval(601), period: "2026-11")
        let a = try await ledger.reserve(request("fresh"), context: later); XCTAssertEqual(a, .firstExperience)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a ledger".utf8).write(to: file)
        XCTAssertThrowsError(try CoachAccessLedger(fileURL: file))
    }
    func testRevisionChainsCannotResetTheTwoAdjustmentAllowanceAndProKeepsAccess() async throws {
        let ledger = try CoachAccessLedger()
        _ = try await ledger.reserve(request("root"), context: context()); try await complete(ledger, "root")
        var child = request("child"); child.parentID = "root"
        _ = try await ledger.reserve(child, context: context()); try await complete(ledger, "child")
        var chain = request("chain"); chain.parentID = "child"
        do { _ = try await ledger.reserve(chain, context: context()); XCTFail("Revisions must reference the canonical root, not mint more allowance") }
        catch CoachLedgerError.operationConflict { }
        var second = request("second"); second.parentID = "root"
        _ = try await ledger.reserve(second, context: context()); try await complete(ledger, "second")
        var third = request("paid-third"); third.parentID = "root"
        let paid = try await ledger.reserve(third, context: context(pro: true))
        XCTAssertEqual(paid, .existingSubscriber)
    }

    func testTextAndPhotoMealExperiencesAreSeparateAndTextUsesSharedMonthlyAllowance() async throws {
        let ledger = try CoachAccessLedger()
        let text = request("meal-text-first", kind: .nutritionText)
        _ = try await ledger.reserve(text, context: context()); try await complete(ledger, text.id)
        var photo = request("meal-photo-first", kind: .nutritionImage); photo.usesImage = true
        let a = try await ledger.reserve(photo, context: context()); XCTAssertEqual(a, .firstExperience)
        try await complete(ledger, photo.id)
        let b = try await ledger.reserve(request("meal-text-second", kind: .nutritionText), context: context())
        XCTAssertEqual(b, .monthlyText)
        var repeated = request("meal-photo-second", kind: .nutritionImage); repeated.usesImage = true
        let c = try await ledger.reserve(repeated, context: context()); XCTAssertEqual(c, .upgrade)
    }

}
