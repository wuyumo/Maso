import XCTest

/// Acceptance for the finished-session report sheet. Duration and heart rate
/// open in place; the older full report page is not part of this flow.
@MainActor
final class SessionReportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCleanFinishShowsCelebrationBeforeTheReport() throws {
        let app = launch("session-report-clean-player")
        XCTAssertFalse(app.descendants(matching: .any)["workout.saveChanges"].exists)
        XCTAssertTrue(app.staticTexts["Workout complete"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport"].exists)
        openReportFromCelebration(app)
        let report = try require("workout.sessionReport", in: app)
        XCTAssertTrue(app.buttons["workout.sessionReport.exit"].exists)
        XCTAssertTrue(app.buttons["workout.sessionReport.share"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.body"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.stats"].exists)
        XCTAssertTrue(app.staticTexts["0:40"].exists)
        XCTAssertTrue(app.staticTexts["480 kg"].exists)
        XCTAssertTrue(app.buttons["workout.sessionReport.muscle.chest"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.exercise.bench_press_barbell"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.spark.bench_press_barbell"].exists)
        XCTAssertFalse(app.staticTexts["No heart rate"].exists)
        XCTAssertFalse(app.staticTexts["Timing incomplete"].exists)
        XCTAssertFalse(app.buttons["workout.sessionReport.info"].exists)
        XCTAssertFalse(app.staticTexts["workout.sessionReport.counting"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.report"].exists)

        keepShot(app, "report-sheet-first")
        let spark = app.descendants(matching: .any)["workout.sessionReport.spark.bench_press_barbell"]
        for _ in 0..<4 where !spark.isHittable { app.swipeUp() }
        keepShot(app, "report-finish-scrolled-to-bench-heart")

        let heartRow = revealButton("workout.sessionReport.heartTable", control: "workout.sessionReport.share", in: app)
        let share = app.buttons["workout.sessionReport.share"]
        XCTAssertEqual(identifierCount("workout.sessionReport.heartTable", in: app), 1)
        XCTAssertTrue(heartRow.exists)
        XCTAssertLessThanOrEqual(heartRow.frame.maxY, share.frame.minY + 1, "last row \(heartRow.frame) share \(share.frame)")
        keepShot(app, "report-sheet-share-over-last-row")

        let grabbers = sheetGrabbers(in: app).count
        let bars = app.navigationBars.count
        let duration = app.buttons["workout.sessionReport.duration"]
        XCTAssertEqual(identifierCount("workout.sessionReport.duration", in: app), 1)
        duration.tap()
        XCTAssertTrue(app.otherElements["workout.sessionReport.durationTable"].waitForExistence(timeout: 5))
        XCTAssertEqual(identifierCount("workout.sessionReport.durationTable", in: app), 1)
        XCTAssertEqual(identifierCount(prefix: "workout.report.exercise.", in: app), 1)
        keepShot(app, "report-duration-expanded")
        XCTAssertEqual(identifierCount("workout.sessionReport.heartTableBody", in: app), 0)
        XCTAssertEqual(identifierCount("workout.report.heart", in: app), 0)
        XCTAssertEqual(identifierCount("workout.report", in: app), 0)
        XCTAssertGreaterThan(grabbers, 0)
        XCTAssertEqual(sheetGrabbers(in: app).count, grabbers)
        XCTAssertEqual(app.navigationBars.count, bars)
        let durationTable = app.otherElements["workout.sessionReport.durationTable"]
        let durationRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.report.exercise.")).element(boundBy: 0)
        showAboveShare(durationTable, in: app, name: "report-duration-above-share")
        let reportBar = app.navigationBars["Workout report"]
        XCTAssertGreaterThanOrEqual(durationRow.frame.minY, reportBar.frame.maxY - 1)
        XCTAssertLessThanOrEqual(durationRow.frame.maxY, share.frame.minY + 1, "duration row \(durationRow.frame) share \(share.frame)")
        XCTAssertEqual(sheetGrabbers(in: app).count, grabbers)
        tapOnScreen(duration, scrolling: durationTable)
        XCTAssertEqual(identifierCount("workout.sessionReport.durationTable", in: app), 0)
        keepShot(app, "report-duration-collapsed")

        let heart = app.buttons["workout.sessionReport.heartTable"]
        heart.tap()
        XCTAssertTrue(app.otherElements["workout.sessionReport.heartTableBody"].waitForExistence(timeout: 5))
        XCTAssertEqual(identifierCount("workout.sessionReport.heartTableBody", in: app), 1)
        XCTAssertEqual(identifierCount("workout.report.heart", in: app), 1)
        keepShot(app, "report-heart-expanded")
        XCTAssertEqual(identifierCount("workout.sessionReport.durationTable", in: app), 0)
        XCTAssertEqual(identifierCount(prefix: "workout.report.exercise.", in: app), 0)
        XCTAssertEqual(identifierCount("workout.report", in: app), 0)
        XCTAssertEqual(sheetGrabbers(in: app).count, grabbers)
        XCTAssertEqual(app.navigationBars.count, bars)
        let heartBody = app.otherElements["workout.sessionReport.heartTableBody"]
        let heartChart = app.descendants(matching: .any).matching(identifier: "workout.report.heart").element(boundBy: 0)
        showAboveShare(heartBody, in: app, name: "report-heart-above-share")
        let heartBar = app.navigationBars["Workout report"].frame.maxY
        let heartShare = app.buttons["workout.sessionReport.share"].frame.minY
        if heartBody.frame.minY >= heartBar - 1, heartBody.frame.maxY <= heartShare + 1 {
            XCTAssertGreaterThanOrEqual(heartChart.frame.minY, heartBar - 1)
            XCTAssertLessThanOrEqual(heartChart.frame.maxY, heartShare + 1, "heart chart \(heartChart.frame) share \(heartShare)")
        }
        XCTAssertEqual(sheetGrabbers(in: app).count, grabbers)
        tapOnScreen(heart, scrolling: heartBody)
        XCTAssertEqual(identifierCount("workout.sessionReport.heartTableBody", in: app), 0)
        XCTAssertEqual(identifierCount("workout.report.heart", in: app), 0)
        keepShot(app, "report-heart-collapsed")
        XCTAssertTrue(report.exists)
        assertExpandedSheet(titled: "Workout report", in: app)
    }

    func testAdjustedFinishReachesTheReportAfterSkipAndAfterSave() throws {
        let skipped = launch("session-report-changed-player")
        let title = skipped.staticTexts["workout.saveChanges.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(title.label, "Save changes to this workout plan?")
        XCTAssertEqual(skipped.buttons["workout.saveChanges.save"].label, "Save to Workout Plan")
        let skip = skipped.buttons["workout.saveChanges.skip"]
        XCTAssertEqual(skip.label, "Don't save")
        XCTAssertTrue(skipped.descendants(matching: .any)["workout.saveChanges.row.step-bench"].exists)
        XCTAssertTrue(skipped.staticTexts["2 × 8 · 62.5 kg"].exists)
        XCTAssertFalse(skipped.descendants(matching: .any)["workout.sessionReport"].exists)
        skip.tap()
        XCTAssertTrue(skipped.staticTexts["Workout complete"].waitForExistence(timeout: 30))
        XCTAssertFalse(skipped.descendants(matching: .any)["workout.sessionReport"].exists)
        openReportFromCelebration(skipped)
        XCTAssertTrue(skipped.buttons["workout.sessionReport.exit"].exists)
        XCTAssertTrue(skipped.descendants(matching: .any)["workout.saveChanges"].waitForNonExistence(timeout: 8))
        skipped.terminate()

        let saved = launch("session-report-changed-player")
        let save = saved.buttons["workout.saveChanges.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        XCTAssertEqual(saved.staticTexts["workout.saveChanges.title"].label, "Save changes to this workout plan?")
        save.tap()
        XCTAssertTrue(saved.staticTexts["Workout complete"].waitForExistence(timeout: 30))
        XCTAssertFalse(saved.descendants(matching: .any)["workout.sessionReport"].exists)
        openReportFromCelebration(saved)
        XCTAssertTrue(saved.buttons["workout.sessionReport.exit"].exists)
        XCTAssertTrue(saved.descendants(matching: .any)["workout.saveChanges"].waitForNonExistence(timeout: 8))
    }

    func testShareDefaultsStayPrivateAndBackReturnsToTheReport() throws {
        let app = launch("session-report-clean-player")
        openReportFromCelebration(app)
        let setLines = recordedSetLines(in: app)
        XCTAssertEqual(setLines.count, 3, "The logged set stays visible on every muscle it trained")
        let setLabel = setLines.element(boundBy: 0).label
        for index in 0..<setLines.count {
            XCTAssertEqual(setLines.element(boundBy: index).label, setLabel)
        }
        let shareText = app.staticTexts["workout.sessionReport.shareText"]
        XCTAssertTrue(shareText.waitForExistence(timeout: 5))
        XCTAssertFalse(shareText.label.contains(setLabel), "viewing the set is not permission to export it")
        XCTAssertFalse(shareText.label.contains("No heart rate"))
        XCTAssertFalse(shareText.label.contains("photo"))
        XCTAssertTrue(shareText.label.contains("0:40"))
        XCTAssertTrue(shareText.label.contains("480 kg"))
        assertOff("workout.sessionReport.shareDetailsToggle", in: app)
        assertOff("workout.sessionReport.shareHeartToggle", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport.sharePreview"].exists)
        XCTAssertEqual(sessionEndCount(app), "0")

        turnOnAboveShare("workout.sessionReport.shareDetailsToggle", in: app)
        turnOnAboveShare("workout.sessionReport.shareHeartToggle", in: app)
        XCTAssertTrue(waitUntil(shareText) { $0.contains(setLabel) })
        XCTAssertTrue(waitUntil(shareText) { $0.contains("130") })
        app.buttons["workout.sessionReport.share"].tap()
        XCTAssertTrue(app.buttons["workout.sessionReport.exit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport.sharePreview"].exists)
        XCTAssertEqual(sessionEndCount(app), "0")
        keepShot(app, "share-scope-on-report")
    }

    func testFinishExitLeavesTheReportAndHistoryUsesBack() throws {
        let finished = launch("session-report-clean-player")
        openReportFromCelebration(finished)
        let exit = finished.buttons["workout.sessionReport.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 30))
        XCTAssertEqual(sessionEndCount(finished), "0")
        exit.tap()
        XCTAssertTrue(finished.staticTexts["Exercise UI test"].waitForExistence(timeout: 8))
        XCTAssertTrue(finished.buttons["workout.sessionReport.exit"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(finished.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 8))
        XCTAssertEqual(sessionEndCount(finished), "1")
        XCTAssertEqual(sessionLiveness(finished), "none")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(sessionEndCount(finished), "1")
        XCTAssertFalse(finished.descendants(matching: .any)["workout.sessionReport"].exists)
        finished.terminate()

        let swiped = launch("session-report-clean-player")
        openReportFromCelebration(swiped)
        XCTAssertEqual(sessionEndCount(swiped), "0")
        let grabber = swiped.buttons.matching(NSPredicate(format: "label == %@", "Sheet Grabber")).firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        let origin = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(swiped.staticTexts["Workout complete"].waitForExistence(timeout: 8))
        XCTAssertTrue(swiped.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 8))
        XCTAssertEqual(sessionEndCount(swiped), "0")
        swiped.buttons["workout.completed.exit"].tap()
        XCTAssertTrue(swiped.staticTexts["Exercise UI test"].waitForExistence(timeout: 8))
        XCTAssertEqual(sessionEndCount(swiped), "1")
        XCTAssertEqual(sessionLiveness(swiped), "none")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(sessionEndCount(swiped), "1")
        XCTAssertFalse(swiped.descendants(matching: .any)["workout.sessionReport"].exists)
        XCTAssertFalse(swiped.staticTexts["Workout complete"].exists)
        swiped.terminate()

        let history = launch("session-report-history")
        let open = history.buttons["workout.sessionReport.openHistory"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        XCTAssertEqual(sessionEndCount(history), "0")
        XCTAssertEqual(sessionLiveness(history), "live")
        open.tap()
        XCTAssertTrue(history.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 10))
        assertExpandedSheet(titled: "Workout report", in: history)
        XCTAssertFalse(history.buttons["workout.sessionReport.exit"].exists)
        XCTAssertFalse(history.buttons["workout.sessionReport.info"].exists)
        XCTAssertTrue(history.buttons["workout.sessionReport.share"].exists)
        let back = history.buttons["workout.sessionReport.historyBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(history.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 5))
        assertExpandedSheet(titled: "History", in: history)
        XCTAssertEqual(sessionEndCount(history), "0")
        XCTAssertEqual(sessionLiveness(history), "live")
    }

    func testFinishHeaderStaysApartInNarrowLightLargeAndChinese() {
        let cases: [(String, String, [String: String], [String])] = [
            ("zh-scroll-top", "zh-Hans", [:], []),
            ("light-scroll-top", "en", ["MASO_TEST_COLOR_SCHEME": "light"], []),
            ("narrow-scroll-top", "en", ["MASO_TEST_NARROW": "1"], []),
            ("large-scroll-top", "en", ["MASO_TEST_LARGE_TYPE": "1"], [])
        ]
        continueAfterFailure = true
        for (name, language, extra, arguments) in cases {
            let app = launch("session-report-clean-player", language: language, extra: extra, moreArguments: arguments)
            openReportFromCelebration(app)
            let title = language == "zh-Hans" ? "训练报告" : "Workout report"
            let bar = app.navigationBars[title]
            let exit = app.buttons["workout.sessionReport.exit"]
            XCTAssertTrue(bar.waitForExistence(timeout: 30), name)
            XCTAssertFalse(app.buttons["workout.sessionReport.info"].exists, name)
            XCTAssertFalse(app.staticTexts["workout.sessionReport.counting"].exists, name)
            XCTAssertTrue(exit.waitForExistence(timeout: 5), name)
            XCTAssertGreaterThanOrEqual(exit.frame.height, 44, "\(name) exit height \(exit.frame.height)")
            if extra["MASO_TEST_LARGE_TYPE"] == "1" {
                let bench = app.staticTexts["workout.sessionReport.exerciseName.chest.bench_press_barbell"]
                XCTAssertTrue(bench.waitForExistence(timeout: 5), name)
                XCTAssertEqual(bench.label, "Bench Press (Barbell)")
                XCTAssertGreaterThan(bench.frame.height, 34, "accessibility3 chest name was \(bench.frame.height)pt")
                let metrics = XCTAttachment(string: "chestNameHeight=\(bench.frame.height) titleHeight=\(bar.frame.height) exitHeight=\(exit.frame.height)")
                metrics.name = "large-type-metrics"
                metrics.lifetime = .keepAlways
                add(metrics)
            }
            keepShot(app, "report-header-\(name)")
            app.terminate()
        }
        continueAfterFailure = false
    }

    func testShareExportWritesDefaultHeartAndPhotoBitmapsWithoutSending() throws {
        let app = launch("session-report-clean-player", extra: [
            "MASO_SESSION_REPORT_EXPORT": "1",
            "MASO_SESSION_REPORT_PHOTO": "1"
        ])
        openReportFromCelebration(app)
        let shareText = app.staticTexts["workout.sessionReport.shareText"]
        XCTAssertTrue(shareText.waitForExistence(timeout: 8))
        let photo = app.switches["workout.sessionReport.sharePhotoToggle"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertFalse(switchIsOn(photo))
        let baseline = shareText.label
        XCTAssertTrue(baseline.contains("0:40"))
        XCTAssertTrue(baseline.contains("480 kg"))
        XCTAssertFalse(baseline.contains("×"))
        XCTAssertFalse(baseline.contains("130"))
        XCTAssertFalse(baseline.contains("photo"))
        app.buttons["workout.sessionReport.share"].tap()
        try attachOriginalExport("session-report-default.png", in: app)
        XCTAssertFalse(app.buttons["workout.sessionReport.shareBack"].exists)

        turnOnAboveShare("workout.sessionReport.shareHeartToggle", in: app)
        XCTAssertTrue(waitUntil(shareText) { $0.contains("130") && !$0.contains("×") && !$0.contains("photo") })
        app.buttons["workout.sessionReport.share"].tap()
        try attachOriginalExport("session-report-heart.png", in: app)
        XCTAssertFalse(app.buttons["workout.sessionReport.shareBack"].exists)

        turnOnAboveShare("workout.sessionReport.sharePhotoToggle", in: app)
        XCTAssertTrue(waitUntil(shareText) { $0.contains("photo") && $0.contains("130") && !$0.contains("×") })
        app.buttons["workout.sessionReport.share"].tap()
        try attachOriginalExport("session-report-heart-photo.png", in: app)
        XCTAssertFalse(app.buttons["workout.sessionReport.shareBack"].exists)
        XCTAssertEqual(sessionEndCount(app), "0")
    }

    func testShareExportWritesTheReportCardAndDoesNotOpenTheSystemSheet() {
        let app = launch("session-report-clean-player", extra: ["MASO_SESSION_REPORT_EXPORT": "1"])
        openReportFromCelebration(app)
        XCTAssertTrue(app.buttons["workout.sessionReport.share"].waitForExistence(timeout: 30))
        let shareText = app.staticTexts["workout.sessionReport.shareText"]
        XCTAssertTrue(shareText.waitForExistence(timeout: 8))
        let before = shareText.label
        XCTAssertFalse(before.contains("×"))
        turnOnAboveShare("workout.sessionReport.shareDetailsToggle", in: app)
        XCTAssertTrue(waitUntil(shareText) { $0.contains("×") })
        let opted = shareText.label
        app.buttons["workout.sessionReport.share"].tap()
        XCTAssertTrue(app.staticTexts["workout.sessionReport.shareExported"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["workout.sessionReport.shareText"].label, opted)
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport.sharePreview"].exists)
        XCTAssertEqual(sessionEndCount(app), "0")
    }

    /// Copies the original PNG bytes out of the app container immediately after that export.
    private func attachOriginalExport(_ name: String, in app: XCUIApplication) throws {
        let marker = app.staticTexts["workout.sessionReport.shareExported"]
        XCTAssertTrue(marker.waitForExistence(timeout: 8))
        XCTAssertEqual(marker.label, name)
        let file = try appDocuments().appendingPathComponent(name)
        let data = try Data(contentsOf: file)
        XCTAssertGreaterThan(data.count, 32)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func appDocuments() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "get_app_container", "booted", "com.yumowu.maso", "data"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return URL(fileURLWithPath: output, isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
    }

    private func recordedSetLines(in app: XCUIApplication) -> XCUIElementQuery {
        let lines = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.sessionReport.set."))
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 8))
        return lines
    }

    /// Scrolls the report itself until the switch is clear of the floating Share button, then turns it on.
    private func turnOnAboveShare(_ identifier: String, in app: XCUIApplication) {
        let share = app.buttons["workout.sessionReport.share"]
        let report = app.descendants(matching: .any)["workout.sessionReport"]
        let control = app.switches[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 8))
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        var clear = false
        for _ in 0..<12 {
            if switchIsClear(control, of: share) { clear = true; break }
            report.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(clear, "\(identifier) frame \(control.frame) stayed under Share \(share.frame)")
        let knob = control.switches.firstMatch
        if knob.exists, knob.isHittable { knob.tap() } else { control.tap() }
        XCTAssertTrue(waitUntilOn(control), "\(identifier) remained off after a hittable tap, value \(String(describing: control.value))")
    }

    private func switchIsClear(_ control: XCUIElement, of share: XCUIElement) -> Bool {
        guard control.exists, share.exists, control.isHittable else { return false }
        let frame = control.frame
        return frame.width > 20 && frame.height > 20 && frame.minY > 80 && frame.maxY <= share.frame.minY - 8
    }

    private func waitUntilOn(_ control: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if switchIsOn(control) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return switchIsOn(control)
    }

    private func switchIsOn(_ control: XCUIElement) -> Bool {
        func on(_ element: XCUIElement) -> Bool {
            let value = String(describing: element.value ?? "").lowercased()
            return value == "1" || value == "on"
        }
        if on(control) { return true }
        let knob = control.switches.firstMatch
        return knob.exists && on(knob)
    }

    private func waitUntil(_ element: XCUIElement, timeout: TimeInterval = 3, where match: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if match(element.label) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return match(element.label)
    }

    private func openReportFromCelebration(_ app: XCUIApplication) {
        let continueToReport = app.buttons["workout.completed.report"]
        XCTAssertTrue(continueToReport.waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport"].exists)
        continueToReport.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 15))
    }

    func testHomeStartButtonOpensThePlayer() {
        let app = launch("home-start")
        let start = app.buttons["home.startTodayWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.primary"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Workout complete"].exists)
    }

    private func launch(_ scene: String, language: String = "en", extra: [String: String] = [:], moreArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        var environment = ["MASO_EXERCISE_UI_TEST_SCENE": scene]
        extra.forEach { environment[$0.key] = $0.value }
        app.launchEnvironment = environment
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))"] + moreArguments
        app.launch()
        return app
    }

    private func require(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 30), identifier)
        return element
    }

    private func matchingPrefix(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// iOS 26 SwiftUI sheets publish a Sheet Grabber button, not XCUIElementTypeSheet.
    private func sheetGrabbers(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == %@", "Sheet Grabber"))
    }

    private func assertExpandedSheet(titled title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), title, file: file, line: line)
        let grabbers = sheetGrabbers(in: app)
        var matched = false
        for index in 0..<grabbers.count {
            let grabber = grabbers.element(boundBy: index)
            let value = String(describing: grabber.value ?? "")
            let gap = bar.frame.minY - grabber.frame.maxY
            if value.contains("Expanded"), grabber.frame.maxY <= bar.frame.minY + 12, gap < 40, gap > -30 {
                matched = true
                break
            }
        }
        XCTAssertTrue(matched, "\(title) bar \(bar.frame) expanded grabbers \(grabbers.count)", file: file, line: line)
    }

    private func sessionEndCount(_ app: XCUIApplication) -> String {
        let element = app.staticTexts["exercise.ui-test.session-end-count"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.label
    }

    private func sessionLiveness(_ app: XCUIApplication) -> String {
        let element = app.staticTexts["exercise.ui-test.session-liveness"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.label
    }

    private func identifierCount(_ identifier: String, in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(identifier: identifier).count
    }

    private func identifierCount(prefix: String, in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).count
    }

    /// Centers `swipeUp` the same way as `revealButton`, then reads frames in Swift.
    /// A table taller than the open band is shot as `-top` and `-bottom`.
    private func showAboveShare(_ element: XCUIElement, in app: XCUIApplication, name: String) {
        let share = app.buttons["workout.sessionReport.share"]
        let bar = app.navigationBars["Workout report"]
        let room = share.frame.minY - bar.frame.maxY
        if element.exists, element.frame.height > 0, element.frame.height <= room {
            revealBand(element, in: app, top: true, bottom: true)
            keepShot(app, name)
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minY, bar.frame.maxY - 1, "\(name) \(frame)")
            XCTAssertLessThanOrEqual(frame.maxY, share.frame.minY + 1, "\(name) \(frame) share \(share.frame)")
            return
        }
        revealBand(element, in: app, top: true, bottom: false)
        keepShot(app, name + "-top")
        let top = element.frame
        XCTAssertGreaterThanOrEqual(top.minY, bar.frame.maxY - 1, "\(name) top \(top)")
        XCTAssertLessThan(top.minY, share.frame.minY, "\(name) top \(top)")
        revealBand(element, in: app, top: false, bottom: true)
        keepShot(app, name + "-bottom")
        let bottom = element.frame
        XCTAssertLessThanOrEqual(bottom.maxY, share.frame.minY + 1, "\(name) bottom \(bottom) share \(share.frame)")
        XCTAssertGreaterThan(bottom.maxY, bar.frame.maxY, "\(name) bottom \(bottom)")
    }

    private func revealBand(_ element: XCUIElement, in app: XCUIApplication, top: Bool, bottom: Bool) {
        let share = app.buttons["workout.sessionReport.share"]
        let bar = app.navigationBars["Workout report"]
        for _ in 0..<8 {
            let frame = element.frame
            let topOnScreen = frame.minY >= bar.frame.maxY - 1 && frame.minY < share.frame.minY
            let bottomOnScreen = frame.maxY <= share.frame.minY + 1 && frame.maxY > bar.frame.maxY
            if element.exists, frame.height > 0, (!top || topOnScreen), (!bottom || bottomOnScreen) { return }
            if element.exists, frame.minY < bar.frame.maxY, bottomOnScreen {
                element.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTFail("\(element.identifier) stayed at \(element.frame), share \(share.frame)")
    }

    private func tapOnScreen(_ button: XCUIElement, scrolling anchor: XCUIElement) {
        for _ in 0..<6 {
            if button.isHittable {
                button.tap()
                return
            }
            anchor.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(button.isHittable, "\(button.identifier) frame \(button.frame)")
        button.tap()
    }

    private func revealButton(_ identifier: String, control: String, in app: XCUIApplication) -> XCUIElement {
        let bar = app.buttons[control]
        let element = app.buttons[identifier]
        for _ in 0..<8 {
            if element.exists, bar.exists, element.frame.maxY > 0, element.frame.maxY <= bar.frame.minY + 1 { return element }
            app.swipeUp()
        }
        return element
    }

    private func revealAbove(_ identifier: String, control: String, in app: XCUIApplication) -> XCUIElement {
        let bar = app.buttons[control]
        let element = app.descendants(matching: .any)[identifier]
        let preview = app.descendants(matching: .any)["workout.sessionReport.sharePreview"]
        for _ in 0..<8 {
            if element.exists, bar.exists, element.frame.maxY > 0, element.frame.maxY <= bar.frame.minY + 1 { return element }
            if preview.exists { preview.swipeUp() } else { app.swipeUp() }
        }
        return element
    }

    private func waitForShareBodyAtTop(_ body: XCUIElement, timeout: TimeInterval) -> CGRect {
        let start = Date()
        var frame = CGRect.null
        while Date().timeIntervalSince(start) < timeout {
            frame = body.frame
            if body.exists, frame.minY > 0, frame.minY < 220, frame.height > 300 { return frame }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return body.frame
    }

    private func keepShot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func assertOff(_ identifier: String, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), identifier)
        let value = String(describing: toggle.value ?? "")
        XCTAssertTrue(value == "0" || value == "off", "\(identifier) started at \(value)")
    }
}
