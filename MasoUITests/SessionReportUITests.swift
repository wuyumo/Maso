import XCTest

/// Native session-report contracts. Per-set/muscle accordion assertions were superseded by the Nov14 aggregate design.
@MainActor
final class SessionReportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRecordNaturalHeartSummary() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "session-report-clean-player", "MASO_PREVIEW_FIVE_EXERCISES": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openReportFromCelebration(app)
        Thread.sleep(forTimeInterval: 3)
        keepShot(app, "curves-summary-top")
        print("CURVE_MARK top \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 1)
        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 2)
        keepShot(app, "curves-summary-middle")
        print("CURVE_MARK middle \(Date().timeIntervalSince1970)")
        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 3)
        keepShot(app, "curves-summary-bottom")
        print("CURVE_MARK bottom \(Date().timeIntervalSince1970)")
        for id in ["bench_press_barbell", "barbell_row", "squat_barbell", "lateral_raise_dumbbell", "triceps_pushdown_straight_bar"] {
            XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.spark.\(id)"].exists)
        }
        app.terminate()
    }

    func testRecordFiveExercisePreview() throws {
        let ids = ["bench_press_barbell", "barbell_row", "squat_barbell", "lateral_raise_dumbbell", "triceps_pushdown_straight_bar"]
        let app = launch("stable-player", extra: ["MASO_MARKETING_PLAYER": "1",
            "MASO_MARKETING_EXERCISE_ID": ids[0], "MASO_PREVIEW_FIVE_EXERCISES": "1",
            "MASO_WORKOUT_HEART_FIXTURE": "1", "MASO_WORKOUT_HEART_CARD": "1", "MASO_TEST_HEART_BPM": "160"])
        XCTAssertTrue(app.staticTexts["160"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 4)
        print("FIVE_MARK heart_start \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 4)
        keepShot(app, "five-heart")
        app.descendants(matching: .any)["workout.playlist.toggle"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        keepShot(app, "five-heart-playlist")
        print("FIVE_MARK heart_end \(Date().timeIntervalSince1970)")
        app.terminate()

        let report = launch("session-report-clean-player", extra: ["MASO_PREVIEW_FIVE_EXERCISES": "1"])
        openReportFromCelebration(report)
        for id in ids { XCTAssertTrue(report.descendants(matching: .any)["workout.sessionReport.exercise.\(id)"].exists) }
        Thread.sleep(forTimeInterval: 2)
        keepShot(report, "five-summary-top")
        print("FIVE_MARK summary_start \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 1)
        report.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 1)
        keepShot(report, "five-summary-middle")
        report.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 2)
        keepShot(report, "five-summary-bottom")
        print("FIVE_MARK summary_end \(Date().timeIntervalSince1970)")

        report.buttons["workout.sessionReport.share"].tap()
        XCTAssertTrue(report.buttons["workout.sessionReport.previewShare"].waitForExistence(timeout: 10))
        for id in ids { XCTAssertTrue(report.descendants(matching: .any)["workout.sessionReport.sharedExercise.\(id)"].exists) }
        Thread.sleep(forTimeInterval: 2)
        keepShot(report, "five-share-top")
        print("FIVE_MARK share_start \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 1)
        report.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 2)
        keepShot(report, "five-share-bottom")
        print("FIVE_MARK share_end \(Date().timeIntervalSince1970)")
        let shared = report.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.sessionReport.sharedExercise."))
        XCTAssertEqual(shared.count, 5)
        report.terminate()
    }

    /// Opt-in real Simulator footage; deterministic demo inputs, no purchases or remote AI calls.
    func testRecordAppStorePreview() throws {
        func mark(_ name: String) { print("PREVIEW_MARK \(name) \(Date().timeIntervalSince1970)") }
        func hold(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        func showcase(_ mode: String, extra: [String: String] = [:]) {
            app.terminate()
            app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": mode,
                "MASO_MARKETING_MUSCLE": "1", "MASO_MARKETING_GYM": "1"].merging(extra) { _, new in new }
            app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            hold(5)
        }
        showcase("muscle_status")
        XCTAssertTrue(app.descendants(matching: .any)["detail.muscleBody3D"].waitForExistence(timeout: 20))
        mark("recovery_start"); hold(2)
        let model = app.descendants(matching: .any)["detail.muscleBody3D"].firstMatch
        model.coordinate(withNormalizedOffset: CGVector(dx: 0.47, dy: 0.28)).tap()
        hold(4); keepShot(app, "preview-recovery"); mark("recovery_end")
        showcase("coach_chat", extra: ["MASO_MARKETING_COACH_NAVIGATION": "plans"])
        mark("coach_start"); hold(3); app.swipeUp(velocity: .slow); hold(4)
        keepShot(app, "preview-coach"); mark("coach_end")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_MARKETING_PLAYER": "1",
            "MASO_MARKETING_EXERCISE_ID": "chest_press_machine_iso_lateral",
            "MASO_WORKOUT_HEART_FIXTURE": "1", "MASO_WORKOUT_HEART_CARD": "1", "MASO_TEST_HEART_BPM": "160"]
        app.launch(); hold(8)
        XCTAssertTrue(app.buttons["workout.primary"].waitForExistence(timeout: 20))
        mark("training_start"); hold(6); keepShot(app, "preview-training"); mark("training_end")
        let heart = app.buttons["workout.heart-rate"]
        if heart.exists { heart.tap(); hold(1) }
        mark("heart_start"); hold(6); keepShot(app, "preview-heart"); mark("heart_end")
        app.terminate()
        let report = launch("session-report-clean-player")
        openReportFromCelebration(report); hold(3)
        mark("summary_start"); hold(2); report.swipeUp(velocity: .slow); hold(3)
        keepShot(report, "preview-summary"); mark("summary_end")
        report.buttons["workout.sessionReport.share"].tap(); hold(3)
        mark("share_start"); hold(4); keepShot(report, "preview-share"); mark("share_end")
        report.terminate()
    }

    /// Targeted retake uses adopted Bench Press media rather than an unverified demo.
    func testRecordPreviewWorkoutRetake() {
        let app = launch("stable-player", extra: ["MASO_MARKETING_PLAYER": "1",
            "MASO_MARKETING_EXERCISE_ID": "bench_press_barbell", "MASO_WORKOUT_HEART_FIXTURE": "1",
            "MASO_WORKOUT_HEART_CARD": "1", "MASO_TEST_HEART_BPM": "160"])
        XCTAssertTrue(app.buttons["workout.primary"].waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 8)
        XCTAssertTrue(app.staticTexts["160"].waitForExistence(timeout: 5))
        print("PREVIEW_MARK training_start \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 7)
        keepShot(app, "retake-training")
        print("PREVIEW_MARK training_end \(Date().timeIntervalSince1970)")
        print("PREVIEW_MARK heart_start \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 6)
        keepShot(app, "retake-heart")
        print("PREVIEW_MARK heart_end \(Date().timeIntervalSince1970)")
        app.terminate()
    }

    func testImportedQRCodePreviewShowsRecordedWeightAndRepetitions() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("import-qr-preview", language: language)
            XCTAssertTrue(app.staticTexts["Push"].waitForExistence(timeout: 30))
            let value = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "60", "8")).firstMatch
            XCTAssertTrue(value.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(value.label.contains("?"))
            keepShot(app, "import-qr-parameters-\(language)")
            app.terminate()
        }
    }

    func testAggregateRowsAndNativeSharePreviewAcrossLanguages() throws {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("session-report-clean-player", language: language)
            let entry = app.buttons["workout.completed.report"]
            XCTAssertTrue(entry.waitForExistence(timeout: 30))
            XCTAssertGreaterThanOrEqual(entry.frame.height, 56)
            openReportFromCelebration(app)
            XCTAssertFalse(matchingPrefix("workout.sessionReport.muscle.", in: app).exists)
            XCTAssertFalse(matchingPrefix("workout.sessionReport.set.", in: app).exists)
            let row = try require("workout.sessionReport.exercise.bench_press_barbell", in: app)
            XCTAssertTrue(row.exists)
            if language == "en" { XCTAssertTrue(app.staticTexts["480 kg"].exists) }
            let stats = app.descendants(matching: .any)["workout.sessionReport.stats"].firstMatch
            let figure = app.descendants(matching: .any)["workout.sessionReport.body"].firstMatch
            XCTAssertLessThanOrEqual(figure.frame.maxY, stats.frame.minY + 1)
            if language == "en" { XCTAssertTrue(app.staticTexts["60 kg × 8 × 1"].exists) }
            XCTAssertFalse(app.buttons["Body front"].exists)
            XCTAssertFalse(app.buttons["Body back"].exists)
            let spark = app.descendants(matching: .any)["workout.sessionReport.spark.bench_press_barbell"].firstMatch
            for _ in 0..<5 where !spark.isHittable { app.swipeUp() }
            XCTAssertTrue(spark.exists)
            XCTAssertEqual(spark.frame.width, 80, accuracy: 1)
            XCTAssertEqual(spark.frame.height, 20, accuracy: 1)
            XCTAssertLessThanOrEqual(spark.frame.maxX, row.frame.maxX + 1)
            keepShot(app, "aggregate-report-\(language)")
            app.buttons["workout.sessionReport.share"].tap()
            let export = app.buttons["workout.sessionReport.previewShare"]
            XCTAssertTrue(export.waitForExistence(timeout: 8))
            XCTAssertFalse(app.switches["workout.sessionReport.shareDetailsToggle"].exists)
            XCTAssertFalse(app.switches["workout.sessionReport.shareHeartToggle"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport.sharedExercise.bench_press_barbell"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport.sharedExercise.bench_press_barbell"].firstMatch.descendants(matching: .any)["workout.sessionReport.spark.bench_press_barbell"].firstMatch.exists)
            keepShot(app, "aggregate-share-preview-\(language)")
            app.terminate()
        }
    }

    func testPhotoConsentAndSummaryExport() throws {
        let app = launch("session-report-clean-player", extra: ["MASO_SESSION_REPORT_EXPORT": "1", "MASO_SESSION_REPORT_PHOTO": "1"])
        openReportFromCelebration(app)
        app.buttons["workout.sessionReport.share"].tap()
        let export = app.buttons["workout.sessionReport.previewShare"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        let marker = app.staticTexts["workout.sessionReport.shareExported"]
        XCTAssertTrue(marker.waitForExistence(timeout: 8))
        XCTAssertEqual(marker.label, "session-report-detail.png")
        for id in ["workout.sessionReport.sharePhotoToggle"] {
            let control = app.switches[id]
            for _ in 0..<6 where !control.isHittable { app.swipeUp() }
            XCTAssertTrue(control.exists)
            XCTAssertFalse(switchIsOn(control))
            let knob = control.switches.firstMatch
            (knob.exists ? knob : control).tap()
            XCTAssertTrue(switchIsOn(control))
        }
        export.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            marker.exists && marker.label == "session-report-photo.png"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
        keepShot(app, "aggregate-share-selected")
        XCTAssertEqual(sessionEndCount(app), "0")
    }

    func testPhotoPickerCanBeCancelledWithoutChangingReport() throws {
        let app = launch("session-report-clean-player")
        openReportFromCelebration(app)
        let photo = app.buttons["share.photo.upload"]
        for _ in 0..<7 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.isHittable)
        photo.tap()
        XCTAssertTrue(app.buttons["Choose from Library"].waitForExistence(timeout: 5))
        app.buttons["Choose from Library"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport"].exists)
        XCTAssertEqual(sessionEndCount(app), "0")
    }


    func testSystemShareCancelReturnsToPreviewAndReport() throws {
        let app = launch("session-report-clean-player")
        openReportFromCelebration(app)
        app.buttons["workout.sessionReport.share"].tap()
        let share = app.buttons["workout.sessionReport.previewShare"]
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        share.tap()
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Close Share Sheet"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15), app.debugDescription)
        close.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["workout.sessionReport.exit"].waitForExistence(timeout: 8))
        XCTAssertEqual(sessionEndCount(app), "0")
    }

    func testPhotoCanBeTurnedOffAfterReturningFromSystemShare() throws {
        let app = launch("session-report-clean-player", extra: ["MASO_SESSION_REPORT_PHOTO": "1", "MASO_SESSION_REPORT_PORTRAIT": "1"])
        openReportFromCelebration(app)
        app.buttons["workout.sessionReport.share"].tap()
        let control = app.switches["workout.sessionReport.sharePhotoToggle"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        control.tap()
        XCTAssertTrue(switchIsOn(control))
        let photo = app.descendants(matching: .any)["workout.sessionReport.sharePhoto"].firstMatch
        XCTAssertTrue(photo.exists)
        app.buttons["workout.sessionReport.previewShare"].tap()
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Close Share Sheet"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        control.tap()
        XCTAssertFalse(switchIsOn(control))
        XCTAssertFalse(photo.exists)
        control.tap()
        XCTAssertTrue(switchIsOn(control))
        XCTAssertTrue(photo.exists)
        keepShot(app, "photo-reenabled-after-system-share")
    }

    func testNarrowLargeTypeToolbarAndPhotoRemainReachable() throws {
        let app = launch("session-report-clean-player", language: "zh-Hans", extra: ["MASO_TEST_NARROW": "1", "MASO_TEST_LARGE_TYPE": "1"])
        openReportFromCelebration(app)
        let share = app.buttons["workout.sessionReport.share"]
        let done = app.buttons["workout.sessionReport.exit"]
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(done.isHittable)
        XCTAssertFalse(share.frame.intersects(done.frame))
        let photo = app.buttons["share.photo.upload"]
        for _ in 0..<9 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.isHittable)
        keepShot(app, "report-narrow-large-type")
    }

    private func openReportFromCelebration(_ app: XCUIApplication) {
        let continueToReport = app.buttons["workout.completed.report"]
        XCTAssertTrue(continueToReport.waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport"].exists)
        continueToReport.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.sessionReport"].waitForExistence(timeout: 15))
    }

    private func keepShot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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

    private func sheetGrabbers(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == %@", "Sheet Grabber"))
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
        assertExpandedSheet(titled: "Workout Summary", in: history)
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

    func testFinishedReportExitsThroughProductionRootAndCanStartAgain() throws {
        // Unlike the isolated report probe, home-start hosts the real RootView cover/onDismiss.
        let app = launch("home-start")
        let start = app.buttons["home.startTodayWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        let complete = app.descendants(matching: .any)["workout.primary"]
        XCTAssertTrue(complete.waitForExistence(timeout: 20))
        complete.tap()
        openReportFromCelebration(app)
        app.buttons["workout.sessionReport.exit"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["workout.sessionReport"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["home.trainingMiniBar"].exists)
        start.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Workout complete"].exists, "Ending the old Root cover must not end the new workout")
        keepShot(app, "production-root-finish-and-restart")
    }

    func testHomeStartButtonOpensThePlayer() {
        let app = launch("home-start")
        let start = app.buttons["home.startTodayWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.primary"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Workout complete"].exists)
    }
}
