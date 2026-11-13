import XCTest

/// Acceptance for the finished-session report. History tests that stop on
/// `workout.report` still cover the older duration and heart-rate tables.
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
        XCTAssertFalse(app.descendants(matching: .any)["workout.report"].exists)

        app.buttons["workout.sessionReport.info"].tap()
        XCTAssertTrue(app.staticTexts["Report counting explanation"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(report.waitForExistence(timeout: 5))

        let duration = app.buttons["workout.sessionReport.duration"]
        for _ in 0..<6 where !duration.isHittable { app.swipeUp() }
        XCTAssertTrue(duration.isHittable)
        duration.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.report"].waitForExistence(timeout: 8))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["workout.report"].exists)
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
        assertOff("workout.sessionReport.shareDetailsToggle", in: app)
        assertOff("workout.sessionReport.shareHeartToggle", in: app)
        XCTAssertTrue(matchingPrefix("workout.sessionReport.shareSummary.", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareDetails.", in: app).exists)
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareSpark.", in: app).exists)

        app.switches["workout.sessionReport.shareHeartToggle"].tap()
        XCTAssertTrue(matchingPrefix("workout.sessionReport.shareDetails.", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.shareSpark.bench_press_barbell"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareSummary.", in: app).exists)

        app.buttons["workout.sessionReport.shareBack"].tap()
        XCTAssertTrue(app.buttons["workout.sessionReport.exit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.sharePreview"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout.sessionReport.shareSend"].exists)
    }

    func testFinishExitLeavesTheReportAndHistoryUsesBack() throws {
        let finished = launch("session-report-clean-player")
        let exit = finished.buttons["workout.sessionReport.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 30))
        exit.tap()
        XCTAssertTrue(finished.staticTexts["Exercise UI test"].waitForExistence(timeout: 8))
        XCTAssertTrue(finished.buttons["workout.sessionReport.exit"].waitForNonExistence(timeout: 8))
        finished.terminate()

        let history = launch("session-report-history")
        let open = history.buttons["workout.sessionReport.openHistory"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()
        XCTAssertTrue(history.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 10))
        XCTAssertFalse(history.buttons["workout.sessionReport.exit"].exists)
        XCTAssertTrue(history.buttons["workout.sessionReport.info"].exists)
        XCTAssertTrue(history.buttons["workout.sessionReport.share"].exists)
        let back = history.buttons["workout.sessionReport.historyBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(history.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 5))
    }

    private func launch(_ scene: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
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

    private func assertOff(_ identifier: String, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), identifier)
        let value = String(describing: toggle.value ?? "")
        XCTAssertTrue(value == "0" || value == "off", "\(identifier) started at \(value)")
    }
}
