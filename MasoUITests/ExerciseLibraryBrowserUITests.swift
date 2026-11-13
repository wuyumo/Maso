import XCTest

/// These tests run in a separate XCTest runner so SwiftUI builds its real
/// accessibility tree. They tap, type, swipe and observe production sheet state.
@MainActor
final class ExerciseLibraryBrowserUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCoachGeneratedPlanCarouselUsesFullScreenWidth() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-save"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let carousel = app.scrollViews["coach.planCarousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 15))
        XCTAssertEqual(carousel.frame.minX, app.frame.minX, accuracy: 2)
        XCTAssertEqual(carousel.frame.maxX, app.frame.maxX, accuracy: 2)
        carousel.swipeLeft()
        XCTAssertTrue(app.staticTexts["DAY 2"].isHittable)
        capture(app, name: "coach-full-width-carousel")
    }

    func testCoachCarouselFitsTallestPlanBeforeAndAfterSwipe() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "coach-save", "MASO_COACH_TALL_CARD": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let carousel = app.scrollViews["coach.planCarousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 15))
        let initialHeight = carousel.frame.height
        carousel.swipeLeft()
        let tallCard = app.descendants(matching: .any).matching(identifier: "plan.carousel.card.1").firstMatch
        XCTAssertTrue(tallCard.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(tallCard.frame.height, 0)
        XCTAssertLessThanOrEqual(tallCard.frame.height, carousel.frame.height + 1)
        XCTAssertEqual(initialHeight, carousel.frame.height, accuracy: 2)
        capture(app, name: "coach-tall-card")
    }

    func testPickerFamilyInlineExpansionDetailAndSelectionInActualSheet() throws {
        let app = try launch(scene: "choose")
        let familyIDs = try exerciseIDs(in: "bench_press.flat")
        let expand = element("exercise.family.expand.name.bench press", in: app)
        try reveal(expand, in: app)
        XCTAssertEqual(primaryIDs(in: app).intersection(familyIDs), ["bench_press_barbell"])
        expand.tap()
        let rare = element("exercise.primary.bench_press_paused", in: app)
        try reveal(rare, in: app)
        XCTAssertTrue(rare.isHittable)
        XCTAssertFalse(element("exercise.family.more.name.bench press", in: app).exists)
        XCTAssertTrue(element("exercise.library.filters", in: app).exists)
        XCTAssertFalse(element("exercise.family.versions", in: app).exists)
        capture(app, name: "en-choose-all-inline")
        let collapse = element("exercise.family.collapse.name.bench press", in: app)
        try reveal(collapse, in: app)
        collapse.tap()
        XCTAssertTrue(collapse.waitForNonExistence(timeout: 5))

        // A fresh presentation puts the concrete favourite and its independent i
        // action on screen without relying on the List's restored scroll offset.
        app.terminate()
        let selectionApp = try launch(scene: "choose")
        let info = element("exercise.info.bench_press_barbell", in: selectionApp)
        try requireHittable(info)
        info.tap()
        let detailPin = selectionApp.buttons["Unpin"].firstMatch
        XCTAssertTrue(detailPin.waitForExistence(timeout: 10), "i opens the real Exercise Details sheet")
        capture(selectionApp, name: "en-choose-details")
        let done = selectionApp.buttons.matching(identifier: "Done").allElementsBoundByIndex.first(where: \.isHittable)
        try XCTUnwrap(done).tap()
        let primary = element("exercise.primary.bench_press_barbell", in: selectionApp)
        try requireHittable(primary)
        XCTAssertTrue(element("exercise.library.filters", in: selectionApp).exists, "i must leave the picker open")
        primary.tap()
        try assertSelection("bench_press_barbell", in: selectionApp)
    }

    func testInlineFamilyExpansionInLibraryAndPickerAcrossLanguages() throws {
        for language in ["zh-Hans", "ar"] {
            for scene in ["library", "choose"] {
                let app = try launch(scene: scene, language: language)
                let expand = element("exercise.family.expand.name.bench press", in: app)
                try reveal(expand, in: app)
                expand.tap()
                let rare = element("exercise.primary.bench_press_paused", in: app)
                try reveal(rare, in: app)
                XCTAssertTrue(rare.isHittable)
                XCTAssertFalse(element("exercise.family.more.name.bench press", in: app).exists)
                XCTAssertFalse(element("exercise.family.versions", in: app).exists)
                capture(app, name: "\(language)-\(scene)-all")
                if scene == "choose" {
                    rare.tap()
                    try assertSelection("bench_press_paused", in: app)
                }
                app.terminate()
            }
        }
    }

    func testReplacementRecommendationSelectsOnceAndDoesNotReopenSheet() throws {
        let app = try launch(scene: "replace")
        let first = element("exercise.primary.bench_press_dumbbell", in: app)
        try requireHittable(first)
        capture(app, name: "en-replace-recommendations")
        first.tap()
        try assertSelection("bench_press_dumbbell", in: app)
        // Wait through a complete presentation cycle; no follow-up picker or
        // parameter sheet may appear after the original dismissal callback.
        let remainedClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.element("exercise.library.filters", in: app).exists
        }, object: nil)
        remainedClosed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [remainedClosed], timeout: 1.5), .completed)
        XCTAssertEqual(app.staticTexts["exercise.ui-test.selection-count"].label, "1")
        XCTAssertEqual(app.staticTexts["exercise.ui-test.dismissal-count"].label, "1")
    }

    func testExactSearchShowsConcreteVersionInTheRealPicker() throws {
        let app = try launch(scene: "choose")
        let search = app.searchFields.firstMatch
        try requireHittable(search)
        search.tap()
        search.typeText("Incline Dumbbell Bench Press")
        let result = element("exercise.primary.incline_bench_press_dumbbell", in: app)
        try requireHittable(result)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture(app, name: "en-choose-exact-search-keyboard")
        result.tap()
        try assertSelection("incline_bench_press_dumbbell", in: app)
    }

    func testExerciseMediaReportQueuesOfflineWithoutSending() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "library", "MASO_SHOWCASE_SEED": "1", "MASO_FEEDBACK_TEST_OFFLINE": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(element("exercise.library.filters", in: app).waitForExistence(timeout: 20))
        if !app.searchFields.firstMatch.exists { app.buttons["Search"].firstMatch.tap() }
        let search = app.searchFields.firstMatch
        try requireHittable(search)
        search.tap(); search.typeText("Cat-Cow")
        let row = element("exercise.primary.cat_cow", in: app)
        try requireHittable(row); row.tap()
        let report = element("exercise.media.report", in: app)
        try reveal(report, in: app)
        capture(app, name: "media-report-entry")
        report.tap()
        XCTAssertTrue(app.staticTexts["Cat-Cow Stretch"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Submit report"].exists)
        XCTAssertFalse(app.buttons["Submit report"].isEnabled)
        app.buttons["Wrong exercise"].tap()
        XCTAssertTrue(app.buttons["Submit report"].isEnabled)
        app.buttons["Submit report"].tap()
        XCTAssertTrue(element("feedback.queued", in: app).waitForExistence(timeout: 10))
        capture(app, name: "media-report-offline")
        app.terminate()
    }

    func testAdoptedDemoPostersVisibleBeforeOpeningDetails() throws {
        for query in ["Cat-Cow", "Chest Fly"] {
            let app = try launch(scene: "library")
            if !app.searchFields.firstMatch.exists { app.buttons["Search"].firstMatch.tap() }
            let search = app.searchFields.firstMatch
            try requireHittable(search)
            search.tap(); search.typeText(query)
            capture(app, name: "poster-before-detail-\(query)")
            let id = query == "Cat-Cow" ? "cat_cow" : "dumbbell_fly_flat"
            let row = element("exercise.primary.\(id)", in: app)
            try requireHittable(row)
            row.tap()
            XCTAssertTrue(element("exercise.media.hero", in: app).waitForExistence(timeout: 8))
            capture(app, name: "poster-detail-\(query)")
            app.terminate()
        }
    }

    func testActualExercisesChooseAndReplacePagesInFourLanguages() throws {
        for language in ["en", "zh-Hans", "de", "ar"] {
            for scene in ["library", "choose", "replace"] {
                let app = try launch(scene: scene, language: language)
                let scope = element("exercise.library.filters", in: app)
                XCTAssertLessThan(scope.frame.minY, app.frame.height * 0.35,
                                  "The native large sheet must finish its presentation before capture")
                XCTAssertTrue(app.navigationBars.firstMatch.exists)
                XCTAssertGreaterThan(scrollContainer(in: app).frame.height, app.frame.height * 0.45)
                let topIDs = primaryIDs(in: app)
                XCTAssertFalse(topIDs.isEmpty)
                capture(app, name: "\(language)-\(scene)-top")
                scrollContainer(in: app).swipeUp()
                XCTAssertTrue(scope.exists)
                XCTAssertFalse(primaryIDs(in: app).isEmpty)
                capture(app, name: "\(language)-\(scene)-scrolled")
                app.terminate()
            }
        }
    }

    private func launch(scene: String, language: String = "en") throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene, "MASO_SHOWCASE_SEED": "1"]
        // Standard launch arguments override the app preference only in this
        // process; LanguageManager then applies its normal localization pathway.
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        print("EXERCISE_UI_LAUNCH \(scene) \(language) \(app.launchEnvironment)")
        app.launch()
        let scope = element("exercise.library.filters", in: app)
        guard wait(timeout: 20, { scope.exists && scope.isHittable }) else {
            capture(app, name: "\(language)-\(scene)-launch-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "exercise-ui-launch-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTFail("Production exercise sheet did not become ready: \(scene), \(language)")
            throw FixtureError.missingControl
        }
        return app
    }

    private func assertSelection(_ id: String, in app: XCUIApplication) throws {
        let selected = app.staticTexts["exercise.ui-test.selection-id"]
        XCTAssertTrue(wait { selected.exists && selected.label == id })
        XCTAssertEqual(app.staticTexts["exercise.ui-test.selection-count"].label, "1")
        XCTAssertTrue(wait { app.staticTexts["exercise.ui-test.dismissal-count"].label == "1" })
        XCTAssertFalse(element("exercise.library.filters", in: app).exists)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func requireHittable(_ element: XCUIElement, timeout: TimeInterval = 10) throws {
        let ready = wait(timeout: timeout) { element.exists && element.isHittable }
        XCTAssertTrue(ready, "Visible native control did not become hittable")
        if !ready { throw FixtureError.missingControl }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            scrollContainer(in: app).swipeUp()
        }
        try requireHittable(element)
    }

    private func scrollContainer(in app: XCUIApplication) -> XCUIElement {
        if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
        if app.tables.firstMatch.exists { return app.tables.firstMatch }
        return app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height } ?? app
    }

    private func primaryIDs(in app: XCUIApplication) -> Set<String> {
        let prefix = "exercise.primary."
        return Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.map { String($0.identifier.dropFirst(prefix.count)) })
    }

    private func exerciseIDs(in family: String) throws -> Set<String> {
        struct Catalog: Decodable {
            struct Entry: Decodable { let exerciseID: String; let programmingGroupID: String }
            let entries: [Entry]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "exercise-selection", withExtension: "json"))
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        return Set(catalog.entries.filter { $0.programmingGroupID == family }.map(\.exerciseID))
    }

    private func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "exercise-library-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum FixtureError: Error { case missingControl }
}

