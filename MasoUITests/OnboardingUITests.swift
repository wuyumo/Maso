import XCTest

final class OnboardingUITests: XCTestCase {
    func testFirstHomeMuscleIntroductionEndsAfterLeavingHome() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": "home_muscle_intro"]
        app.launchArguments = ["-maso.selectedLanguage", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let intro = app.staticTexts["肌肉图展示各部位的训练情况。"]
        XCTAssertTrue(intro.waitForExistence(timeout: 20))
        capture(app, "first-home-muscle-intro")
        app.buttons["home.coach"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["home.coach"].waitForExistence(timeout: 10))
        XCTAssertFalse(intro.exists)
    }

    func testFirstRunCoachTooltipCanBeDismissedWithoutBlockingCoach() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": "coach_tip"]
        app.launchArguments = ["-maso.selectedLanguage", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let close = app.buttons["home.coachTip.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        let tipText = app.staticTexts["home.coachTip.text"]
        XCTAssertTrue(tipText.exists)
        XCTAssertEqual(tipText.label, "想调整训练计划？试试 AI Coach。")
        let tip = app.otherElements["home.coachTip"]
        XCTAssertEqual(tipText.frame.midX, tip.frame.midX, accuracy: 3)
        XCTAssertTrue(app.buttons["home.coach"].isHittable)
        XCTAssertLessThan(close.frame.maxY, app.buttons["home.coach"].frame.minY,
                          "Tooltip must sit above the launcher, not overlap it")
        capture(app, "coach-first-run-tip")
        close.tap()
        XCTAssertFalse(close.exists)
        app.buttons["home.coach"].tap()
        XCTAssertFalse(close.exists)
        capture(app, "coach-after-tip-dismissal")
    }

    func testBodyPhotoTipOpensCoachAndPhotoPicker() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": "coach_photo_tip"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let action = app.buttons["home.coachTip.photo"]
        XCTAssertTrue(action.waitForExistence(timeout: 20))
        action.tap()
        XCTAssertTrue(app.navigationBars["AI Coach"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        let prompt = app.textViews.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue((prompt.value as? String ?? "").contains("Review my body photo"))
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testTrainingPreferencesUsesHomePickerAndCancelPreservesProfile() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "settings-ai", "MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let preferences = app.buttons["Training Preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 10))
        preferences.tap()
        let home = app.buttons["training.equipment.home"]
        for _ in 0..<6 {
            if home.exists && home.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["training.equipment.gym"].isSelected)
        home.tap()
        let dumbbell = app.buttons["training.home-equipment.dumbbell"]
        for _ in 0..<6 {
            if dumbbell.exists && dumbbell.isHittable { break }
            app.swipeUp()
        }
        dumbbell.tap()
        XCTAssertTrue(dumbbell.isSelected)
        capture(app, "preferences-home")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(preferences.waitForExistence(timeout: 5))
        preferences.tap()
        XCTAssertTrue(app.buttons["training.equipment.gym"].isSelected)
        XCTAssertFalse(app.buttons["training.home-equipment.dumbbell"].exists)
    }

