import XCTest

@MainActor
final class HomeQuickActionUITests: XCTestCase {
    func testCalendarShareSwitchesWeekMonthWithSharedFooter() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SCREENSHOT_CAPTURE": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let menu = app.buttons["home.calendar.more"]
        for _ in 0..<6 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        let share = app.buttons["calendar.share.rhythm"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let period = app.segmentedControls["calendar.share.period"]
        XCTAssertTrue(period.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Average sleep"].exists)
        XCTAssertFalse(app.staticTexts["A missing log is not a missed workout"].exists)
        XCTAssertFalse(app.staticTexts["Heart rate, body weight, location, and your name stay off this card."].exists)
        period.buttons["Month"].tap()
        XCTAssertTrue(app.staticTexts["This month"].exists)
        period.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["This week"].exists)
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "share.footer.qr").firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "calendar-share-shared-footer"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private func menu(_ title: String) {
        XCUIDevice.shared.press(.home)
        let query = springboard.icons.matching(identifier: "Masso")
        func visibleIcon() -> XCUIElement? { query.allElementsBoundByIndex.first { $0.isHittable } }
        for _ in 0..<8 where visibleIcon() == nil { springboard.swipeLeft() }
        for _ in 0..<8 where visibleIcon() == nil { springboard.swipeRight() }
        guard let icon = visibleIcon() else { XCTFail(springboard.debugDescription); return }
        // Public Haptic Touch + slide gesture, using the observed iPhone 17 Pro
        // Home menu layout. Avoids SpringBoard's 60s idle waits with a menu open.
        let rows: [String: CGFloat] = ["Start workout": 0.404, "Add meal": 0.450, "Free workout": 0.498, "AI Coach": 0.547]
        let target = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.625, dy: rows[title]!))
        icon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: target)
    }
    func testActualHomeIconMenuColdMealWarmFreeWorkoutAndCoach() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 20))
        // Root's normal background flush persists the onboarding-complete fixture for an OS cold launch.
        XCUIDevice.shared.press(.home)
        app.terminate()
        menu("Add meal")
        XCTAssertTrue(app.navigationBars["Add meal"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.textViews.firstMatch.exists)
        let cold = XCTAttachment(screenshot: app.screenshot()); cold.name = "quick-action-cold-meal"; cold.lifetime = .keepAlways; add(cold)
        app.navigationBars["Add meal"].buttons["Cancel"].tap()
        menu("Free workout")
        XCTAssertTrue(app.navigationBars["Choose your first exercise"].waitForExistence(timeout: 10))
        let free = XCTAttachment(screenshot: app.screenshot()); free.name = "quick-action-free-picker"; free.lifetime = .keepAlways; add(free)
        // Dismiss through the picker sheet, then verify the fourth menu entry on a warm scene.
        app.navigationBars["Choose your first exercise"].buttons["Cancel"].tap()
        menu("AI Coach")
        XCTAssertTrue(app.navigationBars["AI Coach"].waitForExistence(timeout: 15))
        let coach = XCTAttachment(screenshot: app.screenshot()); coach.name = "quick-action-coach"; coach.lifetime = .keepAlways; add(coach)

    }
    func testHomeWorkoutCardLongPressMenu() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 20))
        let start = app.buttons["workout.card.start"].firstMatch
        for _ in 0..<8 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let point = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -100, dy: -90))
        point.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "home-workout-context-menu"; image.lifetime = .keepAlways; add(image)
    }

    func testWorkoutShortcutResumesSavedProgressWithContinuousHomeGesture() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = [:]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 20))
        menu("Start workout")
        let progress = app.descendants(matching: .any).matching(identifier: "workout.progress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        let complete = app.buttons["Complete set"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        let completedProgress = progress.value as? String
        XCTAssertTrue(completedProgress?.hasPrefix("1/") == true)
        XCUIDevice.shared.press(.home)
        app.terminate()
        menu("Start workout")
        XCTAssertTrue(progress.waitForExistence(timeout: 25))
        XCTAssertEqual(progress.value as? String, completedProgress, "A cold shortcut resumes the completed set instead of creating a new workout")
        let resume = XCTAttachment(screenshot: app.screenshot()); resume.name = "quick-action-resumed-workout"; resume.lifetime = .keepAlways; add(resume)
    }

}