@MainActor
final class TrainingRefinementsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scene: String, language: String = "en", emptyWeight: Bool = false, emptyMeals: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene]
        if scene == "diet-health" { app.launchEnvironment["MASO_HEALTH_BODY_FIXTURE"] = "1" }
        if emptyWeight { app.launchEnvironment["MASO_TEST_EMPTY_WEIGHT"] = "1" }
        if emptyMeals { app.launchEnvironment["MASO_TEST_EMPTY_MEALS"] = "1" }
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        // A simulator reinstall can restore a pending widget launch before XCTest's
        // environment is applied. Retry only when the real home (not this host) is visible.
        if !app.buttons["exercise.ui-test.open"].waitForExistence(timeout: 3), app.buttons["home.settings"].exists {
            app.terminate()
            app.launch()
        }
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testWorkoutVariantDropdownSwitchesWithinIntentAndQueueAddIsInHeader() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("short-player", language: language)
            let menu = element("workout.variants", app)
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            let title = element("workout.current.info", app)
            let original = title.label
            menu.tap()
            let dumbbell = app.buttons["workout.variant.bench_press_dumbbell"]
            XCTAssertTrue(dumbbell.waitForExistence(timeout: 5))
            capture(app, "\(language)-variants-menu")
            dumbbell.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                title.exists && title.label != original
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            menu.tap()
            let base = app.buttons["workout.variant.bench_press_barbell"]
            XCTAssertTrue(base.waitForExistence(timeout: 5)); base.tap()
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in title.label == original }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
            element("workout.playlist.toggle", app).tap()
            let addButton = element("workout.queue.add", app)
            XCTAssertTrue(addButton.waitForExistence(timeout: 5))
            XCTAssertTrue(addButton.isHittable)
            capture(app, "\(language)-queue-header")
            addButton.tap()
            XCTAssertTrue(element("exercise.picker.search", app).waitForExistence(timeout: 5) || app.searchFields.firstMatch.exists)
            app.terminate()
        }
    }

    func testShareUploadMarginsAndFooterGeometryInNativeSheet() {
        for language in ["en", "zh-Hans", "ar"] {
            for hasPhoto in [false, true] {
                let app = launch(hasPhoto ? "share-layout-photo" : "share-layout", language: language)
                let upload = app.buttons["share.photo.upload"]
                XCTAssertTrue(upload.waitForExistence(timeout: 15))
                XCTAssertEqual(upload.frame.minX, app.frame.minX + 16, accuracy: 1)
                XCTAssertEqual(upload.frame.maxX, app.frame.maxX - 16, accuracy: 1)
                capture(app, "\(language)-share-upload-\(hasPhoto)")
                upload.tap()
                let cancel = app.buttons.matching(NSPredicate(format: "label == %@", language == "zh-Hans" ? "取消" : language == "ar" ? "إلغاء" : "Cancel")).allElementsBoundByIndex.last!
                XCTAssertTrue(cancel.waitForExistence(timeout: 5))
                cancel.tap()
                let qr = element("share.footer.qr", app)
                for _ in 0..<5 where !qr.isHittable { app.swipeUp() }
                XCTAssertTrue(qr.exists)
                let brand = element("share.footer.brand", app)
                XCTAssertLessThanOrEqual(qr.frame.maxY, brand.frame.minY)
                XCTAssertFalse(app.staticTexts["Train with Masso"].exists)
                if hasPhoto {
                    let photo = element("share.footer.photo", app)
                    XCTAssertTrue(photo.exists)
                    XCTAssertEqual(photo.frame.width, photo.frame.height, accuracy: 1)
                    XCTAssertEqual(photo.frame.width, qr.frame.width, accuracy: 1)
                    XCTAssertEqual(photo.frame.height, qr.frame.height, accuracy: 1)
                    XCTAssertGreaterThan(photo.frame.minX, qr.frame.maxX)
                    XCTAssertEqual(photo.frame.maxX, app.frame.maxX - 20, accuracy: 1)
                    XCTAssertEqual(photo.frame.minY, qr.frame.minY, accuracy: 1)
                } else {
                    XCTAssertFalse(element("share.footer.photo", app).exists)
                    XCTAssertEqual(qr.frame.midX, app.frame.midX, accuracy: 1)
                    XCTAssertEqual(brand.frame.midX, app.frame.midX, accuracy: 1)
                }
                capture(app, "\(language)-share-footer-\(hasPhoto)")
                app.terminate()
            }
        }
    }

    func testMealTimeCanBackdateSaveAndReopenAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("diet-targets", language: language)
            let addMeal = app.buttons["diet.add-meal"]
            XCTAssertTrue(addMeal.waitForExistence(timeout: 15))
            addMeal.tap()
            let picker = app.datePickers["meal.time"]
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            let initial = picker.buttons.firstMatch.value as? String ?? ""
            XCTAssertFalse(initial.isEmpty)
            capture(app, "\(language)-meal-time-default")
            picker.buttons.firstMatch.tap()
            let calendarPicker = app.datePickers.matching(NSPredicate(format: "identifier != %@", "meal.time")).firstMatch
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
            if calendar.component(.day, from: Date()) == 1 { app.buttons["DatePicker.PreviousMonth"].tap() }
            let day = calendar.component(.day, from: yesterday)
            let date = calendarPicker.staticTexts.allElementsBoundByIndex.first {
                Int($0.label.compactMap { $0.wholeNumberValue }.map(String.init).joined()) == day
            }
            XCTAssertNotNil(date)
            date?.tap()
            if app.buttons["PopoverDismissRegion"].exists {
                app.buttons["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
            }
            picker.buttons.allElementsBoundByIndex.last!.tap()
            let hour = app.pickerWheels.firstMatch
            XCTAssertTrue(hour.waitForExistence(timeout: 5))
            let previousHour = hour.value as? String
            hour.swipeUp()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in hour.value as? String != previousHour }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            if app.buttons["PopoverDismissRegion"].exists {
                app.buttons["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
            }
            let selected = picker.buttons.firstMatch.value as? String ?? ""
            XCTAssertNotEqual(selected, initial)
            let input = app.textViews.firstMatch
            input.tap(); input.typeText("200 grams cooked chicken breast")
            app.buttons["meal.save"].tap()
            XCTAssertTrue(input.waitForNonExistence(timeout: 10))
            let archive = app.buttons["history.all"]
            for _ in 0..<4 where !archive.isHittable { app.swipeUp() }
            XCTAssertTrue(archive.isHittable)
            archive.tap()
            let food = app.staticTexts["200 grams cooked chicken breast"].firstMatch
            XCTAssertTrue(food.waitForExistence(timeout: 5))
            capture(app, "\(language)-meal-time-backdated-record")
            food.tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertEqual(picker.buttons.firstMatch.value as? String, selected)
            capture(app, "\(language)-meal-time-reopened")
            app.terminate()
        }
    }

    func testCaloriesUpdateAfterMealAndAppearInHistoryAndEditor() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("diet-targets", language: language)
            let calories = element("diet.daily.calories", app)
            XCTAssertTrue(calories.waitForExistence(timeout: 15))
            func labels(_ item: XCUIElement) -> String {
                item.label + item.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label).joined()
            }
            XCTAssertTrue(labels(calories).contains("—"))
            capture(app, "\(language)-calories-empty")
            app.buttons["diet.add-meal"].tap()
            let input = app.textViews.firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.tap(); input.typeText("200 grams cooked chicken breast")
            app.buttons["meal.save"].tap()
            XCTAssertTrue(input.waitForNonExistence(timeout: 10))
            XCTAssertFalse(labels(calories).contains("≈"))
            capture(app, "\(language)-calories-saved")
            let recordCalories = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "kcal", "/")).firstMatch
            for _ in 0..<4 where !recordCalories.isHittable { app.swipeUp() }
            XCTAssertTrue(recordCalories.exists, app.debugDescription)
            XCTAssertTrue(recordCalories.label.contains("kcal"))
            capture(app, "\(language)-calories-history")
            app.staticTexts["200 grams cooked chicken breast"].firstMatch.tap()
            XCTAssertTrue(app.datePickers["meal.time"].waitForExistence(timeout: 5))
            let estimate = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "kcal")).firstMatch
            for _ in 0..<4 where !estimate.isHittable { app.swipeUp() }
            XCTAssertTrue(estimate.exists)
            XCTAssertTrue(estimate.label.contains("≈"))
            capture(app, "\(language)-calories-editor")
            app.terminate()
        }
    }

    func testSavedNutritionTargetsMatchTheDailyCardAndReopenedEditor() {
        func grams(_ text: String) -> Int? {
            let digits = text.compactMap { $0.wholeNumberValue }.map(String.init).joined()
            return Int(digits)
        }
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("diet-targets", language: language)
            let preferences = app.buttons["diet.preferences"]
            XCTAssertTrue(preferences.waitForExistence(timeout: 15))
            preferences.tap()
            var expected: [String: Int] = [:]
            let calorieTarget = element("diet.target.calories", app)
            XCTAssertTrue(calorieTarget.waitForExistence(timeout: 5))
            let initialCalories = calorieTarget.label
            for (id, position) in [("protein", CGFloat(0.62)), ("carbs", CGFloat(0.77)), ("fat", CGFloat(0.42))] {
                let slider = app.sliders["diet.target.slider.\(id)"]
                XCTAssertTrue(slider.waitForExistence(timeout: 5))
                if !slider.isHittable { app.swipeUp() }
                slider.adjust(toNormalizedSliderPosition: position)
                expected[id] = grams(slider.value as? String ?? "")
                XCTAssertNotNil(expected[id])
            }
            XCTAssertNotEqual(calorieTarget.label, initialCalories)
            let expectedCalories = expected["protein"]! * 4 + expected["carbs"]! * 4 + expected["fat"]! * 9
            XCTAssertEqual(grams(calorieTarget.label), expectedCalories)
            capture(app, "\(language)-nutrition-targets-edited")
            app.buttons["diet.preferences.save"].tap()
            XCTAssertTrue(preferences.waitForExistence(timeout: 5))
            for id in ["protein", "carbs", "fat"] {
                let metric = element("diet.daily.\(id)", app)
                XCTAssertTrue(metric.exists)
                let label = metric.descendants(matching: .staticText).allElementsBoundByIndex
                    .map(\.label).first { $0.contains("/") } ?? metric.label
                XCTAssertEqual(grams(label), expected[id], "Saved \(id) must be used exactly on the daily card: \(label)")
            }
            capture(app, "\(language)-nutrition-targets-applied")
            preferences.tap()
            for id in ["protein", "carbs", "fat"] {
                XCTAssertEqual(grams(app.sliders["diet.target.slider.\(id)"].value as? String ?? ""), expected[id])
            }
            app.terminate()
        }
    }

    func testHealthBodyReferenceAndProfileAdoptionAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("diet-health", language: language)
            let reference = app.buttons["settings.health-body"]
            for _ in 0..<8 where !reference.isHittable { app.swipeUp() }
            XCTAssertTrue(reference.waitForExistence(timeout: 15))
            reference.tap()
            let profile = app.buttons["profile.body.weight"]
            XCTAssertTrue(profile.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["profile.body.height"].exists)
            func digits(_ item: XCUIElement) -> String {
                let text = item.label + item.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label).joined()
                return text.compactMap { $0.wholeNumberValue }.map(String.init).joined()
            }
            XCTAssertTrue(digits(profile).contains("80"))
            capture(app, "\(language)-health-body-before")
            let useWeight = app.switches["profile.body.follow-weight"]
            XCTAssertTrue(useWeight.exists)
            useWeight.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.1 : 0.9, dy: 0.5)).tap()
            let adopted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in digits(profile).contains("725") }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [adopted], timeout: 5), .completed)
            XCTAssertTrue(digits(profile).contains("725"))
            capture(app, "\(language)-health-body-adopted")
            if language == "en" {
                profile.tap()
                let input = app.textFields.firstMatch
                XCTAssertTrue(input.waitForExistence(timeout: 5))
                input.tap(); input.typeText("81")
                app.buttons["profile.body.save"].tap()
                XCTAssertTrue(profile.waitForExistence(timeout: 5))
                XCTAssertTrue(digits(profile).contains("81"))
                XCTAssertEqual(useWeight.value as? String, "0")
                useWeight.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in digits(profile).contains("725") }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
            }
            app.buttons["profile.health.details"].tap()
            let history = app.buttons["health.body.history"]
            for _ in 0..<4 where !history.isHittable { app.swipeUp() }
            XCTAssertTrue(history.isHittable)
            history.tap()
            XCTAssertTrue(app.staticTexts["Scale"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Scale")).count, 3, "All measurement history, including older than one year")
            capture(app, "\(language)-health-body-history")
            app.terminate()
        }
    }

    func testMissingBodyFieldsUseOneOptionalManualEditor() {
        let app = launch("body-profile-empty")
        let weight = app.buttons["profile.body.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        XCTAssertTrue(weight.label.contains("—"))
        weight.tap()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Body weight") // native placeholder, no fabricated 70 kg
        XCTAssertFalse(app.buttons["profile.body.save"].isEnabled)
        input.tap(); input.typeText("82.5")
        app.buttons["profile.body.save"].tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(weight.label.contains("82.5"))
        let height = app.buttons["profile.body.height"]
        height.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("178")
        app.buttons["profile.body.save"].tap()
        XCTAssertTrue(height.waitForExistence(timeout: 5))
        XCTAssertTrue(height.label.contains("178"))
        capture(app, "body-profile-manual")
        app.terminate()
    }

    func testHomeDietProgressUpdatesImmediatelyAfterEachSavedMeal() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("home-overview", language: language, emptyMeals: true)
            let addMeal = app.buttons["home.add-meal"]
            XCTAssertTrue(addMeal.waitForExistence(timeout: 15))
            let progress = element("home.diet.progress", app)
            XCTAssertTrue(progress.exists)
            let energy = element("home.diet.calories", app)
            XCTAssertTrue(energy.exists)
            XCTAssertTrue(energy.label.contains("kcal"))
            XCTAssertTrue(energy.label.contains("—"))
            for index in 1...2 {
                let before = progress.label
                addMeal.tap()
                let input = app.textViews.firstMatch
                XCTAssertTrue(input.waitForExistence(timeout: 5))
                input.tap()
                // Fully weighed catalog food uses the real offline parser, with no remote AI request.
                input.typeText("200 grams cooked chicken breast")
                app.buttons["meal.save"].tap()
                XCTAssertTrue(input.waitForNonExistence(timeout: 10))
                XCTAssertTrue(addMeal.waitForExistence(timeout: 5))
                let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    progress.exists && progress.label != before
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed,
                               "Home Diet bar must reflect meal \(index) without opening Diet or leaving Home")
                XCTAssertFalse(energy.label.contains("≈"))
                let actualText = energy.label.components(separatedBy: "/").first ?? ""
                let actual = Int(actualText.compactMap { $0.wholeNumberValue }.map(String.init).joined())
                // Sum the catalog's unrounded nutrients: 312.42 kcal per meal, 624.84 for two.
                XCTAssertEqual(actual, index == 1 ? 312 : 625)
                let targetText = energy.label.components(separatedBy: "/").last ?? ""
                let target = Double(targetText.compactMap { $0.wholeNumberValue }.map(String.init).joined())!
                let percent = Int(progress.label.compactMap { $0.wholeNumberValue }.map(String.init).joined())
                XCTAssertEqual(percent, Int((312.42 * Double(index) / target * 100).rounded()))
                capture(app, "\(language)-home-meal-\(index)-immediate-progress")
            }
            app.terminate()
        }
    }

    func testHomeDietButtonOpensTheSharedMealEditorInEnglishAndArabic() {
        for language in ["en", "ar"] {
            let app = launch("home-overview", language: language)
            let button = app.buttons["home.add-meal"]
            XCTAssertTrue(button.waitForExistence(timeout: 15))
            XCTAssertTrue(button.isHittable)
            capture(app, "\(language)-home-add-meal")
            button.tap()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
            capture(app, "\(language)-home-meal-editor")
            app.terminate()
        }
    }
    func testNextExercisePickerHasFinishAtTopRightAndMediaLink() {
        let app = launch("free-picker")
        let finish = app.buttons["open-workout.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        XCTAssertTrue(finish.isHittable)
        XCTAssertLessThan(finish.frame.midY, app.frame.height * 0.22)
        XCTAssertGreaterThan(finish.frame.midX, app.frame.width * 0.5)
        capture(app, "free-picker-finish-top-right")
        let info = element("exercise.info.bench_press_barbell", app)
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        let youtube = element("exercise.youtube", app)
        XCTAssertTrue(youtube.waitForExistence(timeout: 15))
        XCTAssertTrue(youtube.isHittable)
        XCTAssertGreaterThan(youtube.frame.midX, app.frame.width * 0.5)
        capture(app, "exercise-detail-youtube")
        app.buttons["Done"].firstMatch.tap()
        finish.tap()
        XCTAssertTrue(app.buttons["exercise.ui-test.open"].waitForExistence(timeout: 10))
    }
    func testInlineTutorialWithoutManualPiPStopsOnMinimizeAndReopensTraining() {
        let app = launch("stable-player")
        let youtube = element("workout.youtube", app)
        XCTAssertTrue(youtube.waitForExistence(timeout: 15))
        youtube.tap()
        XCTAssertTrue(element("workout.youtube.player", app).waitForExistence(timeout: 8))
        let handle = element("workout.handle", app)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let reopen = app.buttons["exercise.ui-test.open"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        reopen.tap()
        XCTAssertTrue(youtube.waitForExistence(timeout: 10))
        XCTAssertFalse(youtube.isSelected)
        XCTAssertFalse(element("workout.youtube.player", app).exists)
        capture(app, "youtube-ordinary-minimize-reopen")
    }

    func testInlineYouTubeSelectsInPlacePreservesTrainingAndStopsOnQueueOrVariant() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("stable-player", language: language)
            let youtube = element("workout.youtube", app)
            XCTAssertTrue(youtube.waitForExistence(timeout: 15))
            let panel = element("workout.current.edit", app)
            let panelFrame = panel.frame
            let controlsFrame = element("workout.controls", app).frame
            XCTAssertFalse(youtube.isSelected)
            youtube.tap()
            let player = element("workout.youtube.player", app)
            XCTAssertTrue(player.waitForExistence(timeout: 8))
            XCTAssertTrue(youtube.isSelected)
            XCTAssertFalse(element("workout.youtubeTip", app).exists)
            let handle = element("workout.handle", app)
            XCTAssertTrue(handle.exists)
            // AX includes the handle’s 10pt bottom hit padding; compare the visible capsule.
            let upperGap = player.frame.minY - (handle.frame.maxY - 10)
            let lowerGap = element("workout.current.info", app).frame.minY - player.frame.maxY
            XCTAssertGreaterThanOrEqual(upperGap, 0)
            XCTAssertEqual(upperGap, lowerGap, accuracy: 2)
            XCTAssertEqual(player.frame.minX, app.frame.minX, accuracy: 1)
            XCTAssertEqual(player.frame.width, app.frame.width, accuracy: 1)
            XCTAssertEqual(player.frame.height, max(200, player.frame.width * 9 / 16), accuracy: 1)
            let failedText = language == "zh-Hans" ? "暂时无法播放视频" : language == "ar" ? "الفيديو غير متاح" : "Video unavailable"
            if player.value as? String != failedText {
                XCTAssertFalse(element("workout.youtube.external", app).exists)
            }
            XCTAssertEqual(panel.frame.minY, panelFrame.minY, accuracy: 1)
            XCTAssertEqual(element("workout.controls", app).frame.minY, controlsFrame.minY, accuracy: 1)
            XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
            let elapsed = element("workout.elapsed", app)
            let before = elapsed.label
            let ticking = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in elapsed.label != before }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ticking], timeout: 5), .completed)
            if language == "en" {
                let outcome = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let value = player.value as? String
                    return value == "Video playing" || value == "Video unavailable"
                }, object: nil)
                _ = XCTWaiter.wait(for: [outcome], timeout: 23)
                print("INLINE_YOUTUBE_LIVE_RESULT: \(player.value as? String ?? "unknown")")
            }
            capture(app, "\(language)-inline-youtube")
            youtube.tap()
            XCTAssertFalse(player.exists)
            XCTAssertFalse(youtube.isSelected)
            youtube.tap()
            element("workout.playlist.toggle", app).tap()
            XCTAssertFalse(player.exists)
            XCTAssertFalse(youtube.isSelected)
            element("workout.playlist.toggle", app).tap()
            youtube.tap()
            element("workout.variants", app).tap()
            app.buttons["workout.variant.bench_press_dumbbell"].tap()
            XCTAssertFalse(player.exists)
            XCTAssertFalse(youtube.isSelected)
            app.terminate()
        }
    }

    func testLeadingMusclesTrailingSwitchCenteredSingleTitleAndInsetFooter() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("stable-player", language: language)
            let menu = element("workout.variants", app)
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            let muscles = element("workout.muscles", app)
            let title = element("workout.exercise.title", app)
            let titleButton = element("workout.current.info", app)
            XCTAssertFalse(element("workout.exercise.subtitle", app).exists)
            XCTAssertEqual(titleButton.label, language == "zh-Hans" ? "卧推" : "Bench Press")
            XCTAssertEqual(titleButton.frame.midY, muscles.frame.midY, accuracy: 2)
            if language == "ar" {
                XCTAssertGreaterThan(muscles.frame.midX, app.frame.width * 0.75)
                XCTAssertLessThan(menu.frame.midX, app.frame.width * 0.2)
            } else {
                XCTAssertLessThan(muscles.frame.midX, app.frame.width * 0.25)
                XCTAssertGreaterThan(menu.frame.midX, app.frame.width * 0.8)
            }
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Last:")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "上次:")).firstMatch.exists)
            let youtube = element("workout.youtube", app)
            let queue = element("workout.playlist.toggle", app)
            XCTAssertGreaterThan(youtube.frame.midX, 60)
            XCTAssertLessThan(queue.frame.midX, app.frame.width - 60)
            XCTAssertEqual(element("workout.elapsed", app).frame.midX, app.frame.midX, accuracy: 2)
            XCTAssertEqual(youtube.frame.midX, element("workout.previous", app).frame.midX, accuracy: 1)
            XCTAssertEqual(queue.frame.midX, element("workout.end", app).frame.midX, accuracy: 1)
            capture(app, "\(language)-aligned-single-title")
            menu.tap()
            app.buttons["workout.variant.bench_press_dumbbell"].tap()
            XCTAssertTrue(element("workout.exercise.subtitle", app).waitForExistence(timeout: 5))
            if language == "ar" {
                XCTAssertEqual(title.frame.maxX, titleButton.frame.maxX, accuracy: 2)
            } else {
                XCTAssertEqual(title.frame.minX, titleButton.frame.minX, accuracy: 2)
            }
            capture(app, "\(language)-aligned-subtitle")
            app.terminate()
        }
    }

    func testVariantMenuOrdersDefaultThenVariantsAndReplacesAcrossMuscles() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("short-player", language: language)
            let menu = element("workout.variants", app)
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            let originalTitle = element("workout.current.info", app).label
            menu.tap()
            let base = app.buttons["workout.variant.bench_press_barbell"]
            let variant = app.buttons["workout.variant.bench_press_dumbbell"]
            let replace = app.buttons["workout.variant.replace-other"]
            XCTAssertTrue(replace.waitForExistence(timeout: 5))
            XCTAssertLessThan(base.frame.midY, variant.frame.midY)
            XCTAssertLessThan(replace.frame.midY, base.frame.midY)
            capture(app, "\(language)-variant-menu-replacement")
            replace.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText("Squat")
            let squat = app.buttons["exercise.primary.squat_barbell"]
            XCTAssertTrue(squat.waitForExistence(timeout: 5))
            squat.tap()
            let title = element("workout.current.info", app)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                title.exists && title.label != originalTitle
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            app.buttons[language == "ar" ? "المجموعة الكاملة" : language == "zh-Hans" ? "完成本组" : "Complete set"].firstMatch.tap()
            let skip = app.buttons[language == "ar" ? "إسترح" : language == "zh-Hans" ? "跳过休息" : "Skip rest"].firstMatch
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            menu.tap()
            for _ in 0..<4 where !replace.exists { app.swipeUp() }
            XCTAssertTrue(replace.waitForExistence(timeout: 5))
            replace.tap()
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testCenteredTwoLineHeadingKeepsDetailsAndVariantMenuWorking() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("short-player", language: language)
            let menu = element("workout.variants", app)
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            let muscles = element("workout.muscles", app)
            XCTAssertEqual(muscles.frame.height, 40, accuracy: 1)
            menu.tap()
            app.buttons["workout.variant.bench_press_dumbbell"].tap()
            let title = element("workout.exercise.title", app)
            let subtitle = element("workout.exercise.subtitle", app)
            XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, language == "zh-Hans" ? "卧推" : "Bench Press")
            XCTAssertEqual(subtitle.label, language == "zh-Hans" ? "哑铃" : language == "ar" ? "دمبل" : "Dumbbell")
            XCTAssertGreaterThan(subtitle.frame.midY, title.frame.midY)
            let group = muscles.frame.union(element("workout.current.info", app).frame).union(menu.frame)
            XCTAssertEqual(group.midX, app.frame.midX, accuracy: 2)
            capture(app, "\(language)-centered-two-line-heading")
            element("workout.current.info", app).tap()
            XCTAssertTrue(app.buttons[language == "zh-Hans" ? "完成" : language == "ar" ? "تم" : "Done"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testDiscardAlertExplainsRemovalAndClosesTheWorkout() {
        for (language, discard, message) in [
            ("en", "Discard workout", "Finish saves this workout. Discard removes it from history."),
            ("zh-Hans", "放弃本次训练", "完成并结束会保存训练；放弃会删除本次训练记录。"),
            ("ar", "تجاهل التمرين", "الإنهاء يحفظ التمرين. التجاهل يزيله من السجل.")
        ] {
            let app = launch("stable-player", language: language)
            let complete = app.buttons[language == "ar" ? "المجموعة الكاملة" : language == "zh-Hans" ? "完成本组" : "Complete set"].firstMatch
            XCTAssertTrue(complete.waitForExistence(timeout: 15))
            complete.tap()
            app.buttons["workout.end"].tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.staticTexts[message].exists)
            capture(app, "\(language)-discard-workout-confirmation")
            alert.buttons[discard].tap()
            XCTAssertTrue(app.buttons["exercise.ui-test.open"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["workout.end"].exists)
            app.terminate()
        }
    }

    func testBackUndoesRestThenCompletionAndAllowsCompletingAgain() {
        for language in ["en", "ar"] {
            let app = launch("stable-player", language: language)
            let back = app.buttons["workout.previous"]
            XCTAssertTrue(back.waitForExistence(timeout: 15))
            XCTAssertFalse(back.isEnabled)
            let complete = app.buttons[language == "ar" ? "المجموعة الكاملة" : "Complete set"].firstMatch
            let skip = app.buttons[language == "ar" ? "إسترح" : "Skip rest"].firstMatch
            complete.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
            XCTAssertTrue(complete.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(complete.waitForExistence(timeout: 5))
            XCTAssertFalse(back.isEnabled)
            XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
            complete.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            XCTAssertEqual(element("workout.progress", app).value as? String, "1/6")
            capture(app, "\(language)-playback-undo-recomplete")
            app.terminate()
        }
    }

    func testMissingLoadKeepsBlankWeightColumnAndCanBeAdjustedDuringRest() {
        for language in ["en", "ar"] {
            let app = launch("stable-player", language: language, emptyWeight: true)
            let increase = app.buttons["workout.parameter.weight.increase"]
            XCTAssertTrue(increase.waitForExistence(timeout: 15))
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "kg")).firstMatch.exists)
            capture(app, "\(language)-empty-weight-current")
            app.buttons[language == "ar" ? "المجموعة الكاملة" : "Complete set"].firstMatch.tap()
            XCTAssertTrue(app.buttons[language == "ar" ? "إسترح" : "Skip rest"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(increase.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "kg")).firstMatch.exists)
            capture(app, "\(language)-empty-weight-rest")
            increase.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2.5")).firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testRowsStayFixedAndProgressIsCenteredAcrossSetsAndRest() {
        for language in ["en", "ar"] {
            let app = launch("stable-player", language: language)
            let title = element("workout.current.info", app)
            let panel = app.buttons["workout.current.edit"]
            let controls = element("workout.controls", app)
            let progress = element("workout.progress", app)
            XCTAssertTrue(panel.waitForExistence(timeout: 15))
            let titleFrame = title.frame
            let panelFrame = panel.frame
            let controlsFrame = controls.frame
            func checkPositions() {
                XCTAssertEqual(title.frame.minY, titleFrame.minY, accuracy: 1)
                XCTAssertEqual(panel.frame.minY, panelFrame.minY, accuracy: 1)
                XCTAssertEqual(panel.frame.height, panelFrame.height, accuracy: 1)
                XCTAssertEqual(controls.frame.minY, controlsFrame.minY, accuracy: 1)
                XCTAssertEqual(progress.frame.midY, (panel.frame.maxY + controls.frame.minY) / 2, accuracy: 1)
            }
            checkPositions()
            capture(app, "\(language)-three-set-current")
            app.buttons["workout.parameter.weight.increase"].tap()
            checkPositions()
            let complete = app.buttons[language == "ar" ? "المجموعة الكاملة" : "Complete set"].firstMatch
            let skip = app.buttons[language == "ar" ? "إسترح" : "Skip rest"].firstMatch
            complete.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5)); checkPositions()
            capture(app, "\(language)-three-set-rest")
            skip.tap()
            XCTAssertTrue(complete.waitForExistence(timeout: 5)); checkPositions()
            complete.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5)); skip.tap()
            XCTAssertTrue(complete.waitForExistence(timeout: 5)); complete.tap()
            XCTAssertTrue(skip.waitForExistence(timeout: 5)); checkPositions()
            capture(app, "\(language)-next-action-three-sets")
            skip.tap()
            XCTAssertTrue(complete.waitForExistence(timeout: 5)); checkPositions()
            app.terminate()
        }
    }

    func testPlayerQueueKeepsControlsFixedAcrossQueueAndRest() {
        for language in ["en", "ar"] {
            let app = launch("short-player", language: language)
            let toggle = element("workout.playlist.toggle", app)
            XCTAssertTrue(toggle.waitForExistence(timeout: 15))
            let controls = element("workout.controls", app)
            let initialY = controls.frame.minY
            let initialToggleY = toggle.frame.minY
            let initialProgressY = element("workout.progress", app).frame.midY
            XCTAssertGreaterThan(initialToggleY, app.frame.height * 0.75)
            let elapsed = element("workout.elapsed", app)
            XCTAssertEqual(elapsed.frame.midX, app.frame.midX, accuracy: 2)
            let muscles = element("workout.muscles", app)
            XCTAssertEqual(muscles.frame.midY, element("workout.current.info", app).frame.midY, accuracy: 8)
            XCTAssertGreaterThan(toggle.frame.midX, app.frame.width * 0.75)
            let youtube = element("workout.youtube", app)
            XCTAssertTrue(youtube.exists)
            XCTAssertLessThan(youtube.frame.midX, app.frame.width * 0.25)
            XCTAssertGreaterThan(youtube.frame.minY, element("workout.progress", app).frame.maxY)
            XCTAssertLessThan(element("workout.previous", app).frame.midX, element("workout.end", app).frame.midX)
            capture(app, "\(language)-queue-closed")
            toggle.tap()
            let queue = element("workout.playlist.list", app)
            XCTAssertTrue(queue.waitForExistence(timeout: 5))
            XCTAssertLessThan(queue.frame.maxY, element("workout.progress", app).frame.minY)
            XCTAssertEqual(controls.frame.minY, initialY, accuracy: 1)
            XCTAssertEqual(toggle.frame.minY, initialToggleY, accuracy: 1)
            XCTAssertFalse(element("workout.current.info", app).exists)
            XCTAssertFalse(element("workout.muscles", app).exists)
            XCTAssertFalse(element("workout.variants", app).exists)
            XCTAssertEqual(element("workout.progress", app).frame.midY, initialProgressY, accuracy: 1)
            XCTAssertFalse(app.buttons["workout.current.edit"].exists)
            capture(app, "\(language)-queue-short-open")
            app.buttons[language == "ar" ? "المجموعة الكاملة" : "Complete set"].firstMatch.tap()
            let skip = app.buttons[language == "ar" ? "إسترح" : "Skip rest"].firstMatch
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            XCTAssertEqual(controls.frame.minY, initialY, accuracy: 1)
            XCTAssertFalse(app.buttons["workout.current.edit"].exists)
            XCTAssertEqual(element("workout.progress", app).frame.midY, initialProgressY, accuracy: 1)
            capture(app, "\(language)-queue-rest")
            toggle.tap()
            XCTAssertEqual(controls.frame.minY, initialY, accuracy: 1)
            XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 5))
            XCTAssertEqual(element("workout.progress", app).frame.midY, initialProgressY, accuracy: 1)
            capture(app, "\(language)-queue-rest-closed")
            skip.tap()
            XCTAssertTrue(element("workout.current.info", app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testLongPlayerQueueScrollDoesNotDismissAndDetailsStillOpen() {
        let app = launch("long-player")
        let toggle = element("workout.playlist.toggle", app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 15)); toggle.tap()
        let queue = element("workout.playlist.list", app)
        let top = queue.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = queue.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        bottom.press(forDuration: 0.1, thenDragTo: top)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertLessThan(queue.frame.maxY, element("workout.progress", app).frame.minY)
        capture(app, "queue-long-scrolled")
        XCTAssertFalse(element("workout.current.info", app).exists)
        toggle.tap()
        let info = element("workout.current.info", app)
        info.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 5))
        app.buttons["workout.current.edit"].tap()
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "queue-edit-sheet")
        app.terminate()
    }
    func testQueueFitsAllLanguagesAndLargeText() {
        for language in ["zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru"] {
            let app = launch("short-player", language: language)
            let toggle = element("workout.playlist.toggle", app)
            XCTAssertTrue(toggle.waitForExistence(timeout: 15)); toggle.tap()
            let info = element("workout.current.info", app)
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !info.exists && self.element("workout.queue.add", app).isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            XCTAssertFalse(app.buttons["workout.current.edit"].exists)
            XCTAssertLessThan(element("workout.queue.add", app).frame.maxY, toggle.frame.minY)
            capture(app, "\(language)-queue-open")
            app.terminate()
        }
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "long-player"]
        app.launchArguments = ["-maso.selectedLanguage", "de", "-AppleLanguages", "(de)", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let toggle = element("workout.playlist.toggle", app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 15)); toggle.tap()
        let info = element("workout.current.info", app)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !info.exists && self.element("workout.queue.add", app).isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["workout.current.edit"].exists)
        capture(app, "de-queue-accessibility-xxxl")
        app.terminate()
    }
    func testWorkoutCountAndWeightFieldsUseNumericKeyboards() {
        let app = launch("free-picker")
        let primary = element("exercise.primary.bench_press_barbell", app)
        XCTAssertTrue(primary.waitForExistence(timeout: 15)); primary.tap()
        let sets = app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Sets")).firstMatch
        XCTAssertTrue(sets.waitForExistence(timeout: 10))
        sets.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.keys["1"].exists)
        XCTAssertFalse(app.keyboards.keys["q"].exists)
        capture(app, "sets-number-keyboard")
        app.toolbars.buttons["Done"].tap()
        let weight = app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Weight")).firstMatch
        if weight.frame.maxY > app.frame.height - 140 { app.swipeUp() }
        XCTAssertTrue(weight.isHittable)
        weight.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.keys["1"].exists)
        XCTAssertFalse(app.keyboards.keys["q"].exists)
        capture(app, "weight-decimal-keyboard")
    }
    func testTrainingPreferenceToggleCanSwitchWithoutLosingContrast() {
        let app = launch("preferences")
        let more = app.buttons["More training settings"]
        XCTAssertTrue(more.waitForExistence(timeout: 15)); more.tap()
        let toggle = app.switches["Keep screen awake during workouts"]
        for _ in 0..<4 { if toggle.isHittable && toggle.frame.maxY < app.frame.height - 140 { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        let initial = toggle.value as? String
        capture(app, "training-preference-switch-before")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in toggle.value as? String != initial }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
        capture(app, "training-preference-switch-selected")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in toggle.value as? String == initial }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 3), .completed)
    }

    func testWeeklyFrequencyRequiresConfirmationBeforeGenerating() {
        let app = launch("coach-frequency")
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("Train three times per week")
        app.buttons["Send"].tap()
        let confirm = app.buttons["coach.preferences.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["coach.test.status"].label.contains("success: 2"))
        capture(app, "coach-frequency-confirmation")
        app.buttons["coach.preferences.decline"].tap()
        XCTAssertTrue(app.staticTexts["coach.test.status"].label.contains("success: 2"))
    }
    func testFrequencyConfirmationFitsChineseGermanAndArabic() {
        for language in ["zh-Hans", "de", "ar"] {
            let app = launch("coach-frequency", language: language)
            let input = app.textViews.firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 15))
            input.tap(); input.typeText("Train three times per week")
            let send = app.buttons.matching(identifier: "coach.send").firstMatch
            if send.exists { send.tap() }
            else {
                // Composer accessibility labels follow the selected language.
                let labels = ["zh-Hans": "发送", "de": "Senden", "ar": "أرسل"]
                app.buttons[labels[language]!].tap()
            }
            let confirm = app.buttons["coach.preferences.confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 15))
            XCTAssertTrue(confirm.isHittable)
            XCTAssertGreaterThan(confirm.frame.width, 30)
            capture(app, "\(language)-coach-frequency-confirmation")
            app.buttons["coach.preferences.decline"].tap()
            app.terminate()
        }
    }

    func testAcceptedWeeklyFrequencyProducesThreeActualAIRoutines() throws {
        guard ProcessInfo.processInfo.environment["MASO_LIVE_COACH_DIAGNOSTIC"] == "1" else { throw XCTSkip("Opt-in live AI check") }
        let app = launch("coach-frequency")
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("Train three times per week")
        app.buttons["Send"].tap()
        let confirm = app.buttons["coach.preferences.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15)); confirm.tap()
        if app.alerts["AI data sharing"].waitForExistence(timeout: 5) { app.alerts["AI data sharing"].buttons["Allow"].tap() }
        let status = app.staticTexts["coach.test.status"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && (status.label == "success: 3" || status.label.hasPrefix("fallback:"))
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 180), .completed)
        capture(app, "coach-confirmed-three-routines")
        XCTAssertEqual(status.label, "success: 3")
    }
}

