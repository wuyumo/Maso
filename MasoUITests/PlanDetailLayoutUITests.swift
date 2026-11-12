import XCTest

/// Layout checks follow the live window. XCUIDevice cannot rotate this Duo, so
/// portrait is a separate entry and a rotation entry samples the AX window while
/// DeviceHub turns the inner display. The page probe is never treated as a fixed size.
@MainActor
final class PlanDetailLayoutUITests: XCTestCase {
    private let fixture = [
        "bench_press_barbell", "squat_barbell", "pull_up",
        "leg_curl_lying", "overhead_press_barbell", "barbell_row",
    ]

    override func setUpWithError() throws { continueAfterFailure = false }

    /// Whichever orientation the inner display is in right now.
    func testLandscapeAndPortraitLastRowClearsStartButton() throws {
        let app = launch()
        let size = try requireInner(app)
        assertFixture(app)
        try assertModeMatchesLiveWindow(app, size: size)
        assertLastRowClearsStart(app)
    }

    /// Run after the inner display is already portrait (DeviceHub RotateRight, then launch).
    func testPortraitInnerUsesStackAndClearsStart() throws {
        let app = launch()
        let size = try requireInner(app)
        guard size.height > size.width else {
            throw XCTSkip("Inner window is \(label(size)), not portrait. Rotate with DeviceHub, then run this test. XCUIDevice is not used.")
        }
        assertFixture(app)
        try assertModeMatchesLiveWindow(app, size: size)
        assertLastRowClearsStart(app)
    }

