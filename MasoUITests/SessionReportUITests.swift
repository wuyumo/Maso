import XCTest

/// Acceptance for the finished-session report sheet. Duration and heart rate
/// open in place; the older full report page is not part of this flow.
@MainActor
final class SessionReportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCleanFinishOpensSessionReportNotTheOldCompletionPage() throws {
        let app = launch("session-report-clean-player")
        let report = try require("workout.sessionReport", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["workout.saveChanges"].exists)
        XCTAssertFalse(app.staticTexts["Workout complete"].exists)
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
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.descendants(matching: .any)["workout.sessionReport"].exists)

        keepShot(app, "report-sheet-first")
        let spark = app.descendants(matching: .any)["workout.sessionReport.spark.bench_press_barbell"]
        for _ in 0..<4 where !spark.isHittable { app.swipeUp() }
        keepShot(app, "report-finish-scrolled-to-bench-heart")

        let heartRow = revealAbove("workout.sessionReport.heartTable", control: "workout.sessionReport.share", in: app)
        let share = app.buttons["workout.sessionReport.share"]
        XCTAssertTrue(heartRow.exists)
        XCTAssertLessThanOrEqual(heartRow.frame.maxY, share.frame.minY + 1, "last row \(heartRow.frame) share \(share.frame)")
        keepShot(app, "report-sheet-share-over-last-row")

        let sheets = app.sheets.count
        let bars = app.navigationBars.count
        let duration = app.descendants(matching: .any)["workout.sessionReport.duration"]
        duration.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.durationTable"].waitForExistence(timeout: 5))
        XCTAssertTrue(matchingPrefix("workout.report.exercise.", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport.heartTableBody"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.report.heart"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.report"].exists)
        XCTAssertEqual(app.sheets.count, sheets)
        XCTAssertEqual(app.navigationBars.count, bars)
        keepShot(app, "report-duration-expanded")
        duration.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.durationTable"].waitForNonExistence(timeout: 5))
        keepShot(app, "report-duration-collapsed")

        let heart = app.descendants(matching: .any)["workout.sessionReport.heartTable"]
        heart.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.heartTableBody"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout.report.heart"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport.durationTable"].exists)
        XCTAssertFalse(matchingPrefix("workout.report.exercise.", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.report"].exists)
        XCTAssertEqual(app.sheets.count, sheets)
        XCTAssertEqual(app.navigationBars.count, bars)
        keepShot(app, "report-heart-expanded")
        heart.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.heartTableBody"].waitForNonExistence(timeout: 5))
        keepShot(app, "report-heart-collapsed")
        XCTAssertTrue(report.exists)
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
        XCTAssertTrue(skipped.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 30))
        XCTAssertTrue(skipped.buttons["workout.sessionReport.exit"].exists)
        XCTAssertTrue(skipped.descendants(matching: .any)["workout.saveChanges"].waitForNonExistence(timeout: 8))
        XCTAssertFalse(skipped.staticTexts["Workout complete"].exists)
        skipped.terminate()

        let saved = launch("session-report-changed-player")
        let save = saved.buttons["workout.saveChanges.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        XCTAssertEqual(saved.staticTexts["workout.saveChanges.title"].label, "Save changes to this workout plan?")
        save.tap()
        XCTAssertTrue(saved.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 30))
        XCTAssertTrue(saved.buttons["workout.sessionReport.exit"].exists)
        XCTAssertTrue(saved.descendants(matching: .any)["workout.saveChanges"].waitForNonExistence(timeout: 8))
        XCTAssertFalse(saved.staticTexts["Workout complete"].exists)
    }

    func testShareDefaultsStayPrivateAndBackReturnsToTheReport() throws {
        let app = launch("session-report-clean-player")
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 30))
        app.buttons["workout.sessionReport.share"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.sharePreview"].waitForExistence(timeout: 8))
        let shareStats = app.descendants(matching: .any)["workout.sessionReport.shareStats"]
        XCTAssertTrue(shareStats.waitForExistence(timeout: 5))
        XCTAssertTrue(shareStats.staticTexts["Work time"].exists)
        XCTAssertTrue(shareStats.staticTexts["Sets"].exists)
        XCTAssertTrue(shareStats.staticTexts["Volume"].exists)
        XCTAssertTrue(shareStats.staticTexts["0:40"].exists)
        XCTAssertTrue(shareStats.staticTexts["480 kg"].exists)
        assertOff("workout.sessionReport.shareDetailsToggle", in: app)
        assertOff("workout.sessionReport.shareHeartToggle", in: app)
        XCTAssertTrue(matchingPrefix("workout.sessionReport.shareSummary.", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareDetails.", in: app).exists)
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareSpark.", in: app).exists)
        keepShot(app, "share-default-scroll-top")
        let heartToggle = revealAbove("workout.sessionReport.shareHeartToggle", control: "workout.sessionReport.shareSend", in: app)
        let send = app.buttons["workout.sessionReport.shareSend"]
        XCTAssertTrue(heartToggle.exists)
        XCTAssertLessThanOrEqual(heartToggle.frame.maxY, send.frame.minY + 1, "share toggle \(heartToggle.frame) send \(send.frame)")
        keepShot(app, "share-send-over-last-row")

        let heart = app.switches["workout.sessionReport.shareHeartToggle"]
        heart.tap()
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        let heartValue = String(describing: heart.value ?? "")
        XCTAssertTrue(heartValue == "1" || heartValue == "on", "heart toggle stayed \(heartValue)")
        XCTAssertTrue(matchingPrefix("workout.sessionReport.shareDetails.", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.shareSpark.bench_press_barbell"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareSummary.", in: app).exists)
        // XCTNSPredicateExpectation only rechecks existence for an XCUIElement.
        // frame.minY is not key-value coding on that element, so the predicate stays
        // false while a later Swift read of the same frame reports the real rect.
        let shareBody = app.images["workout.sessionReport.shareBody"]
        let frame = waitForShareBodyAtTop(shareBody, timeout: 3)
        XCTAssertGreaterThan(frame.minY, 0)
        XCTAssertLessThan(frame.minY, 220)
        XCTAssertGreaterThan(frame.height, 300, "share body \(frame)")
        keepShot(app, "share-heart-scroll-top")
        let shareSpark = app.descendants(matching: .any)["workout.sessionReport.shareSpark.bench_press_barbell"]
        let preview = app.descendants(matching: .any)["workout.sessionReport.sharePreview"]
        for _ in 0..<4 where !shareSpark.isHittable { preview.swipeUp() }
        keepShot(app, "share-heart-scrolled-to-spark")

        app.buttons["workout.sessionReport.shareBack"].tap()
        XCTAssertTrue(app.buttons["workout.sessionReport.exit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.sharePreview"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout.sessionReport.shareSend"].exists)
        XCTAssertFalse(app.buttons["workout.sessionReport.info"].exists)
        keepShot(app, "share-back-to-report")
    }

    func testFinishExitLeavesTheReportAndHistoryUsesBack() throws {
        let finished = launch("session-report-clean-player")
        let exit = finished.buttons["workout.sessionReport.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 30))
        exit.tap()
        XCTAssertTrue(finished.staticTexts["Exercise UI test"].waitForExistence(timeout: 8))
        XCTAssertTrue(finished.buttons["workout.sessionReport.exit"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(finished.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 8))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(finished.descendants(matching: .any)["workout.sessionReport"].exists)
        finished.terminate()

        let swiped = launch("session-report-clean-player")
        XCTAssertTrue(swiped.buttons["workout.sessionReport.exit"].waitForExistence(timeout: 30))
        swiped.navigationBars["Workout report"].swipeDown()
        XCTAssertTrue(swiped.staticTexts["Exercise UI test"].waitForExistence(timeout: 8))
        XCTAssertTrue(swiped.buttons["workout.sessionReport.exit"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(swiped.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 8))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(swiped.staticTexts["Exercise UI test"].exists)
        XCTAssertFalse(swiped.descendants(matching: .any)["workout.sessionReport"].exists)
        swiped.terminate()

        let history = launch("session-report-history")
        let open = history.buttons["workout.sessionReport.openHistory"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        let hostSheets = history.sheets.count
        open.tap()
        XCTAssertTrue(history.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(history.sheets.count, hostSheets)
        XCTAssertFalse(history.buttons["workout.sessionReport.exit"].exists)
        XCTAssertFalse(history.buttons["workout.sessionReport.info"].exists)
        XCTAssertTrue(history.buttons["workout.sessionReport.share"].exists)
        let back = history.buttons["workout.sessionReport.historyBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(history.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(history.sheets.count, hostSheets)
        XCTAssertTrue(history.navigationBars["History"].exists)
    }

    func testFinishHeaderStaysApartInNarrowLightLargeAndChinese() {
        let cases: [(String, String, [String: String], [String])] = [
            ("zh-scroll-top", "zh-Hans", [:], []),
            ("light-scroll-top", "en", ["MASO_TEST_COLOR_SCHEME": "light"], []),
            ("narrow-scroll-top", "en", ["MASO_TEST_NARROW": "1"], []),
            ("large-scroll-top", "en", ["MASO_TEST_LARGE_TYPE": "1"], [])
        ]
        for (name, language, extra, arguments) in cases {
            let app = launch("session-report-clean-player", language: language, extra: extra, moreArguments: arguments)
            let title = language == "zh-Hans" ? "训练报告" : "Workout report"
            let bar = app.navigationBars[title]
            let exit = app.buttons["workout.sessionReport.exit"]
            XCTAssertTrue(bar.waitForExistence(timeout: 30), name)
            XCTAssertFalse(app.buttons["workout.sessionReport.info"].exists, name)
            XCTAssertFalse(app.staticTexts["workout.sessionReport.counting"].exists, name)
            XCTAssertTrue(exit.exists, name)
            XCTAssertGreaterThanOrEqual(exit.frame.height, 44, name)
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
    }

    func testShareExportWritesTheReportCardAndDoesNotOpenTheSystemSheet() {
        let app = launch("session-report-clean-player", extra: ["MASO_SESSION_REPORT_EXPORT": "1"])
        XCTAssertTrue(app.buttons["workout.sessionReport.share"].waitForExistence(timeout: 30))
        app.buttons["workout.sessionReport.share"].tap()
        app.buttons["workout.sessionReport.shareSend"].tap()
        XCTAssertTrue(app.staticTexts["workout.sessionReport.shareExported"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["workout.sessionReport.shareBack"].exists)
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