    func testMuscleFocusPickerKeepsTrainingPreferencesOpen() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "settings-ai", "MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["Training Preferences"].waitForExistence(timeout: 15))
        app.buttons["Training Preferences"].tap()
        let focus = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Muscles to focus")).firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.tap()
        XCTAssertTrue(app.navigationBars["Muscles to focus"].waitForExistence(timeout: 5))
        app.navigationBars["Muscles to focus"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Training Preferences"].waitForExistence(timeout: 5))
        app.navigationBars["Training Preferences"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Training Preferences"].waitForExistence(timeout: 5))
    }

    func testHomeEquipmentExpandsTogglesAndSurvivesEnvironmentSwitching() throws {
        let app = launch()
        let primary = app.buttons["onboarding.continue"]
        primary.tap()
        let home = app.buttons["onboarding.equipment.home"]
        try reveal(home, app: app)
        XCTAssertTrue(app.buttons["onboarding.equipment.gym"].isSelected)
        home.tap()
        XCTAssertTrue(app.staticTexts["onboarding.home-equipment.empty"].exists)
        XCTAssertTrue(primary.isEnabled)
        let dumbbell = app.buttons["onboarding.home-equipment.dumbbell"]
        try reveal(dumbbell, app: app)
        dumbbell.tap()
        XCTAssertTrue(dumbbell.isSelected)
        dumbbell.tap()
        XCTAssertFalse(dumbbell.isSelected)
        XCTAssertTrue(app.staticTexts["onboarding.home-equipment.empty"].exists)
        dumbbell.tap()
        app.buttons["onboarding.equipment.gym"].tap()
        XCTAssertFalse(dumbbell.exists)
        home.tap()
        XCTAssertTrue(dumbbell.isSelected)
        let bench = app.buttons["onboarding.home-equipment.bench_flat"]
        try reveal(bench, app: app)
        bench.tap()
        capture(app, "home-equipment")
        primary.tap()
        XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(home.isSelected)
        XCTAssertTrue(dumbbell.isSelected)
        XCTAssertTrue(bench.isSelected)
        primary.tap()
        primary.tap()
        XCTAssertTrue(app.staticTexts["onboarding.test.completed"].waitForExistence(timeout: 5))
    }

    func testRealFreshLaunchContinueTransitionsPromptly() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_FRESH_ONBOARDING_UI_TEST": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let primary = app.buttons["onboarding.continue"]
        XCTAssertTrue(primary.waitForExistence(timeout: 20))
        let started = Date()
        primary.tap()
        XCTAssertTrue(app.staticTexts["onboarding.question.schedule"].waitForExistence(timeout: 4))
        let elapsed = Date().timeIntervalSince(started)
        let timing = XCTAttachment(string: "Fresh first-to-second-step including XCUI tap synchronization: \(elapsed) seconds")
        timing.lifetime = .keepAlways; add(timing)
        XCTAssertLessThan(elapsed, 5)
        capture(app, "fresh-schedule")
    }

