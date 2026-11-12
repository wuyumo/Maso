import XCTest

/// Explicit opt-in production diagnostic using only the synthetic preview profile.
/// Never part of the ordinary UI regression suite or a real user's saved profile.
@MainActor
final class CoachLiveDiagnosticUITests: XCTestCase {
    func testMarketingMuscleFromHome() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_MARKETING_MUSCLE": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.terminate(); app.launch()
        let body = app.descendants(matching: .any).matching(identifier: "today.muscleBody3D").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 30)); body.tap()
        let button = app.buttons["Train the gaps"]
        XCTAssertTrue(button.waitForExistence(timeout: 15)); XCTAssertTrue(button.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "marketing-muscle-enabled"; shot.lifetime = .keepAlways; add(shot)
        button.tap()
        XCTAssertTrue(app.buttons["workout.end"].waitForExistence(timeout: 15))
    }

    func testMarketingPhotoReportAfterYes() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-photo-report", "MASO_SHOWCASE_SEED": "1", "MASO_MARKETING_BODY_PHOTO": "1", "MASO_COACH_TEST_DAYS": "2", "MASO_COACH_TEST_EXERCISES": "4"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.terminate()
        app.launch()
        let yes = app.buttons["coach.photo.confirm"]
        XCTAssertTrue(yes.waitForExistence(timeout: 20))
        yes.tap()
        if app.alerts["AI data sharing"].waitForExistence(timeout: 5) { app.alerts["AI data sharing"].buttons["Allow"].tap() }
        let saved = app.buttons["coach.save-batch"]
        XCTAssertTrue(saved.waitForExistence(timeout: 150), "The generated plan cards did not appear")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "showing templates instead")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "marketing-photo-after-yes"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testAdviceDeckCyclesBothSwipeDirectionsWithoutDismissing() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-live", "MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": "coach_advice"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let deck = app.descendants(matching: .any).matching(identifier: "coach.adviceDeck").firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Give your legs more attention"].exists)
        deck.swipeLeft()
        XCTAssertTrue(app.staticTexts["Keep sessions manageable"].waitForExistence(timeout: 5))
        deck.swipeRight()
        XCTAssertTrue(app.staticTexts["Make room for recovery"].waitForExistence(timeout: 5))
        deck.swipeLeft()
        XCTAssertTrue(app.staticTexts["Give your legs more attention"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Suggestion removed"].exists)
        XCTAssertTrue(app.buttons["coach.applyAdvice"].exists)
        XCTAssertTrue(app.buttons["coach.skipAdvice"].exists)
        app.buttons["coach.skipAdvice"].tap()
        XCTAssertTrue(app.staticTexts["Keep sessions manageable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Suggestion removed"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["Give your legs more attention"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testAdviceCardsOnlyAppearInEmptyConversation() {
        for (scene, expected) in [("coach-live", true), ("coach-photo-report", false)] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene, "MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": "coach_advice"]
            app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
            app.launch()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
            let advice = app.descendants(matching: .any).matching(identifier: "coach.adviceDeck").firstMatch
            if expected { XCTAssertTrue(advice.waitForExistence(timeout: 5)) }
            else { XCTAssertFalse(advice.exists) }
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "advice-\(scene)"; image.lifetime = .keepAlways; add(image)
            app.terminate()
        }
    }

    func testPhotoReportWaitsForConfirmationAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-photo-report", "MASO_SHOWCASE_SEED": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let yes = app.buttons["coach.photo.confirm"], no = app.buttons["coach.photo.decline"]
            XCTAssertTrue(yes.waitForExistence(timeout: 15))
            XCTAssertFalse(no.exists)
            XCTAssertTrue(app.otherElements["coach.photo.focusMap"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["coach.save-batch"].exists, "A report must not generate plan cards automatically")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(language)-photo-report-confirmation"; screenshot.lifetime = .keepAlways; add(screenshot)
            XCTAssertTrue(yes.isHittable)
            XCTAssertFalse(app.buttons["coach.save-batch"].exists)
            app.terminate()
        }
    }

    func testPhotoReportConsentGeneratesRealPlans() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_AI_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Real plan generation requires opt-in")
        }
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-photo-report", "MASO_SHOWCASE_SEED": "1", "MASO_COACH_TEST_DAYS": "2", "MASO_COACH_TEST_EXERCISES": "4"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let yes = app.buttons["coach.photo.confirm"]
        XCTAssertTrue(yes.waitForExistence(timeout: 15))
        let count = app.staticTexts["routine.test.saved-count"].label
        yes.tap()
        if app.alerts["AI data sharing"].waitForExistence(timeout: 5) {
            app.alerts["AI data sharing"].buttons["Allow"].tap()
        }
        let status = app.staticTexts["coach.test.status"]
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && (status.label.hasPrefix("success:") || status.label.hasPrefix("fallback:"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 150), .completed)
        XCTAssertEqual(status.label, "success: 2", "Must use real AI, not template fallback")
        XCTAssertEqual(app.staticTexts["routine.test.saved-count"].label, count, "Generating cards must not replace saved plans")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "photo-report-real-plans"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testSingleWorkoutStartsWithoutSavingAndSavingStaysOptional() throws {
        continueAfterFailure = false
        for (language, end) in [("en", "End"), ("zh-Hans", "结束"), ("ar", "النهاية")] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-session"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let saved = app.staticTexts["routine.test.saved-count"]
            XCTAssertTrue(saved.waitForExistence(timeout: 15))
            let before = try XCTUnwrap(Int(saved.label))
            let start = app.buttons["workout.card.start"].firstMatch
            for _ in 0..<5 { if start.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(start.isHittable, app.debugDescription)
            let card = XCTAttachment(screenshot: app.screenshot())
            card.name = "\(language)-single-workout-ready"; card.lifetime = .keepAlways; add(card)
            start.tap()
            XCTAssertTrue(app.buttons["workout.end"].waitForExistence(timeout: 10), app.debugDescription)
            let playing = XCTAttachment(screenshot: app.screenshot())
            playing.name = "\(language)-single-workout-playing"; playing.lifetime = .keepAlways; add(playing)
            app.buttons["workout.end"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.firstMatch.buttons[end].tap()
            XCTAssertTrue(saved.waitForExistence(timeout: 10))
            XCTAssertEqual(Int(saved.label), before, "Starting must not save a routine")
            let save = app.buttons["coach.save-batch"]
            for _ in 0..<5 { if save.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(save.isHittable)
            save.tap()
            let add = app.buttons["routine.save.add"]
            if before > 0 { XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap() }
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in saved.label == String(before + 1) }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
            app.terminate()
        }
    }

    func testSyntheticSingleWorkoutGenerationAndDirectStart() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_AI_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Live diagnostics require explicit opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-live", "MASO_COACH_TEST_DAYS": "3"]
        app.launchArguments = ["-maso.selectedLanguage", "zh-Hans", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans"]
        app.launch()
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("给我一个30分钟的腹肌训练")
        app.buttons["发送"].tap()
        if app.alerts["AI 数据共享"].waitForExistence(timeout: 5) {
            let allow = app.alerts["AI 数据共享"].buttons["Allow"]
            if allow.exists { allow.tap() } else { app.alerts["AI 数据共享"].buttons["允许"].tap() }
        }
        let status = app.staticTexts["coach.test.status"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && (status.label.hasPrefix("success:") || status.label.hasPrefix("fallback:"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 150), .completed)
        XCTAssertEqual(status.label, "success: 1", app.debugDescription)
        let start = app.buttons["workout.card.start"].firstMatch
        for _ in 0..<6 { if start.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(start.isHittable, app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "zh-single-workout-live-generation"; attachment.lifetime = .keepAlways; add(attachment)
        start.tap()
        XCTAssertTrue(app.buttons["workout.end"].waitForExistence(timeout: 10))
        app.terminate()
    }

    func testSettingsConnectionDiagnostics() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_MEAL_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Live diagnostics require explicit opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "settings-ai"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let button = app.buttons["settings.ai.test"]
        XCTAssertTrue(app.buttons["Training Preferences"].waitForExistence(timeout: 15))
        for _ in 0..<8 {
            if button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
        let primary = app.descendants(matching: .any).matching(identifier: "settings.ai.Primary route").firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            primary.exists && primary.label.contains("OK")
        }, object: nil)
        let result = XCTWaiter.wait(for: [finished], timeout: 40)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-ai-connection-result"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed, "Connection diagnostic: \(app.debugDescription)")
    }

    func testSyntheticMealTextRecognitionAndSave() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_MEAL_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Live meal diagnostic requires explicit opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "meal-live",
                                 "MASO_TEST_FREE_USER": ProcessInfo.processInfo.environment["MASO_TEST_FREE_USER"] ?? "0"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let addMeal = app.buttons["Add meal"].firstMatch
        XCTAssertTrue(addMeal.waitForExistence(timeout: 15))
        if !addMeal.isHittable { app.swipeUp() }
        addMeal.tap()
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("Two eggs, a bowl of rice and a glass of milk")
        try XCTUnwrap(app.buttons.matching(identifier: "Add meal").allElementsBoundByIndex.last).tap()
        if ProcessInfo.processInfo.environment["MASO_TEST_FREE_USER"] == "1" {
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
            app.buttons["Close"].tap()
        }
        if app.alerts["AI data sharing"].waitForExistence(timeout: 5) {
            app.alerts["AI data sharing"].buttons["Allow"].tap()
        }
        let saved = app.staticTexts["meal.test.status"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            saved.exists && saved.label == "saved: 1"
        }, object: nil)
        let result = XCTWaiter.wait(for: [completed], timeout: 110)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "meal-live-text-result"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed, "Meal did not save: \(app.debugDescription)")
    }

    func testSyntheticRoutineGenerationAndCardActions() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_AI_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Live production diagnostic requires explicit opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        let days = ProcessInfo.processInfo.environment["MASO_COACH_TEST_DAYS"] ?? "3"
        let exercises = ProcessInfo.processInfo.environment["MASO_COACH_TEST_EXERCISES"] ?? "4"
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-live",
                                 "MASO_COACH_TEST_DAYS": days, "MASO_COACH_TEST_EXERCISES": exercises,
                                 "MASO_TEST_FREE_USER": ProcessInfo.processInfo.environment["MASO_TEST_FREE_USER"] ?? "0"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText(ProcessInfo.processInfo.environment["MASO_COACH_TEST_PROMPT"] ?? "Create my weekly training routines")
        app.buttons["Send"].tap()
        if ProcessInfo.processInfo.environment["MASO_TEST_FREE_USER"] == "1" {
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
            app.buttons["Close"].tap()
        }
        if app.alerts["AI data sharing"].waitForExistence(timeout: 5) {
            app.alerts["AI data sharing"].buttons["Allow"].tap()
        }
        let status = app.staticTexts["coach.test.status"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && (status.label.hasPrefix("success:") || status.label.hasPrefix("fallback:"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 180), .completed)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "coach-live-generated-routines"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(status.label, "success: \(days)", "Actual production generation result: \(status.label)")
        XCTAssertFalse(app.buttons["Exercise demos"].exists)
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.buttons["Exercise demos"].exists)
    }
}

