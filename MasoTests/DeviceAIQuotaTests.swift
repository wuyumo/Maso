import XCTest
import UIKit
@testable import Maso

@MainActor final class DeviceAIQuotaTests: XCTestCase {
    private func task(_ manager: DeviceAIQuota, _ id: String, kind: CoachTaskKind = .focus,
                      now: Date = Date(), pro: Bool = false) async throws -> String {
        try await manager.perform(kind: kind, isPro: pro, operationID: id, now: now,
            valid: { !$0.isEmpty }) { "validated fixture" }
    }

    func testSuccessfulDeviceTaskPersistsAndReplayAcrossEntrancesDoesNotCallAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = DeviceAIQuota(directory: directory)
        var calls = 0
        let a: String = try await first.perform(kind: .focus, isPro: false, operationID: "same", valid: { !$0.isEmpty }) { calls += 1; return "exact result" }
        let recreated = DeviceAIQuota(directory: directory)
        let b: String = try await recreated.perform(kind: .focus, isPro: false, operationID: "same", capacity: false, valid: { !$0.isEmpty }) { calls += 1; return "not allowed to run" }
        XCTAssertEqual(a, b); XCTAssertEqual(calls, 1)
        await recreated.refresh(); XCTAssertEqual(recreated.results.count, 1)
        let otherDevice = DeviceAIQuota()
        let c = try await task(otherDevice, "same")
        XCTAssertFalse(c.isEmpty, "Different installations intentionally do not share counters")
    }

    func testFailedUnchangedCancelledAndNoCapacityNeverConsumeExperience() async throws {
        let manager = DeviceAIQuota()
        var calls = 0
        do {
            let _: String = try await manager.perform(kind: .weeklyPlan, isPro: false, capacity: false, valid: { !$0.isEmpty }) { calls += 1; return "no" }
            XCTFail("Capacity must be checked before network work")
        } catch DeviceAIQuotaError.capacity { }
        XCTAssertEqual(calls, 0)
        do {
            let _: String = try await manager.perform(kind: .focus, isPro: false, valid: { !$0.isEmpty }) { throw URLError(.notConnectedToInternet) }
            XCTFail("Offline")
        } catch { }
        let _: String = try await manager.perform(kind: .focus, isPro: false, valid: { _ in false }) { "unchanged" }
        let used = await manager.ledger.hasExperience(.focus); XCTAssertFalse(used)
        _ = try await task(manager, "success")
        let after = await manager.ledger.hasExperience(.focus); XCTAssertTrue(after)
    }

    func testTwoMonthlyTextTasksSharedAcrossKindsAndUTCMonthReset() async throws {
        let manager = DeviceAIQuota()
        let november = Date(timeIntervalSince1970: 1794484800)
        _ = try await task(manager, "first-focus", now: november)
        _ = try await task(manager, "first-equipment", kind: .equipment, now: november)
        _ = try await task(manager, "monthly1", now: november)
        _ = try await task(manager, "monthly2", kind: .equipment, now: november)
        do { _ = try await task(manager, "third", now: november); XCTFail("Shared two, not two per UI") }
        catch DeviceAIQuotaError.upgrade { }
        let december = Date(timeIntervalSince1970: 1796126400)
        _ = try await task(manager, "next-month", now: december)
        let count = await manager.ledger.monthlyUsed(DeviceAIQuota.period(december)); XCTAssertEqual(count, 1)
    }

    func testNoticeMigrationIsExplicitRetainedAndDoesNotGuessHistoricalUse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let manager = DeviceAIQuota(directory: directory, legacy: true, acknowledged: false)
        XCTAssertTrue(manager.needsDisclosure)
        _ = try await task(manager, "before-notice") // App/AI is never acknowledgement-gated.
        manager.recordNoticePresentation(at:now)
        manager.recordNoticePresentation(at:now.addingTimeInterval(86400))
        XCTAssertEqual(manager.graceEnds,now.addingTimeInterval(30 * 86400))
        manager.acknowledge(at:now.addingTimeInterval(2 * 86400))
        XCTAssertEqual(manager.graceEnds,now.addingTimeInterval(30 * 86400),"Dismiss must not restart grace")
        _ = try await task(manager, "grace", now: now.addingTimeInterval(15 * 86400))
        let experienced = await manager.ledger.hasExperience(.focus); XCTAssertFalse(experienced)
        let recreated = DeviceAIQuota(directory: directory, legacy: false, acknowledged: false)
        XCTAssertFalse(recreated.needsDisclosure); XCTAssertTrue(recreated.legacy)
        _ = try await task(recreated, "after-grace", now: now.addingTimeInterval(31 * 86400))
        let first = await recreated.ledger.hasExperience(.focus); XCTAssertTrue(first)
    }

    func testNewInstallAIWorksWithoutAnInterruptionAndLegacyNoticeIsStableOnRelaunch() async throws {
        let fresh = DeviceAIQuota(acknowledged:false)
        _ = try await task(fresh,"new-install")
        let first = await fresh.ledger.hasExperience(.focus); XCTAssertTrue(first)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let now = Date(); let original = DeviceAIQuota(directory:dir,legacy:true,acknowledged:false)
        original.recordNoticePresentation(at:now)
        let reloaded = DeviceAIQuota(directory:dir,legacy:false,acknowledged:false)
        XCTAssertTrue(reloaded.needsDisclosure); XCTAssertEqual(reloaded.graceEnds,original.graceEnds)
        reloaded.acknowledge(at:now.addingTimeInterval(86400))
        let dismissed = DeviceAIQuota(directory:dir,legacy:false,acknowledged:false)
        XCTAssertFalse(dismissed.needsDisclosure); XCTAssertEqual(dismissed.graceEnds,original.graceEnds)
    }

    func testAutomaticRecommendationHasSeparateSuccessOnlyDailyBudget() async throws {
        let manager = DeviceAIQuota()
        let now = Date()
        let _: String = try await manager.perform(kind: .singleWorkout, isPro: false, automatic: true, now: now, valid: { _ in false }) { "failed" }
        let _: String = try await manager.perform(kind: .singleWorkout, isPro: false, automatic: true, now: now, valid: { !$0.isEmpty }) { "automatic" }
        do {
            let _: String = try await manager.perform(kind: .singleWorkout, isPro: false, automatic: true, now: now, valid: { !$0.isEmpty }) { "should not run" }
            XCTFail("Daily budget")
        } catch DeviceAIQuotaError.automatic { }
        let used = await manager.ledger.hasExperience(.singleWorkout); XCTAssertFalse(used)
        _ = try await task(manager, "active-first", kind: .singleWorkout)
    }

    func testCorruptLocalQuotaDoesNotResetOrBlockBasicAppAccess() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("usage-results.json")
        try Data("invalid fixture".utf8).write(to: file)
        let manager = DeviceAIQuota(directory: dir, acknowledged: false)
        XCTAssertTrue(manager.storageError)
        manager.acknowledge()
        XCTAssertFalse(manager.needsDisclosure, "Basic training must remain reachable")
        do { _ = try await task(manager, "blocked"); XCTFail("Do not reset quota") }
        catch DeviceAIQuotaError.storage { }
        XCTAssertEqual(try String(contentsOf: file), "invalid fixture")
    }

    func testRootMicroAdjustmentsAndExistingPaidRights() async throws {
        let manager = DeviceAIQuota()
        _ = try await task(manager, "root")
        for i in 0..<2 {
            let _: String = try await manager.perform(kind: .focus, isPro: false, operationID: "edit-\(i)", goalID: "root", parentID: "root", valid: { !$0.isEmpty }) { "edited fixture" }
        }
        do {
            let _: String = try await manager.perform(kind: .focus, isPro: false, operationID: "edit3", goalID: "root", parentID: "root", valid: { !$0.isEmpty }) { "not run" }
            XCTFail("No edit-menu unlimited retry")
        } catch DeviceAIQuotaError.upgrade { }
        for i in 0..<35 { _ = try await task(manager, "paid-\(i)", pro: true) }
        await manager.refresh(); XCTAssertEqual(manager.results.count, 38)
    }

    func testCopyMessageUsesExactOriginalUnicodeAndLineBreaks() {
        let source = "原文 first line\n  第二行：3 × 10 💪"
        CoachMessageTextActions.copy(source)
        XCTAssertEqual(UIPasteboard.general.string, source)
    }
}