@MainActor
final class RoutineSavePopoverUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scene: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene]
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }
    private func reveal(_ button: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        for _ in 0..<10 {
            if button.isHittable && button.frame.minY > 200 && button.frame.maxY < app.frame.height - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func assertAbove(_ anchor: CGRect, app: XCUIApplication) {
        let choices = app.descendants(matching: .any).matching(identifier: "routine.save.choices").firstMatch
        XCTAssertTrue(choices.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(choices.frame.maxY, anchor.minY + 4, "Popover must open above the source save button")
        XCTAssertLessThan(anchor.minY - choices.frame.maxY, 64, "Popover must stay near its source")
        XCTAssertTrue(app.buttons["routine.save.add"].isHittable)
        XCTAssertTrue(app.buttons["routine.save.replace"].isHittable)
    }
    func testCoachBatchPopoverIsAboveItsButtonAndCancelDoesNotSaveInFourLanguages() {
        for language in ["en", "zh-Hans", "de", "ar"] {
            let app = launch("coach-save", language: language)
            let save = app.buttons["coach.save-batch"]
            reveal(save, app: app)
            let count = app.staticTexts["routine.test.saved-count"].label
            let anchor = save.frame
            save.tap(); assertAbove(anchor, app: app)
            let title = ["en": "Save to My Workout Plans", "zh-Hans": "保存到我的训练计划",
                         "de": "In meinen Trainingsplänen speichern", "ar": "حفظ في خطط التمرين الخاصة بي"][language]!
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3), app.debugDescription)
            capture(app, "\(language)-coach-save-above")
            app.buttons["routine.save.cancel"].tap()
            XCTAssertEqual(app.staticTexts["routine.test.saved-count"].label, count)
            app.terminate()
        }
    }
    func testCoachPopoverAddAndReplaceSaveTheWholeBatch() {
        for replacing in [false, true] {
            let app = launch("coach-save")
            let save = app.buttons["coach.save-batch"]
            reveal(save, app: app)
            let oldCount = Int(app.staticTexts["routine.test.saved-count"].label) ?? -1
            let anchor = save.frame
            save.tap(); assertAbove(anchor, app: app)
            app.buttons[replacing ? "routine.save.replace" : "routine.save.add"].tap()
            let expected = replacing ? 3 : oldCount + 3
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["routine.test.saved-count"].label == String(expected)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 8), .completed)
            capture(app, replacing ? "coach-replaced-batch" : "coach-added-batch")
            app.terminate()
        }
    }
    func testClassicsCollectionUsesTheSameAnchoredChoices() {
        let app = launch("classics-save")
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "classics.save-batch.")).firstMatch
        reveal(save, app: app)
        let anchor = save.frame
            save.tap(); assertAbove(anchor, app: app)
        capture(app, "classics-save-above")
        app.buttons["routine.save.cancel"].tap()
    }
}


