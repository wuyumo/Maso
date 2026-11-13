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

        keepShot(app, "report-finish-scroll-top")
        let spark = app.descendants(matching: .any)["workout.sessionReport.spark.bench_press_barbell"]
        for _ in 0..<4 where !spark.isHittable { app.swipeUp() }
        keepShot(app, "report-finish-scrolled-to-bench-heart")

        app.buttons["workout.sessionReport.info"].tap()
        XCTAssertTrue(app.navigationBars["How this is counted"].waitForExistence(timeout: 5))
        let counting = app.staticTexts["workout.sessionReport.counting"]
        XCTAssertTrue(counting.waitForExistence(timeout: 5))
        XCTAssertEqual(counting.label, "Green is this workout's relative training, not recovery over time. The three numbers are work time, completed sets, and loaded volume. Loaded volume is external weight times reps and each completed set is counted once. The number on a muscle is 1.0 for the main muscle and 0.4 for a muscle that assists; it is not kilograms. Bodyweight and timed sets are not converted to weight. Cardio is not drawn on the body. Heart-rate lines follow the timed parts of a set and break across pauses, rest, and gaps over 20 seconds. Saving routine changes updates the next plan only.")
        keepShot(app, "counting-sheet")
        app.buttons["workout.sessionReport.countingClose"].tap()
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

        app.switches["workout.sessionReport.shareHeartToggle"].tap()
        XCTAssertTrue(matchingPrefix("workout.sessionReport.shareDetails.", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.shareSpark.bench_press_barbell"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchingPrefix("workout.sessionReport.shareSummary.", in: app).exists)
        let shareBody = app.descendants(matching: .any)["workout.sessionReport.shareBody"]
        XCTAssertTrue(shareBody.waitForExistence(timeout: 5))
        let backAtTop = NSPredicate(format: "exists == true AND hittable == true AND frame.minY < 220")
        let top = XCTNSPredicateExpectation(predicate: backAtTop, object: shareBody)
        XCTAssertEqual(XCTWaiter().wait(for: [top], timeout: 3), .completed, "share body minY \(shareBody.frame.minY) after scrollTo top")
        keepShot(app, "share-heart-scroll-top")
        let shareSpark = app.descendants(matching: .any)["workout.sessionReport.shareSpark.bench_press_barbell"]
        let preview = app.descendants(matching: .any)["workout.sessionReport.sharePreview"]
        for _ in 0..<4 where !shareSpark.isHittable { preview.swipeUp() }
        keepShot(app, "share-heart-scrolled-to-spark")

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
        XCTAssertTrue(finished.descendants(matching: .any)["workout.sessionReport"].waitForNonExistence(timeout: 8))
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

    func testFinishHeaderStaysApartInNarrowLightLargeAndChinese() {
        let cases: [(String, String, [String: String], [String])] = [
            ("zh-scroll-top", "zh-Hans", [:], []),
            ("light-scroll-top", "en", ["MASO_TEST_COLOR_SCHEME": "light"], []),
            ("narrow-scroll-top", "en", ["MASO_TEST_NARROW": "1"], []),
            ("large-scroll-top", "en", ["MASO_TEST_LARGE_TYPE": "1"], [])
        ]
        for (name, language, extra, arguments) in cases {
            let app = launch("session-report-clean-player", language: language, extra: extra, moreArguments: arguments)
            let info = app.buttons["workout.sessionReport.info"]
            let title = app.staticTexts["workout.sessionReport.heading"]
            let exit = app.buttons["workout.sessionReport.exit"]
            XCTAssertTrue(title.waitForExistence(timeout: 30), name)
            XCTAssertEqual(info.label, language == "zh-Hans" ? "统计说明" : "How this is counted")
            XCTAssertLessThanOrEqual(info.frame.maxX, title.frame.minX + 1, name)
            XCTAssertGreaterThanOrEqual(exit.frame.minX, title.frame.maxX - 1, name)
            XCTAssertGreaterThanOrEqual(info.frame.height, 44, name)
            XCTAssertGreaterThanOrEqual(exit.frame.height, 44, name)
            if extra["MASO_TEST_LARGE_TYPE"] == "1" {
                let bench = app.staticTexts["workout.sessionReport.exerciseName.chest.bench_press_barbell"]
                XCTAssertTrue(bench.waitForExistence(timeout: 5), name)
                XCTAssertEqual(bench.label, "Bench Press (Barbell)")
                XCTAssertGreaterThan(bench.frame.height, 34, "accessibility3 chest name was \(bench.frame.height)pt")
                let metrics = XCTAttachment(string: "chestNameHeight=\(bench.frame.height) titleHeight=\(title.frame.height) infoHeight=\(info.frame.height)")
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
