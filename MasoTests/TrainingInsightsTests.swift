import XCTest
@testable import Maso

final class TrainingInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_791_720_000)
    private func record(_ daysAgo: Int, weight: Double? = 50, reps: Int = 8,
                        id: String = "bench", category: ExerciseCategory = .strength) -> SetRecord {
        SetRecord(id: UUID().uuidString, exerciseId: id, exerciseName: id, category: category,
                  weight: weight, reps: reps, duration: nil,
                  performedAt: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, planId: nil)
    }
    private func build(_ sets: [SetRecord], weeks: Int = 4,
                       muscles: [String: Set<MuscleGroup>] = ["bench": [.chest]]) -> TrainingInsightsSnapshot {
        TrainingInsightsSnapshot.build(sets: sets, names: [:], primarySections: muscles,
                                       range: weeks == 12 ? .twelveWeeks : .fourWeeks, calendar: calendar, now: now)
    }
    func testHomePreviewUsesOnlyComparablePositiveProgress() throws {
        let rising = build([record(12), record(0, weight: 52.5)])
        guard case .lift(let lift) = WorkoutPreviewContent.select(from: rising) else { return XCTFail("Expected a comparable gain") }
        XCTAssertEqual(lift.change, 2.5)
        for records in [[record(0)], [record(10), record(0)], [record(10, weight: 55), record(0)],
                        [record(10, reps: 8), record(0, weight: 55, reps: 6)]] {
            guard case .muscles = WorkoutPreviewContent.select(from: build(records)) else { return XCTFail("A baseline or unmatched set is not improvement") }
        }
    }
    func testHomeFallbackShowsOnlyCurrentWeekMuscleSetsAndHandlesUnknownData() {
        let summary = build([record(0), record(0), record(8), record(-1), record(0, id: "row")],
                            muscles: ["bench": [.chest], "row": [.back]])
        guard case .muscles(let muscles) = WorkoutPreviewContent.select(from: summary) else { return XCTFail("Expected weekly volume") }
        XCTAssertEqual(muscles.first?.group, .chest)
        XCTAssertEqual(muscles.first?.sets, 2)
        XCTAssertEqual(muscles.first { $0.group == .back }?.sets, 1)
        XCTAssertEqual(muscles.count, 3)
        guard case .muscles(let empty) = WorkoutPreviewContent.select(from: build([])) else { return XCTFail() }
        XCTAssertTrue(empty.allSatisfy { $0.sets == 0 })
        guard case .muscles(let unknown) = WorkoutPreviewContent.select(from: build([record(0, id: "unknown")])) else { return XCTFail() }
        XCTAssertTrue(unknown.isEmpty)
    }

    func testWeeklyFallbackRetainsAllTrainedMusclesBeyondThree() {
        let groups: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .arms, .core]
        let records = groups.map { record(0, id: $0.rawValue) } + [record(0, id: MuscleGroup.core.rawValue)]
        let mappings = Dictionary(uniqueKeysWithValues: groups.map { ($0.rawValue, Set([$0])) })
        guard case .muscles(let muscles) = WorkoutPreviewContent.select(from: build(records, muscles: mappings)) else { return XCTFail() }
        XCTAssertEqual(muscles.count, 6)
        XCTAssertEqual(muscles.map(\.group), groups)
        XCTAssertEqual(muscles.last?.sets, 2)
    }

    func testImprovementTrendRequiresRepeatedComparableLiftsAndCanDecline() {
        let snapshot = build([record(12, weight: 50), record(8, weight: 55), record(0, weight: 50),
                              record(0, id: "single")])
        XCTAssertEqual(snapshot.improvementTrend.map(\.value), [0, 1, 0])
        XCTAssertTrue(build([record(0)]).improvementTrend.isEmpty)
        XCTAssertEqual(build([record(8), record(0)]).improvementTrend.map(\.value), [0, 0])
    }

    func testWeightProgressUsesMatchingRepsAndDailyBest() {
        let result = build([record(12), record(0, weight: 52), record(0, weight: 55), record(0, weight: 70, reps: 2)])
        XCTAssertEqual(result.lifts.first?.change, 5)
        XCTAssertEqual(result.lifts.first?.points.count, 2)
        guard case .weight(let reps) = result.lifts.first?.metric else { return XCTFail("Expected weight benchmark") }
        XCTAssertEqual(reps, 8)
    }
    func testRepProgressAtConstantWeightAndBodyweight() {
        XCTAssertEqual(build([record(10, reps: 10), record(0, reps: 12)]).lifts.first?.change, 2)
        let bodyweight = build([record(10, weight: nil, reps: 10, category: .calisthenics),
                                record(0, weight: nil, reps: 12, category: .calisthenics)])
        XCTAssertEqual(bodyweight.lifts.first?.change, 2)
    }
    func testIncomparableRecordsAndSingleDayAreNotImprovement() {
        let incomparable = build([record(10), record(0, weight: 55, reps: 10)])
        XCTAssertNil(incomparable.lifts.first?.change)
        XCTAssertFalse(incomparable.lifts.first?.improved ?? true)
        XCTAssertNil(build([record(0), record(0, weight: 55)]).lifts.first?.change)
        XCTAssertTrue(incomparable.comparableLifts.isEmpty)
        XCTAssertTrue(build([record(0), record(0, weight: 55)]).comparableLifts.isEmpty)
        XCTAssertTrue(build([]).comparableLifts.isEmpty)
        XCTAssertTrue(build([record(0)]).comparableLifts.isEmpty)
        let mixed = build([record(10), record(0), record(0, id: "baseline-only")])
        XCTAssertEqual(mixed.lifts.count, 2)
        XCTAssertEqual(mixed.comparableLifts.map(\.id), ["bench"])
    }
    func testFlatAndDecliningRecordsAreNotPositive() {
        XCTAssertEqual(build([record(10), record(0)]).lifts.first?.change, 0)
        XCTAssertEqual(build([record(10), record(0)]).comparableLifts.count, 1)
        let decrease = build([record(10, weight: 55), record(0)])
        XCTAssertEqual(decrease.lifts.first?.change, -5)
        XCTAssertFalse(decrease.lifts.first?.improved ?? true)
        XCTAssertEqual(decrease.comparableLifts.count, 1)
    }
    func testRangeFutureAndInvalidLoads() {
        let records = [record(50, weight: 40), record(10), record(0, weight: 55), record(-1, weight: 80),
                       record(0, weight: .nan), record(0, weight: nil), record(0, reps: 0)]
        XCTAssertEqual(build(records).lifts.first?.change, 5)
        XCTAssertEqual(build(records, weeks: 12).lifts.first?.change, 15)
        XCTAssertEqual(build(records).trainingDates.count, 2)
    }
    func testPrimaryMusclesAndTrainingDaysAreCountedWithoutDuplicatingSets() {
        let result = build([record(0), record(0), record(0, id: "unknown")],
                           muscles: ["bench": [.chest, .arms]])
        XCTAssertEqual(result.weekTrainingDays, 1)
        XCTAssertEqual(result.muscles.first { $0.group == .chest }?.sets, 2)
        XCTAssertEqual(result.muscles.first { $0.group == .arms }?.sets, 2)
        XCTAssertEqual(result.muscles.first { $0.group == .back }?.sets, 0)
        XCTAssertEqual(result.unmappedSets, 1)
        XCTAssertTrue(build([]).lifts.isEmpty)
    }
}