/// Exercises the same URL delivered by WidgetKit through the real application root.
@MainActor
final class WidgetMealLinkUITests: XCTestCase {
    func testMealLinkOpensEditorOnColdAndWarmLaunch() throws {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        app.terminate()
        app.open(URL(string: "maso://widget/addMeal")!)
        let editor = app.navigationBars["Add meal"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25))
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        let cold = XCTAttachment(screenshot: app.screenshot()); cold.name = "widget-meal-cold"; cold.lifetime = .keepAlways; add(cold)
        editor.buttons["Cancel"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.open(URL(string: "maso://widget/addMeal")!)
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let warm = XCTAttachment(screenshot: app.screenshot()); warm.name = "widget-meal-warm"; warm.lifetime = .keepAlways; add(warm)
        editor.buttons["Cancel"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        app.terminate()
    }
}


@MainActor
final class WidgetWorkoutLinkUITests: XCTestCase {
    func testHomeWorkoutMenuOpensQuickWorkoutFormAndCancelKeepsDraft() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let play = app.buttons["home.startTodayWorkout"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        play.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Today's Workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start custom workout"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workout.playlist.toggle"].exists)
        app.buttons["AI Quick Workout"].tap()
        let generate = app.buttons["quickWorkout.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["quickWorkout.duration"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home-ai-quick-workout-form"; shot.lifetime = .keepAlways; add(shot)
        let requirements = app.descendants(matching: .any)["quickWorkout.requirements"].firstMatch
        requirements.tap()
        requirements.typeText("Avoid jumping")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(generate.waitForNonExistence(timeout: 5))
        app.buttons["Add"].tap()
        app.buttons["AI Quick Workout"].tap()
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["quickWorkout.requirements"].firstMatch.value as? String, "Avoid jumping")
        app.buttons["Cancel"].tap()
        app.terminate()
    }

