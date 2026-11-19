import XCTest
@testable import Maso

@MainActor
final class WatchPlayerTests: XCTestCase {
    private func fixture() throws -> (TrainingSessionStore, DataStore) {
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById.values.first { $0.category == .strength && ExerciseWeightReference.expectsLoad($0) })
        let steps = [PlanStep(id: "one", exerciseId: exercise.id, sets: 3, reps: 8, weight: 20, duration: nil),
                     PlanStep(id: "two", exerciseId: exercise.id, sets: 2, reps: 10, weight: 30, duration: nil)]
        let plan = Plan(id: "watch-test", name: "Watch", steps: steps, createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 30))
        return (store, data)
    }
    private func command(_ store: TrainingSessionStore, _ kind: WatchCommand.Kind, value: Double? = nil, stepID: String? = nil) throws -> WatchCommand {
        let state = store.makeWatchState()
        return WatchCommand(sessionID: try XCTUnwrap(state.workoutSessionID), context: try XCTUnwrap(state.context), kind: kind, stepID: stepID, value: value)
    }
    func testEditOnlyCurrentSetAndRejectStaleCommands() throws {
        let (store, data) = try fixture(); defer { store.end() }
        let old = try command(store, .advance)
        XCTAssertTrue(store.applyWatchCommand(try command(store, .weight, value: 25), data: data))
        XCTAssertEqual(store.plan?.steps[0].weightForSet(1), 25)
        XCTAssertEqual(store.plan?.steps[0].weightForSet(2), 20)
        XCTAssertFalse(store.applyWatchCommand(old, data: data))
        XCTAssertEqual(store.session?.completedSets.count, 0)
    }
    func testCompletionCannotRepeatAndUndoRemovesExactRecord() throws {
        let (store, data) = try fixture(); defer { store.end() }
        let count = data.sets.count
        let advance = try command(store, .advance)
        XCTAssertTrue(store.applyWatchCommand(advance, data: data))
        XCTAssertFalse(store.applyWatchCommand(advance, data: data))
        XCTAssertEqual(data.sets.count, count + 1)
        XCTAssertEqual(store.makeWatchState().rows?.first?.completed, 1)
        XCTAssertTrue(store.applyWatchCommand(try command(store, .undo), data: data))
        XCTAssertEqual(data.sets.count, count)
        XCTAssertEqual(store.session?.completedSets.count, 0)
    }
    func testJumpDoesNotLogSkippedSets() throws {
        let (store, data) = try fixture(); defer { store.end() }
        XCTAssertTrue(store.applyWatchCommand(try command(store, .jump, stepID: "two"), data: data))
        XCTAssertEqual(store.currentSegment?.stepId, "two")
        XCTAssertEqual(store.session?.completedSets.count, 0)
        XCTAssertFalse(store.applyWatchCommand(try command(store, .jump, stepID: "missing"), data: data))
    }
    func testRestEditPreservesPauseAndDoesNotChangePreference() throws {
        let (store, data) = try fixture(); defer { store.end() }
        XCTAssertTrue(store.applyWatchCommand(try command(store, .advance), data: data))
        XCTAssertEqual(store.makeWatchState().mode, .rest)
        store.togglePlay()
        let defaultRest = data.settings.defaultRestSeconds
        XCTAssertTrue(store.applyWatchCommand(try command(store, .rest, value: 120), data: data))
        XCTAssertEqual(store.makeWatchState().restDuration, 120)
        XCTAssertEqual(store.session?.playing, false)
        XCTAssertEqual(data.settings.defaultRestSeconds, defaultRest)
        XCTAssertFalse(store.applyWatchCommand(try command(store, .weight, value: 40), data: data))
    }
    func testInvalidEditsAndCrossSessionAreRejected() throws {
        let (store, data) = try fixture(); defer { store.end() }
        for value in [-1.0, 501, Double.infinity, Double.nan] {
            XCTAssertFalse(store.applyWatchCommand(try command(store, .weight, value: value), data: data))
        }
        for value in [0.0, 1.5, 1000] {
            XCTAssertFalse(store.applyWatchCommand(try command(store, .reps, value: value), data: data))
        }
        var foreign = try command(store, .advance); foreign.sessionID = "old-session"
        XCTAssertFalse(store.applyWatchCommand(foreign, data: data))
    }
    func testDiscardRemovesOnlyOwnedRecordsAndMarksWatchHealthDiscard() throws {
        let (store, data) = try fixture(); defer { store.end() }
        let before = data.sets.map(\.id)
        XCTAssertTrue(store.applyWatchCommand(try command(store, .advance), data: data))
        XCTAssertTrue(store.applyWatchCommand(try command(store, .discard), data: data))
        XCTAssertEqual(data.sets.map(\.id), before)
        XCTAssertNil(store.session)
        XCTAssertEqual(store.makeWatchState().discarded, true)
    }
    func testWatchPreviewEnvMapsLongNameTimedAndHeartWithoutRenderingUI() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let long = WatchPreviewFixture.snapshot(environment: [
            "MASSO_WATCH_PREVIEW": "exercise",
            "MASSO_WATCH_PREVIEW_NAME": "long"
        ], language: "en", now: now)
        XCTAssertEqual(long?.scene, "exercise")
        XCTAssertEqual(long?.state.exerciseName, WatchPreviewFixture.longExerciseName)
        XCTAssertEqual(long?.state.manualConfirm, true)
        XCTAssertEqual(long?.state.rows?.first?.name, WatchPreviewFixture.longExerciseName)
        XCTAssertTrue(long?.textSizeComesFromSystemSettings == true)
        XCTAssertNil(long?.heart)

        let timed = WatchPreviewFixture.snapshot(environment: [
            "MASSO_WATCH_PREVIEW": "timed",
            "MASSO_WATCH_MARKETING_HEART": "0"
        ], language: "en", now: now)
        XCTAssertEqual(timed?.state.mode, .exercise)
        XCTAssertEqual(timed?.state.manualConfirm, false)
        XCTAssertEqual(timed?.state.paused, true)
        XCTAssertEqual(timed?.state.pausedRemaining, 45)
        XCTAssertNil(timed?.state.reps)
        XCTAssertNil(timed?.heart)
        XCTAssertNil(WatchPreviewFixture.heartSample(environment: ["MASSO_WATCH_MARKETING_HEART": "0"], now: now))
        XCTAssertNil(WatchPreviewFixture.heartSample(environment: [:], now: now))

        let valued = WatchPreviewFixture.snapshot(environment: [
            "MASSO_WATCH_PREVIEW": "exercise",
            "MASSO_WATCH_MARKETING_HEART": "1",
            "MASSO_WATCH_MARKETING_BPM": "126"
        ], language: "en", now: now)
        XCTAssertEqual(valued?.heart?.bpm, 126)
        XCTAssertEqual(valued?.heart?.date, now)
        XCTAssertEqual(WatchPreviewFixture.heartSample(environment: ["MASSO_WATCH_MARKETING_HEART": "1"], now: now)?.bpm, 128)

        let rest = WatchPreviewFixture.snapshot(environment: ["MASSO_WATCH_PREVIEW": "rest"], language: "en", now: now)
        XCTAssertEqual(rest?.state.mode, .rest)
        let queue = WatchPreviewFixture.snapshot(environment: ["MASSO_WATCH_PREVIEW": "queue"], language: "en", now: now)
        XCTAssertEqual(queue?.scene, "queue")
        XCTAssertEqual(queue?.state.mode, .exercise)
        XCTAssertNil(WatchPreviewFixture.snapshot(environment: [:], language: "en", now: now))
        XCTAssertEqual(WatchPreviewFixture.marketingName("bench_press_machine", language: "zh"), "推胸（器械）")
        let marketed = WatchPreviewFixture.snapshot(environment: [
            "MASSO_WATCH_PREVIEW": "exercise",
            "MASSO_WATCH_MARKETING_EXERCISE": "bench_press_machine"
        ], language: "en", now: now)
        XCTAssertEqual(marketed?.state.exerciseName, "Chest Press (Machine)")
    }

    /// Reserved slots, not a rendered watch. The 40mm and 46mm captures hid the load
    /// digits because a second title line and a tall button consumed the first screen.
    func testSetAndLoadStayAboveThePrimaryOnEveryWatch() throws {
        XCTAssertFalse(WatchPlayerLayout.supportedScreens.isEmpty)
        for screen in WatchPlayerLayout.supportedScreens {
            let page = WatchPlayerLayout.firstScreen(on: screen)
            XCTAssertTrue(page.fits, screen.name)
            XCTAssertLessThanOrEqual(page.setMaxY, page.parameterMinY, screen.name)
            XCTAssertLessThanOrEqual(page.parameterMaxY, page.primaryMinY, screen.name)
            XCTAssertGreaterThanOrEqual(page.parameterHeight, 24, screen.name)
            XCTAssertEqual(page.primaryHeight, 44, screen.name)
            XCTAssertEqual(WatchPlayerLayout.primaryVisualHeight, 36, screen.name)
            XCTAssertLessThan(WatchPlayerLayout.primaryVisualHeight, page.primaryHeight, screen.name)
            XCTAssertEqual(page.footerHeight, WatchPlayerLayout.footerHeight, screen.name)
            XCTAssertLessThanOrEqual(page.footerMinY + page.footerHeight, page.contentHeight + 0.5, screen.name)
        }
        let small = try XCTUnwrap(WatchPlayerLayout.supportedScreens.first { $0.name == "40mm" })
        XCTAssertEqual(WatchPlayerLayout.firstScreen(on: small).titleLines, 1)
        let wide = try XCTUnwrap(WatchPlayerLayout.supportedScreens.first { $0.name == "46mm" })
        XCTAssertEqual(WatchPlayerLayout.firstScreen(on: wide).titleLines, 2)
    }

    /// Point-geometry unit over recorded watch sizes. It does not launch or render the Watch UI.
    func testPinnedFooterStaysInsideEverySupportedWatchSafeArea() {
        XCTAssertFalse(WatchPlayerLayout.supportedScreens.isEmpty)
        for screen in WatchPlayerLayout.supportedScreens {
            let footer = WatchPlayerLayout.footer(on: screen)
            XCTAssertTrue(WatchPlayerLayout.footerIsReachable(footer, on: screen), screen.name)
            XCTAssertGreaterThanOrEqual(footer.height, 44, screen.name)
            XCTAssertGreaterThanOrEqual(footer.controlWidth, 36, screen.name)
        }
    }

    func testMirrorContextStableAcrossRepeatedReads() throws {
        let (store, _) = try fixture(); defer { store.end() }
        let context = store.makeWatchState().context
        for _ in 0..<100 { XCTAssertEqual(store.makeWatchState().context, context) }
    }
    func testOldMirrorRemainsDecodable() throws {
        let bytes = try JSONEncoder().encode(WatchSyncState.idle)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["context", "rows", "reps", "weight", "canUndo", "weightUnit", "discarded"] { object.removeValue(forKey: key) }
        XCTAssertEqual(WatchSyncState.decode(try JSONSerialization.data(withJSONObject: object))?.mode, .idle)
    }
}
