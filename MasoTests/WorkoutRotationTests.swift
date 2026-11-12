import XCTest
@testable import Maso

final class WorkoutRotationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_791_849_600)
    private var plans: [Plan] {
        ["A", "B", "C"].map {
            Plan(id: $0, name: $0, steps: [PlanStep(id: $0, exerciseId: "press", reps: 10, weight: 20, duration: nil)],
                 createdAt: now, updatedAt: now)
        }
    }
    private func completion(_ id: String, secondsAgo: TimeInterval = 60) -> WorkoutCompletion {
        WorkoutCompletion(sessionID: UUID().uuidString, planID: id, finishedAt: now.addingTimeInterval(-secondsAgo))
    }
    private func rotation(_ records: [WorkoutCompletion], date: Date? = nil) -> WorkoutRotation {
        WorkoutRotation(plans: plans, completions: records, calendar: calendar, now: date ?? now)
    }
    func testFirstLaunchAndOutOfOrderCompletionKeepStoredOrder() {
        XCTAssertEqual(rotation([]).todayPlanID, "A")
        let result = rotation([completion("B")])
        XCTAssertEqual(plans.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(result.todayPlanID, "C")
        XCTAssertEqual(result.defaultPlanID, "C")
        XCTAssertEqual(result.completedPlanIDs, ["B"])
    }
    func testSkipsCompletedPlansAndWrapsInOriginalOrder() {
        XCTAssertEqual(rotation([completion("B", secondsAgo: 120), completion("A")]).todayPlanID, "C")
        XCTAssertEqual(rotation([completion("B", secondsAgo: 120), completion("C")]).todayPlanID, "A")
    }
    func testRepeatDoesNotCompleteOtherPlansAndAllFinishedHasNoRecommendation() {
        XCTAssertEqual(rotation([completion("B", secondsAgo: 120), completion("B")]).todayPlanID, "C")
        let result = rotation([completion("A", secondsAgo: 180), completion("B", secondsAgo: 120), completion("C")])
        XCTAssertNil(result.todayPlanID)
        XCTAssertEqual(result.defaultPlanID, "C")
    }
    func testReopenFromPersistedCompletionsAndNextWeek() throws {
        let records = [completion("B")]
        let restored = try JSONDecoder().decode([WorkoutCompletion].self, from: JSONEncoder().encode(records))
        XCTAssertEqual(rotation(restored).todayPlanID, "C")
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        XCTAssertTrue(rotation(restored, date: nextWeek).completedPlanIDs.isEmpty)
        XCTAssertEqual(rotation(restored, date: nextWeek).todayPlanID, "C")
    }
    func testDeletedPlanAndEmptyLibrary() {
        XCTAssertEqual(rotation([completion("deleted")]).todayPlanID, "A")
        let result = WorkoutRotation(plans: [], completions: [], calendar: calendar, now: now)
        XCTAssertNil(result.todayPlanID)
        XCTAssertNil(result.defaultPlanID)
    }
}
