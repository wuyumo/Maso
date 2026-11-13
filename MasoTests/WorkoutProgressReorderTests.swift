import XCTest
@testable import Maso

@MainActor
final class WorkoutProgressReorderTests: XCTestCase {
    func testContiguousMoveMatchesArrayMoveAndSkipsNoOps() {
        let samples = [(from: 0, to: 2, expected: ["b", "c", "a", "d"]),
                       (from: 0, to: 3, expected: ["b", "c", "d", "a"]),
                       (from: 3, to: 0, expected: ["d", "a", "b", "c"]),
                       (from: 2, to: 1, expected: ["a", "c", "b", "d"]),
                       (from: 1, to: 3, expected: ["a", "c", "d", "b"])]
        for sample in samples {
            var items = ["a", "b", "c", "d"]
            let move = try! XCTUnwrap(WorkoutProgressReorder.move(count: 4, from: sample.from, toFinalIndex: sample.to))
            items.move(fromOffsets: move.source, toOffset: move.destination)
            XCTAssertEqual(items, sample.expected, "\(sample.from) → \(sample.to)")
            let direct = WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 1, 2, 3], from: sample.from, toFinalIndex: sample.to)
            XCTAssertEqual(direct, move)
        }
        XCTAssertNil(WorkoutProgressReorder.move(count: 4, from: 1, toFinalIndex: 1))
        XCTAssertNil(WorkoutProgressReorder.move(count: 1, from: 0, toFinalIndex: 0))
        XCTAssertNil(WorkoutProgressReorder.move(count: 4, from: -1, toFinalIndex: 0))
        XCTAssertNil(WorkoutProgressReorder.move(count: 4, from: 0, toFinalIndex: 4))
    }

    func testGappedVisibleSegmentsMoveInPlanIndexSpace() {
        // Plan slots 0 and 2 are on the bar. Slot 1 is a step with no playable segments.
        let move = try! XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 2, 3], from: 0, toFinalIndex: 2))
        var items = ["visible-a", "hidden", "visible-b", "visible-c"]
        items.move(fromOffsets: move.source, toOffset: move.destination)
        XCTAssertEqual(items, ["hidden", "visible-b", "visible-c", "visible-a"])
        var back = items
        let reverse = try! XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [1, 2, 3], from: 2, toFinalIndex: 0))
        back.move(fromOffsets: reverse.source, toOffset: reverse.destination)
        XCTAssertEqual(back, ["visible-a", "hidden", "visible-b", "visible-c"])

        var across = ["visible-a", "hidden", "visible-b", "visible-c"]
        let ontoNext = try XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 2, 3], from: 2, toFinalIndex: 1))
        across.move(fromOffsets: ontoNext.source, toOffset: ontoNext.destination)
        XCTAssertEqual(across, ["visible-a", "hidden", "visible-c", "visible-b"])
        var restored = across
        let backToGap = try XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 2, 3], from: 2, toFinalIndex: 1))
        restored.move(fromOffsets: backToGap.source, toOffset: backToGap.destination)
        XCTAssertEqual(restored, ["visible-a", "hidden", "visible-b", "visible-c"])
        XCTAssertNil(WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 2, 3], from: 1, toFinalIndex: 1))
        XCTAssertNil(WorkoutProgressReorder.planMove(visiblePlanIndices: [1, 2], from: 0, toFinalIndex: -1))
    }

    func testNarrowSlotsEdgesAndCancellation() {
        let width: CGFloat = 96
        let count = 8
        let spacing = WorkoutProgressReorder.spacing
        let slot = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let pitch = slot + spacing
        XCTAssertLessThan(slot, 12, "This fixture is the narrow-segment case")
        for index in 0..<count {
            let center = CGFloat(index) * pitch + slot / 2
            XCTAssertEqual(WorkoutProgressReorder.slotIndex(x: center, count: count, width: width, rightToLeft: false), index)
        }
        let size = CGSize(width: width, height: 44)
        XCTAssertEqual(WorkoutProgressReorder.landingIndex(count: count, location: CGPoint(x: -20, y: 22), size: size, rightToLeft: false), 0)
        XCTAssertEqual(WorkoutProgressReorder.landingIndex(count: count, location: CGPoint(x: width + 20, y: 22), size: size, rightToLeft: false), count - 1)
        XCTAssertNil(WorkoutProgressReorder.landingIndex(count: count, location: CGPoint(x: width / 2, y: -40), size: size, rightToLeft: false))
        XCTAssertNil(WorkoutProgressReorder.landingIndex(count: count, location: CGPoint(x: width + 80, y: 22), size: size, rightToLeft: false))
        XCTAssertNil(WorkoutProgressReorder.landingIndex(count: count, location: CGPoint(x: 10, y: 120), size: size, rightToLeft: false))
        XCTAssertNil(WorkoutProgressReorder.move(count: count, from: 3, toFinalIndex: 3))
    }

    func testRightToLeftTreatsTheTrailingEdgeAsEarlier() {
        let size = CGSize(width: 300, height: 44)
        XCTAssertEqual(WorkoutProgressReorder.landingIndex(count: 3, location: CGPoint(x: 299, y: 22), size: size, rightToLeft: true), 0)
        XCTAssertEqual(WorkoutProgressReorder.landingIndex(count: 3, location: CGPoint(x: 1, y: 22), size: size, rightToLeft: true), 2)
        XCTAssertEqual(WorkoutProgressReorder.neighborOffset(index: 1, source: 0, finalIndex: 2, pitch: 40, rightToLeft: false), -40)
        XCTAssertEqual(WorkoutProgressReorder.neighborOffset(index: 1, source: 0, finalIndex: 2, pitch: 40, rightToLeft: true), 40)
        XCTAssertEqual(WorkoutProgressReorder.neighborOffset(index: 0, source: 0, finalIndex: 2, pitch: 40, rightToLeft: false), 0)
    }

    func testReorderPreservesExerciseIdentitySetsRecordsAndDoesNotWriteHistory() throws {
        let (store, data, plan) = try session(exerciseIDs: ["bench_press_barbell", "squat_barbell", "pull_up"])
        defer { store.end() }
        data.plans = [plan]
        let savedPlans = data.plans
        let savedSets = data.sets
        let counts = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, $0.sets) })
        var records: [SetRecord] = []
        store.advance { records.append($0) }
        let secondSet = try XCTUnwrap(exerciseIndex(stepId: "step-1", setN: 2, in: store))
        store.setIndex(secondSet)
        let playing = store.session?.playing
        let completed = store.session?.completedSets
        let order = store.session?.completionOrder
        let entered = store.session?.segmentEnteredAt
        let timing = store.session?.timingKey
        let move = try XCTUnwrap(WorkoutProgressReorder.move(count: 3, from: 2, toFinalIndex: 0))
        store.reorderSteps(from: move.source, to: move.destination, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)

        let current = try XCTUnwrap(identity(store))
        XCTAssertEqual(store.plan?.steps.map(\.id), ["step-2", "step-0", "step-1"])
        XCTAssertEqual(current.stepId, "step-1")
        XCTAssertEqual(current.setN, 2)
        XCTAssertEqual(store.session?.playing, playing)
        XCTAssertEqual(store.session?.completedSets, completed)
        XCTAssertEqual(store.session?.recordedSetIDs, Optional(Set(records.map(\.id))))
        XCTAssertEqual(records.map(\.stepID), [Optional("step-0")])
        XCTAssertEqual(records.map(\.setNumber), [Optional(1)])
        XCTAssertEqual(store.session?.completionOrder, order)
        XCTAssertEqual(store.session?.timingKey, timing)
        XCTAssertEqual(store.session?.segmentEnteredAt, entered)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (store.plan?.steps ?? []).map { ($0.id, $0.sets) }), counts)
        XCTAssertEqual(Set(store.segments.map(\.id)).count, store.segments.count)
        XCTAssertEqual(data.plans, savedPlans)
        XCTAssertEqual(data.sets, savedSets)
        XCTAssertTrue(store.planParamsDirty)
        XCTAssertEqual(records.first?.stepID, Optional("step-0"))
        XCTAssertEqual(records.first?.setNumber, Optional(1))
    }

    func testIntraSetRestDoesNotFallBackToTheFirstRest() throws {
        let (store, data, _) = try session(exerciseIDs: ["bench_press_barbell", "squat_barbell", "pull_up"])
        defer { store.end() }
        let rest = try XCTUnwrap(restIndex(afterSet: 2, stepId: "step-0", in: store))
        store.setIndex(rest)
        store.updateCurrentRest(seconds: 180)
        let endsAt = store.session?.endsAt
        let entered = store.session?.segmentEnteredAt
        let timing = store.session?.timingKey
        let move = try XCTUnwrap(WorkoutProgressReorder.move(count: 3, from: 2, toFinalIndex: 0))
        store.reorderSteps(from: move.source, to: move.destination, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)

        let current = try XCTUnwrap(store.currentSegment)
        XCTAssertTrue(current.isRest)
        XCTAssertEqual(current.stepId, "step-0")
        let previous = try XCTUnwrap(previousExercise(before: try XCTUnwrap(store.session).segmentIndex, in: store))
        XCTAssertEqual(previous.stepId, "step-0")
        XCTAssertEqual(previous.setN, 2)
        if case .rest(let duration) = current.kind { XCTAssertEqual(duration, 180) } else { XCTFail("Expected the same rest") }
        XCTAssertEqual(store.session?.currentRestDurationOverride, Optional(180))
        XCTAssertEqual(store.session?.endsAt, endsAt)
        XCTAssertEqual(store.session?.timingKey, timing)
        XCTAssertEqual(store.session?.segmentEnteredAt, entered)
        XCTAssertEqual(store.session?.completedSets, Optional(Set<TrainingSessionStore.CompletedSet>()))
    }

    func testCrossExerciseRestStaysPutUntilItsGapDisappears() throws {
        let (store, data, _) = try session(exerciseIDs: ["bench_press_barbell", "squat_barbell", "pull_up"])
        defer { store.end() }
        let rest = try XCTUnwrap(crossRestIndex(after: "step-0", in: store))
        store.setIndex(rest)
        store.togglePlay()
        let remaining = try XCTUnwrap(store.session?.pausedRemaining)
        let moveNeighbor = try XCTUnwrap(WorkoutProgressReorder.move(count: 3, from: 2, toFinalIndex: 0))
        store.reorderSteps(from: moveNeighbor.source, to: moveNeighbor.destination, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.currentSegment?.isRest, Optional(true))
        XCTAssertEqual(store.currentSegment?.stepId, Optional("step-0"))
        XCTAssertEqual(store.session?.playing, Optional(false))
        XCTAssertEqual(store.session?.pausedRemaining ?? -1, remaining, accuracy: 0.001)
        XCTAssertNil(store.session?.endsAt)
        XCTAssertEqual(store.plan?.steps.map(\.id), ["step-2", "step-0", "step-1"])

        store.togglePlay()
        // step-0 is plan index 1. Moving it to the end removes the transition rest after it.
        let toEnd = try XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 1, 2], from: 1, toFinalIndex: 2))
        let amongVisible = try XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [1, 2], from: 0, toFinalIndex: 1))
        XCTAssertEqual(toEnd, amongVisible)
        let endsBefore = store.session?.endsAt
        store.reorderSteps(from: toEnd.source, to: toEnd.destination, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.map(\.id), ["step-2", "step-1", "step-0"])
        let landed = try XCTUnwrap(identity(store))
        XCTAssertEqual(landed.stepId, "step-1")
        XCTAssertEqual(landed.setN, 1)
        XCTAssertEqual(store.currentSegment?.isRest, Optional(false))
        XCTAssertNotEqual(store.session?.endsAt, endsBefore)
        XCTAssertNil(store.session?.endsAt, "A strength set must not inherit the removed rest countdown")
        XCTAssertEqual(store.session?.completedSets, Optional(Set<TrainingSessionStore.CompletedSet>()))
        XCTAssertEqual(store.session?.playing, Optional(true))
    }

    func testHiddenStepStaysPutAndCurrentExerciseDoesNotRestart() throws {
        let data = DataStore.makeMock()
        let bench = try XCTUnwrap(data.exById["bench_press_barbell"])
        let squat = try XCTUnwrap(data.exById["squat_barbell"])
        let steps = [
            PlanStep(id: "step-0", exerciseId: bench.id, sets: 3, reps: 8, weight: 40),
            PlanStep(id: "step-hidden", exerciseId: "missing-exercise", sets: 2, reps: 8, weight: 10),
            PlanStep(id: "step-1", exerciseId: squat.id, sets: 3, reps: 8, weight: 50),
        ]
        let plan = Plan(id: "reorder-hidden", name: "Hidden", steps: steps, createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120))
        defer { store.end() }
        let move = try XCTUnwrap(WorkoutProgressReorder.planMove(visiblePlanIndices: [0, 2], from: 0, toFinalIndex: 1))
        store.reorderSteps(from: move.source, to: move.destination, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.map(\.id), ["step-hidden", "step-1", "step-0"])
        let landed = try XCTUnwrap(identity(store))
        XCTAssertEqual(landed.stepId, "step-0")
        XCTAssertEqual(landed.setN, 1)
        XCTAssertFalse(store.segments.contains { $0.stepId == "step-hidden" })
    }

    func testNoOpAndEmptyMoveLeaveTheSessionUntouched() throws {
        let (store, data, _) = try session(exerciseIDs: ["bench_press_barbell", "squat_barbell"])
        defer { store.end() }
        let before = store.segments.map(\.id)
        let index = store.session?.segmentIndex
        store.reorderSteps(from: IndexSet(integer: 0), to: 1, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)
        store.reorderSteps(from: IndexSet(), to: 0, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120)
        XCTAssertEqual(store.plan?.steps.map(\.id), ["step-0", "step-1"])
        XCTAssertEqual(store.segments.map(\.id), before)
        XCTAssertEqual(store.session?.segmentIndex, index)
        XCTAssertFalse(store.planParamsDirty)
        XCTAssertEqual(store.session?.completedSets, Optional(Set<TrainingSessionStore.CompletedSet>()))
    }

    private func session(exerciseIDs: [String]) throws -> (TrainingSessionStore, DataStore, Plan) {
        let data = DataStore.makeMock()
        let steps = try exerciseIDs.enumerated().map { index, id in
            let exercise = try XCTUnwrap(data.exById[id])
            return PlanStep(id: "step-\(index)", exerciseId: exercise.id, sets: 3, reps: 8, weight: 40)
        }
        let plan = Plan(id: "reorder-\(UUID().uuidString)", name: "Reorder", steps: steps, createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120))
        return (store, data, plan)
    }

    private func identity(_ store: TrainingSessionStore) -> (stepId: String, setN: Int)? {
        guard let segment = store.currentSegment, case .exercise(_, let setN, _, _, _, _, _) = segment.kind else { return nil }
        return (segment.stepId, setN)
    }

    private func exerciseIndex(stepId: String, setN: Int, in store: TrainingSessionStore) -> Int? {
        store.segments.firstIndex { segment in
            guard segment.stepId == stepId, case .exercise(_, let number, _, _, _, _, _) = segment.kind else { return false }
            return number == setN
        }
    }

    private func restIndex(afterSet setN: Int, stepId: String, in store: TrainingSessionStore) -> Int? {
        guard let exercise = exerciseIndex(stepId: stepId, setN: setN, in: store) else { return nil }
        let rest = exercise + 1
        guard store.segments.indices.contains(rest), store.segments[rest].isRest else { return nil }
        return rest
    }

    private func crossRestIndex(after stepId: String, in store: TrainingSessionStore) -> Int? {
        guard let last = store.segments.indices.last(where: { store.segments[$0].stepId == stepId && store.segments[$0].isExercise }) else { return nil }
        let rest = last + 1
        guard store.segments.indices.contains(rest), store.segments[rest].isRest else { return nil }
        return rest
    }

    private func previousExercise(before index: Int, in store: TrainingSessionStore) -> (stepId: String, setN: Int)? {
        var cursor = index - 1
        while cursor >= 0 {
            if case .exercise(_, let setN, _, _, _, _, _) = store.segments[cursor].kind {
                return (store.segments[cursor].stepId, setN)
            }
            cursor -= 1
        }
        return nil
    }
}
