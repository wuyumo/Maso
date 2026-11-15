import XCTest
import CoreImage
@testable import Maso

final class SessionMuscleReportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testGroupedLoadsCountActualMatchingSetsWithoutInventingWeight() {
        let records = [record("a", "bench", weight: 50, reps: 8, at: 0),
                       record("b", "bench", weight: 50, reps: 8, at: 60),
                       record("c", "bench", weight: 50, reps: 8, at: 120),
                       record("d", "bench", weight: 40, reps: 10, at: 180),
                       record("e", "bench", weight: nil, reps: 10, at: 240),
                       record("f", "bench", weight: 40, reps: 10, at: 300)]
        XCTAssertEqual(SessionMuscleReport.groupedLoads(records), [
            .init(weight: 50, reps: 8, sets: 3), .init(weight: 40, reps: 10, sets: 1),
            .init(weight: 40, reps: 10, sets: 1)
        ])
    }

    func testImportedQRCodeStepSummaryUsesRealPerSetValues() throws {
        let previousUnit = WeightUnitProvider.current
        WeightUnitProvider.current = .kg
        defer { WeightUnitProvider.current = previousUnit }
        let first = record("first", "bench_press_barbell", weight: 60, reps: 8, at: 0)
        let link = try XCTUnwrap(SessionMuscleReport.planQRPayload(records: [first], workoutName: "Push"))
        let step = try XCTUnwrap(PlanShareCodec.decodePlans(fromQRPayload: link)?.first?.steps.first)
        let summary = planStepDetailLine(step)
        XCTAssertTrue(summary.contains("60"), summary)
        XCTAssertTrue(summary.contains("8"), summary)
        XCTAssertFalse(summary.contains("?"), summary)
        var second = first
        second.weight = 50; second.reps = 10
        let link2 = try XCTUnwrap(SessionMuscleReport.planQRPayload(records: [first, second], workoutName: "Push"))
        let varied = try XCTUnwrap(PlanShareCodec.decodePlans(fromQRPayload: link2)?.first?.steps.first)
        let variedSummary = planStepDetailLine(varied)
        XCTAssertTrue(variedSummary.contains("60") && variedSummary.contains("50"), variedSummary)
        XCTAssertTrue(variedSummary.contains("8") && variedSummary.contains("10"), variedSummary)
        var missing = second
        missing.weight = nil; missing.reps = nil
        let link3 = try XCTUnwrap(SessionMuscleReport.planQRPayload(records: [first, missing], workoutName: "Push"))
        let incomplete = try XCTUnwrap(PlanShareCodec.decodePlans(fromQRPayload: link3)?.first?.steps.first)
        XCTAssertTrue(planStepDetailLine(incomplete).contains("?"))
        XCTAssertNil(incomplete.weightForSet(2))
        var oversized = step
        oversized.sets = 10_000
        XCTAssertTrue(planStepDetailLine(oversized).hasSuffix("…"))
    }

    func testSessionQRCodeRoundTripsActualSetParameters() throws {
        let first = record("first", "bench", weight: 50, reps: 8, at: 0)
        let second = record("second", "bench", weight: 40, reps: 10, at: 60)
        let third = record("third", "row", weight: nil, reps: 12, at: 120)
        let link = try XCTUnwrap(SessionMuscleReport.planQRPayload(records: [third, first, second], workoutName: "Push"))
        let image = try XCTUnwrap(ShareQR.image(for: link)?.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let detected = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        XCTAssertEqual(detected.first?.messageString, link)
        let plan = try XCTUnwrap(PlanShareCodec.decodePlans(fromQRPayload: link)?.first)
        XCTAssertEqual(plan.steps.map(\.exerciseId), ["bench", "row"])
        XCTAssertEqual(plan.steps[0].sets, 2)
        XCTAssertEqual(plan.steps[0].weightForSet(1), 50)
        XCTAssertEqual(plan.steps[0].weightForSet(2), 40)
        XCTAssertEqual(plan.steps[0].repsForSet(2), 10)
        XCTAssertNil(plan.steps[1].weightForSet(1))
        XCTAssertNil(SessionMuscleReport.planQRPayload(records: [], workoutName: nil))
    }

    func testCompletedSetsIgnoreUnloggedPlansAndIsolateSessions() {
        let bench = exercise("bench", primary: [.chest], secondary: [.triceps])
        let other = record("other-session", "bench", weight: 100, reps: 5, at: 0)
        let done = [
            record("a", "bench", weight: 60, reps: 8, at: 0, intervals: [(0, 22), (28, 40)]),
            record("b", "bench", weight: 60, reps: 6, at: 115, intervals: [(115, 143)], rest: 75)
        ]
        let report = SessionMuscleReport.make(records: done, exercises: ["bench": bench], regions: regions)
        XCTAssertEqual(report.setCount, 2)
        XCTAssertEqual(report.loadedVolumeKg ?? 0, 840, accuracy: 0.001)
        XCTAssertEqual(report.workSeconds ?? 0, 62, accuracy: 0.001)
        XCTAssertFalse(report.timingIncomplete)
        XCTAssertEqual(report.muscles.first { $0.muscle == .chest }?.allocatedSets ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(report.muscles.first { $0.muscle == .triceps }?.allocatedSets ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(other.weight, 100)
        XCTAssertFalse(done.contains { $0.id == other.id })
    }

    func testRepeatedExerciseAndBothSidesCollapseOnce() {
        let press = exercise("press", primary: [.shoulders], secondary: [.triceps])
        let records = [
            record("p1", "press", weight: 20, reps: 8, at: 0, intervals: [(0, 28)]),
            record("p2", "press", weight: 20, reps: 8, at: 90, intervals: [(90, 116)])
        ]
        let report = SessionMuscleReport.make(records: records, exercises: ["press": press], regions: regions)
        XCTAssertEqual(report.muscles.first { $0.muscle == .shoulders }?.exercises.count, 1)
        XCTAssertEqual(report.muscles.first { $0.muscle == .shoulders }?.exercises.first?.setCount, 2)
        XCTAssertEqual(report.muscles.first { $0.muscle == .shoulders }?.allocatedSets ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(report.muscles.first { $0.muscle == .shoulders }?.nodes.sorted(), ["shoulders_left", "shoulders_right"])
        XCTAssertEqual(report.loadedVolumeKg ?? 0, 320, accuracy: 0.001)
    }

    func testBodyweightTimedCardioAndMissingWeightDoNotBecomeKilograms() throws {
        let pushup = exercise("pushup", primary: [.chest], secondary: [], equipment: "body_only")
        let plank = exercise("plank", primary: [.abs], secondary: [.obliques])
        let ride = exercise("ride", primary: [.quads], secondary: [], category: .cardio)
        let records = [
            record("bw", "pushup", weight: nil, reps: 15, at: 0, intervals: [(0, 20)]),
            record("zero", "pushup", weight: 0, reps: 12, at: 30, intervals: [(30, 48)]),
            record("plank", "plank", weight: nil, reps: nil, duration: 45, at: 80, intervals: [(80, 125)]),
            record("ride", "ride", weight: 20, reps: 100, at: 200, intervals: [(200, 680)], category: .cardio)
        ]
        let report = SessionMuscleReport.make(
            records: records,
            exercises: ["pushup": pushup, "plank": plank, "ride": ride],
            regions: regions
        )
        XCTAssertNil(report.loadedVolumeKg)
        XCTAssertEqual(report.exercises.map(\.id), ["pushup", "plank", "ride"])
        XCTAssertEqual(report.setCount, 4)
        XCTAssertEqual(report.muscles.map(\.muscle).sorted { $0.rawValue < $1.rawValue }, [.abs, .chest, .obliques])
        let chest = try XCTUnwrap(report.muscles.first { $0.muscle == .chest }?.exercises.first)
        if case .bodyweight(let sets, let reps) = chest.load {
            XCTAssertEqual(sets, 2)
            XCTAssertEqual(reps, [15, 12])
        } else {
            XCTFail("bodyweight was represented as \(chest.load)")
        }
        let abs = try XCTUnwrap(report.muscles.first { $0.muscle == .abs }?.exercises.first)
        XCTAssertEqual(abs.load, .timed(seconds: 45))
        XCTAssertNil(abs.loadedVolumeKg)
        XCTAssertEqual(report.muscles.first { $0.muscle == .obliques }?.allocatedSets ?? 0, 0.4, accuracy: 0.001)
    }

    func testMissingTimingAndUnmappedExerciseStayVisible() {
        let known = exercise("bench", primary: [.chest], secondary: [])
        var missing = record("m", "bench", weight: 40, reps: 5, at: 0)
        missing.activeIntervals = nil
        let orphan = record("o", "unknown", weight: 30, reps: 4, at: 50, intervals: [(50, 70)])
        let report = SessionMuscleReport.make(records: [missing, orphan], exercises: ["bench": known], regions: regions)
        XCTAssertTrue(report.timingIncomplete)
        XCTAssertEqual(report.workSeconds ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(report.loadedVolumeKg ?? 0, 320, accuracy: 0.001)
        XCTAssertEqual(report.exercises.map(\.id), ["bench", "unknown"])
        XCTAssertEqual(report.muscles.count, 1)
        XCTAssertTrue(report.muscles[0].exercises[0].timingIncomplete)
        XCTAssertEqual(report.muscles[0].exercises[0].setCount, 1)
    }

    func testHeartBreaksAcrossPausesRestAndLongGaps() {
        let samples = [0.0, 4, 8, 20, 28, 32, 48, 70, 100].map {
            SessionMuscleReport.HeartPoint(date: start.addingTimeInterval($0), bpm: 120)
        }
        let paused = record("paused", "bench", weight: 50, reps: 8, at: 50, intervals: [(0, 22), (28, 50)])
        XCTAssertEqual(SessionMuscleReport.heartSegments(for: paused, samples: samples).map(\.points.count), [4, 3])
        let continuous = record("gap", "bench", weight: 50, reps: 8, at: 120, intervals: [(0, 120)])
        let split = SessionMuscleReport.heartSegments(for: continuous, samples: samples)
        XCTAssertEqual(split.map(\.points.count), [7, 1, 1])
        XCTAssertEqual(split.map(\.drawsLine), [true, false, false])
        let exactlyTwenty = [
            SessionMuscleReport.HeartPoint(date: start, bpm: 100),
            SessionMuscleReport.HeartPoint(date: start.addingTimeInterval(20), bpm: 110)
        ]
        let held = record("held", "bench", weight: 50, reps: 8, at: 20, intervals: [(0, 21)])
        XCTAssertEqual(SessionMuscleReport.heartSegments(for: held, samples: exactlyTwenty).map(\.drawsLine), [true])
        XCTAssertTrue(SessionMuscleReport.heartSegments(
            for: record("rest", "bench", weight: 50, reps: 8, at: 10),
            samples: samples
        ).isEmpty)
    }

    func testShareSelectionDoesNotChangeTheSessionTotal() throws {
        let bench = exercise("bench", primary: [.chest], secondary: [.triceps])
        let report = SessionMuscleReport.make(
            records: [record("a", "bench", weight: 60, reps: 8, at: 0, intervals: [(0, 20)])],
            exercises: ["bench": bench],
            regions: regions
        )
        let selection = SessionMuscleReport.ShareSelection()
        XCTAssertFalse(selection.includeDetails)
        XCTAssertFalse(selection.includeHeart)
        XCTAssertEqual(report.loadedVolumeKg ?? 0, 480, accuracy: 0.001)
        XCTAssertEqual(report.intensity[.chest] ?? 0, 1, accuracy: 0.001)
        XCTAssertNil(report.intensity[.quads])
        XCTAssertGreaterThan(report.muscles.first { $0.muscle == .triceps }?.allocatedSets ?? 0, 0)
        let unique = Dictionary(report.muscles.flatMap(\.exercises).map { ($0.id, $0.loadedVolumeKg ?? 0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(unique.values.reduce(0, +), report.loadedVolumeKg ?? 0, accuracy: 0.001)
        XCTAssertGreaterThan(report.muscles.flatMap(\.exercises).count, unique.count)
        let hidden = SessionMuscleReport.shareContent(report: report, workoutName: "Push", selection: selection)
        XCTAssertEqual(hidden.work, "0:20")
        XCTAssertEqual(hidden.sets, "1")
        XCTAssertTrue(hidden.volume.contains("480"))
        XCTAssertTrue(hidden.muscles.allSatisfy { $0.exercises.isEmpty && $0.heart == nil })
        XCTAssertFalse(hidden.lines.contains("photo"))
        XCTAssertFalse(hidden.lines.contains("×"))
        var opted = selection
        opted.includeDetails = true
        opted.includeHeart = true
        let shown = SessionMuscleReport.shareContent(report: report, workoutName: "Push", selection: opted)
        let exercise = try XCTUnwrap(report.muscles.flatMap(\.exercises).first)
        XCTAssertEqual(shown.muscles.first { !$0.exercises.isEmpty }?.exercises.first?.sets, [weightLabel(480)])
        XCTAssertFalse(shown.lines.contains { $0.contains("×") })
        XCTAssertEqual(report.exercises.map(\.id), [exercise.id])
        XCTAssertTrue(shown.muscles.allSatisfy { $0.heart == "No heart rate" })
        XCTAssertNotEqual(hidden.lines, shown.lines)
    }

    func testRecordsWithoutASessionIDStayOutOfAnIdentifiedSession() {
        var identified = record("known", "bench", weight: 40, reps: 8, at: 0)
        identified.planId = "plan"
        identified.workoutSessionID = "session-a"
        var legacy = record("old", "bench", weight: 20, reps: 5, at: 30)
        legacy.planId = "plan"
        var other = record("other", "bench", weight: 80, reps: 3, at: 60)
        other.planId = "plan"
        other.workoutSessionID = "session-b"
        let all = [identified, legacy, other]
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: start)
        XCTAssertEqual(SessionMuscleReport.sets(in: all, planID: "plan", day: day, workoutSessionID: "session-a", calendar: calendar).map(\.id), ["known"])
        XCTAssertEqual(SessionMuscleReport.sets(in: all, planID: "plan", day: day, workoutSessionID: nil, calendar: calendar).map(\.id), ["old"])
        XCTAssertEqual(SessionMuscleReport.sets(in: all, planID: "plan", day: day, workoutSessionID: "session-b", calendar: calendar).map(\.id), ["other"])
    }

    func testASetWithoutWeightRepsOrDurationAddsNoInventedLine() {
        let empty = record("empty", "bench", weight: nil, reps: nil, at: 0)
        XCTAssertNil(SessionMuscleReport.setLine(empty))
        var timed = record("timed", "bench", weight: nil, reps: nil, duration: 45, at: 0)
        XCTAssertEqual(SessionMuscleReport.setLine(timed), "0:45")
        timed.duration = nil
        XCTAssertNil(SessionMuscleReport.setLine(timed))
    }

    private var regions: [MuscleBodyRegion] {
        [
            MuscleBodyRegion(node: "chest_left", muscles: [.chest], fatigueEligible: true),
            MuscleBodyRegion(node: "chest_right", muscles: [.chest], fatigueEligible: true),
            MuscleBodyRegion(node: "shoulders_left", muscles: [.shoulders], fatigueEligible: true),
            MuscleBodyRegion(node: "shoulders_right", muscles: [.shoulders], fatigueEligible: true),
            MuscleBodyRegion(node: "triceps_left", muscles: [.triceps], fatigueEligible: true),
            MuscleBodyRegion(node: "abs_center", muscles: [.abs], fatigueEligible: true),
            MuscleBodyRegion(node: "obliques_left", muscles: [.obliques], fatigueEligible: true),
            MuscleBodyRegion(node: "quads_left", muscles: [.quads], fatigueEligible: true),
            MuscleBodyRegion(node: "head_center", muscles: [], fatigueEligible: false)
        ]
    }

    private func exercise(
        _ id: String,
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        category: ExerciseCategory = .strength,
        equipment: String? = "barbell"
    ) -> Exercise {
        Exercise(id: id, name: id, category: category, tags: [], primaryMuscles: primary,
                 muscleGroups: primary + secondary, imageFolder: nil, equipment: equipment, instructions: [])
    }

    private func record(
        _ id: String,
        _ exerciseID: String,
        weight: Double?,
        reps: Int?,
        duration: Int? = nil,
        at offset: TimeInterval,
        intervals: [(TimeInterval, TimeInterval)] = [],
        rest: Double? = nil,
        category: ExerciseCategory = .strength
    ) -> SetRecord {
        var record = SetRecord(
            id: id, exerciseId: exerciseID, exerciseName: exerciseID, category: category,
            weight: weight, reps: reps, duration: duration, performedAt: start.addingTimeInterval(offset)
        )
        if !intervals.isEmpty {
            record.activeIntervals = intervals.map {
                WorkoutActiveInterval(start: start.addingTimeInterval($0.0), end: start.addingTimeInterval($0.1))
            }
        }
        record.restBeforeSeconds = rest
        return record
    }
}