    func testWeekdayButtonsAndNumericCountStayInSyncWithInlineChoices() throws {
        let app = launch()
        let primary = app.buttons["onboarding.continue"]
        primary.tap()
        XCTAssertTrue(app.staticTexts["onboarding.question.schedule"].waitForExistence(timeout: 5))
        let count = app.textFields["onboarding.days"]
        XCTAssertEqual(count.value as? String, "3")
        for day in 1...7 { XCTAssertTrue(app.buttons["onboarding.weekday.\(day)"].isHittable) }
        app.buttons["onboarding.weekday.2"].tap()
        XCTAssertEqual(count.value as? String, "4")
        count.tap()
        count.typeText("2")
        app.toolbars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["onboarding.weekday.2"].isSelected)
        XCTAssertTrue(app.buttons["onboarding.weekday.5"].isSelected)
        XCTAssertFalse(app.buttons["onboarding.weekday.1"].isSelected)
        XCTAssertTrue(app.buttons["onboarding.duration.45"].isSelected)
        for minutes in [30, 45, 60, 90] { XCTAssertTrue(app.buttons["onboarding.duration.\(minutes)"].isHittable) }
        app.buttons["onboarding.duration.90"].tap()
        app.buttons["onboarding.equipment.bodyweight"].tap()
        XCTAssertTrue(app.buttons["onboarding.duration.90"].isSelected)
        XCTAssertTrue(app.buttons["onboarding.equipment.bodyweight"].isSelected)
        XCTAssertEqual(app.pickers.count, 0)
        capture(app, "inline-schedule")
        app.buttons["onboarding.weekday.2"].tap()
        app.buttons["onboarding.weekday.5"].tap()
        XCTAssertFalse(primary.isEnabled)
        XCTAssertTrue(app.staticTexts["Choose at least one training day"].exists)
        app.buttons["onboarding.weekday.7"].tap()
        XCTAssertTrue(primary.isEnabled)
        primary.tap()
        XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 5))
    }

    func testGuidedCardsSendSelectionsAsMessagesAndGeneratePlans() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["onboarding.question.goal"].waitForExistence(timeout: 15))
        let goal = app.buttons["onboarding.goal.getStronger"]
        try reveal(goal, app: app)
        goal.tap()
        let send = app.buttons["onboarding.continue"]
        try reveal(send, app: app)
        XCTAssertEqual(send.label, "Send")
        send.tap()
        let goalAnswer = app.descendants(matching: .any).matching(identifier: "onboarding.answer.goal").firstMatch
        XCTAssertTrue(goalAnswer.waitForExistence(timeout: 5))
        XCTAssertTrue(goalAnswer.label.contains("Get stronger"))
        XCTAssertFalse(goal.exists)
        XCTAssertTrue(app.staticTexts["onboarding.question.schedule"].waitForExistence(timeout: 5))
        let duration = app.buttons["onboarding.duration.60"]
        try reveal(duration, app: app)
        duration.tap()
        try reveal(send, app: app)
        send.tap()
        let scheduleAnswer = app.descendants(matching: .any).matching(identifier: "onboarding.answer.schedule").firstMatch
        XCTAssertTrue(scheduleAnswer.waitForExistence(timeout: 5))
        XCTAssertTrue(scheduleAnswer.label.contains("60"))
        XCTAssertFalse(duration.exists)
        XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 10))
        capture(app, "guided-messages-preview")
        XCTAssertEqual(send.label, "Save plans & start")
        send.tap()
        XCTAssertTrue(app.staticTexts["onboarding.test.completed"].waitForExistence(timeout: 5))
    }

    func testThreeStepFlowBodyTapToggleAndExactPreviewSave() throws {
        let app = launch()
        let primary = app.buttons["onboarding.continue"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        XCTAssertTrue(primary.isEnabled)
        XCTAssertTrue(app.buttons["onboarding.goal.buildMuscle"].isSelected)
        XCTAssertTrue(app.buttons["muscle.focus.balanced"].isSelected)
        let chest = app.buttons["muscle.focus.chest"]
        let model = app.buttons["onboarding.body"]
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        // Tap the actual 3D chest, not a test-only proxy button.
        let hit = model.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.22))
        for _ in 0..<3 {
            hit.tap()
            if wait({ chest.isSelected }, timeout: 1) { break }
        }
        XCTAssertTrue(chest.isSelected, "3D tap selects the shared chest preference")
        hit.tap()
        XCTAssertTrue(wait { !chest.isSelected }, "Second 3D hit deselects the same group")
        XCTAssertTrue(app.buttons["muscle.focus.balanced"].isSelected)
        capture(app, "body-before-zoom")
        model.pinch(withScale: 1.45, velocity: 1)
        capture(app, "body-after-zoom")
        model.pinch(withScale: 1 / 1.45, velocity: -1)
        chest.tap()
        let core = app.buttons["muscle.focus.core"]
        core.tap()
        XCTAssertTrue(chest.isSelected && core.isSelected)
        app.buttons["onboarding.goal.getStronger"].tap()
        XCTAssertTrue(primary.isEnabled)
        capture(app, "goal")
        primary.tap()
        XCTAssertTrue(app.staticTexts["onboarding.question.schedule"].waitForExistence(timeout: 5))
        capture(app, "schedule")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(chest.waitForExistence(timeout: 5))
        XCTAssertTrue(chest.isSelected && core.isSelected)
        XCTAssertTrue(app.buttons["onboarding.goal.getStronger"].isSelected)
        primary.tap()
        primary.tap()
        XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 5))
        capture(app, "preview")
        let carousel = app.scrollViews["onboarding.planPicker"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        XCTAssertEqual(carousel.frame.minX, app.frame.minX, accuracy: 2)
        XCTAssertEqual(carousel.frame.maxX, app.frame.maxX, accuracy: 2)
        XCTAssertEqual(primary.label, "Save plans & start")
        carousel.swipeLeft()
        XCTAssertTrue(app.staticTexts["DAY 2"].isHittable)
        capture(app, "preview-second-plan")
        primary.tap()
        XCTAssertTrue(app.staticTexts["onboarding.test.completed"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(Int(app.staticTexts["onboarding.test.savedCount"].label) ?? 0, 0)
        XCTAssertFalse(app.staticTexts["onboarding.test.startedPlan"].label.isEmpty)
    }

    func testConciseFlowInChineseGermanAndRTLWithAccessibleType() throws {
        for language in ["zh-Hans", "de", "ar"] {
            let app = launch(language: language, largeType: language == "de")
            capture(app, language + "-initial")
            let goal = app.buttons["onboarding.goal.generalFitness"]
            try reveal(goal, app: app)
            goal.tap()
            XCTAssertTrue(goal.isSelected)
            capture(app, language + "-goal")
            let primary = app.buttons["onboarding.continue"]
            XCTAssertTrue(primary.isHittable)
            primary.tap()
            XCTAssertTrue(app.staticTexts["onboarding.question.schedule"].waitForExistence(timeout: 5))
            let longer = app.buttons["onboarding.duration.90"]
            try reveal(longer, app: app)
            longer.tap()
            XCTAssertTrue(longer.isSelected)
            let home = app.buttons["onboarding.equipment.home"]
            try reveal(home, app: app)
            home.tap()
            let dumbbell = app.buttons["onboarding.home-equipment.dumbbell"]
            try reveal(dumbbell, app: app)
            dumbbell.tap()
            XCTAssertTrue(dumbbell.isSelected)
            let benchLabels = ["zh-Hans": "平板凳", "de": "Flachbank", "ar": "مقعد مسطح"]
            XCTAssertEqual(app.buttons["onboarding.home-equipment.bench_flat"].label, benchLabels[language])
            if language == "de" {
                let barbell = app.buttons["onboarding.home-equipment.barbell"]
                try reveal(barbell, app: app)
                XCTAssertGreaterThanOrEqual(barbell.frame.minX, 8)
                XCTAssertLessThanOrEqual(barbell.frame.maxX, app.frame.width - 8)
            }
            capture(app, language + "-schedule")
            primary.tap()
            XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 5))
            capture(app, language + "-preview")
            XCTAssertTrue(primary.isHittable)
            app.terminate()
        }
    }

    func testExistingUserPreviewDoesNotSavePlans() throws {
        let app = launch(language: "zh-Hans", previewOnly: true)
        XCTAssertTrue(app.buttons["onboarding.goal.buildMuscle"].isSelected)
        XCTAssertTrue(app.buttons["muscle.focus.balanced"].isSelected)
        capture(app, "final-goal")
        let primary = app.buttons["onboarding.continue"]
        primary.tap()
        capture(app, "final-schedule")
        primary.tap()
        XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 5))
        capture(app, "final-preview")
        primary.tap()
        XCTAssertTrue(app.staticTexts["onboarding.test.completed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.test.savedCount"].label, "0")
    }

    func testSettingsPreviewEntryReturnsToSettings() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "settings-ai", "MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let entry = app.buttons["settings.onboarding.preview"]
        for _ in 0..<12 {
            if entry.exists && entry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        let goal = app.buttons["onboarding.goal.buildMuscle"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        let primary = app.buttons["onboarding.continue"]
        XCTAssertTrue(primary.isEnabled)
        // Tap the visible green area beyond the text, in the actual Settings sheet.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: app.frame.maxX - 48, dy: primary.frame.midY
        )).tap()
        XCTAssertTrue(app.staticTexts["onboarding.question.schedule"].waitForExistence(timeout: 5))
        primary.tap()
        XCTAssertTrue(app.scrollViews["onboarding.planPicker"].waitForExistence(timeout: 5))
        primary.tap()
        XCTAssertTrue(wait { entry.isHittable })
    }

    private func launch(language: String = "en", largeType: Bool = false, previewOnly: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_ONBOARDING_UI_TEST": "1", "MASO_ONBOARDING_LARGE_TYPE": largeType ? "1" : "0", "MASO_ONBOARDING_PREVIEW_ONLY": previewOnly ? "1" : "0"]
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<6 {
            // XCUI can report offscreen SwiftUI scroll content as hittable beneath
            // a safe-area footer. Keep the actual tap within the visible viewport.
            let frame = element.frame
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.buttons["onboarding.continue"].frame.minY
            if element.exists && element.isHittable && frame.minY >= top && frame.maxY < bottom { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func wait(_ predicate: @escaping () -> Bool, timeout: TimeInterval = 4) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: timeout) == .completed
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "onboarding-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