final class InsightsCurrentWeekTests: XCTestCase {
    func testDefaultIsThisWeekEvenWithoutRecentRecords() {
        XCTAssertEqual(InsightsTimeRange.defaultValue(records: [], calendar: .current, now: Date()), .thisWeek)
    }
    func testCurrentWeekHonorsConfiguredWeekStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let start = InsightsTimeRange.thisWeek.startDate(calendar: calendar, now: now, records: [])
        XCTAssertEqual(calendar.component(.day, from: start), 12)
        calendar.firstWeekday = 1
        let sundayStart = InsightsTimeRange.thisWeek.startDate(calendar: calendar, now: now, records: [])
        XCTAssertEqual(calendar.component(.day, from: sundayStart), 11)
    }
}

final class InsightsSelectedMuscleRangeTests: XCTestCase {
    func testMusclesAndUnknownMappingsFollowEverySelectedRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 14, hour: 12)))
        let records = [0, 8, 40, 100, 250, 500, -1].map { days in
            SetRecord(id: "set-\(days)", exerciseId: "bench", exerciseName: "Bench", category: .strength,
                      weight: 20, reps: 8, performedAt: calendar.date(byAdding: .day, value: -days, to: now)!)
        } + [SetRecord(id: "unknown", exerciseId: "unknown", exerciseName: "Unknown", category: .strength,
                       reps: 8, performedAt: calendar.date(byAdding: .day, value: -40, to: now)!)]
        for (range, expected) in zip(InsightsTimeRange.allCases, 1...6) {
            let result = TrainingInsightsSnapshot.build(sets: records, names: [:], primarySections: ["bench": [.chest]],
                range: range, calendar: calendar, now: now, muscleScope: .selectedRange)
            XCTAssertEqual(result.muscles.first { $0.group == .chest }?.sets, expected, range.rawValue)
            XCTAssertEqual(result.unmappedSets, expected >= 3 ? 1 : 0, range.rawValue)
        }
        let home = TrainingInsightsSnapshot.build(sets: records, names: [:], primarySections: ["bench": [.chest]],
            range: .fourWeeks, calendar: calendar, now: now)
        XCTAssertEqual(home.muscles.first { $0.group == .chest }?.sets, 1, "Home stays current-week scoped")
    }
}
