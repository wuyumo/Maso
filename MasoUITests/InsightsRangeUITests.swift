import XCTest

@MainActor
final class InsightsRangeUITests: XCTestCase {
    func testFirstCardUpdatesWithRealRangeMenuAndRestoresWeek() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SHOWCASE": "insights"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let picker = app.buttons["insights.range"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        func count() -> Int {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "insights.muscle.")).allElementsBoundByIndex.reduce(0) {
                $0 + (Int(($1.value as? String ?? "").filter(\.isNumber)) ?? 0)
            }
        }
        let week = count()
        picker.tap()
        app.buttons["4 weeks"].tap()
        let caption = app.staticTexts["insights.muscles.range"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertTrue(caption.label.contains("4 weeks"))
        XCTAssertGreaterThan(count(), week, "Seed has older sets that must appear in the first card")
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "workout-range-four-weeks"; image.lifetime = .keepAlways; add(image)
        picker.tap()
        app.buttons["This week"].tap()
        XCTAssertTrue(caption.label.contains("This week"))
        XCTAssertEqual(count(), week)
    }
}
