import XCTest

/// Types into the real Coach composer. Confirm, cancel, and undo are replies, not the swap buttons.
final class CoachEquipmentSwapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testComposerConfirmsThenUndoes() {
        let app = launch()
        let input = composer(app)
        send(app, input, "把所有练胸的杠铃器械都换成machine")
        XCTAssertTrue(preview(app).waitForExistence(timeout: 8))
        XCTAssertTrue(unmatched(app).waitForExistence(timeout: 2))
        XCTAssertFalse(applied(app).exists)
        send(app, input, "就这样改")
        XCTAssertTrue(applied(app).waitForExistence(timeout: 8))
        send(app, input, "撤销")
        XCTAssertTrue(undone(app).waitForExistence(timeout: 8))
    }

    func testComposerCancelsWithoutApplying() {
        let app = launch()
        let input = composer(app)
        send(app, input, "把所有练胸的杠铃器械都换成machine")
        XCTAssertTrue(preview(app).waitForExistence(timeout: 8))
        send(app, input, "取消")
        XCTAssertTrue(cancelled(app).waitForExistence(timeout: 8))
        XCTAssertFalse(applied(app).exists)
    }

    func testUnknownInputIsNotSentToTheAI() {
        let app = launch()
        let input = composer(app)
        send(app, input, "今天练什么")
        XCTAssertTrue(blocked(app).waitForExistence(timeout: 8))
        XCTAssertFalse(applied(app).exists)
    }

    func testNativeUserMessageMenuEditCancelPreservesDraft() {
        for language in ["en", "zh-Hans"] {
            let app = launchMessageMenu(language)
            let input = composer(app)
            input.tap(); input.typeText("KEEP my unsent draft")
            let original = userMessages(app).firstMatch
            XCTAssertTrue(original.waitForExistence(timeout: 10))
            original.press(forDuration: 1)
            let copy = app.buttons[language == "en" ? "Copy message" : "复制信息"]
            XCTAssertTrue(copy.waitForExistence(timeout: 5))
            let edit = app.buttons[language == "en" ? "Edit and resend" : "编辑后重发"]
            XCTAssertTrue(edit.exists)
            snapshot(app, language + "-native-menu")
            edit.tap()
            XCTAssertEqual(input.value as? String, "Fixture original message — 原文 3 × 10")
            snapshot(app, language + "-edit-composer")
            app.buttons["coach.edit.cancel"].tap()
            XCTAssertEqual(input.value as? String, "KEEP my unsent draft")
            XCTAssertEqual(userMessages(app).count, 1)
            snapshot(app, language + "-cancel-draft-restored")
            app.terminate()
        }
    }

    func testNativeCopyActionPastesExactOriginalWithoutSending() {
        for language in ["en","zh-Hans"] {
            let app = launchMessageMenu(language)
            userMessages(app).firstMatch.press(forDuration:1)
            let copy = app.buttons[language == "en" ? "Copy message" : "复制信息"]
            XCTAssertTrue(copy.waitForExistence(timeout:5)); copy.tap()
            let input = composer(app); input.tap(); input.press(forDuration:1)
            let predicate = NSPredicate(format:"label IN %@",["Paste","粘贴","貼上"])
            let menu = app.menuItems.matching(predicate).firstMatch
            let button = app.buttons.matching(predicate).firstMatch
            if menu.waitForExistence(timeout:3) { menu.tap() } else { XCTAssertTrue(button.waitForExistence(timeout:3)); button.tap() }
            XCTAssertEqual(input.value as? String,"Fixture original message — 原文 3 × 10")
            XCTAssertEqual(userMessages(app).count,1)
            snapshot(app,language + "-49-native-copy-pasted-exactly")
            app.terminate()
        }
    }
    func testNativeEditResendAppendsWithoutRemovingOriginalTurn() {
        for language in ["en", "zh-Hans"] {
            let app = launchMessageMenu(language)
            let input = composer(app)
            userMessages(app).firstMatch.press(forDuration: 1)
            app.buttons[language == "en" ? "Edit and resend" : "编辑后重发"].tap()
            input.tap(); input.typeText(" updated")
            snapshot(app, language + "-before-resend")
            app.buttons["coach.send"].tap()
            let two = NSPredicate(format: "count == 2")
            expectation(for: two, evaluatedWith: userMessages(app)); waitForExpectations(timeout: 8)
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fixture original reply")).firstMatch.exists)
            snapshot(app, language + "-after-resend-original-preserved")
            app.terminate()
        }
    }

    func testStrictSourceSingleTwoAndPhotoPreviewsAreNativeAndNotAutosaved() {
        for mode in ["text","two","image"] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MASO_COACH_CHAT_UI_TEST":"1","MASO_SOURCE_EXTRACT_UI_TEST":mode]
            app.launchArguments = ["-maso.selectedLanguage",mode == "image" ? "zh-Hans" : "en"]
            app.launch()
            let carousel = app.scrollViews["coach.planCarousel"]
            XCTAssertTrue(carousel.waitForExistence(timeout:20))
            XCTAssertEqual(carousel.value as? String,mode == "two" ? "2" : "1")
            snapshot(app,"source49-" + mode + "-synthetic-preview")
            app.swipeUp(); snapshot(app,"source49-" + mode + "-synthetic-save-preview")
            app.terminate()
        }
    }
    func testNativeMenuRTLAndGermanAccessibleTypeKeepsDraftAndOriginalTurn() throws {
        for language in ["de","ar"] {
            let app = launchMessageMenu(language,largeType:true)
            let input = composer(app); input.tap(); input.typeText("KEEP draft48")
            let original = userMessages(app).firstMatch
            original.press(forDuration:1)
            let label = language == "de" ? "Bearbeiten und erneut senden" : "\u{062a}\u{062d}\u{0631}\u{064a}\u{0631} \u{0648}\u{0625}\u{0639}\u{0627}\u{062f}\u{0629} \u{0625}\u{0631}\u{0633}\u{0627}\u{0644}"
            let edit = app.buttons[label]; XCTAssertTrue(edit.waitForExistence(timeout:5))
            snapshot(app,language + "-large-native-menu49")
            edit.tap(); XCTAssertEqual(input.value as? String,"Fixture original message \u{2014} \u{539f}\u{6587} 3 \u{00d7} 10")
            let cancel = app.buttons["coach.edit.cancel"]
            XCTAssertTrue(cancel.isHittable); XCTAssertGreaterThanOrEqual(cancel.frame.width,44); XCTAssertGreaterThanOrEqual(cancel.frame.height,44)
            XCTAssertFalse(app.buttons["coach.ai-access"].exists)
            XCTAssertGreaterThanOrEqual(input.frame.minY,app.navigationBars.firstMatch.frame.maxY)
            XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY + 2)
            snapshot(app,language + "-large-edit49")
            app.buttons["coach.edit.cancel"].tap(); XCTAssertEqual(input.value as? String,"KEEP draft48")
            XCTAssertEqual(userMessages(app).count,1)
            // Audit app controls after dismissing Apple's prediction keyboard. Its TUIPredictionViewCell has an SDK audit defect.
            app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","Fixture original reply")).firstMatch.tap()
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            try app.performAccessibilityAudit(for:.sufficientElementDescription)
            snapshot(app,language + "-large-cancel49")
            app.terminate()
        }
    }


    func testAIRulesEntryInTrainingPreferencesNormalFreeAndPro() throws {
        try verifyAIRulesEntryInPreferences(large: false)
    }

    // Run with simctl content_size accessibility-extra-extra-large, not only a presenter override.
    func testAIRulesEntryInTrainingPreferencesAtSystemLargeSize() throws {
        try verifyAIRulesEntryInPreferences(large: true)
    }

    private func verifyAIRulesEntryInPreferences(large: Bool) throws {
        for (language, pro) in [("en", false), ("en", true), ("zh-Hans", false), ("ar", false)] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MASO_COACH_CHAT_UI_TEST":"1", "MASO_COACH_MESSAGE_MENU_TEST":"1",
                "MASO_COACH_PRO_TEST":pro ? "1":"0", "MASO_COACH_LARGE_TYPE":large ? "1":"0",
                "MASO_UI_LIGHT":language == "zh-Hans" ? "1":"0"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let preferences = app.buttons["coach.training-preferences"]
            XCTAssertTrue(preferences.waitForExistence(timeout:15))
            XCTAssertFalse(app.buttons["coach.ai-access"].exists)
            let name = "51-" + language + (pro ? "-pro":"-free") + (large ? "-system-large":"-normal")
            snapshot(app, name + "-coach-no-old-link")
            preferences.tap()
            let entry = app.buttons["training-preferences.ai-access"]
            for _ in 0..<12 {
                if entry.exists && entry.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(entry.exists && entry.isHittable)
            XCTAssertGreaterThanOrEqual(entry.frame.height + 0.001,44)
            XCTAssertGreaterThan(entry.label.count,5)
            XCTAssertLessThan(entry.frame.minX,app.frame.midX)
            snapshot(app,name + "-preferences-bottom")
            entry.tap()
            XCTAssertTrue(app.staticTexts["ai.policy.device-scope"].waitForExistence(timeout:8))
            snapshot(app,name + "-actual-details")
            let detailBar = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
            detailBar.buttons.firstMatch.tap()
            XCTAssertTrue(entry.waitForExistence(timeout:5))
            snapshot(app,name + "-back-to-preferences")
            let preferenceBar = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
            preferenceBar.buttons.firstMatch.tap()
            XCTAssertTrue(preferences.waitForExistence(timeout:5))
            XCTAssertEqual(userMessages(app).count,1)
            XCTAssertFalse(app.buttons["coach.ai-access"].exists)
            snapshot(app,name + "-back-to-original-coach")
            app.terminate()
        }
    }


    func testMachineChestPressChineseEnglishAndTraditionalNativeSource() throws {
        for (language,name) in [("en","Chest Press"),("zh-Hans","\u{63a8}\u{80f8}"),("zh-Hant","\u{63a8}\u{80f8}")] {
            let app = XCUIApplication()
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE":"stable-player",
                "MASO_MARKETING_PLAYER":"1", "MASO_MARKETING_EXERCISE_ID":"bench_press_machine",
                "MASO_WORKOUT_HEART_FIXTURE":"1", "MASO_WORKOUT_HEART_CARD":"1",
                "MASO_TEST_HEART_LIMIT":"180", "MASO_TEST_HEART_BPM":"185"]
            app.launchArguments = ["-maso.selectedLanguage",language,"-AppleLanguages","(\(language))","-AppleLocale",language]
            app.launch()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout:20))
            XCTAssertTrue(app.staticTexts["185"].waitForExistence(timeout:5))
            snapshot(app,"51-machine-press-185-" + language + "-synthetic-native")
            app.terminate()
        }
    }

    private func launchMessageMenu(_ language: String, largeType:Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MASO_COACH_CHAT_UI_TEST": "1", "MASO_COACH_MESSAGE_MENU_TEST": "1", "MASO_COACH_LARGE_TYPE": largeType ? "1" : "0"]
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch(); return app
    }

    private func userMessages(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'coach.user-message.'"))
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "coach-" + name; a.lifetime = .keepAlways; add(a)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["MASO_COACH_CHAT_UI_TEST": "1"]
        app.launch()
        return app
    }

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let input = app.textViews["coachPromptInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        return input
    }

    private func send(_ app: XCUIApplication, _ input: XCUIElement, _ text: String) {
        input.tap()
        input.typeText(text)
        app.buttons["coach.send"].tap()
    }

    private func preview(_ app: XCUIApplication) -> XCUIElement {
        either(app, "还没写入", "Nothing is saved yet")
    }

    private func unmatched(_ app: XCUIApplication) -> XCUIElement {
        either(app, "没有合适替代", "no suitable replacement")
    }

    private func applied(_ app: XCUIApplication) -> XCUIElement {
        either(app, "已替换", "Replaced ")
    }

    private func undone(_ app: XCUIApplication) -> XCUIElement {
        either(app, "已撤销", "Undid that replacement")
    }

    private func cancelled(_ app: XCUIApplication) -> XCUIElement {
        either(app, "已取消", "Cancelled.")
    }

    private func blocked(_ app: XCUIApplication) -> XCUIElement {
        either(app, "Isolated coach: not sent.", "Isolated coach: not sent.")
    }

    private func either(_ app: XCUIApplication, _ zh: String, _ en: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", zh, en)
        return app.staticTexts.matching(predicate).firstMatch
    }
}