    /// Start on landscape with MASO_ROTATION_WAIT set, then DeviceHub RotateRight while the sheet is open.
    /// Fails if the AX window changes and the page probe or stack/wide id does not follow.
    func testOpenSheetFollowsDeviceHubRotation() throws {
        guard let wait = ProcessInfo.processInfo.environment["MASO_ROTATION_WAIT"].flatMap(Double.init), wait > 0 else {
            throw XCTSkip("Set MASO_ROTATION_WAIT to the seconds this test should watch the open sheet. Rotate with DeviceHub during that window. A probe that stays on the old size fails.")
        }
        let app = launch()
        let initial = try requireInner(app)
        let deadline = Date().addingTimeInterval(wait)
        var latest = initial
        while Date() < deadline {
            latest = axWindow(app)
            if moved(latest, from: initial) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        if !moved(latest, from: initial) {
            XCTFail("AX window stayed \(label(initial)). Rotate the inner display with DeviceHub while this test is running.")
            return
        }
        let followed = Date().addingTimeInterval(3)
        var probe = probeValue(app)
        while Date() < followed {
            latest = axWindow(app)
            probe = probeValue(app)
            if same(probe, latest) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(same(probe, latest), "AX window became \(label(latest)) but page probe stayed \(probe)")
        try assertModeMatchesLiveWindow(app, size: latest)
        assertLastRowClearsStart(app)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = [
            "MASO_SHOWCASE": "plan_detail_layout",
            "MASO_SHOWCASE_SEED": "1",
        ]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let detail = app.descendants(matching: .any).matching(identifier: "page.workoutDetail")
        XCTAssertTrue(detail.firstMatch.waitForExistence(timeout: 20), "The layout plan did not open")
        capture(app, "plan-detail-opened")
        attachHierarchy(app, "hierarchy-opened")
        XCTAssertEqual(detail.count, 1, "page.workoutDetail must be one probe. \(detail.count) matches")
        return app
    }

    private func requireInner(_ app: XCUIApplication) throws -> CGSize {
        let size = axWindow(app)
        let probe = probeValue(app)
        XCTAssertTrue(same(probe, size), "page probe \(probe) does not match the AX window \(label(size))")
        guard isDuoInner(size) else {
            capture(app, "precondition-not-inner")
            XCTFail("Precondition failed: AX window \(label(size)) is not the Duo inner display")
            return size
        }
        return size
    }

    /// Wide when the window is short and wide. Stack otherwise. Both identifiers stay strict.
    private func assertModeMatchesLiveWindow(_ app: XCUIApplication, size: CGSize) throws {
        let wide = size.width >= size.height * 1.25 && size.height <= 740
        let wideQuery = app.descendants(matching: .any).matching(identifier: "workout.detail.wide")
        let stackQuery = app.descendants(matching: .any).matching(identifier: "workout.detail.stack")
        if wide {
            XCTAssertEqual(wideQuery.count, 1, "Wide window \(label(size)) did not select workout.detail.wide")
            XCTAssertEqual(stackQuery.count, 0, "Wide window \(label(size)) still exposes workout.detail.stack")
        } else {
            XCTAssertEqual(stackQuery.count, 1, "Portrait window \(label(size)) did not select workout.detail.stack. probe=\(probeValue(app))")
            XCTAssertEqual(wideQuery.count, 0, "Portrait window \(label(size)) still exposes workout.detail.wide")
        }
    }

    private func assertFixture(_ app: XCUIApplication) {
        let steps = unique(app, "workout.detail.planSteps").value as? String ?? ""
        XCTAssertEqual(steps.split(separator: ",").map(String.init), fixture, "Fixture set mismatch. steps=\(steps)")
    }

    private func probeValue(_ app: XCUIApplication) -> String {
        let query = app.descendants(matching: .any).matching(identifier: "page.workoutDetail")
        guard query.count == 1 else { return "matches=\(query.count)" }
        return query.firstMatch.value as? String ?? "nil"
    }

    private func axWindow(_ app: XCUIApplication) -> CGSize {
        app.windows.firstMatch.frame.size
    }

    private func label(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    private func same(_ probe: String, _ size: CGSize) -> Bool {
        let parts = probe.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return false }
        return abs(parts[0] - size.width) < 1.5 && abs(parts[1] - size.height) < 1.5
    }

    private func moved(_ size: CGSize, from initial: CGSize) -> Bool {
        abs(size.width - initial.width) > 2 || abs(size.height - initial.height) > 2
    }

    private func isDuoInner(_ size: CGSize) -> Bool {
        let short = min(size.width, size.height)
        let long = max(size.width, size.height)
        return abs(short - 669) < 40 && abs(long - 951) < 40
    }

    private func unique(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertEqual(query.count, 1, "\(identifier) matched \(query.count) elements")
        return query.firstMatch
    }

    private func assertLastRowClearsStart(_ app: XCUIApplication) {
        // The list id is a 1×1 probe. Swiping it does not scroll, and an id on
        // the Form is copied onto the collection view (two matches).
        _ = unique(app, "workout.detail.list")
        let start = unique(app, "workout.start")
        var last = app.descendants(matching: .any).matching(identifier: "workout.exercise.last").firstMatch
        var swipes = 0
        while swipes < 12 {
            if clears(last, start) {
                capture(app, "plan-detail-scrolled")
                return
            }
            scrollExerciseList(app, above: start)
            swipes += 1
            last = app.descendants(matching: .any).matching(identifier: "workout.exercise.last").firstMatch
        }
        capture(app, "plan-detail-overlap")
        attachHierarchy(app, "hierarchy-overlap")
        XCTAssertTrue(last.exists, "Last exercise was not materialized after scrolling")
        XCTAssertTrue(clears(last, start), "Start covers the last row. last=\(last.frame) start=\(start.frame)")
    }

    /// Drag the lowest exercise row that sits fully above Start.
    /// `workout.exercise.last` at y=567 is under Start at y=579, so a drag
    /// from 20% down that row begins on the button and the list does not move.
    private func scrollExerciseList(_ app: XCUIApplication, above start: XCUIElement) {
        guard start.frame.isUsable else {
            XCTFail("Start frame is not usable: \(start.frame)")
            return
        }
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.exercise."))
        let candidates = rows.allElementsBoundByIndex.filter { element in
            let frame = element.frame
            guard element.exists, frame.isUsable, frame.minY > 80 else { return false }
            let touchY = frame.minY + frame.height * 0.2
            return frame.maxY <= start.frame.minY + 1 && touchY + 8 < start.frame.minY
        }
        guard let row = candidates.last else {
            XCTFail("No visible exercise row is fully above Start at \(start.frame). Not dragging workout.exercise.last.")
            return
        }
        let origin = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: -280)))
    }

    private func clears(_ last: XCUIElement, _ start: XCUIElement) -> Bool {
        guard last.exists, start.exists else { return false }
        let lastFrame = last.frame
        let startFrame = start.frame
        guard lastFrame.isUsable, startFrame.isUsable else { return false }
        return lastFrame.minY >= 0 && lastFrame.maxY <= startFrame.minY + 1
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func attachHierarchy(_ app: XCUIApplication, _ name: String) {
        let text = XCTAttachment(string: app.debugDescription)
        text.name = name
        text.lifetime = .keepAlways
        add(text)
    }
}

private extension CGRect {
    var isUsable: Bool {
        [origin.x, origin.y, size.width, size.height].allSatisfy(\.isFinite)
            && width > 1 && height > 1
    }
}