    func testHomePlayTapStartsTodayWithoutOpeningMenu() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let play = app.buttons["home.startTodayWorkout"]
        XCTAssertTrue(play.waitForExistence(timeout: 25))
        play.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout.playlist.toggle"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["AI Quick Workout"].exists)
        app.terminate()
    }

    func testExplicitPlayLinkStartsTodayWorkoutAndReopensIt() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let homePlay = app.buttons["home.startTodayWorkout"]
        XCTAssertTrue(homePlay.waitForExistence(timeout: 25))
        XCTAssertTrue(homePlay.isEnabled)
        app.terminate()
        app.open(URL(string: "maso://widget/playWorkout")!)
        let handle = app.descendants(matching: .any).matching(identifier: "workout.playlist.toggle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 25))
        let cold = XCTAttachment(screenshot: app.screenshot()); cold.name = "widget-workout-cold"; cold.lifetime = .keepAlways; add(cold)
        XCUIDevice.shared.press(.home)
        app.open(URL(string: "maso://widget/playWorkout")!)
        XCTAssertTrue(handle.waitForExistence(timeout: 12))
        let warm = XCTAttachment(screenshot: app.screenshot()); warm.name = "widget-workout-warm"; warm.lifetime = .keepAlways; add(warm)
        app.terminate()
    }
}


@MainActor
final class PlayerActionButtonUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func progressionElement(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func openProgression(_ app: XCUIApplication) {
        let open = app.buttons["workout.progression.open"]
        for _ in 0..<5 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(app.switches["progression.maintain"].waitForExistence(timeout: 5))
    }
    private func progressionFixture(_ language: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_QUIET_PROGRESSION": "1"]
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["workout.weight.suggestion"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["workout.current.edit"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        return app
    }
    func testProgressionMaintenanceLimitAndCooldownUseNativeSheetInThreeLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = progressionFixture(language)
            openProgression(app)
            XCTAssertTrue(progressionElement("progression.suggestion", app).exists)
            let maintain = app.switches["progression.maintain"]
            maintain.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.05 : 0.95, dy: 0.5)).tap()
            XCTAssertEqual(maintain.value as? String, "1")
            XCTAssertFalse(progressionElement("progression.suggestion", app).exists)
            app.buttons["progression.save"].tap()
            openProgression(app)
            XCTAssertEqual(maintain.value as? String, "1")
            maintain.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.05 : 0.95, dy: 0.5)).tap()
            let limit = app.switches["progression.limit.enabled"]
            limit.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.05 : 0.95, dy: 0.5)).tap()
            XCTAssertFalse(app.buttons["progression.save"].isEnabled, "An enabled empty/zero limit must not save")
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("51")
            XCTAssertTrue(app.buttons["progression.save"].isEnabled)
            app.buttons["progression.save"].tap()
            openProgression(app)
            XCTAssertEqual(limit.value as? String, "1")
            XCTAssertTrue(progressionElement("progression.quiet", app).exists)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "\(language)-quiet-progression-limit"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["progression.save"].tap()
            let save = language == "en" ? "Save" : language == "ar" ? "حفظ" : "保存"
            app.navigationBars.buttons[save].tap()
            XCTAssertTrue(app.staticTexts["50 kg"].waitForExistence(timeout: 5), "Policy changes must not rewrite the training target")
            app.terminate()
        }
    }
    func testGlobalMaintenanceSavesWithoutRegeneratingRoutines() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "preferences"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let toggle = app.switches["training.progression.maintain"]
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertFalse(app.alerts["Update routines?"].exists)
        let reopen = app.buttons["exercise.ui-test.open"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 8)); reopen.tap()
        for _ in 0..<8 where !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "1")
        app.terminate()
    }

    func testProgressionWeightAppliesOnlyAfterExplicitChoiceAndOuterSave() {
        let app = progressionFixture("en")
        openProgression(app)
        XCTAssertTrue(app.buttons["progression.apply"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "optional-weight-progression"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["progression.apply"].tap()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["52.5 kg"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout.weight.suggestion"].exists)
        app.terminate()
    }

    func testQuickButtonsChangeParametersWithoutOpeningSheet() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "short-player"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let plus = app.buttons["workout.parameter.weight.increase"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15)); plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(app.staticTexts["62.5 kg"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].exists)
        app.buttons["workout.parameter.weight.decrease"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.staticTexts["60 kg"].waitForExistence(timeout: 5))
        app.buttons["workout.parameter.reps.increase"].tap()
        XCTAssertTrue(app.staticTexts["9"].exists)
        app.buttons["workout.parameter.sets.increase"].tap()
        XCTAssertTrue(app.staticTexts["1/3"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "quick-parameter-buttons"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }

    func testRestOmitsJustNowAndKeepsGlassVariantMenu() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "short-player"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        let complete = app.buttons["Complete set"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 15)); complete.tap()
        XCTAssertTrue(app.buttons["Skip rest"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Just now:")).firstMatch.exists)
        let menu = app.buttons["workout.variants"]
        XCTAssertTrue(menu.isHittable); menu.tap()
        XCTAssertTrue(app.buttons["workout.variant.bench_press_dumbbell"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "rest-glass-variants-no-just-now"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }

    func testTitleAndParameterPanelOpenTheirSheets() {
        for language in ["en", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.terminate()
            app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))"]
            app.launch()
            app.open(URL(string: "maso://widget/playWorkout")!)
            let replace = app.alerts.buttons[language == "en" ? "Replace" : "يستعاض عن عبارة:"]
            if replace.waitForExistence(timeout: 3) { replace.tap() }
            let info = app.buttons["workout.current.info"]
            let edit = app.buttons["workout.current.edit"]
            XCTAssertTrue(info.waitForExistence(timeout: 15))
            XCTAssertTrue(edit.isHittable)
            XCTAssertGreaterThan(edit.frame.width, app.frame.width * 0.65)
            XCTAssertGreaterThanOrEqual(edit.frame.height, 56)
            XCTAssertLessThan(info.frame.maxY, edit.frame.minY + 1)
            XCTAssertGreaterThanOrEqual(info.frame.minX, 15)
            XCTAssertLessThanOrEqual(info.frame.maxX, app.frame.width - 15)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "\(language)-player-title-and-panel"; image.lifetime = .keepAlways; add(image)
            info.tap()
            let done = app.buttons[language == "en" ? "Done" : "تم"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 8))
            done.tap()
            XCTAssertTrue(edit.waitForExistence(timeout: 8))
            edit.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
            let save = app.buttons[language == "en" ? "Save" : "حفظ"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 8))
            app.terminate()
        }
    }
}