@MainActor
final class CoachImageRouterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scene: String, fixture: String = "qr", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene, "MASO_SHOWCASE_SEED": "1", "MASO_IMAGE_FIXTURE": fixture]
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testPlanQRCodeNeedsReviewAndExplicitAdd() {
        let app = launch("coach-image-local")
        let review = app.buttons["coach.image.routine.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 20), app.debugDescription)
        let saved = app.staticTexts["routine.test.saved-count"]
        let count = Int(saved.label)!
        XCTAssertEqual(app.staticTexts["coach.image.test.kind"].label, "routine")
        capture(app, "qr-routine-before-add")
        review.tap()
        let add = app.buttons["Add (1)"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(Int(saved.label), count)
        capture(app, "qr-routine-import-review")
        add.tap()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Int(saved.label) == count + 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
    }
    func testRealRoutineImageRequestCreatesWorkoutInsteadOfSummary() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_AI_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Real image recognition requires explicit opt-in")
        }
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-image-live", "MASO_SHOWCASE_SEED": "1",
                                 "MASO_IMAGE_FIXTURE": "routine-eight",
                                 "MASO_IMAGE_CAPTION": "把图片中的所有动作做成一张训练卡片。"]
        if ProcessInfo.processInfo.environment["MASO_REQUIRE_USER_FIXTURE"] == "1" {
            XCTAssertNotNil(ProcessInfo.processInfo.environment["MASO_TEST_ROUTINE_IMAGE"], "Original image fixture must be supplied")
        }
        if let fixture = ProcessInfo.processInfo.environment["MASO_TEST_ROUTINE_IMAGE"] {
            app.launchEnvironment["MASO_TEST_ROUTINE_IMAGE"] = fixture
        }
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        if app.alerts["AI data sharing"].waitForExistence(timeout: 8) {
            app.alerts["AI data sharing"].buttons["Allow"].tap()
        }
        let status = app.staticTexts["coach.test.status"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (status.exists && status.label == "success: 1") || app.buttons["coach.image.routine.review"].exists || app.buttons["coach.image.retry"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 150), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["coach.image.change-use"].exists)
        let diagnostic = app.staticTexts["coach.image.test.steps"].value as? String ?? ""
        XCTAssertEqual(status.label, "success: 1", diagnostic + "\n" + app.debugDescription)
        XCTAssertEqual(app.staticTexts["coach.image.test.steps"].label, "8")
        let ids = (app.staticTexts["coach.image.test.steps"].value as? String ?? "").split(separator: ",").map(String.init)
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(ids[0], "pull_up")
        XCTAssertTrue(ids[1].contains("dip") && !ids[1].contains("bench"))
        XCTAssertEqual(ids[2], "push_up")
        XCTAssertEqual(ids[3], "inverted_row")
        XCTAssertEqual(ids[4], "push_up_pike")
        XCTAssertEqual(ids[5], "squat_bodyweight")
        XCTAssertTrue(ids[6].contains("lunge"))
        XCTAssertEqual(ids[7], "rdl_barbell")
        capture(app, "real-image-request-single-workout")
    }

    func testAmbiguousImageOffersOnlySupportedChoicesAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("coach-image-choice", language: language)
            XCTAssertTrue(app.buttons["coach.image.use.body"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["coach.image.use.photo"].exists)
            XCTAssertFalse(app.buttons["coach.image.use.meal"].exists)
            XCTAssertFalse(app.buttons["coach.image.change-use"].exists)
            XCTAssertFalse(app.buttons["coach.image.routine.review"].exists)
            capture(app, "\(language)-supported-image-choices")
            app.terminate()
        }
    }
    func testUnavailableImageAnalysisOffersRetryWithoutPurposeMenu() {
        let app = launch("coach-image-choice", fixture: "error")
        XCTAssertTrue(app.buttons["coach.image.retry"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["coach.image.change-use"].exists)
        XCTAssertFalse(app.buttons["coach.image.use.body"].exists)
        XCTAssertFalse(app.buttons["coach.image.routine.review"].exists)
        XCTAssertFalse(app.buttons["coach.image.meal.review"].exists)
        capture(app, "image-service-failure-retry")
    }

    func testOldConsentRequiresNewProviderDisclosureAndDeclineKeepsImageLocal() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-image-live", "MASO_SHOWCASE_SEED": "1",
                                 "MASO_IMAGE_FIXTURE": "label", "MASO_TEST_OLD_AI_CONSENT": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let consent = app.alerts["AI data sharing"]
        XCTAssertTrue(consent.waitForExistence(timeout: 15), "A Qwen-only v1 grant cannot authorize v2")
        XCTAssertTrue(consent.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Anthropic")).firstMatch.exists)
        consent.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["AI permission wasn't granted. Your image wasn't sent."].waitForExistence(timeout: 8))
        let retry = app.buttons["coach.image.retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(app.buttons["coach.image.meal.review"].exists)
        capture(app, "image-consent-declined-no-record")
        retry.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 8), "Only explicit retry may ask again")
        consent.buttons["Not now"].tap()
        app.terminate()
    }

    func testRealMealCaptionUsesConsumedHalfServing() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_AI_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Real image recognition requires explicit opt-in")
        }
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-image-live", "MASO_SHOWCASE_SEED": "1", "MASO_IMAGE_FIXTURE": "label",
                                 "MASO_IMAGE_CAPTION": "I ate half of this 100 g serving, so I consumed 50 g."]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        if app.alerts["AI data sharing"].waitForExistence(timeout: 6) {
            app.alerts["AI data sharing"].buttons["Allow"].tap()
        }
        XCTAssertTrue(app.buttons["coach.image.meal.review"].waitForExistence(timeout: 120), app.debugDescription)
        let values = app.staticTexts["coach.image.test.macros"].label.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 3)
        guard values.count == 3 else { return }
        XCTAssertEqual(values[0], 10, accuracy: 0.1)
        XCTAssertEqual(values[1], 15, accuracy: 0.1)
        XCTAssertEqual(values[2], 5, accuracy: 0.1)
        capture(app, "real-label-half-serving-caption")
    }

    func testRealNutritionLabelRoutesToExistingMealEditorBeforeSave() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_AI_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Real image recognition requires explicit opt-in")
        }
        let app = launch("coach-image-live", fixture: "label")
        if app.alerts["AI data sharing"].waitForExistence(timeout: 5) {
            app.alerts["AI data sharing"].buttons["Allow"].tap()
        }
        let review = app.buttons["coach.image.meal.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 120), app.debugDescription)
        let count = app.staticTexts["coach.image.test.meals"]
        let before = Int(count.label)!
        capture(app, "real-label-macros-before-save")
        review.tap()
        let save = app.buttons["meal.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertEqual(Int(count.label), before, "Recognizing/opening a meal is not eating or logging it")
        capture(app, "real-label-shared-meal-editor")
        save.tap()
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Int(count.label) == before + 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: 15), .completed)
        XCTAssertTrue(review.waitForExistence(timeout: 6))
        review.tap(); XCTAssertTrue(save.waitForExistence(timeout: 6))
        save.tap()
        XCTAssertEqual(Int(count.label), before + 1, "Reopening the same result edits its meal, not a duplicate")
    }
}