@MainActor
final class WorkoutSignalsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    /// The recorded-day card is the control VoiceOver exposes. The row id is folded into it.
    private func historyCard(in app: XCUIApplication) -> XCUIElement {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12))
        for _ in 0..<6 {
            if card.isHittable, card.frame.minY > 90, card.frame.maxY < app.frame.height - 20 { break }
            if card.frame.minY > app.frame.height * 0.55 { app.swipeUp(velocity: .slow) }
            else { break }
        }
        return card
    }
    private func launch(_ scene: String = "stable-player", language: String = "en", heartFixture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": scene, "MASO_SHOWCASE_SEED": "1"]
        if heartFixture { app.launchEnvironment["MASO_WORKOUT_HEART_FIXTURE"] = "1" }
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRoughLoadsAppearAfterCompletionAndUndoWithdrawsThem() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_ROUGH_LOAD_ESTIMATE": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(element("workout.primary", app).waitForExistence(timeout: 20))
            let skipTitle = language == "ar" ? "إسترح" : language == "zh-Hans" ? "跳过休息" : "Skip rest"
            for _ in 0..<3 {
                element("workout.primary", app).tap()
                let skip = app.buttons[skipTitle].firstMatch
                if skip.waitForExistence(timeout: 6) { skip.tap() }
            }
            element("workout.progress.queue-step-1", app).tap()
            XCTAssertTrue(element("workout.suggested.weight", app).waitForExistence(timeout: 5))
            capture(app, "\(language)-rough-incline-after-bench")
            app.buttons["workout.current.edit"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            let form = element("workout.parameters.form", app)
            let basis = element("parameters.cross-exercise.basis", app)
            for _ in 0..<5 where !basis.exists { form.swipeUp() }
            XCTAssertTrue(basis.waitForExistence(timeout: 5))
            let explanation = element("parameters.weight.source-explanation", app)
            XCTAssertTrue(explanation.exists, "First rough estimate explains its source")
            for _ in 0..<5 where !form.frame.contains(explanation.frame) { form.swipeUp() }
            capture(app, "\(language)-rough-provenance")
            app.buttons["workout.parameters.cancel"].tap()
            element("workout.progress.queue-step-2", app).tap()
            XCTAssertTrue(element("workout.suggested.weight", app).waitForNonExistence(timeout: 5), "Cable pushdowns stay outside the approved table")
            capture(app, "\(language)-rough-pushdown")
            // Jump is undoable. Unwind jumps, then the actual bench completion.
            for _ in 0..<8 {
                if element("workout.progress.queue-step-0", app).value as? String == "0/3" { break }
                element("workout.previous", app).tap()
            }
            XCTAssertEqual(element("workout.progress.queue-step-0", app).value as? String, "0/3")
            element("workout.progress.queue-step-1", app).tap()
            XCTAssertTrue(element("workout.weight.calibration", app).waitForExistence(timeout: 5))
            XCTAssertFalse(element("workout.suggested.weight", app).exists)
            capture(app, "\(language)-rough-withdrawn-after-undo")
            app.terminate()
        }
    }

    func testUnknownWeightCalibrationDoesNotBecomeZeroOnSave() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_TEST_EMPTY_WEIGHT": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(element("workout.weight.calibration", app).waitForExistence(timeout: 20))
            app.buttons["workout.current.edit"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            let calibration = element("parameters.weight.calibration", app)
            XCTAssertTrue(calibration.waitForExistence(timeout: 5))
            let form = element("workout.parameters.form", app)
            for _ in 0..<5 where !form.frame.contains(calibration.frame) { form.swipeUp() }
            XCTAssertGreaterThan(calibration.frame.height, 0)
            XCTAssertTrue(form.frame.contains(calibration.frame))
            capture(app, "\(language)-first-weight-calibration")
            let saveTitle = language == "en" ? "Save" : language == "ar" ? "حفظ" : "保存"
            app.navigationBars.buttons[saveTitle].tap()
            XCTAssertTrue(element("workout.weight.calibration", app).waitForExistence(timeout: 5))
            app.buttons["workout.parameter.weight.increase"].tap()
            XCTAssertTrue(element("workout.explicit.weight", app).waitForExistence(timeout: 5))
            XCTAssertFalse(element("workout.weight.calibration", app).exists)
            app.terminate()
        }
    }

    func testWeightSourceExplainsOnceAndRemainsManuallyAvailable() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_CROSS_EXERCISE_ESTIMATE": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let edit = app.buttons["workout.current.edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 20))
            edit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            let firstBasis = element("parameters.cross-exercise.basis", app)
            let form = element("workout.parameters.form", app)
            for _ in 0..<5 where !firstBasis.exists { form.swipeUp() }
            XCTAssertTrue(firstBasis.exists)
            let explanation = element("parameters.weight.source-explanation", app)
            XCTAssertTrue(explanation.waitForExistence(timeout: 5), "First supported estimate should explain its source once visible")
            for _ in 0..<5 where !form.frame.contains(explanation.frame) { form.swipeUp() }
            XCTAssertTrue(form.frame.contains(explanation.frame))
            capture(app, "\(language)-first-source-explanation")
            app.buttons["workout.parameters.cancel"].tap()
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            edit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            let basis = element("parameters.cross-exercise.basis", app)
            for _ in 0..<5 where !basis.exists { form.swipeUp() }
            XCTAssertTrue(basis.waitForExistence(timeout: 5))
            for _ in 0..<5 where !form.frame.contains(basis.frame) { form.swipeUp() }
            XCTAssertFalse(explanation.exists, "Reopening must not repeat the automatic explanation")
            basis.tap()
            XCTAssertTrue(explanation.waitForExistence(timeout: 5))
            for _ in 0..<5 where !form.frame.contains(explanation.frame) { form.swipeUp() }
            XCTAssertTrue(form.frame.contains(explanation.frame))
            capture(app, "\(language)-source-manually-reopened")
            app.terminate()
        }
    }

    func testPersonalParameterSuggestionsRemainDistinctThroughEditingAndSave() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_PARAMETER_SUGGESTIONS": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 20))
            XCTAssertTrue(element("workout.suggested.weight", app).exists)
            capture(app, "\(language)-suggested-player")
            // Hit the panel background, outside its independent +/- controls.
            app.buttons["workout.current.edit"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            let saveTitle = language == "en" ? "Save" : language == "ar" ? "حفظ" : "保存"
            let save = app.navigationBars.buttons[saveTitle]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            capture(app, "\(language)-suggested-parameter-sheet")
            save.tap()
            XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 5))
            XCTAssertTrue(element("workout.suggested.weight", app).exists)
            app.buttons["workout.parameter.weight.increase"].tap()
            XCTAssertTrue(element("workout.explicit.weight", app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("workout.suggested.reps", app).exists)
            capture(app, "\(language)-manual-weight-suggested-reps")
            app.terminate()
        }
    }

    func testCrossExerciseEstimateShowsResearchBasisAndKeepsManualEdits() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_CROSS_EXERCISE_ESTIMATE": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 20))
            XCTAssertTrue(element("workout.suggested.weight", app).exists)
            capture(app, "\(language)-cross-estimate-player")
            app.buttons["workout.current.edit"].tap()
            let basis = element("parameters.cross-exercise.basis", app)
            for _ in 0..<5 where !basis.isHittable { app.swipeUp() }
            XCTAssertTrue(basis.isHittable)
            if !element("parameters.weight.source-explanation", app).exists { basis.tap() }
            capture(app, "\(language)-cross-estimate-research-basis")
            let saveTitle = language == "en" ? "Save" : language == "ar" ? "حفظ" : "保存"
            app.navigationBars.buttons[saveTitle].tap()
            XCTAssertTrue(app.buttons["workout.parameter.weight.increase"].waitForExistence(timeout: 5))
            app.buttons["workout.parameter.weight.increase"].tap()
            XCTAssertTrue(element("workout.explicit.weight", app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testPersonalCrossExerciseEstimateUsesSharedFaintStyleAndManualProtection() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_PERSONAL_EXERCISE_ESTIMATE": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(app.buttons["workout.current.edit"].waitForExistence(timeout: 20))
            XCTAssertTrue(element("workout.suggested.weight", app).exists)
            capture(app, "\(language)-personal-estimate-player")
            app.buttons["workout.current.edit"].tap()
            let basis = element("parameters.cross-exercise.basis", app)
            for _ in 0..<5 where !basis.isHittable { app.swipeUp() }
            XCTAssertTrue(basis.isHittable)
            if !element("parameters.weight.source-explanation", app).exists { basis.tap() }
            capture(app, "\(language)-personal-estimate-basis")
            XCTAssertFalse(app.links["Research source"].exists, "Personal relationship must not be labeled a population formula")
            let saveTitle = language == "en" ? "Save" : language == "ar" ? "حفظ" : "保存"
            app.navigationBars.buttons[saveTitle].tap()
            XCTAssertTrue(element("workout.suggested.weight", app).waitForExistence(timeout: 5))
            app.buttons["workout.parameter.weight.increase"].tap()
            XCTAssertTrue(element("workout.explicit.weight", app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testRecordedBenchSixRMCanBeConfirmedReopenedAndRevoked() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "workout-history-detail", "MASO_CROSS_REFERENCE_HISTORY": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let reference = app.buttons["workout.record.reference.cross-reference-ui"]
            XCTAssertTrue(reference.waitForExistence(timeout: 20))
            for _ in 0..<5 where !reference.isHittable { app.swipeUp() }
            reference.tap()
            let toggle = app.switches["workout.record.confirm-six-rm"]
            for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertTrue(toggle.isEnabled)
            XCTAssertEqual(toggle.value as? String, "0")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.05 : 0.95, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1", "Tap the native switch, not its row label")
            capture(app, "\(language)-confirmed-six-rm-record-sheet")
            let saveTitle = language == "en" ? "Save" : language == "ar" ? "حفظ" : "保存"
            app.navigationBars.buttons[saveTitle].tap()
            XCTAssertTrue(reference.waitForExistence(timeout: 5))
            reference.tap()
            for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
            XCTAssertEqual(toggle.value as? String, "1", "Confirmation must persist on the real historical record")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.05 : 0.95, dy: 0.5)).tap()
            app.navigationBars.buttons[saveTitle].tap()
            reference.tap()
            for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
            XCTAssertEqual(toggle.value as? String, "0")
            app.terminate()
        }
    }

    func testWidePlayerMediaStageLeavesFadedSideSpace() {
        let app = launch("stable-player")
        let media = element("workout.media.square", app)
        XCTAssertTrue(media.waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let leavesSideSpace = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            media.frame.width < app.frame.width - 20 && media.frame.minX > app.frame.minX + 10
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [leavesSideSpace], timeout: 8), .completed)
        capture(app, "workout-media-side-fade-landscape")
    }
    func testSleepTimelineShowsRealEndpointsAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("sleep-chart", language: language)
            let start = element("sleep.chart.start", app)
            let end = element("sleep.chart.end", app)
            XCTAssertTrue(start.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(end.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(start.label.isEmpty)
            XCTAssertFalse(end.label.isEmpty)
            let fixtureStart = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-2 * 3600 - 17 * 60)
            let format = Date.FormatStyle.dateTime.hour().minute().locale(Locale(identifier: language))
            XCTAssertEqual(start.label, fixtureStart.formatted(format))
            XCTAssertEqual(end.label, fixtureStart.addingTimeInterval(7 * 3600 + 13 * 60).formatted(format))
            XCTAssertFalse(start.frame.intersects(end.frame), "Sleep endpoint labels should not overlap")
            capture(app, "\(language)-sleep-chart-endpoints")
            app.terminate()
        }
    }
    func testBlockedYouTubeUsesBilibiliInSamePlayerAndStopsOnQueueAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.terminate()
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_SHOWCASE_SEED": "1", "MASO_TEST_YOUTUBE_BLOCKED": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let button = element("workout.youtube", app)
            XCTAssertTrue(button.waitForExistence(timeout: 15))
            let progress = element("workout.progress", app).value as? String
            button.tap()
            XCTAssertTrue(element("workout.youtube.player", app).waitForExistence(timeout: 8))
            XCTAssertTrue(element("workout.tutorial.bilibili.external", app).waitForExistence(timeout: 8))
            XCTAssertTrue(button.isSelected)
            XCTAssertEqual(element("workout.progress", app).value as? String, progress)
            if language == "en" {
                let web = element("workout.youtube.webview", app)
                XCTAssertTrue(web.waitForExistence(timeout: 8))
                // The official mobile Bilibili player can require its own play
                // gesture even though autoplay=1 is requested. Do not force it.
                web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    self.element("workout.youtube.player", app).value as? String == "Video playing"
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 15), .completed,
                               "Official Bilibili frame should deliver an actual playing event")
            }
            capture(app, "\(language)-bilibili-fallback-player")
            element("workout.playlist.toggle", app).tap()
            XCTAssertFalse(element("workout.youtube.player", app).exists)
            XCTAssertFalse(button.isSelected)
            app.terminate()
        }
    }
    func testPartialQueueProgressRestEditAndProgressJumpInNativePlayer() {
        let app = launch()
        let primary = element("workout.primary", app)
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        primary.tap()
        let rest = element("workout.rest.edit", app)
        XCTAssertTrue(rest.waitForExistence(timeout: 8))
        let countdown = element("workout.rest.countdown", app)
        XCTAssertTrue(countdown.exists)
        XCTAssertLessThan(rest.frame.height, 32, "Only the Rest label is the editing target")
        countdown.tap()
        XCTAssertFalse(element("workout.rest.duration", app).exists, "Countdown must not open editing")
        rest.tap()
        let duration = element("workout.rest.duration", app)
        capture(app, "rest-editor-diagnostic")
        XCTAssertTrue(duration.waitForExistence(timeout: 6), app.debugDescription)
        element("workout.rest.duration-Increment", app).tap()
        XCTAssertTrue(element("workout.rest.switching", app).exists)
        element("workout.rest.save", app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 4))
        app.alerts.firstMatch.buttons["Save"].tap()
        XCTAssertTrue(rest.waitForExistence(timeout: 6))
        let first = element("workout.progress.queue-step-0", app)
        let second = element("workout.progress.queue-step-1", app)
        XCTAssertEqual(first.value as? String, "1/3")
        second.tap()
        XCTAssertFalse(rest.exists)
        XCTAssertEqual(first.value as? String, "1/3")
        element("workout.playlist.toggle", app).tap()
        let partial = element("workout.queue.progress.queue-step-0", app)
        XCTAssertTrue(partial.waitForExistence(timeout: 5))
        XCTAssertEqual(partial.value as? String, "1/3")
        capture(app, "queue-partial-progress")
        element("workout.playlist.toggle", app).tap()
        first.tap()
        XCTAssertTrue(element("workout.current.edit", app).exists)
        XCTAssertEqual(first.value as? String, "1/3", "Jumping never completes another set")
        capture(app, "progress-first-unfinished")
    }

    /// t387: long-press drag on the progress bar uses the same order as the queue.
    /// A short drag and a drop outside the bar must not move steps or complete sets.
    func testProgressLongPressReorderMatchesQueueAndPreservesCurrentExercise() {
        let app = launch()
        XCTAssertTrue(element("workout.primary", app).waitForExistence(timeout: 15))
        let title = element("workout.current.info", app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let first = element("workout.progress.queue-step-0", app)
        let second = element("workout.progress.queue-step-1", app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertLessThan(first.frame.minX, second.frame.minX)
        XCTAssertEqual(first.value as? String, "0/3")
        XCTAssertEqual(second.value as? String, "0/3")
        XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")

        first.press(forDuration: 0.15, thenDragTo: second)
        XCTAssertLessThan(first.frame.minX, second.frame.minX, "A swipe shorter than the long-press hold must not reorder")
        XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")

        let originalTitle = title.label
        second.tap()
        XCTAssertNotEqual(title.label, originalTitle)
        XCTAssertLessThan(first.frame.minX, second.frame.minX, "Tap jumps and does not reorder")
        XCTAssertEqual(first.value as? String, "0/3")
        XCTAssertEqual(second.value as? String, "0/3")
        let jumped = title.label

        first.press(forDuration: 0.8, thenDragTo: second)
        XCTAssertEqual(title.label, jumped, "Reordering must keep the exercise that was already open")
        XCTAssertEqual(first.value as? String, "0/3")
        XCTAssertEqual(second.value as? String, "0/3")
        XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
        XCTAssertLessThan(second.frame.minX, first.frame.minX)

        element("workout.playlist.toggle", app).tap()
        let row0 = element("workout.queue.row.queue-step-0", app)
        let row1 = element("workout.queue.row.queue-step-1", app)
        XCTAssertTrue(row1.waitForExistence(timeout: 5))
        XCTAssertLessThan(row1.frame.minY, row0.frame.minY, "Queue order is the same plan order as the progress bar")
        element("workout.playlist.toggle", app).tap()

        let away = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 8))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: away)
        XCTAssertLessThan(second.frame.minX, first.frame.minX, "Dragging out of the bar cancels")
        XCTAssertEqual(title.label, jumped)
        XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
    }

    func testVariantListKeepsItsScrollPositionAcrossClockTicksAndOpensReplacement() {
        for language in ["en", "ar"] {
            let app = launch(language: language)
            let switcher = element("workout.variants", app)
            XCTAssertTrue(switcher.waitForExistence(timeout: 15))
            switcher.tap()
            let list = element("workout.variant.list", app)
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            let replace = app.buttons["workout.variant.replace-other"]
            for _ in 0..<6 {
                if replace.exists {
                    let frame = replace.frame
                    if frame.height > 0, frame.minY > list.frame.minY + 44,
                       frame.maxY < app.frame.maxY - 24 { break }
                }
                list.swipeUp()
            }
            XCTAssertTrue(replace.exists)
            let visibleFrame = replace.frame
            XCTAssertGreaterThan(visibleFrame.height, 0)
            XCTAssertLessThan(visibleFrame.maxY, app.frame.maxY - 24)
            // Native List can expose a visible label without an AX activation
            // point. Measure its actual frame and tap that visible row instead.
            let jumped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(replace.frame.minY - visibleFrame.minY) > 3 }, object: nil)
            jumped.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [jumped], timeout: 4), .completed)
            capture(app, "\(language)-variant-scrolled-stable")
            replace.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8))
            capture(app, "\(language)-cross-muscle-replacement")
            app.terminate()
        }
    }
    func testVariantRowsExistOnFirstOpenReopenAndRestWithoutSearchRefresh() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch(language: language)
            let switcher = element("workout.variants", app)
            XCTAssertTrue(switcher.waitForExistence(timeout: 15))
            for phase in 0..<2 {
                for attempt in 0..<2 {
                    switcher.tap()
                    let base = app.buttons["workout.variant.bench_press_barbell"]
                    XCTAssertTrue(base.waitForExistence(timeout: 5), "First open must contain its default action: \(language)/\(phase)/\(attempt). \(app.debugDescription)")
                    XCTAssertTrue(app.buttons["workout.variant.bench_press_dumbbell"].exists)
                    capture(app, "\(language)-variant-\(phase)-\(attempt)")
                    element("workout.variant.done", app).tap()
                    XCTAssertTrue(switcher.waitForExistence(timeout: 5))
                }
                if phase == 0 {
                    switcher.tap()
                    let replace = element("workout.variant.replace-other", app)
                    for _ in 0..<6 where !replace.isHittable { app.swipeUp() }
                    replace.tap()
                    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8))
                    let done = ["en": "Done", "zh-Hans": "完成", "ar": "تم"][language]!
                    app.buttons[done].firstMatch.tap()
                    XCTAssertTrue(switcher.waitForExistence(timeout: 5))
                    switcher.tap()
                    XCTAssertTrue(app.buttons["workout.variant.bench_press_barbell"].waitForExistence(timeout: 5))
                    element("workout.variant.done", app).tap()
                    element("workout.primary", app).tap()
                    XCTAssertTrue(element("workout.rest.edit", app).waitForExistence(timeout: 5))
                }
            }
            app.terminate()
        }
    }
    func testHeartRateMovesWithPlayerSheet() {
        let app = launch()
        let heart = element("workout.heart-rate", app)
        XCTAssertTrue(heart.waitForExistence(timeout: 15))
        let title = element("workout.current.info", app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(heart.frame.maxY, title.frame.minY)
        let panel = element("workout.current.edit", app)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let variants = element("workout.variants", app)
        XCTAssertTrue(variants.waitForExistence(timeout: 5))
        XCTAssertEqual(heart.frame.maxX, panel.frame.maxX, accuracy: 3)
        XCTAssertEqual(variants.frame.maxX, panel.frame.maxX - 4, accuracy: 3)
        let progress = element("workout.progress", app)
        XCTAssertTrue(progress.exists)
        XCTAssertEqual(progress.frame.minX, panel.frame.minX, accuracy: 2)
        XCTAssertEqual(progress.frame.maxX, panel.frame.maxX, accuracy: 2)
        XCTAssertGreaterThan(heart.frame.minY, app.frame.height * 0.3)
        let bottom = heart.frame.maxY
        heart.press(forDuration: 0.8)
        let card = element("workout.heart.warning", app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.maxY, bottom, accuracy: 3)
        XCTAssertEqual(card.frame.maxX, panel.frame.maxX, accuracy: 3)
        card.press(forDuration: 0.8)
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        let handle = element("workout.handle", app)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let before = heart.frame.minY
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 85)), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(heart.exists)
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(heart.frame.minY - before) <= 3 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, "Heart rate returns with the sheet spring")
        capture(app, "heart-sheet-after-drag")
    }

    func testPersonalHeartLimitCanBeEditedWithoutEnablingHealthRead() {
        let app = launch()
        let heart = element("workout.heart-rate", app)
        XCTAssertTrue(heart.waitForExistence(timeout: 15))
        heart.tap()
        let limit = app.textFields["workout.heart.limit"]
        XCTAssertTrue(limit.waitForExistence(timeout: 6))
        limit.tap(); limit.typeText("180")
        element("workout.heart.save", app).tap()
        heart.tap()
        XCTAssertTrue(limit.waitForExistence(timeout: 6))
        XCTAssertEqual(limit.value as? String, "180")
        XCTAssertEqual(app.switches["workout.heart.enable"].value as? String, "0")
        capture(app, "personal-heart-limit")
    }
    func testHeartCardPreferenceInSettings() {
        let app = launch()
        let compact = element("workout.heart-rate", app)
        XCTAssertTrue(compact.waitForExistence(timeout: 15))
        compact.tap()
        let toggle = app.switches["workout.heart.show-card"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(toggle.value as? String, "1")
        element("workout.heart.save", app).tap()
        let card = element("workout.heart.warning", app)
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        card.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        element("workout.heart.save", app).tap()
        XCTAssertTrue(compact.waitForExistence(timeout: 6))
    }
    func testHeartAssistIsOptInAndCanBeDisabled() {
        let app = launch()
        let heart = element("workout.heart-rate", app)
        XCTAssertTrue(heart.waitForExistence(timeout: 15))
        heart.tap()
        let toggle = app.switches["workout.heart.assist"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        element("workout.heart.save", app).tap()
        heart.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        element("workout.heart.save", app).tap()
        app.terminate()
    }
    func testHeartRecoveryAutomaticallyLogsSetAndOffersUndo() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_SHOWCASE_SEED": "1",
                                 "MASO_WORKOUT_HEART_FIXTURE": "1", "MASO_TEST_HEART_ASSIST": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        XCTAssertTrue(element("workout.progress", app).waitForExistence(timeout: 15))
        XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
        let toast = element("workout.heart.assist.undo", app)
        XCTAssertTrue(toast.waitForExistence(timeout: 50))
        XCTAssertTrue(app.staticTexts["Set logged automatically"].exists)
        capture(app, "heart-assist-set-undo")
        XCTAssertEqual(element("workout.progress", app).value as? String, "1/6")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
        app.terminate()
    }
    func testHeartRiseAutomaticallySkipsRestAndOffersUndo() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_SHOWCASE_SEED": "1",
                                 "MASO_WORKOUT_HEART_FIXTURE": "1", "MASO_TEST_HEART_ASSIST": "1", "MASO_TEST_HEART_ASSIST_REST": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let primary = element("workout.primary", app)
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        primary.tap()
        XCTAssertTrue(element("workout.rest.edit", app).waitForExistence(timeout: 6))
        XCTAssertTrue(element("workout.heart.assist.undo", app).waitForExistence(timeout: 35))
        XCTAssertTrue(app.staticTexts["Rest skipped automatically"].exists)
        XCTAssertFalse(element("workout.rest.edit", app).exists)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(element("workout.rest.edit", app).waitForExistence(timeout: 5))
        app.terminate()
    }
    func testHeartCardLongPressAndWarningCompactState() {
        for warning in [false, true] {
            let app = launch(heartFixture: warning)
            let compact = element("workout.heart-rate", app)
            let card = element("workout.heart.warning", app)
            if warning {
                XCTAssertTrue(card.waitForExistence(timeout: 15))
                card.press(forDuration: 0.8)
                XCTAssertTrue(compact.waitForExistence(timeout: 5))
                XCTAssertTrue((compact.value as? String ?? "").contains("Above your reminder limit"))
                capture(app, "warning-heart-compact")
            } else {
                XCTAssertTrue(compact.waitForExistence(timeout: 15))
            }
            compact.press(forDuration: 0.8)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertFalse(element("workout.heart.enable", app).exists, "Long press must not open settings")
            capture(app, warning ? "warning-heart-liquid" : "empty-heart-liquid")
            card.tap()
            XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.press(forDuration: 0.8)
            XCTAssertTrue(compact.waitForExistence(timeout: 5))
            compact.tap()
            XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
            app.terminate()
        }
    }

    func testHeartWarningBackgroundEscalatesOnlyForSustainedHigherReadings() {
        for escalated in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.terminate()
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "stable-player", "MASO_SHOWCASE_SEED": "1",
                                     "MASO_WORKOUT_HEART_FIXTURE": "1", "MASO_TEST_ESCALATED_HEART": escalated ? "1" : "0"]
            app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
            app.launch()
            let card = element("workout.heart.warning", app)
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            capture(app, escalated ? "heart-background-escalated" : "heart-background-normal-warning")
            card.tap()
            XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
            app.terminate()
        }
    }
    func testHeartWarningCardOpensSettingsAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch(language: language, heartFixture: true)
            let card = element("workout.heart.warning", app)
            capture(app, "heart-alert-diagnostic")
            XCTAssertTrue(card.waitForExistence(timeout: 15), app.debugDescription)
            let compactCard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in card.frame.height < 130 }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [compactCard], timeout: 5), .completed, "The heart value and unit should remain compact")
            XCTAssertEqual(card.frame.maxX, app.frame.maxX - 20, accuracy: 3)
            let panel = element("workout.current.edit", app)
            let variants = element("workout.variants", app)
            XCTAssertTrue(panel.exists && variants.exists)
            if language == "ar" {
                XCTAssertEqual(variants.frame.minX, panel.frame.minX + 4, accuracy: 3)
            } else {
                XCTAssertEqual(variants.frame.maxX, panel.frame.maxX - 4, accuracy: 3)
            }
            XCTAssertFalse(element("workout.heart.pause", app).exists)
            capture(app, "\(language)-personal-heart-reminder-fixture")
            XCTAssertTrue(element("workout.primary", app).waitForExistence(timeout: 5))
            XCTAssertNotEqual(card.value as? String, "—")
            XCTAssertEqual(element("workout.progress", app).value as? String, "0/6")
            XCTAssertFalse(app.alerts.firstMatch.exists)
            card.tap()
            XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
            capture(app, "\(language)-heart-settings-from-warning")
            app.terminate()
        }
    }
    func testWarningCardSurvivesPlayerDragAndShowsStaleReading() {
        let app = launch(heartFixture: true)
        let card = element("workout.heart.warning", app)
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let handle = element("workout.handle", app)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let originalY = card.frame.minY
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 85)), withVelocity: .slow, thenHoldForDuration: 1)
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(card.frame.minY - originalY) <= 3 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, "The warning card returns with the player sheet")
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in card.value as? String == "—" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stale], timeout: 25), .completed)
        capture(app, "heart-warning-stale-after-player-drag")
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
        app.terminate()
    }
    func testWellnessSwitchesKeepTheirColorsInSettings() {
        let app = launch("settings-ai")
        let diet = app.switches["Diet"], sleep = app.switches["Sleep"]
        for _ in 0..<8 where !diet.isHittable { app.swipeUp() }
        XCTAssertTrue(diet.waitForExistence(timeout: 8))
        XCTAssertTrue(sleep.exists)
        if diet.value as? String == "0" { diet.tap() }
        if sleep.value as? String == "0" { sleep.tap() }
        XCTAssertEqual(diet.value as? String, "1")
        XCTAssertEqual(sleep.value as? String, "1")
        capture(app, "settings-wellness-switch-colors")
        app.terminate()
    }
    func testTrainingSwitchUsesThemeInRealRootNavigation() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SCREENSHOT_CAPTURE": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let preferences = app.buttons["Training Preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 10)); preferences.tap()
        let more = app.buttons["More training settings"]
        for _ in 0..<5 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let toggle = app.switches["Keep screen awake during workouts"]
        for _ in 0..<5 {
            if toggle.isHittable && toggle.frame.maxY < app.frame.height - 140 { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        if toggle.value as? String == "0" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "1")
        capture(app, "root-training-switch-on")
        app.terminate()
    }
    func testSleepScheduleSwitchKeepsSleepColorInRealNavigation() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
        app.launchEnvironment = ["MASO_SHOWCASE_SEED": "1", "MASO_SCREENSHOT_CAPTURE": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let sleep = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sleep")).firstMatch
        for _ in 0..<6 where !sleep.isHittable {
            if sleep.exists, sleep.frame.minY < 80 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(sleep.waitForExistence(timeout: 20)); XCTAssertTrue(sleep.isHittable); sleep.tap()
        let preferences = app.buttons["Sleep preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 10)); preferences.tap()
        let reminder = app.switches["Bedtime reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 8))
        if reminder.value as? String == "0" {
            reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        let on = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in reminder.value as? String == "1" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 5), .completed)
        capture(app, "real-sleep-reminder-switch-on")
        app.terminate()
    }
    func testActualWorkoutReportShowsTimelineAndSampledHeartDataAcrossLanguages() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("workout-report", language: language)
            let report = element("workout.report", app)
            XCTAssertTrue(report.waitForExistence(timeout: 15))
            let volumeTitle = ["en": "Volume", "zh-Hans": "训练量", "ar": "حجم التدريب"][language]!
            XCTAssertTrue(app.staticTexts["\(volumeTitle) · kg"].exists)
            let heart = element("workout.report.heart", app)
            for _ in 0..<5 where !heart.isHittable { app.swipeUp() }
            XCTAssertTrue(heart.exists)
            capture(app, "\(language)-report-default-peak")
            let defaultSelection = element("workout.report.heart.selection", app)
            XCTAssertTrue(defaultSelection.waitForExistence(timeout: 5))
            XCTAssertTrue(defaultSelection.label.contains("155"), defaultSelection.label)
            heart.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
            capture(app, "\(language)-report-chart-tap")
            let selection = element("workout.report.heart.selection", app)
            XCTAssertTrue(selection.waitForExistence(timeout: 5))
            let firstX = selection.frame.midX
            heart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            XCTAssertTrue(selection.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(abs(selection.frame.midX - firstX), 15, "The card must follow the selected sample")
            XCTAssertGreaterThanOrEqual(selection.frame.minX, heart.frame.minX - 1)
            XCTAssertLessThanOrEqual(selection.frame.maxX, heart.frame.maxX + 1)
            capture(app, "\(language)-report-chart-second-selection")
            let reminders = element("workout.report.heart.reminders", app)
            for _ in 0..<3 where !reminders.isHittable { app.swipeUp() }
            XCTAssertTrue(reminders.isHittable)
            reminders.coordinate(withNormalizedOffset: CGVector(dx: language == "ar" ? 0.06 : 0.94, dy: 0.5)).tap()
            capture(app, "\(language)-report-reminders-expanded")
            let insight = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.report.heart.insight.report-0|")).firstMatch
            XCTAssertTrue(insight.waitForExistence(timeout: 5))
            capture(app, "\(language)-workout-report-fixture")
            let timeline = element("workout.report.timeline", app)
            for _ in 0..<5 where !timeline.exists { app.swipeUp() }
            XCTAssertTrue(timeline.exists)
            let row = element("workout.report.exercise.report-row", app)
            for _ in 0..<5 where !row.exists { app.swipeUp() }
            XCTAssertTrue(row.exists)
            app.terminate()
        }
    }
    func testWorkoutHeartChartFitsWideWorkout() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "workout-report", "MASO_SHOWCASE_SEED": "1", "MASO_REPORT_WIDE": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let chart = element("workout.report.heart", app)
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertLessThanOrEqual(chart.frame.width, app.frame.width)
        XCTAssertGreaterThanOrEqual(chart.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(chart.frame.maxX, app.frame.maxX)
        let tooltip = element("workout.report.heart.selection", app)
        XCTAssertTrue(tooltip.waitForExistence(timeout: 5))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
        XCTAssertTrue(tooltip.waitForExistence(timeout: 5))
        XCTAssertTrue(tooltip.label.contains("Lat Pulldown"), tooltip.label)
        XCTAssertGreaterThanOrEqual(tooltip.frame.minX, 0)
        XCTAssertLessThanOrEqual(tooltip.frame.maxX, app.frame.maxX)
        capture(app, "workout-report-fitted-tooltip")
    }
    func testWorkoutHeartChartDragUpdatesSelectedSample() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("workout-report", language: language)
            let chart = element("workout.report.heart", app)
            XCTAssertTrue(chart.waitForExistence(timeout: 15))
            let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
            let tooltip = element("workout.report.heart.selection", app)
            XCTAssertTrue(tooltip.waitForExistence(timeout: 5))
            let rowName = ["en": "Lat Pulldown", "zh-Hans": "高位下拉", "ar": "توقف"][language]!
            XCTAssertTrue(tooltip.label.localizedCaseInsensitiveContains(rowName), tooltip.label)
            capture(app, "\(language)-heart-chart-drag")
            let timeline = element("workout.report.timeline", app)
            chart.swipeUp()
            for _ in 0..<3 where !timeline.exists { app.swipeUp() }
            XCTAssertTrue(timeline.exists, "Vertical report scrolling remains available")
            app.terminate()
        }
    }

    func testWorkoutReportShowsVolumeInSelectedWeightUnit() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "workout-report", "MASO_SHOWCASE_SEED": "1", "MASO_REPORT_UNIT_LB": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Volume · lb"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["2,777.8"].exists)
        capture(app, "workout-report-pound-volume")
    }
    func testWorkoutReportWithoutHeartDataOpensConsentSettings() {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
        app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "workout-report", "MASO_SHOWCASE_SEED": "1", "MASO_REPORT_NO_HEART": "1"]
        app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
        app.launch()
        let connect = element("workout.report.connect-heart", app)
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        connect.tap()
        XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("workout.heart.save", app).exists)
        capture(app, "report-heart-consent-settings")
        app.terminate()
    }
    func testWorkoutReportOffersHeartConnectionWithExistingSamplesWhenDisabled() {
        let app = launch("workout-report")
        XCTAssertTrue(element("workout.report.heart", app).waitForExistence(timeout: 15))
        let connect = element("workout.report.connect-heart", app)
        for _ in 0..<3 where !connect.isHittable { app.swipeUp() }
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()
        XCTAssertTrue(element("workout.heart.enable", app).waitForExistence(timeout: 8))
        app.terminate()
    }
    func testWorkoutReportHidesHeartEntryWhenReadingEnabled() {
        for noHeart in [true, false] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "workout-report", "MASO_SHOWCASE_SEED": "1",
                                     "MASO_REPORT_HEART_ENABLED": "1", "MASO_REPORT_NO_HEART": noHeart ? "1" : "0"]
            app.launchArguments = ["-maso.selectedLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en"]
            app.launch()
            if noHeart {
                XCTAssertTrue(element("workout.report.no-heart-samples", app).waitForExistence(timeout: 15))
            } else {
                XCTAssertTrue(element("workout.report.heart", app).waitForExistence(timeout: 15))
            }
            XCTAssertFalse(element("workout.report.connect-heart", app).exists)
            XCTAssertFalse(app.buttons["Heart rate settings"].exists)
            capture(app, noHeart ? "report-heart-enabled-no-samples" : "report-heart-enabled-samples")
            app.terminate()
        }
    }
    func testWorkoutHistoryCardPhotoIsSmallAndWholeCardOpensDetails() {
        for (language, hasPhoto) in [("en", true), ("zh-Hans", true), ("ar", true), ("en", false)] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
            app.terminate()
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "workout-history-cards", "MASO_SHOWCASE_SEED": "1",
                                     "MASO_HISTORY_PHOTO": hasPhoto ? "1" : "0"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.day.")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 12))
            let photoLabel = ["en": "Workout photo", "zh-Hans": "训练照片", "ar": "صورة العمل"][language]!
            if hasPhoto {
                XCTAssertTrue(card.label.contains(photoLabel), card.label)
            } else {
                XCTAssertFalse(card.label.contains(photoLabel), card.label)
            }
            capture(app, "\(language)-history-card-\(hasPhoto ? "photo" : "no-photo")")
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
            XCTAssertTrue(element("workout.sessionReport", app).waitForExistence(timeout: 8))
            XCTAssertTrue(element("workout.history.more", app).waitForExistence(timeout: 8))
            XCTAssertFalse(element("workout.history.report", app).exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testWorkoutHistoryCardOpensTheSessionReport() {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("workout-history-cards", language: language)
            let card = historyCard(in: app)
            XCTAssertFalse(element("workout.history.report", app).exists)
            capture(app, "\(language)-history-card")
            card.tap()
            XCTAssertTrue(element("workout.sessionReport", app).waitForExistence(timeout: 8))
            XCTAssertTrue(element("workout.sessionReport.heading", app).waitForExistence(timeout: 5))
            XCTAssertFalse(element("workout.sessionReport.info", app).exists)
            XCTAssertTrue(element("workout.history.more", app).waitForExistence(timeout: 5))
            app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            app.terminate()
        }
    }

    func testWorkoutInsightsHistoryOpensTheSameReport() {
        let app = launch("workout-insights-history", language: "en")
        XCTAssertTrue(app.navigationBars["Workout Insights"].waitForExistence(timeout: 12))
        let card = historyCard(in: app)
        card.tap()
        XCTAssertTrue(element("workout.sessionReport", app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("workout.sessionReport.share", app).exists)
        XCTAssertFalse(element("workout.history.report", app).exists)
        XCTAssertFalse(app.navigationBars["Share Workout"].exists)
        app.terminate()
    }

    /// Closing the report from the same History and Insights cards must leave those
    /// lists up and must not present the workout player. Absence of `workout.primary`
    /// is only that visible check. It does not count `TrainingSessionStore.end()`.
    func testClosingHistoryAndInsightsReportsStaysOnTheListAndDoesNotOpenThePlayer() {
        let history = launch("workout-history-cards", language: "en")
        XCTAssertFalse(element("workout.primary", history).exists)
        let historyCard = historyCard(in: history)
        XCTAssertTrue(history.navigationBars["Workout History"].waitForExistence(timeout: 8))
        historyCard.tap()
        XCTAssertTrue(element("workout.sessionReport", history).waitForExistence(timeout: 8))
        history.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(historyCard.waitForExistence(timeout: 8))
        XCTAssertTrue(history.navigationBars["Workout History"].waitForExistence(timeout: 8))
        XCTAssertFalse(element("workout.sessionReport", history).exists)
        XCTAssertFalse(element("workout.primary", history).exists)
        history.terminate()

        let insights = launch("workout-insights-history", language: "en")
        XCTAssertTrue(insights.navigationBars["Workout Insights"].waitForExistence(timeout: 12))
        XCTAssertFalse(element("workout.primary", insights).exists)
        let insightsCard = historyCard(in: insights)
        insightsCard.tap()
        XCTAssertTrue(element("workout.sessionReport", insights).waitForExistence(timeout: 8))
        insights.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(insights.navigationBars["Workout Insights"].waitForExistence(timeout: 8))
        XCTAssertTrue(insightsCard.waitForExistence(timeout: 8))
        XCTAssertFalse(element("workout.sessionReport", insights).exists)
        XCTAssertFalse(element("workout.primary", insights).exists)
        insights.terminate()
    }

    func testWorkoutHistoryMenuKeepsDeleteOffTheOldShare() {
        let app = launch("workout-history-cards", language: "en")
        let card = historyCard(in: app)
        card.tap()
        let menu = element("workout.history.more", app)
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        XCTAssertTrue(app.buttons["Delete workout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Share Workout"].exists)
        XCTAssertTrue(app.buttons["workout.sessionReport.share"].exists)
        app.terminate()
    }
}

@MainActor
final class CatalogIdentityAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testVUpSynonymSearchReturnsOneCanonicalActionAndNamesShowEquipment() throws {
        for language in ["en", "zh-Hans", "ar"] {
            let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso"); app.terminate()
            app.launchEnvironment = ["MASO_EXERCISE_UI_TEST_SCENE": "library", "MASO_SHOWCASE_SEED": "1", "MASO_IDENTITY_AUDIT": "1"]
            app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 15)); search.tap(); search.typeText("Jackknife")
            let v = app.buttons["exercise.primary.v_up"].firstMatch
            XCTAssertTrue(v.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertEqual(app.buttons.matching(identifier: "exercise.primary.v_up").count, 1)
            XCTAssertFalse(app.buttons["exercise.primary.jackknife"].exists)
            XCTAssertFalse(app.buttons["exercise.primary.sit_up_v"].exists)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "\(language)-one-v-up"; image.lifetime = .keepAlways; add(image)
            search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9)); search.typeText("Bench Press")
            let bench = app.buttons["exercise.primary.bench_press_barbell"].firstMatch
            XCTAssertTrue(bench.waitForExistence(timeout: 8))
            let gear = ["en": "Barbell", "zh-Hans": "杠铃", "ar": "بار"][language]!
            XCTAssertTrue(bench.label.contains(gear), bench.label)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "\(language)-equipment-name"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
}
