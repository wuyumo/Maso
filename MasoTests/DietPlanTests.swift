import XCTest
import SwiftUI
import Observation
import UIKit
import PhotosUI
import CoreImage
import HealthKit
@testable import Maso

@MainActor
final class SleepReferencePopoverTests: XCTestCase {
    @Observable final class Presentation { var visible = false }
    private struct Fixture: View {
        let data: DataStore
        let presentation: Presentation
        var body: some View {
            @Bindable var presentation = presentation
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SleepTargetSummaryContent(targetMinutes: 510, actualMinutes: 448, exportStyle: true)
                        SleepPersonalReferenceInfo(isPresented: $presentation.visible)
                    }.contentCardChrome().padding(16)
                }.background(AppBackground()).navigationTitle("Sleep")
            }.environment(data)
        }
    }

    func testNativeReferencePopoverFitsAllLanguagesAndScrollsAtAccessibilitySizes() async throws {
        let originalLanguage = LanguageManager.currentLanguageCode
        defer { LocalizedBundle.applyLanguage(originalLanguage) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer { previous?.makeKeyAndVisible() }
        let data = DataStore.makeMock()
        let cases = SupportedLanguage.allCases.map { ($0.rawValue, DynamicTypeSize.large) }
            + [("en", .accessibility5)]
        for (language, typeSize) in cases {
            LocalizedBundle.applyLanguage(language)
            let presentation = Presentation()
            let host = UIHostingController(rootView: Fixture(data: data, presentation: presentation)
                .environment(\.locale, Locale(identifier: language))
                .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize).preferredColorScheme(.dark))
            let window = UIWindow(windowScene: scene)
            window.traitOverrides.preferredContentSizeCategory = typeSize == .accessibility5 ? .accessibilityExtraExtraExtraLarge : .large
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(100))
            presentation.visible = true
            try await Task.sleep(for: .milliseconds(450))
            let popover = try XCTUnwrap(host.presentedViewController, "\(language): native popover must open")
            popover.view.layoutIfNeeded()
            let size = popover.view.bounds.size
            XCTAssertGreaterThan(size.width, 270, "\(language): must not shrink to the trigger label")
            XCTAssertGreaterThan(size.height, 100, "\(language): must wrap the full explanation")
            if typeSize == .accessibility5 {
                XCTAssertTrue(scrollViews(in: popover.view).contains { $0.contentSize.height > $0.bounds.height },
                              "Oversized text must remain reachable by scrolling")
            }
            if ["en", "zh-Hans", "de", "ar"].contains(language) {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let name = "sleep-reference-\(language)-\(typeSize)"
                let attachment = XCTAttachment(image: image)
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
            }
            print("SLEEP_REFERENCE \(language) \(typeSize) \(size)")
            presentation.visible = false
            popover.dismiss(animated: false)
            window.isHidden = true
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}

@MainActor
final class MealPhotoPickerTests: XCTestCase {
    private final class CameraSpy: UIImagePickerController {
        var UIKitDismissals = 0
        override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
            UIKitDismissals += 1
            completion?()
        }
    }

    func testCameraResultUsesOneSwiftUIDismissalAndStagesBeforeClosing() {
        var staged: UIImage?
        var events: [String] = []
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { _ in }
        let coordinator = PhotoPicker.Coordinator(
            image: Binding(get: { staged }, set: { staged = $0; events.append("staged") }),
            dismissPicker: { events.append("dismiss") }
        )
        let camera = CameraSpy()
        coordinator.imagePickerController(camera, didFinishPickingMediaWithInfo: [.originalImage: photo])
        coordinator.imagePickerController(camera, didFinishPickingMediaWithInfo: [.originalImage: photo])
        coordinator.imagePickerControllerDidCancel(camera)
        XCTAssertTrue(staged === photo)
        XCTAssertEqual(events, ["staged", "dismiss"])
        XCTAssertEqual(camera.UIKitDismissals, 0)
    }

    func testCancelPreservesTheExistingPhotoAndDismissesOnce() {
        let existing = UIImage()
        var selected: UIImage? = existing
        var dismissals = 0
        let coordinator = PhotoPicker.Coordinator(
            image: Binding(get: { selected }, set: { selected = $0 }),
            dismissPicker: { dismissals += 1 }
        )
        let camera = CameraSpy()
        coordinator.imagePickerControllerDidCancel(camera)
        coordinator.imagePickerControllerDidCancel(camera)
        XCTAssertTrue(selected === existing)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(camera.UIKitDismissals, 0)
    }

    func testInvalidCameraResultReportsFailureWithoutReplacingPhoto() {
        let existing = UIImage()
        var selected: UIImage? = existing
        var failed = 0
        var dismissals = 0
        let coordinator = PhotoPicker.Coordinator(
            image: Binding(get: { selected }, set: { selected = $0 }),
            dismissPicker: { dismissals += 1 }, onLoadFailure: { failed += 1 }
        )
        coordinator.imagePickerController(CameraSpy(), didFinishPickingMediaWithInfo: [:])
        XCTAssertTrue(selected === existing)
        XCTAssertEqual(failed, 1)
        XCTAssertEqual(dismissals, 1)
    }

    func testLibraryCancelDoesNotReplacePhotoOrDismissThroughUIKit() {
        let existing = UIImage()
        var selected: UIImage? = existing
        var dismissals = 0
        let coordinator = PhotoPicker.Coordinator(
            image: Binding(get: { selected }, set: { selected = $0 }),
            dismissPicker: { dismissals += 1 }
        )
        coordinator.picker(PHPickerViewController(configuration: .init()), didFinishPicking: [])
        XCTAssertTrue(selected === existing)
        XCTAssertEqual(dismissals, 1)
    }

    func testCameraPreviewBoundsPixelsAndNormalizesOrientation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let raw = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        }
        let rotated = UIImage(cgImage: try XCTUnwrap(raw.cgImage), scale: 1, orientation: .right)
        let preview = try XCTUnwrap(MealPhotoPreparation.preview(rotated))
        XCTAssertLessThanOrEqual(max(preview.size.width, preview.size.height), 1280)
        XCTAssertEqual(preview.scale, 1)
        XCTAssertEqual(preview.imageOrientation, .up)
        XCTAssertNotNil(preview.jpegData(compressionQuality: 0.8))
    }

    func testEmptyOrInvalidImageCannotReachTheRenderer() {
        XCTAssertNil(MealPhotoPreparation.preview(UIImage()))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { _ in }
        XCTAssertNil(MealPhotoPreparation.preview(image, maxDimension: .nan))
        XCTAssertNil(MealPhotoPreparation.preview(image, maxDimension: 0))
    }
}

final class DietPlanTests: XCTestCase {
    @MainActor func testBackfilledBreakfastSuppressesBreakfastReminderInsteadOfLunch() throws {
        var settings = UserSettings()
        let calendar = Calendar.current, day = calendar.startOfDay(for: Date())
        let breakfast = day.addingTimeInterval(8 * 3600)
        let lunch = day.addingTimeInterval(12 * 3600)
        settings.mealCheckIns = [.init(day: day, mealID: "late-breakfast", title: "Meal", photoFilename: "", foods: "Eggs",
                                     nutrition: .init(protein: 20, carbs: 10, fat: 10), confirmedAt: lunch,
                                     consumedAt: breakfast)]
        XCTAssertTrue(DailyReminderContext.hasLoggedMeal(settings: settings, near: breakfast))
        XCTAssertFalse(DailyReminderContext.hasLoggedMeal(settings: settings, near: lunch))
    }

    @MainActor func testFutureEatingTimeStaysOutOfRecordedHistoryAndCalendar() {
        var settings = UserSettings(); settings.weight = 75
        let now = Date(), day = settings.calendar.startOfDay(for: now)
        settings.mealCheckIns = [.init(day: day, mealID: "future-meal", title: "Meal", photoFilename: "", foods: "Eggs",
                                     nutrition: .init(protein: 20, carbs: 10, fat: 10), confirmedAt: now,
                                     consumedAt: now.addingTimeInterval(3600))]
        let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        XCTAssertTrue(data.historyItems(kind: .diet, now: now).isEmpty)
        XCTAssertTrue(data.dailyRecordSnapshots(now: now).first { $0.kind == .diet }!.progress.isEmpty)
    }

    func testMealTimeDecodesLegacyAndRoundTripsIndependentOfRevisionTime() throws {
        let now = Date()
        var meal = MealCheckIn(day: Calendar.current.startOfDay(for: now), mealID: "time-legacy", title: "Meal",
                              photoFilename: "", foods: "Rice", nutrition: .init(protein: 10, carbs: 40, fat: 5), confirmedAt: now)
        let encoded = try JSONEncoder().encode(meal)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "consumedAt")
        let decoded = try JSONDecoder().decode(MealCheckIn.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.mealTime, now)
        meal.consumedAt = now.addingTimeInterval(-7200)
        let restored = try JSONDecoder().decode(MealCheckIn.self, from: JSONEncoder().encode(meal))
        XCTAssertEqual(restored.mealTime, now.addingTimeInterval(-7200))
        XCTAssertEqual(restored.confirmedAt, now)
        // Revision selection stays based on confirmation time, not the corrected eating time.
        XCTAssertEqual(DietIntakeProgress.calculate(goal: .init(protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: []),
                                                   meals: [restored])?.fraction,
                       DietIntakeProgress.calculate(goal: .init(protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: []),
                                                   meals: [decoded])?.fraction)
    }

    @MainActor func testBackdatedMealMovePreservesCollidingMealAndHistoricalTargets() throws {
        var settings = UserSettings(); settings.weight = 75
        let calendar = settings.calendar, now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let key = SleepPreferences.dayKey(yesterday, calendar: calendar)
        settings.wellnessGoals = [key: .init(protein: 111, carbsMinimum: 222, fatMinimum: 55, sleepMinutes: 480, mealIDs: [])]
        let old = MealCheckIn(day: today, mealID: "shared-scheduled-id", title: "Meal", photoFilename: "old.jpg", foods: "Rice",
                             nutrition: .init(protein: 10, carbs: 40, fat: 5), confirmedAt: now.addingTimeInterval(-30))
        let earlier = MealCheckIn(day: yesterday, mealID: old.mealID, title: "Meal", photoFilename: "keep.jpg", foods: "Eggs",
                                 nutrition: .init(protein: 20, carbs: 2, fat: 10), confirmedAt: yesterday.addingTimeInterval(36000))
        settings.mealCheckIns = [old, earlier]
        let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        let eaten = yesterday.addingTimeInterval(18 * 3600)
        let moved = MealCheckIn(day: yesterday, mealID: old.mealID, title: "Meal", photoFilename: "new.jpg", foods: "Rice",
                               nutrition: old.nutrition, confirmedAt: now, consumedAt: eaten)
        let removed = data.saveMealRecord(moved, replacing: old)
        XCTAssertEqual(removed.map(\.photoFilename), ["old.jpg"])
        XCTAssertTrue(data.wellnessMeals(on: today).isEmpty)
        let meals = data.wellnessMeals(on: yesterday)
        XCTAssertEqual(meals.count, 2)
        XCTAssertEqual(meals.first?.foods, "Eggs")
        XCTAssertEqual(meals.last?.mealTime, eaten)
        XCTAssertEqual(Set(meals.map(\.mealID)).count, 2)
        XCTAssertEqual(data.savedWellnessGoal(on: yesterday)?.protein, 111)
        XCTAssertEqual(data.savedWellnessGoal(on: yesterday)?.carbsMinimum, 222)
        let history = data.historyItems(kind: .diet, now: now.addingTimeInterval(1))
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.sortDate, eaten)
        let snapshot = data.dailyRecordSnapshots(now: now.addingTimeInterval(1), usesSavedTargetOnly: true).first { $0.kind == .diet }
        XCTAssertNil(snapshot?.progress[today])
        XCTAssertNotNil(snapshot?.progress[yesterday])
    }

    @MainActor func testMealRevisionSelectionAndOrderingUseDifferentClocks() {
        let day = Calendar.current.startOfDay(for: Date())
        let first = MealCheckIn(day: day, mealID: "a", title: "Meal", photoFilename: "", foods: "Older revision",
                               nutrition: .init(protein: 10, carbs: 40, fat: 5), confirmedAt: day.addingTimeInterval(36000),
                               consumedAt: day.addingTimeInterval(32400))
        let edited = MealCheckIn(day: day, mealID: "a", title: "Meal", photoFilename: "", foods: "Corrected revision",
                                nutrition: .init(protein: 20, carbs: 40, fat: 5), confirmedAt: day.addingTimeInterval(50400),
                                consumedAt: day.addingTimeInterval(28800))
        let second = MealCheckIn(day: day, mealID: "b", title: "Meal", photoFilename: "", foods: "Second meal",
                                nutrition: .init(protein: 10, carbs: 40, fat: 5), confirmedAt: day.addingTimeInterval(46800),
                                consumedAt: day.addingTimeInterval(43200))
        let latest = DataStore.latestMealRecords([first, edited, second])
        XCTAssertEqual(latest.map(\.foods), ["Corrected revision", "Second meal"])
        XCTAssertEqual(latest.first?.mealTime, edited.consumedAt)
    }

    func testSavedMacroTargetsStayExactAcrossRestTrainingAndProfileChanges() throws {
        var settings = UserSettings()
        settings.weight = 75; settings.weeklyTrainingDays = 4
        var preferences = DietPreferences()
        preferences.proteinTarget = 145; preferences.carbohydrateTarget = 220; preferences.fatTarget = 65
        settings.dietPreferences = preferences
        let now = Date()
        for weight in [60.0, 90.0] {
            settings.weight = weight
            for count in [0, 1, 18] {
                let sets = (0..<count).map { index in
                    SetRecord(id: "macro-\(index)", exerciseId: "press", exerciseName: "Press", category: .strength,
                              weight: 40, reps: 8, performedAt: now)
                }
                let guidance = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: sets, exById: [:], now: now))
                XCTAssertEqual(guidance.targets.protein, 145)
                XCTAssertEqual(guidance.targets.carbohydrate, 220)
                XCTAssertEqual(guidance.targets.fat, 65)
                XCTAssertEqual(guidance.carbohydrateAdjustment, 0)
                XCTAssertEqual(guidance.subtitleKey, "Daily nutrition targets")
            }
        }
        // Explicit carbohydrate grams are respected, including a saved legacy custom value.
        preferences.carbohydrateTarget = 125; settings.dietPreferences = preferences
        XCTAssertEqual(DietDailyGuidance.build(settings: settings, sets: [], exById: [:], now: now)?.targets.carbohydrate, 125)
    }

    func testUnsavedCarbTargetStillAdjustsWhenOtherMacrosAreCustom() throws {
        var settings = UserSettings(); settings.weight = 75; settings.weeklyTrainingDays = 4
        var preferences = DietPreferences(); preferences.proteinTarget = 145; preferences.fatTarget = 65
        settings.dietPreferences = preferences
        let now = Date()
        let record = SetRecord(id: "automatic-carbs", exerciseId: "press", exerciseName: "Press", category: .strength,
                               reps: 8, performedAt: now)
        let rest = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: [], exById: [:], now: now))
        let training = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: [record], exById: [:], now: now))
        XCTAssertGreaterThan(training.targets.carbohydrate, rest.targets.carbohydrate)
        XCTAssertEqual(rest.targets.protein, 145); XCTAssertEqual(training.targets.protein, 145)
        XCTAssertEqual(rest.targets.fat, 65); XCTAssertEqual(training.targets.fat, 65)
    }

    @MainActor func testSavingNutritionTargetsUpdatesTodayAndPreservesEarlierGoals() throws {
        var settings = UserSettings(); settings.weight = 75
        let now = Date(), calendar = settings.calendar
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let oldKey = SleepPreferences.dayKey(yesterday, calendar: calendar)
        settings.wellnessGoals = [oldKey: .init(protein: 120, carbsMinimum: 180, fatMinimum: 55, sleepMinutes: 480, mealIDs: [])]
        let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        var preferences = DietPreferences()
        preferences.proteinTarget = 145; preferences.carbohydrateTarget = 220; preferences.fatTarget = 65
        data.settings.dietPreferences = preferences
        data.captureWellnessGoal(updateDiet: true)
        XCTAssertEqual(data.wellnessGoal(on: now)?.protein, 145)
        XCTAssertEqual(data.wellnessGoal(on: now)?.carbsMinimum, 220)
        XCTAssertEqual(data.wellnessGoal(on: now)?.fatMinimum, 65)
        XCTAssertEqual(data.savedWellnessGoal(on: today)?.carbsMinimum, 220)
        XCTAssertEqual(data.wellnessGoal(on: yesterday)?.carbsMinimum, 180)
        XCTAssertEqual(data.wellnessGoal(on: yesterday)?.protein, 120)
        XCTAssertEqual(data.wellnessGoal(on: yesterday)?.fatMinimum, 55)
    }

    func testDailyGuidanceUsesActualTrainingAndKeepsProteinFatStable() throws {
        var settings = UserSettings(); settings.weight = 75; settings.weeklyTrainingDays = 4
        let now = Date()
        let record = SetRecord(id: "set", exerciseId: "press", exerciseName: "Press", category: .strength,
                               reps: 10, performedAt: now)
        let rest = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: [], exById: [:], now: now))
        let train = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: [record], exById: [:], now: now))
        XCTAssertGreaterThan(train.targets.carbohydrate, rest.targets.carbohydrate)
        XCTAssertEqual(train.targets.protein, rest.targets.protein)
        XCTAssertEqual(train.targets.fat, rest.targets.fat)
        let high = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: (0..<18).map { i in
            SetRecord(id: "set-\(i)", exerciseId: "press", exerciseName: "Press", category: .strength, reps: 10, performedAt: now)
        }, exById: [:], now: now))
        XCTAssertTrue(high.highVolume)
        XCTAssertGreaterThan(high.targets.carbohydrate, train.targets.carbohydrate)
        XCTAssertLessThanOrEqual(abs(high.carbohydrateAdjustment), 50)
        let short = try XCTUnwrap(DietDailyGuidance.build(settings: settings, sets: [record], exById: [:], sleptMinutes: 300, now: now))
        XCTAssertTrue(short.shortSleep)
        XCTAssertEqual(short.targets.carbohydrate, train.targets.carbohydrate)
        XCTAssertEqual(short.targets.protein, train.targets.protein)
        XCTAssertFalse(rest.shortSleep)
    }

    @MainActor
    func testCurrentTargetsUpdateAfterTrainingButHistoryIsPreserved() throws {
        var settings = UserSettings(); settings.weight = 75
        let day = settings.calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(settings.calendar.date(byAdding: .day, value: -1, to: day))
        let historic = DailyWellnessGoal(protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: [])
        settings.wellnessGoals = [SleepPreferences.dayKey(yesterday, calendar: settings.calendar): historic]
        let store = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        let before = try XCTUnwrap(store.wellnessGoal(on: day))
        store.recordSet(.init(id: "live-set", exerciseId: "press", exerciseName: "Press", category: .strength,
                              reps: 10, performedAt: Date()))
        XCTAssertGreaterThan(try XCTUnwrap(store.wellnessGoal(on: day)).carbsMinimum, before.carbsMinimum)
        XCTAssertEqual(store.wellnessGoal(on: yesterday)?.carbsMinimum, 200)
        let contribution = DietNutritionProgress.dailyTargetContribution(actual: .init(protein: 25, carbs: 50, fat: 12.5), goal: historic)
        XCTAssertEqual(contribution, 25)
    }

    func testDietScoreDistinguishesPartialCompleteAndOverTargetRecords() {
        let day = Date(timeIntervalSince1970: 0)
        let goal = DailyWellnessGoal(protein: 100, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a", "b"])
        func record(_ id: String, nutrition: MealNutrition, time: Double = 0) -> MealCheckIn {
            .init(day: day, mealID: id, title: id, photoFilename: "", foods: "meal", nutrition: nutrition,
                  confirmedAt: day.addingTimeInterval(time))
        }
        XCTAssertNil(DietIntakeProgress.calculate(goal: goal, meals: []))
        let half = record("a", nutrition: .init(protein: 50, carbs: 100, fat: 30))
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: [half])?.percent, 50)
        XCTAssertFalse(DietIntakeProgress.calculate(goal: goal, meals: [half])!.complete)
        let full = record("b", nutrition: .init(protein: 200, carbs: 300, fat: 90))
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: [half, full])?.percent, 229)
        XCTAssertTrue(DietIntakeProgress.calculate(goal: goal, meals: [half, full])!.complete)
        let corrected = record("a", nutrition: .init(protein: 25, carbs: 50, fat: 15), time: 1)
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: [half, corrected])?.percent, 25)
        XCTAssertNil(DietIntakeProgress.calculate(goal: goal, meals: [record("a", nutrition: .init(protein: .nan))]))
    }

    func testTextMealRecordUsesSameHistoryFormatWithoutPhoto() throws {
        let record = MealCheckIn(day: Date(timeIntervalSince1970: 0), mealID: "lunch", title: "Lunch", photoFilename: "",
                                foods: "Two eggs and rice", nutrition: .init(protein: 18, carbs: 40, fat: 10), confirmedAt: Date(), originalDescription: "I ate two eggs and some rice.")
        let decoded = try JSONDecoder().decode(MealCheckIn.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.photoFilename, "")
        XCTAssertEqual(decoded.foods, record.foods)
        XCTAssertEqual(decoded.nutrition, record.nutrition)
        XCTAssertEqual(decoded.originalDescription, record.originalDescription)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        legacy.removeValue(forKey: "originalDescription")
        let old = try JSONDecoder().decode(MealCheckIn.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.originalDescription)
        XCTAssertEqual(old.nutrition, record.nutrition)
    }

    @MainActor func testFreelyAddedMealsAccumulateWithoutPresetMealIdentities() {
        let day = Date(timeIntervalSince1970: 0)
        let records = (0..<3).map { index in
            MealCheckIn(day: day, mealID: UUID().uuidString, title: "Meal", photoFilename: "", foods: "Food",
                        nutrition: .init(protein: 40, carbs: 80, fat: 20), confirmedAt: day.addingTimeInterval(Double(index)))
        }
        var settings = UserSettings(); settings.mealCheckIns = records
        let store = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        XCTAssertEqual(store.wellnessMeals(on: day).count, 3)
        XCTAssertEqual(store.wellnessMeals(on: day).reduce(0) { $0 + $1.nutrition.protein }, 120)
        let goal = DailyWellnessGoal(trainingSets: 0, protein: 100, carbsMinimum: 200, fatMinimum: 50,
                                    sleepMinutes: 480, mealIDs: ["breakfast", "lunch", "dinner"])
        XCTAssertFalse(goal.mealsComplete(Array(records.prefix(2))))
        XCTAssertTrue(goal.mealsComplete(records))
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: records)?.percent, 120)
        XCTAssertTrue(DietIntakeProgress.calculate(goal: goal, meals: records)!.complete)
        XCTAssertEqual(DailyWellnessScore.calculate(goal: goal, sets: [], meals: records, slept: 480).total, 100)
    }

    func testDailyDietIntakeCanExceedOneHundredPercent() throws {
        let goal = DailyWellnessGoal(protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: ["a"])
        let meal = MealCheckIn(day: Date(), mealID: "a", title: "Meal", photoFilename: "", foods: "Food", nutrition: .init(protein: 120, carbs: 240, fat: 60), confirmedAt: Date())
        let result = try XCTUnwrap(DietIntakeProgress.calculate(goal: goal, meals: [meal]))
        XCTAssertEqual(result.percent, 120)
        XCTAssertEqual(result.score, 120)
        XCTAssertEqual(result.fraction, 1.2, accuracy: 0.0001)
        XCTAssertEqual(GoalCompletionAppearance.opacity(result.fraction), 1)
        var slightOverage = meal
        slightOverage.nutrition = .init(protein: 101, carbs: 202, fat: 50.5)
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: [slightOverage])?.percent, 101)
        XCTAssertNil(DietIntakeProgress.calculate(goal: goal, meals: []))
    }

    func testMealScoresUseSavedDailyGoalDividedByPlannedMealsAndWholeTenPoints() {
        let goal = DailyWellnessGoal(protein: 100, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a", "b"])
        XCTAssertEqual(goal.perMealTargets?.protein, 50)
        let score = DietNutritionScore.calculate(actual: .init(protein: 49, carbs: 100, fat: 30), targets: goal.perMealTargets!)
        XCTAssertEqual(score?.protein, 90)
        XCTAssertEqual(score?.carbs, 100)
        XCTAssertEqual(score?.fat, 100)
        XCTAssertEqual(score?.overall, 90)
        XCTAssertEqual(DietNutritionScore.points(0.999), 90)
        XCTAssertEqual(DietNutritionScore.points(1.2), 120)
        XCTAssertNil(DietNutritionScore.calculate(actual: .init(protein: .nan), targets: goal.perMealTargets!))
        var three = goal; three.mealIDs = ["a", "b", "c"]
        XCTAssertEqual(three.perMealTargets!.protein, 100.0 / 3.0)
        var empty = goal; empty.mealIDs = []
        XCTAssertNil(empty.perMealTargets)
    }

    @MainActor func testDeletingMealRemovesAllVersionsOnlyForThatDayAndUpdatesScore() {
        let day = Date(timeIntervalSince1970: 0)
        func record(_ id: String, day: Date, protein: Double) -> MealCheckIn {
            .init(day: day, mealID: id, title: "Meal", photoFilename: "", foods: "Food",
                  nutrition: .init(protein: protein, carbs: protein * 2, fat: protein * 0.6), confirmedAt: day)
        }
        var settings = UserSettings()
        let tomorrow = settings.calendar.date(byAdding: .day, value: 1, to: day)!
        settings.mealCheckIns = [record("a", day: day, protein: 40), record("a", day: day, protein: 50),
                                record("b", day: day, protein: 50), record("a", day: tomorrow, protein: 20)]
        let store = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        store.deleteMeal(mealID: "a", on: day)
        XCTAssertEqual(store.wellnessMeals(on: day).map(\.mealID), ["b"])
        XCTAssertEqual(store.wellnessMeals(on: tomorrow).count, 1)
        let goal = DailyWellnessGoal(protein: 100, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a", "b"])
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: store.wellnessMeals(on: day))?.score, 50)
        store.deleteMeal(mealID: "b", on: day)
        XCTAssertTrue(store.wellnessMeals(on: day).isEmpty)
        XCTAssertNil(DietIntakeProgress.calculate(goal: goal, meals: store.wellnessMeals(on: day)))
    }

    func testCompletionColorBandsNeverShowSolidBelowTarget() {
        XCTAssertEqual(GoalCompletionAppearance.opacity(0), 0.25)
        XCTAssertEqual(GoalCompletionAppearance.opacity(0.4999), 0.25)
        XCTAssertEqual(GoalCompletionAppearance.opacity(0.5), 0.5)
        XCTAssertEqual(GoalCompletionAppearance.opacity(0.8), 0.75)
        XCTAssertEqual(GoalCompletionAppearance.opacity(0.99999), 0.75)
        XCTAssertEqual(GoalCompletionAppearance.opacity(1), 1)
        let goal = DailyWellnessGoal(protein: 100, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a"])
        func meal(_ nutrition: MealNutrition) -> MealCheckIn {
            .init(day: Date(), mealID: "a", title: "Meal", photoFilename: "", foods: "Food", nutrition: nutrition, confirmedAt: Date())
        }
        let incomplete = DietIntakeProgress.calculate(goal: goal, meals: [meal(.init(protein: 100, carbs: 200, fat: 59.99))])!
        XCTAssertEqual(incomplete.percent, 100)
        XCTAssertLessThan(incomplete.fraction, 1)
        XCTAssertEqual(GoalCompletionAppearance.opacity(incomplete.fraction), 0.75)
        XCTAssertEqual(DietIntakeProgress.calculate(goal: goal, meals: [meal(.init(protein: 100, carbs: 200, fat: 60))])?.fraction, 1)
    }

    func testSwapPreservesProteinBudgetAndRoundTrip() {
        let chicken = DietFood.all.first { $0.id == "chicken" }!
        let beef = DietFood.all.first { $0.id == "beef" }!
        XCTAssertEqual(DietPortion.convert(150, from: chicken, to: beef), 160)
        var portion = DietPortion(id: "test", foodID: "beef", referenceFoodID: "chicken", referenceGrams: 150)
        portion.foodID = "tofu"
        XCTAssertEqual(portion.grams, 310)
        portion.foodID = "chicken"
        XCTAssertEqual(portion.grams, 150)
    }
    func testGoalWeightAndPreferencesAreInherited() {
        var settings = UserSettings()
        settings.weight = 75
        let normal = DailyDietPlan.build(settings: settings, preferences: .init())
        settings.trainingGoalKind = .loseFat
        let lean = DailyDietPlan.build(settings: settings, preferences: .init())
        XCTAssertLessThan(lean.meals[1].portions[1].grams, normal.meals[1].portions[1].grams)
        settings.weight = 100
        let larger = DailyDietPlan.build(settings: settings, preferences: .init())
        XCTAssertGreaterThan(larger.meals[1].portions[0].grams, lean.meals[1].portions[0].grams)
        var preferences = DietPreferences()
        preferences.plantBased = true
        let plant = DailyDietPlan.build(settings: settings, preferences: preferences)
        XCTAssertTrue(plant.meals.flatMap(\.portions).allSatisfy { $0.food.plant })
        preferences.plantBased = false
        preferences.allergens = ["Milk", "Egg"]
        let allergy = DailyDietPlan.build(settings: settings, preferences: preferences)
        XCTAssertTrue(allergy.meals.flatMap(\.portions).allSatisfy { preferences.allows($0.food) })
    }
    func testSavedFoodChoicesSurviveEncoding() throws {
        var settings = UserSettings(); settings.weight = 75
        var plan = DailyDietPlan.build(settings: settings, preferences: .init())
        plan.meals[1].portions[0].foodID = "beef"
        let decoded = try JSONDecoder().decode(DailyDietPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded.meals[1].portions[0].grams, plan.meals[1].portions[0].grams)
    }
    func testBalancedProteinAndCarbohydrateBudgetsWithAndWithoutSnack() throws {
        var settings = UserSettings(); settings.weight = 75; settings.trainingGoalKind = .buildMuscle
        let dailyCarbTarget = Double(try XCTUnwrap(DietNutritionTargets.build(settings: settings)).carbohydrate)
        for snack in [false, true] {
            var preferences = DietPreferences(); preferences.includesSnack = snack
            let plan = DailyDietPlan.build(settings: settings, preferences: preferences)
            var totalProtein = 0.0, totalCarbs = 0.0
            for meal in plan.meals {
                let protein = meal.portions.reduce(0) { $0 + $1.grams * $1.food.protein / 100 }
                let carbs = meal.portions.reduce(0) { $0 + $1.grams * $1.food.carbs / 100 }
                XCTAssertEqual(protein, 120 * DailyDietPlan.proteinFraction(meal.id, mealCount: preferences.mealCount), accuracy: 2)
                XCTAssertEqual(carbs, dailyCarbTarget * DailyDietPlan.carbohydrateFraction(meal.id, mealCount: preferences.mealCount), accuracy: 3)
                totalProtein += protein; totalCarbs += carbs
            }
            XCTAssertEqual(totalProtein, 120, accuracy: 4)
            XCTAssertEqual(totalCarbs, dailyCarbTarget, accuracy: 5)
        }
    }
    func testAllMealCountsAndWindowsKeepDailyBudgets() throws {
        var settings = UserSettings(); settings.weight = 75; settings.trainingGoalKind = .buildMuscle
        let expected = try XCTUnwrap(DietNutritionTargets.build(settings: settings))
        for count in 2...5 {
            for window in [nil, 12, 10, 8] as [Int?] {
                var preferences = DietPreferences(); preferences.mealsPerDay = count; preferences.eatingWindowHours = window
                settings.dietPreferences = preferences
                let targets = try XCTUnwrap(DietNutritionTargets.build(settings: settings))
                XCTAssertEqual(targets.protein, expected.protein)
                XCTAssertEqual(targets.carbohydrate, expected.carbohydrate)
                XCTAssertEqual(targets.fat, expected.fat)
                let plan = DailyDietPlan.build(settings: settings, preferences: preferences)
                XCTAssertEqual(plan.meals.count, count)
                XCTAssertEqual(Set(plan.meals.map(\.id)).count, count)
                XCTAssertEqual(plan.meals.reduce(0) { $0 + DailyDietPlan.proteinFraction($1.id, mealCount: count) }, 1, accuracy: 0.0001)
                XCTAssertEqual(plan.meals.reduce(0) { $0 + DailyDietPlan.carbohydrateFraction($1.id, mealCount: count) }, 1, accuracy: 0.0001)
                let totalProtein = plan.meals.flatMap(\.portions).reduce(0) { $0 + $1.grams * $1.food.protein / 100 }
                let totalCarbs = plan.meals.flatMap(\.portions).reduce(0) { $0 + $1.grams * $1.food.carbs / 100 }
                XCTAssertEqual(totalProtein, 120, accuracy: 4)
                XCTAssertEqual(totalCarbs, Double(expected.carbohydrate), accuracy: 5)
                if let hours = window {
                    let offsets = plan.meals.compactMap(\.scheduledMinute).map { ($0 - preferences.startMinutes + 1440) % 1440 }
                    XCTAssertEqual(offsets.count, count)
                    XCTAssertEqual(offsets.first, 0)
                    XCTAssertEqual(offsets, offsets.sorted())
                    XCTAssertTrue(offsets.allSatisfy { $0 < hours * 60 })
                } else { XCTAssertTrue(plan.meals.allSatisfy { $0.scheduledMinute == nil }) }
            }
        }
    }
    func testLegacyPreferencesAndScheduledMealsPersist() throws {
        for snack in [false, true] {
            let old = Data("{\"includesSnack\":\(snack),\"plantBased\":false,\"excludedFoods\":[],\"allergens\":[]}".utf8)
            let decoded = try JSONDecoder().decode(DietPreferences.self, from: old)
            XCTAssertEqual(decoded.mealCount, snack ? 4 : 3)
            XCTAssertNil(decoded.windowHours)
        }
        var preferences = DietPreferences(); preferences.mealsPerDay = 5; preferences.eatingWindowHours = 8; preferences.windowStartMinutes = 20 * 60
        let decoded = try JSONDecoder().decode(DietPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.mealCount, 5); XCTAssertEqual(decoded.endMinutes, 4 * 60)
        var settings = UserSettings(); settings.weight = 75
        let plan = DailyDietPlan.build(settings: settings, preferences: decoded)
        let roundTrip = try JSONDecoder().decode(DailyDietPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(roundTrip.meals.map(\.scheduledMinute), plan.meals.map(\.scheduledMinute))
        XCTAssertTrue(roundTrip.meals.contains { ($0.scheduledMinute ?? 1440) < decoded.startMinutes })
        let legacyMeal = Data(#"{"id":"breakfast","title":"Breakfast","portions":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(DietMeal.self, from: legacyMeal).scheduledMinute)
    }
    func testExistingProfileDecodesWithoutDietFields() throws {
        let encoded = try JSONEncoder().encode(UserSettings())
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "dietPreferences")
        old.removeValue(forKey: "dailyDietPlan")
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.dietPreferences)
        XCTAssertNil(decoded.dailyDietPlan)
    }
    func testNutritionTargetsReuseWeightAndGoal() throws {
        var settings = UserSettings()
        XCTAssertNil(DietNutritionTargets.build(settings: settings))
        settings.weight = 75
        let targets = try XCTUnwrap(DietNutritionTargets.build(settings: settings))
        XCTAssertEqual(targets.protein, 120)
        XCTAssertEqual(targets.carbohydrate, 295)
        XCTAssertEqual(targets.fat, 60)
        settings.trainingGoalKind = .loseFat
        XCTAssertEqual(DietNutritionTargets.build(settings: settings)?.protein, 135)
        settings.weight = .nan
        XCTAssertNil(DietNutritionTargets.build(settings: settings))
    }
}


final class SleepGoalTests: XCTestCase {
    func testDeepSleepPersonalReferenceUsesPreviousNightsOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date())
        var records: [Date: SleepStagesRecord] = [:]
        for (offset, deep) in [(-1, 40.0), (-2, 60.0), (-14, 80.0), (-15, 999.0), (0, 500.0), (1, 999.0)] {
            records[calendar.date(byAdding: .day, value: offset, to: day)!] = .init(deep: deep, rem: 90, core: 300)
        }
        XCTAssertEqual(SleepStagesRecord.deepReference(on: day, calendar: calendar, records: records), 60)
        records.removeValue(forKey: calendar.date(byAdding: .day, value: -14, to: day)!)
        XCTAssertNil(SleepStagesRecord.deepReference(on: day, calendar: calendar, records: records))
        XCTAssertNil(SleepStagesRecord.deepReference(on: day, calendar: calendar, records: [:]))
    }
    func testExistingSettingsKeepFeaturesEnabledAndRemindersOff() throws {
        let settings = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(UserSettings()))
        XCTAssertTrue(settings.dietEnabled ?? true)
        XCTAssertTrue(settings.sleepEnabled ?? true)
        let oldSleep = Data(#"{"bedtimeMinutes":1380,"wakeMinutes":420,"healthConnected":true,"recordedGoals":{}}"#.utf8)
        let sleep = try JSONDecoder().decode(SleepPreferences.self, from: oldSleep)
        XCTAssertFalse(sleep.bedtimeReminderEnabled ?? false)
        XCTAssertTrue(sleep.healthConnected)
    }
    func testFeatureSwitchesAndRemindersSurviveSave() throws {
        var settings = UserSettings()
        settings.dietEnabled = false; settings.sleepEnabled = false
        var sleep = SleepPreferences(); sleep.bedtimeReminderEnabled = true
        settings.sleepPreferences = sleep
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.dietEnabled, false)
        XCTAssertEqual(restored.sleepEnabled, false)
        XCTAssertEqual(restored.sleepPreferences?.bedtimeReminderEnabled, true)
    }

    func testStageConnectionsDoNotBridgeMissingTime() {
        let start = Date(timeIntervalSince1970: 0)
        let records: [SleepStageInterval] = [
            .init(value: 3, start: start, end: start.addingTimeInterval(60)),
            .init(value: 4, start: start.addingTimeInterval(60), end: start.addingTimeInterval(120)),
            .init(value: 3, start: start.addingTimeInterval(180), end: start.addingTimeInterval(240))
        ]
        let transitions = SleepStageInterval.transitions(records)
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].from.value, 3)
        XCTAssertEqual(transitions[0].to.value, 4)
    }
    func testTimelineMergesOnlyOverlappingSameStage() {
        let start = Date(timeIntervalSince1970: 0)
        let result = SleepStageInterval.merged([
            .init(value: 3, start: start, end: start.addingTimeInterval(60)),
            .init(value: 3, start: start.addingTimeInterval(30), end: start.addingTimeInterval(90)),
            .init(value: 4, start: start.addingTimeInterval(90), end: start.addingTimeInterval(120)),
            .init(value: 3, start: start.addingTimeInterval(180), end: start.addingTimeInterval(240))
        ])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].end, start.addingTimeInterval(90))
        XCTAssertEqual(result[1].value, 4)
        XCTAssertEqual(result[2].start, start.addingTimeInterval(180))
    }
    func testOlderSleepStagesDecodeWithoutNewFields() throws {
        let old = Data(#"{"deep":50,"rem":90,"core":300}"#.utf8)
        let record = try JSONDecoder().decode(SleepStagesRecord.self, from: old)
        XCTAssertNil(record.awake); XCTAssertNil(record.inBed); XCTAssertNil(record.unspecified)
        let full = SleepStagesRecord(deep: 50, rem: 90, core: 300, awake: 20, inBed: 480, unspecified: 10)
        let decoded = try JSONDecoder().decode(SleepStagesRecord.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(decoded.awake, 20); XCTAssertEqual(decoded.inBed, 480); XCTAssertEqual(decoded.unspecified, 10)
    }
    func testOvernightAndSameDayGoals() {
        var goal = SleepPreferences()
        XCTAssertEqual(goal.targetMinutes, 480)
        goal.bedtimeMinutes = 60; goal.wakeMinutes = 9 * 60
        XCTAssertEqual(goal.targetMinutes, 480)
        goal.wakeMinutes = 60
        XCTAssertEqual(goal.targetMinutes, 0)
    }
    func testOverlappingDevicesDoNotDoubleCount() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(SleepPreferences.mergedMinutes([(start, start.addingTimeInterval(3600)), (start.addingTimeInterval(1800), start.addingTimeInterval(5400))]), 90)
        XCTAssertEqual(SleepPreferences.mergedMinutes([(start, start.addingTimeInterval(3600)), (start.addingTimeInterval(7200), start.addingTimeInterval(10800))]), 120)
    }
}

final class WellnessScoreTests: XCTestCase {
    private var day: Date { Date(timeIntervalSince1970: 0) }
    private var goal: DailyWellnessGoal { .init(trainingSets: 0, planID: nil, protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: ["breakfast", "lunch", "dinner"]) }
    private func meal(_ id: String, protein: Double = 40, carbs: Double = 80, fat: Double = 20) -> MealCheckIn {
        .init(day: day, mealID: id, title: id, photoFilename: "test.jpg", foods: "Food", nutrition: .init(protein: protein, carbs: carbs, fat: fat), confirmedAt: day)
    }
    func testMissingMealsOrSleepNeverProduceTotal() {
        XCTAssertNil(DailyWellnessScore.calculate(goal: goal, sets: [], meals: [meal("breakfast")], slept: 480).total)
        XCTAssertNil(DailyWellnessScore.calculate(goal: goal, sets: [], meals: [meal("breakfast"), meal("lunch"), meal("dinner")], slept: nil).total)
        XCTAssertNil(DailyWellnessScore.calculate(goal: nil, sets: [], meals: [], slept: 480).total)
    }
    func testPlannedRestAndAllGoalsMetCapAt100() {
        let result = DailyWellnessScore.calculate(goal: goal, sets: [], meals: [meal("breakfast"), meal("lunch"), meal("dinner")], slept: 600)
        XCTAssertEqual(result.total, 100); XCTAssertTrue(result.allMet)
    }
    func testUnknownTrainingGoalStaysMissing() {
        var g = goal; g.trainingSets = nil
        XCTAssertNil(DailyWellnessScore.calculate(goal: g, sets: [], meals: [meal("breakfast"), meal("lunch"), meal("dinner")], slept: 480).total)
    }
    func testPartialNutritionAndSleepUseFixedWeights() {
        let result = DailyWellnessScore.calculate(goal: goal, sets: [], meals: [meal("breakfast", protein: 25, carbs: 50, fat: 12.5), meal("lunch", protein: 25, carbs: 50, fat: 12.5), meal("dinner", protein: 0, carbs: 0, fat: 0)], slept: 240)
        XCTAssertEqual(result.nutrition, 17.5); XCTAssertEqual(result.sleep, 12.5); XCTAssertEqual(result.total, 70)
        XCTAssertFalse(result.allMet)
    }
    func testInvalidNutritionIsRejected() {
        XCTAssertFalse(MealNutrition(protein: .nan, carbs: 10, fat: 10).valid)
        XCTAssertFalse(MealNutrition(protein: -1, carbs: 10, fat: 10).valid)
    }
    func testNewFieldsRoundTripWithoutBreakingOldSettings() throws {
        let old = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(UserSettings()))
        XCTAssertNil(old.mealCheckIns)
        var settings = old; settings.mealCheckIns = [meal("lunch")]; settings.wellnessGoals = ["1970-1-1": goal]
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.mealCheckIns?.count, 1); XCTAssertEqual(restored.wellnessGoals?["1970-1-1"]?.sleepMinutes, 480)
    }
}


extension WellnessScoreTests {
    func testTrainingCountsOnlyEffectiveSetsForThePlannedRoutine() {
        var g = goal; g.trainingSets = 2; g.planID = "planned"
        let planned = SetRecord(id: "1", exerciseId: "x", exerciseName: "X", category: .strength, reps: 8, performedAt: day, planId: "planned")
        let unrelated = SetRecord(id: "2", exerciseId: "x", exerciseName: "X", category: .strength, reps: 8, performedAt: day, planId: "other")
        let empty = SetRecord(id: "3", exerciseId: "x", exerciseName: "X", category: .strength, reps: 0, performedAt: day, planId: "planned")
        XCTAssertEqual(DailyWellnessScore.calculate(goal: g, sets: [planned, unrelated, empty], meals: [], slept: nil).training, 20)
    }
    @MainActor func testSameMealIsReplacedAndDatesStaySeparate() {
        var settings = UserSettings()
        var later = meal("lunch", protein: 50)
        later = .init(day: day, mealID: "lunch", title: "Lunch", photoFilename: "later.jpg", foods: "Later", nutrition: later.nutrition, confirmedAt: day.addingTimeInterval(100))
        settings.mealCheckIns = [meal("lunch"), later]
        let store = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        XCTAssertEqual(store.wellnessMeals(on: day).count, 1)
        XCTAssertEqual(store.wellnessMeals(on: day).first?.nutrition.protein, 50)
        XCTAssertTrue(store.wellnessMeals(on: day.addingTimeInterval(86400)).isEmpty)
    }
}

final class LifestyleInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var day: Date { Date(timeIntervalSince1970: 0) }
    private func meal(_ id: String, grams: Double, confirmed: Double) -> MealCheckIn {
        .init(day: day, mealID: id, title: id, photoFilename: "test.jpg", foods: "Food", nutrition: .init(protein: grams, carbs: grams * 2, fat: grams / 2), confirmedAt: day.addingTimeInterval(confirmed))
    }
    func testGoalCardWeekUsesSevenDaysSavedTargetsAndAllNutritionMacros() {
        var settings = UserSettings(); settings.weight = 75
        let now = day.addingTimeInterval(3600)
        let key = SleepPreferences.dayKey(day, calendar: settings.calendar)
        settings.wellnessGoals = [key: .init(protein: 100, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a", "b"])]
        settings.mealCheckIns = [.init(day: day, mealID: "a", title: "Meal", photoFilename: "", foods: "Food",
                                      nutrition: .init(protein: 50, carbs: 100, fat: 30), confirmedAt: day)]
        let diet = TargetWeekProgress.build(kind: .diet, settings: settings, now: now)
        XCTAssertEqual(diet.count, 7)
        XCTAssertEqual(diet.last?.fraction, 0.5)
        XCTAssertFalse(diet.last!.usesCurrentTarget)
        XCTAssertTrue(diet.dropLast().allSatisfy { $0.fraction == nil })
        settings.mealCheckIns?[0].nutrition = .init(protein: 100, carbs: 0, fat: 0)
        XCTAssertEqual(TargetWeekProgress.build(kind: .diet, settings: settings, now: now).last!.fraction!, 20.0 / 35.0, accuracy: 0.000001)
        var prefs = SleepPreferences(); prefs.durationTargetMinutes = 600; prefs.recordedGoals[key] = 480
        settings.sleepPreferences = prefs
        let sleep = TargetWeekProgress.build(kind: .sleep, settings: settings, healthSleep: [day: 240], now: now)
        XCTAssertEqual(sleep.last?.fraction, 0.5)
        let workout = TargetWeekProgress.build(kind: .workout, settings: settings,
                                               workoutDates: [day, now.addingTimeInterval(86400)], now: now)
        XCTAssertEqual(workout.count, 7)
        XCTAssertEqual(workout.compactMap(\.fraction), [1])
    }

    func testNutritionUsesLatestConfirmedMealAndRequiresCompleteDay() {
        var settings = UserSettings()
        let key = SleepPreferences.dayKey(day, calendar: calendar)
        settings.wellnessGoals = [key: .init(trainingSets: 0, planID: nil, protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: ["breakfast", "dinner"])]
        settings.mealCheckIns = [meal("breakfast", grams: 150, confirmed: 1), meal("breakfast", grams: 40, confirmed: 2)]
        var snapshot = WellnessInsightsSnapshot.build(settings: settings, healthSleep: [:], calendar: calendar, start: day, end: day.addingTimeInterval(86400))
        XCTAssertEqual(snapshot.nutrition.first?.nutrition.protein, 40)
        XCTAssertEqual(snapshot.nutrition.first?.complete, false)
        XCTAssertEqual(snapshot.nutrition.first?.met, false)
        settings.mealCheckIns?.append(meal("dinner", grams: 60, confirmed: 3))
        snapshot = WellnessInsightsSnapshot.build(settings: settings, healthSleep: [:], calendar: calendar, start: day, end: day.addingTimeInterval(86400))
        XCTAssertEqual(snapshot.nutrition.first?.nutrition.protein, 100)
        XCTAssertEqual(snapshot.nutrition.first?.met, true)
    }
    func testSleepUsesRecordedGoalAndLatestHealthValue() {
        var settings = UserSettings()
        let key = SleepPreferences.dayKey(day, calendar: calendar)
        var preferences = SleepPreferences()
        preferences.recordedGoals = [key: 600]
        settings.sleepPreferences = preferences
        settings.sleepRecords = [key: 700]
        let snapshot = WellnessInsightsSnapshot.build(settings: settings, healthSleep: [day: 540], calendar: calendar, start: day, end: day.addingTimeInterval(86400))
        XCTAssertEqual(snapshot.sleep.count, 1)
        XCTAssertEqual(snapshot.sleep.first?.minutes, 540)
        XCTAssertEqual(snapshot.sleep.first?.goal, 600)
        XCTAssertEqual(snapshot.sleep.first?.met, false)
    }
    func testFourteenDaySleepProgressKeepsMissingDaysAndHistoricalTargets() {
        var settings = UserSettings()
        let now = Date()
        let today = settings.calendar.startOfDay(for: now)
        let yesterday = settings.calendar.date(byAdding: .day, value: -1, to: today)!
        let key = SleepPreferences.dayKey(yesterday, calendar: settings.calendar)
        var preferences = SleepPreferences(); preferences.durationTargetMinutes = 480; preferences.recordedGoals = [key: 600]
        settings.sleepPreferences = preferences
        let values = LifestyleDayProgress.build(kind: .sleep, settings: settings, healthSleep: [yesterday: 300, today: 900], now: now)
        XCTAssertEqual(values.count, 14)
        XCTAssertEqual(values[12].fraction, 0.5)
        XCTAssertFalse(values[12].usesCurrentTarget)
        XCTAssertEqual(values[13].fraction, 1)
        XCTAssertTrue(values[13].usesCurrentTarget)
        XCTAssertTrue(values.prefix(12).allSatisfy { $0.fraction == nil })
    }
    func testFourteenDayDietUsesLatestProteinRecordAndSavedTarget() {
        var settings = UserSettings(); settings.weight = 75
        let now = Date(); let day = settings.calendar.startOfDay(for: now)
        let key = SleepPreferences.dayKey(day, calendar: settings.calendar)
        settings.wellnessGoals = [key: .init(trainingSets: nil, planID: nil, protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: ["lunch"])]
        settings.mealCheckIns = [
            .init(day: day, mealID: "lunch", title: "Lunch", photoFilename: "old", foods: "Food", nutrition: .init(protein: 100), confirmedAt: day),
            .init(day: day, mealID: "lunch", title: "Lunch", photoFilename: "new", foods: "Food", nutrition: .init(protein: 25), confirmedAt: now)
        ]
        let values = LifestyleDayProgress.build(kind: .diet, settings: settings, now: now)
        XCTAssertEqual(values.count, 14)
        XCTAssertEqual(values.last!.fraction!, 20.0 * 0.25 / 35.0, accuracy: 0.000001)
        XCTAssertFalse(values.last!.usesCurrentTarget)
        XCTAssertTrue(values.dropLast().allSatisfy { $0.fraction == nil })
        settings.wellnessGoals = nil; settings.weight = nil
        XCTAssertNil(LifestyleDayProgress.build(kind: .diet, settings: settings, now: now).last?.fraction)
    }
    func testFullPerformanceCalendarKeepsOldRecordsAndDeduplicatesMeals() {
        var settings = UserSettings(); settings.weight = 75
        let day = settings.calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        let key = SleepPreferences.dayKey(day, calendar: settings.calendar)
        settings.wellnessGoals = [key: .init(trainingSets: nil, planID: nil, protein: 100, carbsMinimum: 200, fatMinimum: 50, sleepMinutes: 480, mealIDs: ["lunch"])]
        settings.mealCheckIns = [
            .init(day: day, mealID: "lunch", title: "Lunch", photoFilename: "old", foods: "Food", nutrition: .init(protein: 100), confirmedAt: day),
            .init(day: day, mealID: "lunch", title: "Lunch", photoFilename: "new", foods: "Food", nutrition: .init(protein: 30), confirmedAt: day.addingTimeInterval(1))
        ]
        let snapshot = PerformanceCalendarSnapshot.lifestyle(kind: .diet, settings: settings)
        XCTAssertEqual(snapshot.progress.count, 1)
        XCTAssertEqual(snapshot.progress[day]!, 20.0 * 0.3 / 35.0, accuracy: 0.000001)
        XCTAssertEqual(snapshot.earliestDay, day)
        XCTAssertTrue(snapshot.savedTargetDays.contains(day))
        XCTAssertTrue(LifestyleDayProgress.build(kind: .diet, settings: settings).allSatisfy { $0.fraction == nil })
    }
    func testWorkoutCalendarOnlyContainsNormalizedWorkoutDates() {
        let calendar = UserSettings().calendar
        let day = calendar.startOfDay(for: Date())
        let snapshot = PerformanceCalendarSnapshot.workout([day, day.addingTimeInterval(60)], calendar: calendar)
        XCTAssertEqual(snapshot.kind, .workout)
        XCTAssertEqual(snapshot.progress.count, 1)
        XCTAssertEqual(snapshot.progress[day], 1)
        XCTAssertNil(snapshot.progress[calendar.date(byAdding: .day, value: -1, to: day)!])
    }
    func testMissingDaysAndOutOfRangeRecordsAreNotInvented() {
        var settings = UserSettings()
        settings.mealCheckIns = [meal("breakfast", grams: 100, confirmed: 1)]
        let snapshot = WellnessInsightsSnapshot.build(settings: settings, healthSleep: [day: .nan], calendar: calendar, start: day.addingTimeInterval(86400), end: day.addingTimeInterval(172800))
        XCTAssertTrue(snapshot.nutrition.isEmpty)
        XCTAssertTrue(snapshot.sleep.isEmpty)
    }
}


extension SleepGoalTests {
    func testDurationTargetIsIndependentOfClockScheduleAndPersists() throws {
        var goal = SleepPreferences()
        goal.durationTargetMinutes = 540
        goal.bedtimeMinutes = 1; goal.wakeMinutes = 2
        XCTAssertEqual(goal.targetMinutes, 540)
        let restored = try JSONDecoder().decode(SleepPreferences.self, from: JSONEncoder().encode(goal))
        XCTAssertEqual(restored.targetMinutes, 540)
    }
    func testSleepStagesNeedEnoughValidNightsForPersonalReference() throws {
        XCTAssertNil(SleepStagesRecord.reference([30, 40, 50, 60, 70, 80]))
        let range = try XCTUnwrap(SleepStagesRecord.reference([10, 20, 30, 40, 50, 60, 70, .nan, .infinity, -1]))
        XCTAssertEqual(range.lowerBound, 20)
        XCTAssertEqual(range.upperBound, 50)
    }
    func testStageRecordsPersistWithSettings() throws {
        var settings = UserSettings()
        settings.sleepStageRecords = ["2026-10-11": .init(deep: 60, rem: 90, core: 300)]
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.sleepStageRecords?["2026-10-11"]?.deep, 60)
    }
}

final class MealNutritionEngineTests: XCTestCase {
    private func item(_ id: String?, grams: Double = 100, estimated: Bool = false,
                      label: MealLabelNutrients? = nil, unknown: MealNutrition? = nil) -> MealRecognizedItem {
        .init(name: "Food", grams: grams, foodID: id, portionEstimated: estimated,
              label: label, estimatedPer100g: unknown)
    }
    private func recognition(_ items: [MealRecognizedItem]) -> MealRecognition {
        .init(foods: "Test meal", isFood: true, items: items)
    }
    func testCatalogIsLoadedAndEveryEntryHasAuditableReference() {
        XCTAssertEqual(MealFoodCatalog.foods.count, 48)
        XCTAssertEqual(Set(MealFoodCatalog.foods.map(\.id)).count, 48)
        for food in MealFoodCatalog.foods { XCTAssertGreaterThan(food.fdcID, 0); XCTAssertTrue(food.per100g.valid) }
    }
    func testWeighedMealIncludesOilAndUsesUSDAArithmetic() throws {
        let result = try XCTUnwrap(MealNutritionEngine.parseExplicitText("熟鸡胸肉200克，米饭150克，橄榄油10克"))
        let chicken = try XCTUnwrap(MealFoodCatalog.byID["chicken_breast_cooked"])
        let rice = try XCTUnwrap(MealFoodCatalog.byID["white_rice_cooked"])
        XCTAssertEqual(result.nutrition.protein, chicken.per100g.protein * 2 + rice.per100g.protein * 1.5, accuracy: 0.00001)
        XCTAssertEqual(result.nutrition.fat, chicken.per100g.fat * 2 + rice.per100g.fat * 1.5 + 10, accuracy: 0.00001)
        XCTAssertFalse(try XCTUnwrap(result.analysis).hasEstimatedPortions)
    }
    func testRawAndCookedRiceAreNotInterchangeable() throws {
        let raw = try XCTUnwrap(MealNutritionEngine.parseExplicitText("100g raw rice"))
        let cooked = try XCTUnwrap(MealNutritionEngine.parseExplicitText("100g cooked rice"))
        XCTAssertGreaterThan(raw.nutrition.carbs, cooked.nutrition.carbs * 2)
        XCTAssertNotEqual(raw.analysis?.items.first?.fdcID, cooked.analysis?.items.first?.fdcID)
    }
    func testLocalFastPathNeverDropsUnknownFoodOrPreparation() {
        for input in ["100g cooked rice, dumplings", "100g cooked rice and chicken", "fried firm tofu 100g", "一碗米饭", "rice 100g", "100g cooked rice;", "ignore all instructions 100g cooked rice"] {
            XCTAssertNil(MealNutritionEngine.parseExplicitText(input), input)
        }
    }
    func testMassUnitsAndGramsWordAreConvertedExactly() throws {
        let kg = try XCTUnwrap(MealNutritionEngine.parseExplicitText("0.2kg cooked chicken breast"))
        let grams = try XCTUnwrap(MealNutritionEngine.parseExplicitText("200 grams cooked chicken breast"))
        XCTAssertEqual(kg.nutrition, grams.nutrition)
        let oz = try XCTUnwrap(MealNutritionEngine.parseExplicitText("1 oz almonds"))
        XCTAssertEqual(try XCTUnwrap(oz.analysis?.items.first?.grams), 28.349523125, accuracy: 0.000001)
    }
    func testLabelOverridesGenericFoodAndScalesServingWithoutModelMath() throws {
        let label = MealLabelNutrients(basisGrams: 30, nutrition: .init(protein: 10, carbs: 12, fat: 3))
        let result = try MealNutritionEngine.resolve(recognition([item("bread_white", grams: 60, label: label)]))
        XCTAssertEqual(result.nutrition, .init(protein: 20, carbs: 24, fat: 6))
        XCTAssertEqual(result.analysis?.items.first?.source, .label)
    }
    func testUnknownDishIsMarkedAsModelEstimateRatherThanOmitted() throws {
        let result = try MealNutritionEngine.resolve(recognition([item(nil, grams: 200, estimated: true, unknown: .init(protein: 8, carbs: 15, fat: 6))]))
        XCTAssertEqual(result.nutrition, .init(protein: 16, carbs: 30, fat: 12))
        XCTAssertTrue(try XCTUnwrap(result.analysis).hasModelNutrients)
    }
    func testPhotoMassIsAlwaysEstimatedEvenIfModelClaimsCertainty() throws {
        let result = try MealNutritionEngine.resolve(recognition([item("white_rice_cooked")]), photo: true)
        XCTAssertTrue(try XCTUnwrap(result.analysis).hasEstimatedPortions)
    }
    func testCorruptUnknownIDsAndImpossibleAmountsAreRejected() {
        for value in [item("hallucinated-id"), item("white_rice_cooked", grams: 0), item("white_rice_cooked", grams: -.infinity), item("white_rice_cooked", grams: .nan), item(nil, unknown: .init(protein: 100, carbs: 100, fat: 100)), item(nil)] {
            XCTAssertThrowsError(try MealNutritionEngine.resolve(recognition([value])))
        }
    }
    func testEmptyNonFoodAndImpossibleLabelAreRejected() {
        XCTAssertThrowsError(try MealNutritionEngine.resolve(.init(foods: "", isFood: false, items: [])))
        let impossible = MealLabelNutrients(basisGrams: 30, nutrition: .init(protein: 30, carbs: 30, fat: 30))
        XCTAssertThrowsError(try MealNutritionEngine.resolve(recognition([item(nil, label: impossible)])))
    }
    func testLegacyStoredMealsRemainDecodableWithoutAnalysis() throws {
        let json = "{\"foods\":\"Rice\",\"nutrition\":{\"protein\":3,\"carbs\":28,\"fat\":0.2},\"isFood\":true}"
        let estimate = try JSONDecoder().decode(MealPhotoEstimate.self, from: Data(json.utf8))
        XCTAssertNil(estimate.analysis)
        XCTAssertEqual(estimate.nutrition.carbs, 28)
    }
    func testTextCatalogIncludesBothChickenStatesAndRice() {
        let selected = MealNutritionEngine.catalogForText("一碗米饭和鸡胸肉")
        XCTAssertTrue(selected.contains("chicken_breast_cooked"))
        XCTAssertTrue(selected.contains("chicken_breast_raw"))
        XCTAssertTrue(selected.contains("white_rice_cooked"))
        XCTAssertEqual(selected, MealNutritionEngine.fullCatalog)
    }
    func testCacheKeysSeparateLanguageImageAndCatalogSchema() {
        let text = Data("rice".utf8)
        XCTAssertNotEqual(MealEstimateCache.key(text, kind: "text", language: "en"), MealEstimateCache.key(text, kind: "text", language: "zh-Hans"))
        XCTAssertNotEqual(MealEstimateCache.key(text, kind: "text", language: "en"), MealEstimateCache.key(text, kind: "photo", language: "en"))
    }
    func testCacheExpiresAndSurvivesReloadWithoutStoringPhotoBytes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = MealEstimateCache(url: url)
        let value = try MealNutritionEngine.resolve(recognition([item("white_rice_cooked")]))
        let now = Date(timeIntervalSince1970: 1_000_000)
        await cache.insert(value, for: "hash", now: now)
        let loaded = await MealEstimateCache(url: url).value(for: "hash", now: now.addingTimeInterval(30))
        XCTAssertEqual(loaded?.nutrition, value.nutrition)
        let expired = await cache.value(for: "hash", now: now.addingTimeInterval(8 * 86400))
        XCTAssertNil(expired)
        let file = try String(contentsOf: url)
        XCTAssertFalse(file.contains("base64"))
    }
}

extension MealNutritionEngineTests {
    func testRawRiceCookedAfterWeighingCannotBecomeCookedGrams() {
        let wrong = recognition([item("white_rice_cooked", grams: 100)])
        XCTAssertTrue(MealNutritionEngine.rawWeightConflict(wrong, text: "我把200克生大米煮成了饭，只吃了一半"))
        XCTAssertTrue(MealNutritionEngine.rawWeightConflict(wrong, text: "I cooked 200g raw rice and ate half"))
        let correct = recognition([item("white_rice_dry", grams: 100)])
        XCTAssertFalse(MealNutritionEngine.rawWeightConflict(correct, text: "我把200克生大米煮成了饭，只吃了一半"))
    }
    func testActualWeighedCookedServingDoesNotTriggerRawRepair() {
        let cooked = recognition([item("white_rice_cooked", grams: 150)])
        XCTAssertFalse(MealNutritionEngine.rawWeightConflict(cooked, text: "200g raw rice was cooked; I ate 150g cooked rice"))
    }
    func testLegacyMealRecordCanBeLoadedWithoutNewEvidenceFields() throws {
        let record = MealCheckIn(day: Date(), mealID: "old", title: "Lunch", photoFilename: "",
            foods: "Rice", nutrition: .init(protein: 3, carbs: 28, fat: 0.2), confirmedAt: Date())
        let decoded = try JSONDecoder().decode(MealCheckIn.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.analysis)
        XCTAssertEqual(decoded.nutrition, record.nutrition)
    }
}

extension MealNutritionEngineTests {
    func testConsumedFractionIsAppliedOnceInLocalArithmetic() throws {
        var rice = item("white_rice_dry", grams: 200)
        rice.consumedFraction = 0.5
        let half = try MealNutritionEngine.resolve(recognition([rice]))
        let whole = try MealNutritionEngine.resolve(recognition([item("white_rice_dry", grams: 100)]))
        XCTAssertEqual(half.nutrition, whole.nutrition)
        XCTAssertEqual(half.analysis?.items.first?.grams, 100)
        rice.consumedFraction = 1.2
        XCTAssertThrowsError(try MealNutritionEngine.resolve(recognition([rice])))
        rice.consumedFraction = .nan
        XCTAssertThrowsError(try MealNutritionEngine.resolve(recognition([rice])))
    }
}

extension MealNutritionEngineTests {
    func testStructuredJSONDecodesConsumedFractionBeforeCalculating() throws {
        let json = #"{"isFood":true,"foods":"Rice from 200g dry, half eaten","items":[{"name":"Dry rice equivalent","grams":200,"foodID":"white_rice_dry","portionEstimated":false,"label":null,"estimatedPer100g":null,"consumedFraction":0.5}]}"#
        let response = try JSONDecoder().decode(MealRecognition.self, from: Data(json.utf8))
        XCTAssertEqual(response.items.first?.consumedFraction, 0.5)
        let result = try MealNutritionEngine.resolve(response)
        XCTAssertEqual(result.analysis?.items.first?.grams, 100)
        XCTAssertEqual(result.nutrition.carbs, MealFoodCatalog.byID["white_rice_dry"]!.per100g.carbs)
    }
}

extension MealNutritionEngineTests {
    func testBatchRecipeUsesConsumedMassInsteadOfRejectingWholeBatchSize() throws {
        var batch = item("white_rice_dry", grams: 4000)
        batch.consumedFraction = 0.025
        let portion = try MealNutritionEngine.resolve(recognition([batch]))
        XCTAssertEqual(portion.analysis?.items.first?.grams, 100)
        batch.consumedFraction = 1
        XCTAssertThrowsError(try MealNutritionEngine.resolve(recognition([batch])))
    }
}

final class LastMealSuggestionTests: XCTestCase {
    func testRemainingNeverBecomesNegativeWhenAlreadyOverTarget() throws {
        let plan = try XCTUnwrap(LastMealSuggestion.build(goal: .init(protein: 100, carbs: 200, fat: 60),
            consumed: .init(protein: 120, carbs: 220, fat: 70), proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked"))
        XCTAssertEqual(plan.remaining, MealNutrition())
        XCTAssertTrue(plan.portions.isEmpty)
    }
    func testSuggestedPlateUsesFullMacrosAndIsNotAutomaticallyLogged() throws {
        let goal = MealNutrition(protein: 120, carbs: 240, fat: 60)
        let eaten = MealNutrition(protein: 80, carbs: 180, fat: 45)
        let plan = try XCTUnwrap(LastMealSuggestion.build(goal: goal, consumed: eaten, proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked"))
        XCTAssertEqual(plan.remaining, .init(protein: 40, carbs: 60, fat: 15))
        XCTAssertLessThan(abs(plan.nutrition.protein - 40), 6)
        XCTAssertLessThan(abs(plan.nutrition.carbs - 60), 6)
        XCTAssertLessThan(abs(plan.nutrition.fat - 15), 3)
        XCTAssertTrue(plan.nutrition.valid)
        XCTAssertEqual(plan.estimate().nutrition, plan.nutrition)
        XCTAssertEqual(plan.estimate().analysis?.items.count, plan.portions.count)
    }
    func testChangingFoodRecalculatesAmountsFromItsComposition() throws {
        let chicken = try XCTUnwrap(LastMealSuggestion.build(goal: .init(protein: 40, carbs: 60, fat: 20), consumed: .init(), proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked"))
        let tofu = try XCTUnwrap(LastMealSuggestion.build(goal: .init(protein: 40, carbs: 60, fat: 20), consumed: .init(), proteinID: "tofu_firm", starchID: "potato_boiled"))
        XCTAssertNotEqual(chicken.portions.map(\.id), tofu.portions.map(\.id))
        XCTAssertTrue(tofu.portions.contains { $0.food.id == "tofu_firm" })
        XCTAssertLessThanOrEqual(tofu.portions.first { $0.food.id == "tofu_firm" }?.grams ?? 0, 250)
    }
    func testFatGapDoesNotRecommendDrinkingOilAsMeal() throws {
        let plan = try XCTUnwrap(LastMealSuggestion.build(goal: .init(protein: 100, carbs: 200, fat: 60), consumed: .init(protein: 100, carbs: 200, fat: 50), proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked"))
        XCTAssertFalse(plan.portions.count == 1 && plan.portions.first?.food.id == "olive_oil")
        let restricted = try XCTUnwrap(LastMealSuggestion.build(goal: .init(protein: 100, carbs: 200, fat: 60), consumed: .init(protein: 100, carbs: 200, fat: 50), proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked", allowNuts: false))
        XCTAssertFalse(restricted.portions.contains { $0.food.id == "almonds" })
    }
    func testSuggestionEntryStartsAtFiftyAndDisappearsWhenTargetsMet() {
        let goal = MealNutrition(protein: 100, carbs: 200, fat: 60)
        XCTAssertFalse(LastMealSuggestion.shouldOffer(score: 49, goal: goal, consumed: .init(protein: 40, carbs: 80, fat: 24)))
        XCTAssertTrue(LastMealSuggestion.shouldOffer(score: 50, goal: goal, consumed: .init(protein: 50, carbs: 100, fat: 30)))
        XCTAssertFalse(LastMealSuggestion.shouldOffer(score: 100, goal: goal, consumed: goal))
        XCTAssertFalse(LastMealSuggestion.shouldOffer(score: nil, goal: goal, consumed: .init()))
    }
    func testVegetableChoiceUsesItsOwnNutritionAndCanBeOmitted() throws {
        let goal = MealNutrition(protein: 40, carbs: 60, fat: 20)
        let plan = try XCTUnwrap(LastMealSuggestion.build(goal: goal, consumed: .init(), proteinID: "beef_ground_cooked", starchID: "white_rice_cooked", vegetableID: "spinach_boiled"))
        let vegetable = try XCTUnwrap(plan.portions.first { $0.id == "spinach_boiled" })
        XCTAssertEqual(vegetable.title, "Spinach")
        XCTAssertEqual(vegetable.nutrition.protein, vegetable.food.per100g.protein * vegetable.grams / 100, accuracy: 0.001)
        XCTAssertFalse(plan.portions.contains { $0.id == "broccoli_boiled" })
        let without = try XCTUnwrap(LastMealSuggestion.build(goal: goal, consumed: .init(), proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked", includeVegetables: false))
        XCTAssertFalse(without.portions.contains { $0.id == "broccoli_boiled" })
    }
    func testInvalidInputsAndUnknownFoodAreRejected() {
        XCTAssertNil(LastMealSuggestion.build(goal: .init(protein: .nan), consumed: .init(), proteinID: "chicken_breast_cooked", starchID: "white_rice_cooked"))
        XCTAssertNil(LastMealSuggestion.build(goal: .init(protein: 100), consumed: .init(), proteinID: "unknown", starchID: "white_rice_cooked"))
    }
}

final class PerformanceShareSummaryTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ day: Int, hour: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
    func testSingleDayIncludesAllItsRecordsAndDeduplicates() {
        let snapshot = PerformanceCalendarSnapshot(kind: .workout, progress: [date(12, hour: 1): 1, date(12, hour: 18): 1, date(11): 1])
        let result = PerformanceShareSummary.entries(snapshot, start: date(12, hour: 10), end: date(12, hour: 10), calendar: calendar, now: date(13))
        XCTAssertEqual(result, [date(12): 1])
    }
    func testMonthBoundariesAndFutureExcluded() {
        let snapshot = PerformanceCalendarSnapshot(kind: .workout, progress: [date(1): 1, date(13): 1, date(14): 1, date(31): 1])
        let result = PerformanceShareSummary.entries(snapshot, start: date(1), end: date(31), calendar: calendar, now: date(13, hour: 12))
        XCTAssertEqual(Set(result.keys), [date(1), date(13)])
    }
    func testUnknownDaysRemainMissingAndInvalidValuesIgnored() {
        let snapshot = PerformanceCalendarSnapshot(kind: .diet, progress: [date(1): 0.8, date(2): .nan, date(3): -1])
        let result = PerformanceShareSummary.entries(snapshot, start: date(1), end: date(7), calendar: calendar, now: date(13))
        XCTAssertEqual(result, [date(1): 0.8])
    }
    func testInvalidPeriodEmpty() {
        let snapshot = PerformanceCalendarSnapshot(kind: .sleep, progress: [date(12): 1])
        XCTAssertTrue(PerformanceShareSummary.entries(snapshot, start: date(13), end: date(12), calendar: calendar, now: date(13)).isEmpty)
    }
}

final class DailyRecordCalendarTests: XCTestCase {
    private func calendar(firstWeekday: Int = 2, zone: String = "America/Los_Angeles") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = firstWeekday
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func testWeekHonorsUserStartAndCrossesYear() {
        for first in [1, 2, 7] {
            let cal = calendar(firstWeekday: first)
            let days = DailyRecordCalendar.days(date(2026, 1, 1, calendar: cal), monthly: false, calendar: cal)
            XCTAssertEqual(days.count, 7)
            XCTAssertEqual(cal.component(.weekday, from: days[0]), first)
            XCTAssertEqual(Set(days).count, 7)
            XCTAssertTrue(days.contains { cal.component(.year, from: $0) == 2025 })
        }
    }
    func testLeapMonthIncludesEveryDayExactlyOnce() {
        let cal = calendar()
        let days = DailyRecordCalendar.days(date(2024, 2, 15, calendar: cal), monthly: true, calendar: cal)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.filter { cal.component(.month, from: $0) == 2 }.count, 29)
        XCTAssertEqual(Set(days).count, 42)
    }
    func testMonthPageContainsOnlyItsOwnDatesWithCorrectWeekdayColumns() throws {
        for firstWeekday in [1, 2, 7] {
            let cal = calendar(firstWeekday: firstWeekday)
            for (year, month) in [(2024, 2), (2026, 2), (2026, 8), (2026, 12), (2027, 1)] {
                let anchor = date(year, month, 15, calendar: cal)
                let cells = DailyRecordCalendar.cells(anchor, monthly: true, calendar: cal)
                let visible = cells.compactMap { $0 }
                let daysInMonth = try XCTUnwrap(cal.range(of: .day, in: .month, for: anchor))
                XCTAssertEqual(cells.count, 42)
                XCTAssertEqual(visible.count, daysInMonth.count)
                XCTAssertEqual(visible.map { cal.component(.day, from: $0) }, Array(daysInMonth))
                for (index, day) in cells.enumerated() {
                    guard let day else { continue }
                    XCTAssertEqual(cal.component(.month, from: day), month)
                    XCTAssertEqual(cal.component(.year, from: day), year)
                    XCTAssertEqual((cal.component(.weekday, from: day) - firstWeekday + 7) % 7, index % 7)
                }
            }
        }
    }
    func testWeekPageKeepsAdjacentMonthDates() {
        let cal = calendar()
        let anchor = date(2026, 1, 1, calendar: cal)
        XCTAssertEqual(DailyRecordCalendar.cells(anchor, monthly: false, calendar: cal).compactMap { $0 },
                       DailyRecordCalendar.days(anchor, monthly: false, calendar: cal))
    }
    func testMonthNavigationDoesNotSkipShortMonths() {
        let cal = calendar()
        let feb = DailyRecordCalendar.shifted(date(2026, 1, 31, calendar: cal), by: 1, monthly: true, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: feb), 2)
        XCTAssertEqual(cal.component(.day, from: feb), 1)
        let march = DailyRecordCalendar.shifted(feb, by: 1, monthly: true, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: march), 3)
    }
    func testDSTUsesSevenCalendarDaysNotFixedSeconds() {
        let cal = calendar(firstWeekday: 1)
        let days = DailyRecordCalendar.days(date(2026, 3, 8, calendar: cal), monthly: false, calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { cal.component(.hour, from: $0) == 0 })
        XCTAssertEqual(days[1].timeIntervalSince(days[0]), 23 * 3600)
    }
    func testRecoveryCalendarUsesActualWorkoutsAndStopsAfterTwoDays() {
        let cal = calendar()
        let first = date(2026, 3, 7, calendar: cal)
        let second = date(2026, 3, 10, calendar: cal)
        let snapshot = PerformanceCalendarSnapshot.workout([first, second], calendar: cal)
        let now = date(2026, 3, 15, calendar: cal)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: first))! }
        XCTAssertNil(snapshot.recoveryFraction(on: day(0), calendar: cal, now: now))
        XCTAssertEqual(snapshot.recoveryFraction(on: day(1), calendar: cal, now: now), 0.6)
        XCTAssertEqual(snapshot.recoveryFraction(on: day(2), calendar: cal, now: now), 0.3)
        XCTAssertNil(snapshot.recoveryFraction(on: day(3), calendar: cal, now: now))
        XCTAssertEqual(snapshot.recoveryFraction(on: day(4), calendar: cal, now: now), 0.6)
        XCTAssertNil(snapshot.recoveryFraction(on: day(6), calendar: cal, now: now))
        XCTAssertNil(snapshot.recoveryFraction(on: day(4), calendar: cal, now: first))
        XCTAssertNil(snapshot.progress[day(1)])
    }

    func testWorkoutCalendarDoesNotColorUnloggedRecoveryDays() {
        let cal = calendar()
        let logged = date(2026, 3, 8, calendar: cal)
        let snapshot = PerformanceCalendarSnapshot.workout([logged], calendar: cal)
        XCTAssertEqual(snapshot.progress[cal.startOfDay(for: logged)], 1)
        XCTAssertNil(snapshot.progress[cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: logged))!])
    }
}

@MainActor
final class DailyRecordLayoutTests: XCTestCase {
    func testHomeCalendarFitsPhoneWidth() throws {
        let data = DataStore.makeMock()
        data.settings.dietEnabled = true
        data.settings.sleepEnabled = true
        for locale in ["en", "zh-Hans", "de", "ar"] {
            let content = DailyOverviewCard(onReplay: { _ in })
                .environment(data).environment(\.locale, Locale(identifier: locale))
                .environment(\.layoutDirection, locale == "ar" ? .rightToLeft : .leftToRight)
                .environment(\.colorScheme, .dark)
                .frame(width: 362).padding(20).background(MasoColor.background)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 402, accuracy: 1)
            // This card now includes the restored 64pt Workout value. Its natural
            // height is not capped; the actual Home scroll view is tested separately.
            XCTAssertTrue(image.size.height.isFinite)
            XCTAssertGreaterThan(image.size.height, 0)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Daily calendar \(locale)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("daily-calendar-\(locale).png"))
        }
    }
}

@MainActor
final class DailyRecordAggregationTests: XCTestCase {
    func testCompleteDailyRecordsPreserveDeletedPlanAndExcludeFutureSets() throws {
        let data = DataStore.makeMock()
        let now = Date()
        let earlier = now.addingTimeInterval(-120)
        let exercise = try XCTUnwrap(data.exById.values.first)
        func set(_ id: String, at date: Date, plan: String?) -> SetRecord {
            .init(id: id, exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category,
                  weight: 30, reps: 10, duration: nil, performedAt: date, planId: plan, planName: "Deleted workout")
        }
        data.sets = [set("past", at: earlier, plan: "removed"), set("free", at: earlier, plan: nil),
                     set("future", at: now.addingTimeInterval(3600), plan: "removed")]
        let sessions = data.recordedWorkoutSessions(on: earlier)
        XCTAssertEqual(sessions.count, 2)
        let saved = try XCTUnwrap(sessions.first { $0.planId == "removed" })
        XCTAssertEqual(saved.planName, "Deleted workout")
        XCTAssertEqual(saved.setCount, 1)
        XCTAssertEqual(data.recordedSets(for: saved).map(\.id), ["past"])
        XCTAssertEqual(data.recordedExerciseStats(for: saved).first?.setCount, 1)
        XCTAssertEqual(data.dailyRecordSnapshots().first?.progress.count, 1)
    }

    func testIdentifiedAndLegacySetsStaySeparateAndDeleteOneCard() throws {
        let data = DataStore.makeMock()
        let day = data.settings.calendar.startOfDay(for: Date().addingTimeInterval(-3600))
        let when = day.addingTimeInterval(10 * 3600)
        let exercise = try XCTUnwrap(data.exById.values.first)
        func set(_ id: String, session: String?) -> SetRecord {
            var record = SetRecord(id: id, exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category,
                                   weight: 20, reps: 8, duration: nil, performedAt: when, planId: "same-plan")
            record.workoutSessionID = session
            return record
        }
        data.sets = [set("legacy", session: nil), set("blank", session: ""), set("one", session: "session-1"), set("two", session: "session-2")]
        let sessions = data.recordedWorkoutSessions(on: when)
        XCTAssertEqual(sessions.count, 3)
        let legacy = try XCTUnwrap(sessions.first { $0.workoutSessionID == nil })
        XCTAssertEqual(Set(data.recordedSets(for: legacy).map(\.id)), ["legacy", "blank"])
        let first = try XCTUnwrap(sessions.first { $0.workoutSessionID == "session-1" })
        XCTAssertEqual(data.recordedSets(for: first).map(\.id), ["one"])
        data.deleteRecordedSession(first)
        XCTAssertEqual(Set(data.sets.map(\.id)), ["legacy", "blank", "two"])
        let remaining = data.recordedWorkoutSessions(on: when)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(remaining.contains { $0.workoutSessionID == "session-1" })
    }
}

@MainActor
final class DailyCalendarPagingTests: XCTestCase {
    func testNativePagerStartsOnCurrentPeriodAndMovesContinuously() async throws {
        let data = DataStore.makeMock()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let content = NavigationStack {
            ScrollView { DailyOverviewCard(onReplay: { _ in }).padding(20) }
        }.environment(data).environment(\.layoutDirection, .leftToRight)
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; oldKey?.makeKeyAndVisible() }
        func horizontalPager(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width * 2 { return scroll }
            return view.subviews.lazy.compactMap { horizontalPager(in: $0) }.first
        }
        var pager: UIScrollView?
        for _ in 0..<20 {
            window.layoutIfNeeded()
            pager = horizontalPager(in: window)
            if pager != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let scroll = try XCTUnwrap(pager)
        try await Task.sleep(for: .milliseconds(200))
        let start = scroll.contentOffset.x
        let last = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
        XCTAssertEqual(start, last, accuracy: 2, "Initial page must be the current week, not the oldest loaded week")
        let preview = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: preview)
        attachment.name = "Native calendar in navigation and vertical scroll context"
        attachment.lifetime = .keepAlways
        add(attachment)
        try preview.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("native-calendar-context.png"))
        let target = start - scroll.bounds.width
        scroll.setContentOffset(CGPoint(x: target, y: scroll.contentOffset.y), animated: true)
        try await Task.sleep(for: .milliseconds(60))
        let intermediate = scroll.contentOffset.x
        XCTAssertLessThan(intermediate, start - 1)
        XCTAssertGreaterThan(intermediate, target + 1, "Calendar must expose intermediate positions, not flash to the next period")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(scroll.contentOffset.x, target, accuracy: 2)
    }
}

@MainActor
final class DailyRecordSnapshotTests: XCTestCase {
    func testCompleteDayShareExportsWorkoutMacrosAndSleepSummary() throws {
        let data = DataStore.makeMock()
        let day = data.settings.calendar.startOfDay(for: Date().addingTimeInterval(-86400 * 3))
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        let exercises = Array(data.exById.values.sorted { $0.id < $1.id }.prefix(6))
        data.sets = exercises.enumerated().map { index, exercise in
            SetRecord(id: "share-\(index)", exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category,
                      weight: 30, reps: 10, performedAt: day.addingTimeInterval(3600 + Double(index) * 60), planId: "historic", planName: "Recorded workout")
        }
        data.settings.wellnessGoals = [key: DailyWellnessGoal(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a"])]
        data.settings.mealCheckIns = [MealCheckIn(day: day, mealID: "a", title: "Meal 1", photoFilename: "", foods: "Chicken and rice",
                                               nutrition: MealNutrition(protein: 130, carbs: 220, fat: 65), confirmedAt: day.addingTimeInterval(12 * 3600))]
        data.settings.sleepRecords = [key: 448]
        let image = try XCTUnwrap(ShareImageRenderer.render { DailyRecordShareCard(day: day).environment(data).environment(TrainingSessionStore()) })
        let export = FullPageExport(items: [image])
        XCTAssertEqual(export.items.count, 1)
        XCTAssertTrue(export.items[0] is UIImage)
        XCTAssertFalse(export.items.contains { $0 is URL })
        XCTAssertGreaterThan(image.size.height, 700)
        let attachment = XCTAttachment(image: image); attachment.name = "Full daily record export"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("daily-record-full-share.png"))
        // A real stage timeline must remain visible when exported; no interactive details row.
        let graph = try XCTUnwrap(ShareImageRenderer.render {
            VStack(spacing: 20) {
                SleepTargetSummaryContent(targetMinutes: 480, actualMinutes: 448, actualLabel: "Total sleep", exportStyle: true)
                SleepNightChart(day: day, intervals: [
                    .init(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: day.addingTimeInterval(-8 * 3600), end: day.addingTimeInterval(-6 * 3600)),
                    .init(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start: day.addingTimeInterval(-6 * 3600), end: day.addingTimeInterval(-5 * 3600)),
                    .init(value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: day.addingTimeInterval(-5 * 3600), end: day.addingTimeInterval(-4 * 3600)),
                    .init(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: day.addingTimeInterval(-4 * 3600), end: day.addingTimeInterval(-3600))
                ], minutes: 448, embedded: true, usesSavedTargetOnly: true, showsStandaloneSummary: false, showsDetailsControl: false)
            }.padding(20).environment(data).environment(\.colorScheme, .dark)
        })
        try graph.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("daily-record-sleep-chart-export.png"))
    }

    func testDailyImageOpensNativeActivitySheetRepeatedly() async throws {
        let data = DataStore.makeMock()
        let image = try XCTUnwrap(ShareImageRenderer.render {
            DailyRecordShareCard(day: Date()).environment(data).environment(TrainingSessionStore())
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Color.black)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(350))
        for _ in 0..<2 {
            let activity = UIActivityViewController(activityItems: FullPageExport(items: [image]).items, applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = host.view
            activity.popoverPresentationController?.sourceRect = CGRect(x: 20, y: 20, width: 24, height: 24)
            await withCheckedContinuation { continuation in
                host.present(activity, animated: false) { continuation.resume() }
            }
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(host.presentedViewController === activity)
            XCTAssertFalse(activity.view.subviews.isEmpty)
            await withCheckedContinuation { continuation in
                host.dismiss(animated: false) { continuation.resume() }
            }
        }
    }

    func testHistoricalWorkoutIgnoresLaterPlanEditsAndKeepsMissingExercises() throws {
        let data = DataStore.makeMock()
        let day = data.settings.calendar.date(byAdding: .day, value: -3, to: Date())!
        let exercise = try XCTUnwrap(data.exById.values.first)
        data.plans = [Plan(id: "changed", name: "Renamed plan", steps: [], createdAt: day, updatedAt: Date())]
        data.sets = [
            SetRecord(id: "known", exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category,
                      weight: 35, reps: 10, performedAt: day, planId: "changed", planName: "Original training"),
            SetRecord(id: "missing", exerciseId: "removed-exercise", exerciseName: "Recorded exercise", category: .strength,
                      weight: 25, reps: 12, performedAt: day.addingTimeInterval(60), planId: "changed", planName: "Original training")
        ]
        let session = try XCTUnwrap(data.recordedWorkoutSessions(on: day).first)
        let recorded = try XCTUnwrap(data.recordedWorkoutPlan(for: session))
        XCTAssertEqual(recorded.name, "Original training")
        XCTAssertEqual(recorded.steps.map(\.exerciseId), [exercise.id, "removed-exercise"])
        XCTAssertEqual(recorded.steps.reduce(0) { $0 + $1.sets }, 2)
        XCTAssertEqual(data.recordedWorkoutLibrary(for: session)["removed-exercise"]?.name, "Recorded exercise")
        XCTAssertTrue(data.plans[0].steps.isEmpty)
    }
    func testMissingHistoricalTargetsNeverUseCurrentPreferences() {
        let data = DataStore.makeMock()
        let day = data.settings.calendar.date(byAdding: .day, value: -20, to: Date())!
        data.settings.wellnessGoals = [:]
        var sleep = SleepPreferences()
        sleep.durationTargetMinutes = 510
        data.settings.sleepPreferences = sleep
        XCTAssertNil(data.savedWellnessGoal(on: day))
        XCTAssertNil(data.savedSleepTarget(on: day))
        data.settings.sleepRecords = [SleepPreferences.dayKey(day, calendar: data.settings.calendar): 450]
        XCTAssertTrue(data.dailyRecordSnapshots(usesSavedTargetOnly: true).first { $0.kind == .sleep }!.progress.isEmpty)
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.wellnessGoals = [key: DailyWellnessGoal(protein: 120, carbsMinimum: 210, fatMinimum: 60, sleepMinutes: 480, mealIDs: [])]
        XCTAssertEqual(data.savedWellnessGoal(on: day)?.protein, 120)
        XCTAssertEqual(data.savedSleepTarget(on: day), 480)
        sleep.recordedGoals[key] = 450
        data.settings.sleepPreferences = sleep
        XCTAssertEqual(data.savedSleepTarget(on: day), 450)
    }
    func testWorkoutInsightsNativePageLayout() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        let now = Date()
        let exercise = try XCTUnwrap(data.exById["bench_press_barbell"])
        data.sets = [0, -1, -2, -3, -4, -20].enumerated().map { index, offset in
            let date = data.settings.calendar.date(byAdding: .day, value: offset, to: now)!.addingTimeInterval(-60)
            return SetRecord(id: "insights-history-\(index)", exerciseId: exercise.id, exerciseName: exercise.name,
                             category: .strength, weight: 40, reps: 8, performedAt: date,
                             planId: "insights-plan-\(index)", planName: "Workout \(index + 1)")
        }
        let window = UIWindow(windowScene: scene)
        let oldLanguage = LanguageManager.shared.selectedLanguage
        defer { window.isHidden = true; previous?.makeKeyAndVisible(); LanguageManager.shared.selectedLanguage = oldLanguage }
        let comparisonRecords = data.sets
        let cases: [(SupportedLanguage, String)] = [(.en, "empty"), (.en, "baseline"), (.en, "comparison"),
                                                   (.zhHans, "empty"), (.zhHans, "baseline"), (.de, "empty"),
                                                   (.ar, "empty"), (.ar, "baseline")]
        for (language, scenario) in cases {
            data.sets = scenario == "empty" ? [] : scenario == "baseline" ? Array(comparisonRecords.prefix(1)) : comparisonRecords
            LanguageManager.shared.selectedLanguage = language
            let state = HistoryNavigationTestState()
            window.rootViewController = UIHostingController(rootView: HistoryNavigationTestFixture(state: state)
                .environment(data).environment(SubscriptionManager()).environment(TrainingSessionStore())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            state.path = [6]
            try await Task.sleep(for: .milliseconds(1200))
            window.layoutIfNeeded()
            func scroll(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 10 { return scroll }
                return view.subviews.lazy.compactMap { scroll($0) }.first
            }
            for position in ["top", "bottom"] {
                if position == "bottom", let scrolling = scroll(window) {
                    scrolling.setContentOffset(CGPoint(x: 0, y: max(-scrolling.adjustedContentInset.top,
                        scrolling.contentSize.height - scrolling.bounds.height + scrolling.adjustedContentInset.bottom)), animated: false)
                    try await Task.sleep(for: .milliseconds(200))
                }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let name = "insights-progress-\(scenario)-\(language.rawValue)-\(position)"
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
            }
        }
    }

    func testActualFirstDietAndCombinedSleepPages() async throws {
        let data = DataStore.makeMock()
        let day = data.settings.calendar.startOfDay(for: Date())
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.sleepStageRecords = Dictionary(uniqueKeysWithValues: (0...3).map { offset in
            let date = data.settings.calendar.date(byAdding: .day, value: -offset, to: day)!
            return (SleepPreferences.dayKey(date, calendar: data.settings.calendar), SleepStagesRecord(deep: offset == 0 ? 45 : 60, rem: 90, core: 300))
        })
        data.settings.wellnessGoals = [key: .init(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 510, mealIDs: ["a"])]
        var preferences = SleepPreferences()
        preferences.durationTargetMinutes = 600
        preferences.recordedGoals[key] = 510
        preferences.healthConnected = false
        data.settings.sleepPreferences = preferences
        data.settings.sleepRecords = [key: 448]
        data.settings.mealCheckIns = [.init(day: day, mealID: "a", title: "Meal", photoFilename: "", foods: "Rice and chicken",
            nutrition: .init(protein: 145, carbs: 230, fat: 75), confirmedAt: Date())]
        XCTAssertEqual(data.savedSleepTarget(on: day), 510)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        for name in ["diet", "sleep", "sleep-chart", "sleep-empty"] {
            if name == "sleep-empty" { data.settings.sleepRecords = [:] }
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                if name == "diet" { DietScreen() }
                else if name == "sleep-chart" {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SleepTargetSummaryContent(targetMinutes: 510, actualMinutes: 448)
                            Divider()
                            SleepNightChart(day: day, intervals: [
                                .init(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: day.addingTimeInterval(-8 * 3600), end: day.addingTimeInterval(-6 * 3600)),
                                .init(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start: day.addingTimeInterval(-6 * 3600), end: day.addingTimeInterval(-5 * 3600)),
                                .init(value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: day.addingTimeInterval(-5 * 3600), end: day.addingTimeInterval(-4 * 3600)),
                                .init(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: day.addingTimeInterval(-4 * 3600), end: day.addingTimeInterval(-3600))
                            ], minutes: 448, embedded: true, usesSavedTargetOnly: true, showsStandaloneSummary: false)
                        }.contentCardChrome().padding(MasoMetrics.pagePaddingHorizontal)
                    }.navigationTitle("Sleep")
                } else { SleepScreen() }
            }.environment(data).preferredColorScheme(.dark))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Actual-first \(name)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("actual-first-\(name).png"))
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
    }

    func testDailyRecordPageRendersInNativeNavigationWithInlineRecords() async throws {
        let data = DataStore.makeMock()
        let day = data.settings.calendar.startOfDay(for: Date().addingTimeInterval(-86400 * 3))
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        let exercise = try XCTUnwrap(data.exById.values.first)
        data.sets = [SetRecord(id: "day-record", exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category,
                              weight: 30, reps: 10, performedAt: day.addingTimeInterval(3600), planId: "historic", planName: "Recorded workout")]
        data.settings.wellnessGoals = [key: DailyWellnessGoal(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a", "b"])]
        data.settings.mealCheckIns = [
            MealCheckIn(day: day, mealID: "a", title: "Meal 1", photoFilename: "", foods: "Rice and chicken",
                        nutrition: MealNutrition(protein: 55, carbs: 80, fat: 20), confirmedAt: day.addingTimeInterval(3600 * 12)),
            MealCheckIn(day: day, mealID: "b", title: "Meal 2", photoFilename: "", foods: "Beef and vegetables",
                        nutrition: MealNutrition(protein: 50, carbs: 70, fat: 25), confirmedAt: day.addingTimeInterval(3600 * 18))
        ]
        data.settings.sleepRecords = [key: 450]
        data.settings.externalWorkouts = [.init(id: "health-walk", activity: .walking,
            startedAt: day.addingTimeInterval(3600 * 9), endedAt: day.addingTimeInterval(3600 * 9 + 1800),
            duration: 1800, distanceMeters: 2500, kilocalories: 110,
            sourceBundleID: "com.apple.health", sourceName: "Apple Watch")]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DailyRecordSheet(day: day, onReplay: { _ in })
            .environment(data).environment(TrainingSessionStore()).environment(\.colorScheme, .dark))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; oldKey?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        func verticalScroll(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 100 { return scroll }
            return view.subviews.lazy.compactMap { verticalScroll(in: $0) }.first
        }
        let scroll = try XCTUnwrap(verticalScroll(in: window))
        for (name, offset) in [("top", -Double(scroll.adjustedContentInset.top)), ("diet", 500.0), ("sleep", Double(scroll.contentSize.height - scroll.bounds.height))] {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try await Task.sleep(for: .milliseconds(80))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Daily records \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("daily-records-\(name).png"))
        }
    }
}


@MainActor
final class QARegressionTests: XCTestCase {
    func testLocalizedSleepPageKeepsNativeUnitsAndTargetsVisible() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let originalLanguage = LanguageManager.shared.selectedLanguage
        let data = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let calendar = data.settings.calendar
        let day = calendar.startOfDay(for: Date())
        let key = SleepPreferences.dayKey(day, calendar: calendar)
        var preferences = SleepPreferences(); preferences.healthConnected = false
        preferences.recordedGoals[key] = 510
        data.settings.sleepPreferences = preferences
        data.settings.sleepRecords = [key: 448]
        data.settings.sleepStageRecords = Dictionary(uniqueKeysWithValues: (0...9).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: day)!
            return (SleepPreferences.dayKey(date, calendar: calendar), SleepStagesRecord(deep: 45, rem: 90, core: 313))
        })
        defer { previous?.makeKeyAndVisible(); LanguageManager.shared.selectedLanguage = originalLanguage }
        for language in [SupportedLanguage.en, .zhHans, .de, .ar] {
            LanguageManager.shared.selectedLanguage = language
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: AppNavigationStack { SleepScreen() }
                .environment(data).environment(\.locale, LanguageManager.currentLocale)
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let name = "qa-sleep-native-\(language.rawValue)"
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
            window.isHidden = true
        }
    }

    func testSleepDetailReferencesUseSelectedNightAndPreviousFourteenDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: .init(year: 2026, month: 10, day: 16))!
        var records: [Date: SleepStagesRecord] = [:]
        for offset in 1...7 {
            let date = calendar.date(byAdding: .day, value: -offset, to: day)!
            records[date] = .init(deep: Double(40 + offset), rem: Double(80 + offset), core: 300)
        }
        records[day] = .init(deep: 999, rem: 999, core: 300)
        records[calendar.date(byAdding: .day, value: 1, to: day)!] = .init(deep: 999, rem: 999, core: 300)
        records[calendar.date(byAdding: .day, value: -15, to: day)!] = .init(deep: 999, rem: 999, core: 300)
        let deep = SleepStagesRecord.priorValues(on: day, calendar: calendar, records: records, stage: \.deep)
        let rem = SleepStagesRecord.priorValues(on: day, calendar: calendar, records: records, stage: \.rem)
        XCTAssertEqual(deep.sorted(), (41...47).map(Double.init))
        XCTAssertEqual(rem.sorted(), (81...87).map(Double.init))
        XCTAssertEqual(SleepStagesRecord.reference(deep), 42...45)
        XCTAssertEqual(SleepStagesRecord.deepReference(on: day, calendar: calendar, records: records), 44)
        XCTAssertNil(SleepStagesRecord.reference(Array(deep.prefix(6))))
    }

    func testEmptyHealthReadDoesNotEraseSavedSleepHistoryOrGoals() {
        let data = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let day = data.settings.calendar.startOfDay(for: Date())
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.sleepRecords = [key: 448]
        data.settings.sleepStageRecords = [key: .init(deep: 45, rem: 80, core: 323)]
        data.settings.sleepPreferences = SleepPreferences()
        data.settings.sleepPreferences?.recordedGoals[key] = 480
        data.applySleepSummary(minutes: [:], stages: [:])
        XCTAssertEqual(data.settings.sleepRecords?[key], 448)
        XCTAssertEqual(data.settings.sleepStageRecords?[key]?.deep, 45)
        XCTAssertEqual(data.savedSleepTarget(on: day), 480)
        data.applySleepSummary(minutes: [day: .nan], stages: [:])
        XCTAssertEqual(data.settings.sleepRecords?[key], 448)
        data.applySleepSummary(minutes: [day: 450], stages: [day: .init(deep: 50, rem: 90, core: 310)])
        XCTAssertEqual(data.settings.sleepRecords?[key], 450)
        XCTAssertEqual(data.settings.sleepStageRecords?[key]?.deep, 50)
        XCTAssertEqual(data.savedSleepTarget(on: day), 480)
    }

    func testSleepDurationUsesNativeUnitsInAllLanguagesAndRejectsInvalidInput() {
        for language in SupportedLanguage.allCases {
            let locale = Locale(identifier: language.rawValue)
            let formatter = DateComponentsFormatter()
            var calendar = Calendar(identifier: .gregorian); calendar.locale = locale
            formatter.calendar = calendar; formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated; formatter.zeroFormattingBehavior = .dropAll
            XCTAssertEqual(MassoDurationFormatter.sleep(449, locale: locale), formatter.string(from: 449 * 60))
            formatter.allowedUnits = [.minute]
            XCTAssertEqual(MassoDurationFormatter.sleep(28, locale: locale), formatter.string(from: 28 * 60))
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
            XCTAssertEqual(MassoDurationFormatter.sleep(invalid, locale: Locale(identifier: "en")), "—")
        }
    }

    func testUnreadableAndNewerSnapshotsAreArchivedBeforeFreshDataCanReplaceThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let current = data.currentSnapshot()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let newer = PersistenceController.Snapshot(version: PersistenceController.schemaVersion + 1,
            plans: [], sets: [], settings: UserSettings(), updatedAt: Date())
        for original in [Data("unreadable snapshot".utf8), try encoder.encode(newer)] {
            let url = directory.appendingPathComponent("maso-data.json")
            try original.write(to: url)
            let persistence = PersistenceController(storageURL: url)
            XCTAssertNil(persistence.load())
            XCTAssertEqual(try Data(contentsOf: url), original, "Reading must not mutate the original")
            XCTAssertTrue(persistence.save(current))
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("maso-data-recovery-") }
            XCTAssertTrue(try backups.contains { try Data(contentsOf: $0) == original })
            let count = backups.count
            XCTAssertTrue(persistence.save(current))
            XCTAssertNotNil(persistence.load())
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, count + 1)
        }
    }

    func testFailedRecoveryCopyNeverOverwritesTheOnlyOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("maso-data.json")
        let original = Data("original unreadable data".utf8)
        try original.write(to: url)
        let persistence = PersistenceController(storageURL: url)
        XCTAssertNil(persistence.load())
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let data = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        XCTAssertFalse(persistence.save(data.currentSnapshot()))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}

final class NumericFractionTests: XCTestCase {
    func testRecognizesLocalizedNumericMetricsWithoutChangingSpacing() throws {
        for (input, numerator, denominator, separator) in [
            ("1/2", "1", "2", "/"),
            ("49.5 / 120", "49.5", "120", " / "),
            ("1.234,5 / 2.000", "1.234,5", "2.000", " / "),
            ("١٢٫٥ / ١٢٠", "١٢٫٥", "١٢٠", " / "),
            ("1\u{202f}234 / 2\u{202f}000", "1\u{202f}234", "2\u{202f}000", " / ")
        ] {
            let parts = try XCTUnwrap(NumericFractionParts(value: input))
            XCTAssertEqual(parts.numerator, numerator)
            XCTAssertEqual(parts.denominator, denominator)
            XCTAssertEqual(parts.separator, separator)
        }
    }

    func testProseUnitsDatesAndMissingValuesRemainUnparsed() {
        for input in ["Training: 1 / 2", "1/2 lifts improving", "STEP 1 / 2", "120 g / day", "g/day", "7h28m/8h30m", "10/13/2026", "—/100", "1/", "/2", "100"] {
            XCTAssertNil(NumericFractionParts(value: input), input)
        }
    }
}

@MainActor
final class HomeCompositionSnapshotTests: XCTestCase {
    func testHomeCompositionInNativeNavigationAndFooterStates() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        for state in ["ready", "volume", "gain", "active", "empty"] {
            let data = DataStore.makeMock()
            data.aiTodayPlanEditedAt = Date() // Keep this local layout check off the generation service.
            data.settings.dietEnabled = true
            data.settings.sleepEnabled = true
            if state == "volume" || state == "gain" {
                let day = data.settings.calendar.startOfDay(for: Date())
                let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
                data.settings.wellnessGoals = [key: .init(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 510, mealIDs: ["home-meal"])]
                data.settings.sleepRecords = [key: 420]
                data.settings.mealCheckIns = [.init(day: day, mealID: "home-meal", title: "Meal", photoFilename: "", foods: "Chicken and rice",
                    nutrition: .init(protein: state == "gain" ? 150 : 100, carbs: 220, fat: 70), confirmedAt: Date())]
            }
            let training = TrainingSessionStore()
            if state == "volume" {
                let groups: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .arms, .core]
                data.sets = []
                for (index, group) in groups.enumerated() {
                    let exercise = try XCTUnwrap(data.exById.values.first { $0.primaryMuscles.contains { $0.section == group } })
                    data.sets += (0..<(6-index)).map { setIndex in
                        SetRecord(id: "volume-\(index)-\(setIndex)", exerciseId: exercise.id, exerciseName: exercise.name,
                                  category: .strength, weight: 20, reps: 8, performedAt: Date().addingTimeInterval(-60))
                    }
                }
            }
            if state == "gain" {
                let exercise = try XCTUnwrap(data.exById["bench_press_barbell"])
                data.sets = [
                    SetRecord(id: "gain-before", exerciseId: exercise.id, exerciseName: exercise.name, category: .strength,
                              weight: 50, reps: 8, performedAt: Date().addingTimeInterval(-8 * 86400)),
                    SetRecord(id: "gain-now", exerciseId: exercise.id, exerciseName: exercise.name, category: .strength,
                              weight: 52.5, reps: 8, performedAt: Date().addingTimeInterval(-60))
                ]
            }
            if state == "empty" { data.plans = []; data.aiTodayPlan = nil }
            if state == "active", let plan = data.todayRecommendedPlan {
                training.start(planId: plan.id, plan: plan,
                               segments: expandPlan(plan, exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                                                    defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds))
            }
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIHostingController(rootView: RootView().environment(data).environment(training).environment(\.colorScheme, .dark))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            func verticalScroll(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 100 { return scroll }
                return view.subviews.lazy.compactMap { verticalScroll(in: $0) }.first
            }
            let scroll = try XCTUnwrap(verticalScroll(in: window))
            for position in ["top", "workouts"] {
                let offset = position == "top" ? -scroll.adjustedContentInset.top : scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                try await Task.sleep(for: .milliseconds(120))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Home \(state) \(position)"; attachment.lifetime = .keepAlways; add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("home-composition-\(state)-\(position).png"))
            }
            window.isHidden = true
            oldKey?.makeKeyAndVisible()
        }
    }
    func testActiveTrainingFooterAcrossNativeDestinations() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        data.aiTodayPlanEditedAt = Date()
        let training = TrainingSessionStore()
        let plan = try XCTUnwrap(data.todayRecommendedPlan)
        training.start(planId: plan.id, plan: plan,
                       segments: expandPlan(plan, exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                                            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds))
        if training.session?.playing == true { training.togglePlay() }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: RootView().environment(data).environment(training).environment(SubscriptionManager()).environment(\.colorScheme, .dark))
        window.makeKeyAndVisible()
        defer { training.end(); AppRouter.shared.requestedDestination = nil; window.isHidden = true; oldKey?.makeKeyAndVisible() }
        let destinations: [(String, AppDestination)] = [
            ("home", .today), ("coach", .coach), ("workout", .history), ("insights", .insights),
            ("diet", .diet), ("sleep", .sleep), ("exercises", .exerciseLibrary),
            ("classics", .classicRoutines), ("settings", .settings), ("muscles", .muscleStatus), ("return-home", .today)
        ]
        try await Task.sleep(for: .milliseconds(800))
        for (name, destination) in destinations {
            AppRouter.shared.requestedDestination = destination
            try await Task.sleep(for: .milliseconds(800))
            window.layoutIfNeeded()
            XCTAssertNil(AppRouter.shared.requestedDestination)
            XCTAssertEqual(training.session?.planId, plan.id)
            XCTAssertEqual(training.session?.completed, false)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Active training — \(name)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("minibar-\(name).png"))
        }
    }


    func testWorkoutDetailInLargeSheetWithScrollableExercises() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let oldLayout = UserDefaults.standard.object(forKey: "planStepCardLayout")
        defer { UserDefaults.standard.set(oldLayout, forKey: "planStepCardLayout"); oldKey?.makeKeyAndVisible() }
        let data = DataStore.makeMock()
        var initial = try XCTUnwrap(data.plans.first)
        let sourceSteps = initial.steps
        initial.steps = (0..<12).map { index in
            let step = sourceSteps[index % sourceSteps.count]
            return PlanStep(id: "detail-\(index)", exerciseId: step.exerciseId, sets: 3, reps: 8)
        }
        for layout in [false, true] {
            UserDefaults.standard.set(layout, forKey: "planStepCardLayout")
            let window = UIWindow(windowScene: scene)
            let presenter = UIViewController()
            window.rootViewController = presenter
            window.makeKeyAndVisible()
            let detail = UIHostingController(rootView: PlanDetailSheet(initialPlan: initial, onStart: { _ in })
                .environment(data).environment(SubscriptionManager()).preferredColorScheme(.dark))
            detail.modalPresentationStyle = .pageSheet
            detail.sheetPresentationController?.detents = [.large()]
            detail.sheetPresentationController?.prefersGrabberVisible = true
            presenter.present(detail, animated: false)
            try await Task.sleep(for: .milliseconds(1000))
            window.layoutIfNeeded()
            func scrollView(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 50 { return scroll }
                return view.subviews.lazy.compactMap { scrollView($0) }.first
            }
            let scroll = try XCTUnwrap(scrollView(window))
            for position in ["top", "bottom"] {
                let offset = position == "top" ? -scroll.adjustedContentInset.top : scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                try await Task.sleep(for: .milliseconds(200))
                if position == "bottom" {
                    // Native Form resolves estimated row heights as the rows become visible.
                    for _ in 0..<3 {
                        window.layoutIfNeeded()
                        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom), animated: false)
                        try await Task.sleep(for: .milliseconds(200))
                    }
                }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let name = "workout-detail-\(layout ? "grid" : "list")-\(position)"
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
            }
            detail.dismiss(animated: false)
            window.isHidden = true
        }
    }


    func testCreateWorkoutKeepsDraftOutOfLibraryInNativeSheet() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        let savedPlans = data.plans
        let template = try XCTUnwrap(savedPlans.first)
        for ready in [false, true] {
            let now = Date()
            let draft = Plan(id: "unsaved-\(UUID().uuidString)", name: ready ? "Upper body" : "", steps: ready ? template.steps : [], createdAt: now, updatedAt: now)
            let window = UIWindow(windowScene: scene)
            let presenter = UIViewController()
            window.rootViewController = presenter
            window.makeKeyAndVisible()
            defer { window.isHidden = true; oldKey?.makeKeyAndVisible() }
            let detail = UIHostingController(rootView: PlanDetailSheet(initialPlan: draft, isCreating: true, onStart: { _ in XCTFail("Creation must not start training") })
                .environment(data).environment(SubscriptionManager()).preferredColorScheme(.dark))
            detail.modalPresentationStyle = .pageSheet
            detail.sheetPresentationController?.detents = [.large()]
            detail.sheetPresentationController?.prefersGrabberVisible = true
            presenter.present(detail, animated: false)
            try await Task.sleep(for: .milliseconds(700))
            window.layoutIfNeeded()
            XCTAssertEqual(data.plans, savedPlans, "Opening creation must not persist a draft")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let name = "create-workout-\(ready ? "ready" : "empty")"
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
            detail.dismiss(animated: false)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(data.plans, savedPlans, "Cancelling creation must leave saved workouts unchanged")
        }
    }

}

@MainActor
final class ExternalWorkoutImportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func record(_ id: String = "walk", dayOffset: Int = -1, source: String = "com.apple.health", duration: Double = 1800) -> ExternalWorkout {
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: dayOffset, to: now)!
        return .init(id: id, activity: .walking, startedAt: start, endedAt: start.addingTimeInterval(1800), duration: duration,
                     distanceMeters: nil, kilocalories: nil, sourceBundleID: source, sourceName: "Apple Watch")
    }
    func testNormalizationRejectsOwnExportsFutureInvalidAndDuplicateRecords() {
        let walk = record()
        let records = ExternalWorkout.normalized([walk, walk, record("watch", source: "com.yumowu.maso.watchkitapp"),
            record("phone", source: "com.yumowu.maso"), record("future", dayOffset: 1), record("invalid", duration: .nan)], now: now)
        XCTAssertEqual(records, [walk])
        XCTAssertNil(records.first?.distanceMeters)
        XCTAssertNil(records.first?.kilocalories)
    }
    func testExternalAndLocalActivityCountOneDayWithoutAdvancingPlansOrStrength() throws {
        let data = DataStore.makeMock()
        data.settings.externalWorkoutImportEnabled = true
        data.settings.workoutCompletions = []
        let originalPlans = data.plans.map(\.id)
        let next = data.todayRecommendedPlan?.id
        let walk = record()
        let cycle = record("cycle")
        let exercise = try XCTUnwrap(data.exercises.first)
        data.sets = [.init(id: "local", exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category, weight: 20, reps: 10,
                           performedAt: walk.startedAt, planId: nil)]
        data.replaceExternalWorkoutSnapshot([walk, cycle], now: now)
        XCTAssertEqual(data.recordedWorkoutDates(now: now).count, 1)
        let day = data.settings.calendar.startOfDay(for: walk.startedAt)
        XCTAssertEqual(data.dailyRecordSnapshots(now: now).first { $0.kind == .workout }?.progress[day], 1)
        XCTAssertEqual(data.recordedExternalWorkouts(on: day, now: now).count, 2)
        XCTAssertEqual(data.plans.map(\.id), originalPlans)
        XCTAssertEqual(data.todayRecommendedPlan?.id, next)
        XCTAssertEqual(data.sets.count, 1)
        XCTAssertTrue(data.workoutRotation.completedPlanIDs.isEmpty)
    }
    func testReplacingSnapshotRemovesDeletedRecordsAndDisabledImportDoesNotMutateHistory() {
        let data = DataStore.makeMock()
        data.settings.externalWorkoutImportEnabled = true
        let walk = record()
        data.replaceExternalWorkoutSnapshot([walk, walk], now: now)
        XCTAssertEqual(data.settings.externalWorkouts, [walk])
        data.settings.externalWorkoutImportEnabled = false
        data.replaceExternalWorkoutSnapshot([], now: now)
        XCTAssertEqual(data.settings.externalWorkouts, [walk])
        data.settings.externalWorkoutImportEnabled = true
        data.replaceExternalWorkoutSnapshot([], now: now)
        XCTAssertEqual(data.settings.externalWorkouts, [])
    }
    func testLegacySettingsAndImportedRecordsRoundTrip() throws {
        let settings = UserSettings()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        payload.removeValue(forKey: "externalWorkoutImportEnabled")
        payload.removeValue(forKey: "externalWorkouts")
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(decoded.externalWorkoutImportEnabled)
        let encoded = try JSONEncoder().encode([record()])
        XCTAssertEqual(try JSONDecoder().decode([ExternalWorkout].self, from: encoded), [record()])
    }
}

final class DailyCalendarNavigationTests: XCTestCase {
    private func calendar(first: Int = 2) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = first
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: .init(year: year, month: month, day: day, hour: 12))!
    }
    func testExpansionPreservesBrowsedDatePageAndWeekAcrossRepeatedToggles() {
        for first in [1, 2, 7] {
            let cal = calendar(first: first)
            let now = date(2026, 10, 13, calendar: cal)
            var nav = DailyCalendarNavigation(now: now, calendar: cal)
            let id = nav.pages[7].id
            nav.select(id, calendar: cal)
            let focus = nav.focus
            let week = DailyRecordCalendar.days(focus, monthly: false, calendar: cal)
            for _ in 0..<4 {
                nav.toggle(calendar: cal, now: now)
                XCTAssertTrue(nav.expanded)
                XCTAssertEqual(nav.visibleID, id)
                XCTAssertEqual(nav.focus, focus)
                let month = DailyRecordCalendar.days(nav.focus, monthly: true, calendar: cal)
                XCTAssertTrue(month.contains(week[0]), "The existing week must remain one of the same month rows")
                nav.toggle(calendar: cal, now: now)
                XCTAssertFalse(nav.expanded)
                XCTAssertEqual(nav.visibleID, id)
                XCTAssertEqual(DailyRecordCalendar.days(nav.focus, monthly: false, calendar: cal), week)
                XCTAssertTrue(cal.isDate(nav.pages.last!.focus, equalTo: now, toGranularity: .weekOfYear))
            }
        }
    }
    func testCrossMonthWeekExpandsTheFocusedMonthRatherThanTheWeeksFirstDay() {
        let cal = calendar()
        let now = date(2026, 10, 1, calendar: cal)
        var nav = DailyCalendarNavigation(now: now, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: DailyRecordCalendar.start(now, monthly: false, calendar: cal)), 9)
        let id = nav.visibleID
        nav.toggle(calendar: cal, now: now)
        XCTAssertEqual(nav.visibleID, id)
        XCTAssertEqual(cal.component(.month, from: nav.focus), 10)
        let dates = DailyRecordCalendar.cells(nav.focus, monthly: true, calendar: cal).compactMap { $0 }
        XCTAssertEqual(dates.count, 31)
        XCTAssertTrue(dates.allSatisfy { cal.component(.month, from: $0) == 10 })
        nav.toggle(calendar: cal, now: now)
        XCTAssertEqual(nav.focus, now)
    }
    func testMonthPagingCollapsesToTheWeekContainingItsFocusAndLoadsOlderDates() {
        let cal = calendar()
        let now = date(2026, 3, 31, calendar: cal)
        var nav = DailyCalendarNavigation(now: now, calendar: cal)
        nav.toggle(calendar: cal, now: now)
        let index = nav.pages.firstIndex { $0.id == nav.visibleID }!
        let older = nav.pages[index - 1]
        nav.select(older.id, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: nav.focus), 2)
        XCTAssertEqual(cal.component(.day, from: nav.focus), 28)
        let focus = nav.focus
        nav.toggle(calendar: cal, now: now)
        XCTAssertEqual(nav.visibleID, older.id)
        XCTAssertEqual(nav.focus, focus)
        XCTAssertTrue(DailyRecordCalendar.days(nav.focus, monthly: false, calendar: cal).contains(cal.startOfDay(for: focus)))
        let oldest = nav.pages.first!
        let count = nav.pages.count
        nav.select(oldest.id, calendar: cal)
        XCTAssertEqual(nav.pages.count, count + 12)
        XCTAssertEqual(nav.visibleID, oldest.id)
        XCTAssertEqual(nav.focus, oldest.focus)
    }
    func testOnlyExplicitTodayActionMovesFocusAfterTheDateChanges() {
        let cal = calendar()
        let before = date(2026, 12, 31, calendar: cal)
        let after = date(2027, 1, 4, calendar: cal)
        var nav = DailyCalendarNavigation(now: before, calendar: cal)
        let oldID = nav.visibleID
        nav.toggle(calendar: cal, now: after)
        XCTAssertEqual(nav.focus, before)
        XCTAssertEqual(nav.visibleID, oldID)
        nav.showToday(calendar: cal, now: after)
        XCTAssertEqual(nav.focus, after)
        XCTAssertEqual(cal.component(.month, from: nav.focus), 1)
    }
}

@MainActor
final class DailyCalendarExpansionLayoutTests: XCTestCase {
    @Observable final class Driver {
        var navigation: DailyCalendarNavigation
        init(now: Date, calendar: Calendar) { navigation = .init(now: now, calendar: calendar) }
    }
    func testNativePagerKeepsOlderFocusDuringExpansionCollapseAndRecreation() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let now = calendar.date(from: .init(year: 2026, month: 10, day: 13, hour: 12))!
        let driver = Driver(now: now, calendar: calendar)
        let selected = driver.navigation.pages[7]
        driver.navigation.select(selected.id, calendar: calendar)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; oldKey?.makeKeyAndVisible() }
        let content = NavigationStack {
            ScrollView {
                DailyRecordCalendarView(navigation: Binding(get: { driver.navigation }, set: { driver.navigation = $0 }),
                    calendar: calendar, now: now, snapshots: [
                        .init(kind: .workout, progress: [calendar.startOfDay(for: selected.focus): 1, calendar.startOfDay(for: now): 1], savedTargetDays: []),
                        .init(kind: .diet, progress: [calendar.startOfDay(for: selected.focus): 0.65, calendar.startOfDay(for: now): 0.65], savedTargetDays: []),
                        .init(kind: .sleep, progress: [calendar.startOfDay(for: selected.focus): 0.85, calendar.startOfDay(for: now): 0.85], savedTargetDays: [])
                    ], onSelect: { _ in }, onShowRules: {})
                    .padding(20).contentCardChrome(padding: 0).padding(20)
            }
        }.environment(\.colorScheme, .dark).environment(\.layoutDirection, .leftToRight)
        func pager(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width * 2 { return scroll }
            return view.subviews.lazy.compactMap { pager(in: $0) }.first
        }
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(pager(in: window))
        func assertFocus(_ scroll: UIScrollView) {
            let index = driver.navigation.pages.firstIndex { $0.id == selected.id }!
            XCTAssertEqual(driver.navigation.visibleID, selected.id)
            XCTAssertEqual(driver.navigation.focus, selected.focus)
            XCTAssertEqual(scroll.contentOffset.x, CGFloat(index) * scroll.bounds.width, accuracy: 2)
        }
        func capture(_ name: String) throws {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("calendar-expand-\(name).png"))
        }
        assertFocus(scroll)
        try capture("week")
        withAnimation(.spring(response: 0.38, dampingFraction: 1)) { driver.navigation.toggle(calendar: calendar, now: now) }
        var intermediateHeight: CGFloat?
        for _ in 0..<16 {
            try await Task.sleep(for: .milliseconds(25))
            let height = scroll.layer.presentation()?.bounds.height ?? scroll.bounds.height
            if height > 83 && height < 401 { intermediateHeight = height; break }
        }
        XCTAssertNotNil(intermediateHeight, "Expansion must expose intermediate heights rather than jump")
        try capture("transition")
        func waitForSettledHeight(_ expected: CGFloat) async throws {
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(20))
                if abs(scroll.bounds.height - expected) < 1 { break }
            }
            XCTAssertEqual(scroll.bounds.height, expected, accuracy: 1)
        }
        try await waitForSettledHeight(402)
        assertFocus(scroll)
        try capture("month")
        withAnimation(.spring(response: 0.38, dampingFraction: 1)) { driver.navigation.toggle(calendar: calendar, now: now) }
        try await waitForSettledHeight(82)
        assertFocus(scroll)
        window.rootViewController = UIHostingController(rootView: content)
        try await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
        assertFocus(try XCTUnwrap(pager(in: window)))
        try capture("returned")
        driver.navigation.showToday(calendar: calendar, now: now)
        try await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
        try capture("today")
    }
}

@MainActor
final class PreferenceTransactionTests: XCTestCase {
    @Observable final class EditorState {
        var draft: TrainingPreferenceDraft
        let original: TrainingPreferenceDraft
        init(_ settings: UserSettings) {
            original = TrainingPreferenceDraft(settings: settings)
            draft = original
        }
    }
    struct EditorFixture: View {
        @Bindable var state: EditorState
        var body: some View {
            NavigationStack {
                Form { TrainingSettingsSection(settings: $state.draft) }
                    .navigationTitle("Training Preferences")
            }.confirmPreferenceDismissal(hasChanges: state.draft != state.original)
        }
    }

    struct PresentedEditor: View {
        let page: AnyView
        @State private var presented = false
        var body: some View {
            Color.black.sheet(isPresented: $presented) { page.presentationDetents([.large]) }
                .task { presented = true }
        }
    }

    func testAllThreeProductionEditorsUseNativeSheetDismissalGuard() async throws {
        let data = DataStore.makeMock()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let initialSettings = try encoder.encode(data.settings)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        defer { previous?.makeKeyAndVisible() }
        let pages: [(String, AnyView)] = [
            ("training", AnyView(TrainingPreferencesSheet(onConfirm: {}).environment(data))),
            ("diet", AnyView(DietPreferencesSheet(initial: DietPreferences(), settings: data.settings, save: { _ in }).environment(data))),
            ("sleep", AnyView(SleepScheduleSheet(initial: SleepPreferences(), save: { _ in }).environment(data)))
        ]
        for (name, page) in pages {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: PresentedEditor(page: page).preferredColorScheme(.dark))
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(600))
            let sheet = try XCTUnwrap(host.presentedViewController, name)
            let presentation = try XCTUnwrap(sheet.presentationController)
            let delegate = try XCTUnwrap(presentation.delegate as? PreferenceDismissalObserver.DismissalDelegate, name)
            XCTAssertTrue(delegate.presentationControllerShouldDismiss(presentation), name)
            XCTAssertEqual(try encoder.encode(data.settings), initialSettings)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("preferences-" + name + "-native.png"))
            host.dismiss(animated: false)
            window.isHidden = true
        }
    }

    func testDraftIsIsolatedAndCommitsOnlyTrainingFields() {
        var settings = UserSettings()
        let original = TrainingPreferenceDraft(settings: settings)
        var draft = original
        draft.weeklyTrainingDays = 5
        draft.coachMemory = "Prioritize upper chest"
        draft.wantStrengthen = [.upperChest]
        XCTAssertEqual(settings.weeklyTrainingDays, 3)
        XCTAssertEqual(settings.coachMemory, "")
        XCTAssertTrue(draft.affectsRoutine(comparedTo: original))
        settings.sleepRecords = ["2026-10-14": 480]
        settings.language = "ja"
        draft.apply(to: &settings)
        XCTAssertEqual(settings.weeklyTrainingDays, 5)
        XCTAssertEqual(settings.coachMemory, draft.coachMemory)
        XCTAssertEqual(settings.sleepRecords?["2026-10-14"], 480)
        XCTAssertEqual(settings.language, "ja")
        var awakeOnly = original
        awakeOnly.keepScreenAwakeDuringWorkout.toggle()
        XCTAssertNotEqual(awakeOnly, original)
        XCTAssertFalse(awakeOnly.affectsRoutine(comparedTo: original))
    }

    func testNativeSheetInterceptsDirtySwipeAndAllowsCleanDismissal() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(350))
        let state = EditorState(UserSettings())
        let host = UIHostingController(rootView: EditorFixture(state: state))
        host.modalPresentationStyle = .pageSheet
        host.sheetPresentationController?.detents = [.large()]
        await withCheckedContinuation { continuation in presenter.present(host, animated: false) { continuation.resume() } }
        try await Task.sleep(for: .milliseconds(350))
        let presentation = try XCTUnwrap(host.presentationController)
        let delegate = try XCTUnwrap(presentation.delegate as? PreferenceDismissalObserver.DismissalDelegate)
        XCTAssertTrue(delegate.presentationControllerShouldDismiss(presentation))
        state.draft.coachMemory = "Prioritize upper chest"
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(delegate.presentationControllerShouldDismiss(presentation))
        delegate.presentationControllerDidAttemptToDismiss(presentation)
        try await Task.sleep(for: .milliseconds(350))
        func alert(in controller: UIViewController) -> UIAlertController? {
            if let result = controller as? UIAlertController { return result }
            if let presented = controller.presentedViewController, let result = alert(in: presented) { return result }
            return controller.children.compactMap { alert(in: $0) }.first
        }
        let confirmation = try XCTUnwrap(alert(in: host))
        XCTAssertEqual(confirmation.actions.map(\.style), [.destructive, .cancel])
        XCTAssertTrue(presenter.presentedViewController === host)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("preferences-unsaved-confirmation.png"))
        await withCheckedContinuation { continuation in confirmation.dismiss(animated: false) { continuation.resume() } }
        state.draft = state.original
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(delegate.presentationControllerShouldDismiss(presentation))
        presenter.dismiss(animated: false)
    }
}

final class SleepPreferenceTargetTests: XCTestCase {
    func testSaveUpdatesTodayAcrossSnapshotsWithoutChangingHistoryOrNutrition() throws {
        var settings = UserSettings()
        let today = settings.calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(settings.calendar.date(byAdding: .day, value: -1, to: today))
        let key = SleepPreferences.dayKey(today, calendar: settings.calendar)
        let oldKey = SleepPreferences.dayKey(yesterday, calendar: settings.calendar)
        var preferences = SleepPreferences()
        preferences.durationTargetMinutes = 510
        preferences.recordedGoals = [key: 510, oldKey: 510]
        settings.sleepPreferences = preferences
        settings.sleepRecords = [key: 480, oldKey: 480]
        let goal = DailyWellnessGoal(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 510, mealIDs: [])
        settings.wellnessGoals = [key: goal, oldKey: goal]
        preferences.durationTargetMinutes = 480
        settings.applySleepPreferences(preferences, now: today)
        XCTAssertEqual(settings.sleepPreferences?.targetMinutes, 480)
        XCTAssertEqual(settings.sleepPreferences?.recordedGoals[key], 480)
        XCTAssertEqual(settings.wellnessGoals?[key]?.sleepMinutes, 480)
        XCTAssertEqual(settings.wellnessGoals?[key]?.protein, 120)
        XCTAssertEqual(settings.wellnessGoals?[oldKey]?.sleepMinutes, 510)
        let snapshot = PerformanceCalendarSnapshot.lifestyle(kind: .sleep, settings: settings)
        XCTAssertEqual(try XCTUnwrap(snapshot.progress[today]), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.progress[yesterday]), 480.0 / 510.0, accuracy: 0.0001)
    }
}

extension MealNutritionEngineTests {
    func testEquivalentBasilRiceDescriptionsShareRecognitionAndCacheKey() {
        let inputs = ["一份牛肉打抛饭", "牛肉打泡饭", "1份牛肉打拋飯", " 牛肉打抛飯 "]
        let canonical = inputs.map(MealNutritionEngine.canonicalText)
        XCTAssertTrue(canonical.allSatisfy { $0 == "牛肉打抛饭" })
        for language in ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "it", "pt-BR", "ru", "ar"] {
            let keys = canonical.map { MealEstimateCache.key(Data($0.utf8), kind: "text", language: language) }
            XCTAssertEqual(Set(keys).count, 1)
        }
    }
    func testMealNormalizationNeverCollapsesRealPortionOrRecipeDifferences() {
        let variants = ["牛肉打抛饭", "两份牛肉打抛饭", "半份牛肉打抛饭", "小份牛肉打抛饭", "牛肉打抛饭不加饭", "牛肉打抛饭加煎蛋", "牛肉打抛饭牛肉200g", "牛肉打抛饭牛肉100g"]
        XCTAssertEqual(Set(variants.map(MealNutritionEngine.canonicalText)).count, variants.count)
        XCTAssertEqual(MealNutritionEngine.canonicalText("200g raw beef, half eaten"), "200g raw beef, half eaten")
    }
    func testMixedDishCatalogIncludesRiceOilAndMeat() {
        let catalog = MealNutritionEngine.catalogForText("牛肉打泡饭")
        for id in ["white_rice_cooked", "beef_ground_raw", "beef_ground_cooked", "canola_oil", "soy_sauce", "sugar"] {
            XCTAssertTrue(catalog.split(separator: ",").contains(Substring(id)))
        }
    }
    func testExactReferenceRepairsMissingIDWithoutTreatingMixedDishAsPlainMeat() throws {
        let estimate = try MealNutritionEngine.resolve(.init(foods: "Rice", isFood: true, items: [
            .init(name: "cooked rice", grams: 200, foodID: nil, portionEstimated: false, label: nil, estimatedPer100g: .init(protein: 90, carbs: 0, fat: 0))
        ]))
        let reference = try XCTUnwrap(MealFoodCatalog.byID["white_rice_cooked"])
        XCTAssertEqual(estimate.nutrition.protein, reference.per100g.protein * 2, accuracy: 0.001)
        XCTAssertEqual(estimate.analysis?.items.first?.source, .database)
        let dish = try MealNutritionEngine.resolve(.init(foods: "Beef rice", isFood: true, items: [
            .init(name: "beef rice bowl", grams: 300, foodID: nil, portionEstimated: true, label: nil, estimatedPer100g: .init(protein: 8, carbs: 22, fat: 5))
        ]))
        XCTAssertEqual(dish.analysis?.items.first?.source, .model)
        XCTAssertEqual(dish.nutrition.protein, 24, accuracy: 0.001)
    }
}

extension MealNutritionEngineTests {
    func testExplicitDishServingsScaleOneEstimateWithoutModelGuessing() throws {
        let regular = try MealNutritionEngine.resolve(.init(foods: "Beef rice", isFood: true, items: [
            .init(name: "Rice", grams: 200, foodID: "white_rice_cooked", portionEstimated: true, label: nil, estimatedPer100g: nil),
            .init(name: "Beef", grams: 100, foodID: "beef_ground_cooked", portionEstimated: true, label: nil, estimatedPer100g: nil)
        ]))
        for (text, factor) in [("半份牛肉打泡饭", 0.5), ("两份牛肉打抛饭", 2.0), ("2份牛肉打拋飯", 2.0)] {
            let input = MealNutritionEngine.textRequest(text)
            XCTAssertEqual(input.text, "牛肉打抛饭")
            XCTAssertEqual(input.servings, factor)
            let result = try MealNutritionEngine.scaledServing(regular, servings: input.servings)
            XCTAssertEqual(result.nutrition.protein, regular.nutrition.protein * factor, accuracy: 0.001)
            XCTAssertEqual(result.nutrition.carbs, regular.nutrition.carbs * factor, accuracy: 0.001)
            XCTAssertEqual(result.analysis?.items.first?.grams, 200 * factor)
        }
    }
    func testComplexPortionsNeverScaleOtherFoodsOrExplicitWeightsTwice() {
        for text in ["两份牛肉打抛饭和一杯奶", "半份牛肉打抛饭，米饭200g", "两份牛肉打抛饭吃一半", "2 servings of beef rice with an egg", "两份牛肉打抛饭加蛋"] {
            XCTAssertEqual(MealNutritionEngine.textRequest(text).servings, 1)
        }
        XCTAssertEqual(MealNutritionEngine.textRequest("two servings of beef rice").servings, 2)
    }
}

@MainActor
final class RecordHistorySectionTests: XCTestCase {
    func testWorkoutHistoryUsesTheInsightsRangeWithoutFallingBackToOldRecords() throws {
        let data = DataStore.makeMock()
        let now = Date()
        let calendar = data.settings.calendar
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let old = calendar.date(byAdding: .day, value: -14, to: week)!
        let ancient = calendar.date(byAdding: .day, value: -500, to: week)!
        let exercise = try XCTUnwrap(data.exById["bench_press_barbell"])
        data.sets = [("week", week), ("old", old), ("ancient", ancient)].map { id, date in
            SetRecord(id: id, exerciseId: exercise.id, exerciseName: exercise.name, category: .strength,
                      weight: 40, reps: 8, performedAt: date, planId: id, planName: id)
        }
        data.settings.externalWorkouts = [.init(id: "insights-import", activity: .walking,
            startedAt: old.addingTimeInterval(-3600), endedAt: old, duration: 3600,
            distanceMeters: 2000, kilocalories: 100, sourceBundleID: "com.apple.health", sourceName: "Apple Watch")]
        let items = data.historyItems(kind: .workout, now: now)
        for range in InsightsTimeRange.allCases {
            let filtered = RecordHistoryFilter.items(items, range: range, calendar: calendar, now: now)
            let expected = range == .thisWeek ? 1 : range == .allTime ? 4 : 3
            XCTAssertEqual(filtered.count, expected, range.rawValue)
            let chart = TrainingInsightsSnapshot.build(sets: data.sets, names: [:], primarySections: [:],
                                                       range: range, calendar: calendar, now: now)
            XCTAssertTrue(filtered.allSatisfy { $0.date <= chart.end && (range == .allTime || $0.date >= chart.start) })
        }
        data.sets.removeAll { $0.id == "week" }
        XCTAssertTrue(RecordHistoryFilter.items(data.historyItems(kind: .workout), range: .thisWeek,
                                              calendar: calendar, now: now).isEmpty)
        XCTAssertEqual(data.historyItems(kind: .workout).count, 3, "The All history count retains records outside the selected range")
    }

    func testMealsDeduplicateWithinDayBeforeFilteringAndKeepHistoricalTargets() throws {
        let data = DataStore.makeMock()
        let now = Date()
        let today = data.settings.calendar.startOfDay(for: now)
        let yesterday = data.settings.calendar.date(byAdding: .day, value: -1, to: today)!
        func meal(_ day: Date, _ id: String, _ time: Date, _ protein: Double) -> MealCheckIn {
            .init(day: day, mealID: id, title: "Meal", photoFilename: "", foods: "Rice and chicken",
                  nutrition: .init(protein: protein, carbs: 50, fat: 10), confirmedAt: time)
        }
        data.settings.mealCheckIns = [
            meal(today, "a", now.addingTimeInterval(-300), 10),
            meal(today, "a", now.addingTimeInterval(-200), 25),
            meal(today, "a", now.addingTimeInterval(3600), 99),
            meal(today, "b", now.addingTimeInterval(-100), 30),
            meal(yesterday, "a", yesterday.addingTimeInterval(100), 20)
        ]
        let key = SleepPreferences.dayKey(yesterday, calendar: data.settings.calendar)
        data.settings.wellnessGoals = [key: .init(protein: 111, carbsMinimum: 222, fatMinimum: 66, sleepMinutes: 480, mealIDs: [])]
        let before = try JSONEncoder().encode(data.settings)
        let items = data.historyItems(kind: .diet, now: now)
        let meals = items.compactMap { item -> MealCheckIn? in if case .meal(let meal, _) = item { return meal }; return nil }
        XCTAssertEqual(meals.map(\.nutrition.protein), [30, 25, 20])
        XCTAssertEqual(items.compactMap { item -> Int? in if case .meal(_, let number) = item { return number }; return nil }, [2, 1, 1])
        XCTAssertEqual(data.savedWellnessGoal(on: yesterday)?.protein, 111)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(data.settings), try encoder.encode(JSONDecoder().decode(UserSettings.self, from: before)))
    }

    func testRangeFiltersRespectCalendarDaysAndNeverInventMissingRecords() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12))!
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let old = calendar.date(byAdding: .day, value: -40, to: now)!
        let items: [RecordHistoryItem] = [.sleep(day: old, minutes: 450), .sleep(day: monday, minutes: 460),
            .sleep(day: calendar.startOfDay(for: now), minutes: 470), .sleep(day: now.addingTimeInterval(86400), minutes: 480)]
        XCTAssertEqual(RecordHistoryFilter.items(items, range: .thisWeek, calendar: calendar, now: now).count, 2)
        XCTAssertEqual(RecordHistoryFilter.items(items, range: .thisWeek, calendar: calendar, now: now, excludingDay: now).count, 1)
        XCTAssertEqual(RecordHistoryFilter.items(items, range: .allTime, calendar: calendar, now: now).count, 3)
        XCTAssertTrue(RecordHistoryFilter.items([], range: .allTime, calendar: calendar, now: now).isEmpty)
    }

    func testWorkoutHistoryIncludesHealthWorkoutsAndOnlyActualTraining() throws {
        let data = DataStore.makeMock()
        let now = Date()
        let day = data.settings.calendar.date(byAdding: .day, value: -1, to: data.settings.calendar.startOfDay(for: now))!
        let midday = day.addingTimeInterval(12 * 3600)
        let exercise = try XCTUnwrap(data.exById["bench_press_barbell"])
        data.sets = [SetRecord(id: "history-actual", exerciseId: exercise.id, exerciseName: exercise.name,
                              category: .strength, weight: 40, reps: 8, performedAt: midday)]
        data.settings.externalWorkouts = [.init(id: "history-walk", activity: .walking,
            startedAt: midday.addingTimeInterval(1800), endedAt: midday.addingTimeInterval(3000), duration: 1200,
            distanceMeters: 1000, kilocalories: 80, sourceBundleID: "com.apple.health", sourceName: "Apple Watch")]
        let items = data.historyItems(kind: .workout, now: now)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { if case .workout = $0 { return true }; return false })
        XCTAssertTrue(items.contains { if case .external = $0 { return true }; return false })
        let days = RecordHistoryFilter.days(items, calendar: data.settings.calendar)
        XCTAssertEqual(days.count, 1, "App and Apple Health sessions on the same day share one history card")
        XCTAssertEqual(days.first?.items.count, 2)
        data.sets = []; data.settings.externalWorkouts = []
        XCTAssertTrue(data.historyItems(kind: .workout).isEmpty)
    }

    func testDailyHistoryGroupsMealsByLocalDateAndCountsDaysInsteadOfMeals() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12))!
        let offsets = [0, 0, 0, -1, -4, -8]
        let items = offsets.enumerated().map { index, offset -> RecordHistoryItem in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let meal = MealCheckIn(day: date, mealID: "daily-\(index)", title: "Meal", photoFilename: "", foods: "Rice",
                                  nutrition: .init(protein: 20, carbs: 40, fat: 10),
                                  confirmedAt: date.addingTimeInterval(Double(index * 60)))
            return .meal(meal, number: index + 1)
        }
        let groups = RecordHistoryFilter.days(items.reversed(), calendar: calendar)
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups.map { $0.items.count }, [3, 1, 1, 1])
        XCTAssertEqual(groups.first?.date, calendar.startOfDay(for: today))
        XCTAssertEqual(groups.first?.items.map(\.id), Array(items.prefix(3)).map(\.id))
        XCTAssertEqual(groups.map(\.date), [0, -1, -4, -8].map {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: today)!)
        })
        XCTAssertTrue(RecordHistoryFilter.days([], calendar: calendar).isEmpty)
    }

    func testSharedHistorySectionsAndArchivesInNativePages() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let oldLanguage = LanguageManager.shared.selectedLanguage
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible(); LanguageManager.shared.selectedLanguage = oldLanguage }
        let data = DataStore.makeMock()
        let now = Date(); let calendar = data.settings.calendar; let today = calendar.startOfDay(for: now)
        let exercise = try XCTUnwrap(data.exById["bench_press_barbell"])
        data.sets = (0..<10).map { index in
            let time = calendar.date(byAdding: .day, value: -(index / 2), to: now)!.addingTimeInterval(Double(-(index % 2) * 600 - 60))
            return SetRecord(id: "history-native-\(index)", exerciseId: exercise.id, exerciseName: exercise.name,
                      category: .strength, weight: 40, reps: 8, performedAt: time,
                      planId: "history-plan-\(index)", planName: "Recorded workout \(index + 1)")
        }
        data.settings.mealCheckIns = (0..<10).map { index in
            let time = calendar.date(byAdding: .day, value: -(index / 2), to: now)!.addingTimeInterval(Double(-(index % 2) * 600 - 60))
            return MealCheckIn(day: calendar.startOfDay(for: time), mealID: "history-meal-\(index)", title: "Meal", photoFilename: "", foods: "Chicken, rice and vegetables",
                        nutrition: .init(protein: 25, carbs: 50, fat: 10), confirmedAt: time)
        }
        data.settings.sleepRecords = [:]; data.settings.wellnessGoals = [:]
        var preferences = SleepPreferences(); preferences.healthConnected = false
        data.settings.sleepPreferences = preferences
        for offset in 0..<9 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let key = SleepPreferences.dayKey(day, calendar: calendar)
            data.settings.sleepRecords?[key] = 450
            data.settings.wellnessGoals?[key] = .init(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: [])
        }
        for (language, pages) in [(SupportedLanguage.en, Array(0...5)), (.zhHans, [1,2,4,5]), (.de, [1,2,4,5]), (.ar, [1,2,4,5])] {
            LanguageManager.shared.selectedLanguage = language
            let state = HistoryNavigationTestState()
            let host = UIHostingController(rootView: HistoryNavigationTestFixture(state: state)
                .environment(data).environment(TrainingSessionStore()).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(250))
            for page in pages {
                state.path = [page]
                // The first Workout push warms the shared muscle render cache; capture its settled page.
                try await Task.sleep(for: .milliseconds(language == .en && page == 0 ? 1600 : 650))
                window.layoutIfNeeded()
                func scroll(_ view: UIView) -> UIScrollView? {
                    if let result = view as? UIScrollView, result.contentSize.height > result.bounds.height + 10 { return result }
                    return view.subviews.lazy.compactMap { scroll($0) }.first
                }
                let scrolling = scroll(window)
                for position in ["top", "bottom"] {
                    if position == "bottom", let scrolling {
                        scrolling.setContentOffset(CGPoint(x: 0, y: max(-scrolling.adjustedContentInset.top,
                            scrolling.contentSize.height - scrolling.bounds.height + scrolling.adjustedContentInset.bottom)), animated: false)
                        try await Task.sleep(for: .milliseconds(150))
                    }
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                    let name = "record-history-\(language.rawValue)-\(page)-\(position)"
                    let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                    try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
                }
            }
            window.isHidden = true
        }
    }
}

private final class HistoryNavigationTestState: ObservableObject { @Published var path = [Int]() }
private struct HistoryNavigationTestFixture: View {
    @ObservedObject var state: HistoryNavigationTestState
    var body: some View {
        AppNavigationStack(path: $state.path) {
            Color.clear.navigationTitle("Home").navigationDestination(for: Int.self) { page in
                switch page {
                case 0: HistoryScreen(onReplay: { _ in }, onOpenSettings: {}, mode: .records)
                case 1: DietScreen()
                case 2: SleepScreen()
                case 3: RecordHistoryArchiveScreen(kind: .workout)
                case 4: RecordHistoryArchiveScreen(kind: .diet)
                case 6: HistoryScreen(onReplay: { _ in }, onOpenSettings: {}, mode: .insights)
                default: RecordHistoryArchiveScreen(kind: .sleep)
                }
            }
        }
    }
}


@MainActor
final class ShareCardSelectionTests: XCTestCase {
    private func squareCropSource() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
        }
    }

    private func greenPhotoBounds(_ image: UIImage) throws -> CGRect? {
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        var minX = cg.width, minY = cg.height, maxX = -1, maxY = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let offset = (y * cg.width + x) * 4
                if pixels[offset] < 5 && pixels[offset + 1] > 245 && pixels[offset + 2] < 5 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func testFooterExportKeepsSquareCenterCropAndScannableQRInAllLanguages() throws {
        let original = LanguageManager.shared.selectedLanguage
        defer { LanguageManager.shared.selectedLanguage = original }
        let source = squareCropSource()
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for language in SupportedLanguage.allCases {
            LanguageManager.shared.selectedLanguage = language
            for side in [CGFloat(38), 64, 104] {
                let image = try XCTUnwrap(ShareImageRenderer.render {
                    ShareCardFooter(qrPayload: MasoLinks.appStore, qrSize: side, photo: source)
                        .environment(\.locale, LanguageManager.currentLocale)
                        .environment(\.layoutDirection, language.rawValue == "ar" ? .rightToLeft : .leftToRight)
                })
                let bounds = try XCTUnwrap(greenPhotoBounds(image))
                XCTAssertEqual(bounds.width, bounds.height, accuracy: 2)
                XCTAssertEqual(bounds.width, (side + 6) * image.scale, accuracy: 2)
                XCTAssertEqual(bounds.maxX, image.size.width * image.scale - 20 * image.scale, accuracy: 2)
                let ciImage = try XCTUnwrap(CIImage(image: image))
                let codes = detector.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                XCTAssertTrue(codes.contains(MasoLinks.appStore), "QR must remain scannable: \(language.rawValue), \(side)")
                if side == 64, ["en", "zh-Hans", "ar"].contains(language.rawValue) {
                    let attachment = XCTAttachment(image: image); attachment.name = "\(language.rawValue)-share-footer-export"
                    attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
    }

    func testExcludedPhotoIsAbsentAndExportHasNoLargePhotoBanner() throws {
        let selection = ShareCardSelection()
        let source = squareCropSource()
        selection.setIncluded(false, id: "workout-photo")
        let excluded = try XCTUnwrap(ShareImageRenderer.render {
            ShareCardFooter(qrPayload: MasoLinks.appStore, qrSize: 64, photo: source, photoSelectionID: "workout-photo")
                .shareSelection(selection, editing: false)
        })
        XCTAssertNil(try greenPhotoBounds(excluded))
        func workout(_ photo: UIImage?) -> WorkoutDetailShareCard {
            WorkoutDetailShareCard(planName: "Workout", muscles: [], detail: [], setCount: 4,
                                   totalVolumeKg: 120, durationLabel: "30 min", qrPayload: MasoLinks.appStore,
                                   userPhoto: photo, footerQRSize: 64)
        }
        let withPhoto = try XCTUnwrap(ShareImageRenderer.render { workout(source) })
        let withoutPhoto = try XCTUnwrap(ShareImageRenderer.render { workout(nil) })
        XCTAssertGreaterThanOrEqual(withoutPhoto.size.height, withPhoto.size.height)
        let bounds = try XCTUnwrap(greenPhotoBounds(withPhoto))
        XCTAssertEqual(bounds.width, 70 * withPhoto.scale, accuracy: 2)
        XCTAssertEqual(bounds.height, bounds.width, accuracy: 2)
        let attachment = XCTAttachment(image: withPhoto); attachment.name = "workout-share-footer-photo-export"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSelectionCanBeRestoredAndAllOffDisablesSharing() {
        let selection = ShareCardSelection()
        selection.available = ["daily-workout", "daily-diet", "daily-sleep"]
        for id in selection.available { selection.setIncluded(false, id: id) }
        XCTAssertFalse(selection.canShare)
        selection.setIncluded(true, id: "daily-diet")
        XCTAssertTrue(selection.canShare)
        XCTAssertTrue(selection.includes("daily-diet"))
        XCTAssertFalse(selection.includes("daily-sleep"))
    }

    func testDailySelectionChangesFinalImageAndPreviewSwitchesStayAvailable() async throws {
        let data = DataStore.makeMock()
        let training = TrainingSessionStore()
        let day = data.settings.calendar.startOfDay(for: Date())
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.sleepRecords = [key: 448]
        data.settings.wellnessGoals = [key: DailyWellnessGoal(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: [])]
        let selection = ShareCardSelection()
        func export() throws -> UIImage {
            try XCTUnwrap(ShareImageRenderer.render {
                DailyRecordShareCard(day: day).environment(data).environment(training)
                    .shareSelection(selection, editing: false)
            })
        }
        let full = try export()
        selection.setIncluded(false, id: "daily-sleep")
        let withoutSleep = try export()
        XCTAssertLessThan(withoutSleep.size.height, full.size.height)
        selection.setIncluded(true, id: "daily-sleep")
        XCTAssertEqual(try export().size.height, full.size.height, accuracy: 1)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let host = UIHostingController(rootView: FullPageShareSheet(title: "Share day", surface: "test", imageOnly: true, selection: selection) {
            DailyRecordShareCard(day: day).environment(data).environment(training)
        }.preferredColorScheme(.dark))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(selection.available, ["daily-workout", "daily-diet", "daily-sleep"])
        for id in selection.available { selection.setIncluded(false, id: id) }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(selection.canShare)
        // Disabled cards retain their controls, so they can always be restored.
        XCTAssertEqual(selection.available.count, 3)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Share day all cards off"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("share-cards-all-off.png"))
        selection.setIncluded(true, id: "daily-diet")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(selection.canShare)
        let selected = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try selected.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("share-cards-diet-only.png"))
    }
}

extension ShareCardSelectionTests {
    func testNativeShareSheetsExposeCardControlsForWorkoutInsightsAndPlans() async throws {
        let data = DataStore.makeMock()
        data.settings.debugProUnlock = true // This fixture expects both free and Pro Insights sections.
        let plan = try XCTUnwrap(data.plans.first)
        let oldLanguage = LanguageManager.shared.selectedLanguage
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { LanguageManager.shared.selectedLanguage = oldLanguage; window.isHidden = true; previous?.makeKeyAndVisible() }
        let cases: [(String, String, Int, () -> AnyView)] = [
            ("routine", "en", 3, { AnyView(RoutineShareCard(plan: plan, exById: data.exById, qrPayload: MasoLinks.appStore)) }),
            ("insights", "zh-Hans", 2, { AnyView(InsightsChartsView(data: data, forSharing: true, range: .constant(.thisWeek))) }),
            ("complete", "ar", 3, { AnyView(WorkoutDetailShareCard(dateLabel: nil, planName: plan.name,
                muscles: [.chest], detail: [], setCount: 4, totalVolumeKg: 120, durationLabel: "30 min", qrPayload: MasoLinks.appStore)) })
        ]
        for (name, language, count, makeContent) in cases {
            LanguageManager.shared.selectedLanguage = SupportedLanguage(rawValue: language)
            let selection = ShareCardSelection()
            let host = UIHostingController(rootView: FullPageShareSheet(title: NSLocalizedString("Share", comment: ""), surface: name, selection: selection) {
                VStack(spacing: 16) { makeContent() }.padding(20)
            }.environment(data).environment(\.locale, LanguageManager.currentLocale)
                .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark))
            host.modalPresentationStyle = .pageSheet
            host.sheetPresentationController?.detents = [.large()]
            await withCheckedContinuation { continuation in
                presenter.present(host, animated: false) { continuation.resume() }
            }
            for _ in 0..<30 {
                if selection.available.count == count { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(selection.available.count, count, name)
            func switches(_ view: UIView) -> [UISwitch] {
                (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches)
            }
            let toggle = try XCTUnwrap(switches(host.view).first, name)
            toggle.setOn(false, animated: false)
            toggle.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(selection.excluded.count, 1, "Native toggle must update export selection: \(name)")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Share selection \(name) \(language)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("share-selection-\(name).png"))
            await withCheckedContinuation { continuation in
                host.dismiss(animated: false) { continuation.resume() }
            }
        }
    }
}

extension ShareCardSelectionTests {
    func testActualInsightsShareControlsParticipateInHitTesting() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let oldLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        let data = DataStore.makeMock()
        data.settings.debugProUnlock = true // Both free and Pro sections are expected in this fixture.
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AppNavigationStack {
            HistoryScreen(onReplay: { _ in }, onOpenSettings: {}, mode: .insights, insightsSharePresented: true)
        }.environment(data).environment(SubscriptionManager())
            .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
            .preferredColorScheme(.dark))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { LanguageManager.shared.selectedLanguage = oldLanguage; window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(600))
        try await Task.sleep(for: .milliseconds(700))
        func switches(_ view: UIView) -> [UISwitch] { (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches) }
        let controls = switches(window)
        XCTAssertEqual(controls.count, 2)
        for toggle in controls {
            let center = toggle.convert(CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: window)
            let hit = try XCTUnwrap(window.hitTest(center, with: nil))
            XCTAssertTrue(hit === toggle || hit.isDescendant(of: toggle), "Share toggle is blocked by an ancestor: \(type(of: hit))")
        }
        if let toggle = controls.first {
            toggle.setOn(false, animated: false); toggle.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertFalse(toggle.isOn)
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("actual-insights-share-toggle.png"))
    }
}

final class NutritionEnergyTests: XCTestCase {
    func testEnergyUsesUnroundedMacrosAndRejectsInvalidValues() throws {
        XCTAssertEqual(try XCTUnwrap(MealNutrition(protein: 100, carbs: 200, fat: 50).estimatedCalories), 1650)
        XCTAssertEqual(try XCTUnwrap(MealNutrition(protein: 1.25, carbs: 2.5, fat: 0.5).estimatedCalories), 19.5)
        XCTAssertEqual(MealNutrition().estimatedCalories, 0)
        for invalid in [Double.nan, .infinity, -1] {
            XCTAssertNil(MealNutrition(protein: invalid).estimatedCalories)
        }
    }

    func testLegacyMealRoundTripAndHistoricalTargetRemainDerived() throws {
        let original = MealNutrition(protein: 25, carbs: 40, fat: 10)
        let json = try JSONEncoder().encode(original)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("Calories"))
        let decoded = try JSONDecoder().decode(MealNutrition.self, from: json)
        XCTAssertEqual(decoded.estimatedCalories, 350)
        let previousTarget = MealNutrition(protein: 120, carbs: 240, fat: 60)
        let changedTarget = MealNutrition(protein: 120, carbs: 180, fat: 60)
        XCTAssertEqual(previousTarget.estimatedCalories, 1980)
        XCTAssertEqual(changedTarget.estimatedCalories, 1740)
        XCTAssertEqual((decoded + decoded).estimatedCalories, 700)
    }
}

@MainActor
final class NutritionEnergyRenderingTests: XCTestCase {
    func testSummaryRendersAllLanguagesWithMissingAndRecordedIntake() throws {
        let original = LanguageManager.currentLanguageCode
        defer { LocalizedBundle.applyLanguage(original) }
        let directory = URL(fileURLWithPath: "/tmp/masso-calorie-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = MealNutrition(protein: 120, carbs: 240, fat: 60)
        for language in SupportedLanguage.allCases {
            LocalizedBundle.applyLanguage(language.rawValue)
            for typeSize in [DynamicTypeSize.large, .accessibility3] {
                for hasRecords in [false, true] {
                    let card = DietNutritionSummaryContent(targets: target,
                        actual: MealNutrition(protein: 92, carbs: 160, fat: 45), progress: nil,
                        hasRecords: hasRecords, exportStyle: true)
                        .contentCardChrome(padding: 0)
                        .padding(16).frame(width: 393)
                        .background(MasoColor.background)
                        .environment(\.locale, Locale(identifier: language.rawValue))
                        .environment(\.layoutDirection, language.rawValue == "ar" ? .rightToLeft : .leftToRight)
                        .environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: card)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertGreaterThan(image.size.height, 100)
                    XCTAssertEqual(image.size.width, 393)
                    let name = "\(language.rawValue)-\(typeSize == .large ? "normal" : "large")-\(hasRecords).png"
                    try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name))
                }
            }
        }
    }
}

/// Hosts the production pages on an AppNavigationStack path, the same pattern as
/// HomeHeaderBlurTests. SwiftUI button identifiers are not UIView IDs here, so this
/// does not walk or tap the UIKit tree.
/// shortcut: finger-swipe and menu taps need MasoUITests (XCUIApplication). This target
/// pops by clearing the path and only checks that the interactive pop gesture is enabled.
@MainActor
final class WorkoutPageNavigationTests: XCTestCase {
    private final class Pages: ObservableObject {
        @Published var path: [String] = []
        var day = Date()
        var plan: Plan?
        var session: SessionSummary?
        var stats: [SessionExerciseStat] = []
        var replay: Plan?
        var started: Plan?
    }

    private struct Stack: View {
        @ObservedObject var pages: Pages
        var body: some View {
            AppNavigationStack(path: $pages.path) {
                Color.clear.navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: String.self) { id in
                        switch id {
                        case "day":
                            DailyRecordSheet(day: pages.day, onReplay: { pages.started = $0; pages.path = [] }, pushed: true)
                        case "workout":
                            PlanDetailSheet(initialPlan: pages.plan!, onStart: { pages.started = $0; pages.path = [] }, usesParentNavigation: true)
                        case "session":
                            RecordedSessionReport(session: pages.session!, onReplay: { pages.started = $0; pages.path = [] })
                        default:
                            EmptyView()
                        }
                    }
            }
        }
    }

    private struct CreateSheet: View {
        let draft: Plan
        @State private var shown = false
        var body: some View {
            Color.clear
                .sheet(isPresented: $shown) {
                    PlanDetailSheet(initialPlan: draft, isCreating: true, onStart: { _ in })
                        .presentationDetents([.large]).presentationDragIndicator(.visible)
                }
                .task { shown = true }
        }
    }

    func testProductionPagesPushReturnAndCreateStaysASheet() async throws {
        let priorLanguage = LanguageManager.shared.selectedLanguage
        let priorConsent = UserDefaults.standard.object(forKey: "masso.aiDataSharingConsent.v2")
        AIDataConsent.shared.revoke()
        defer {
            LanguageManager.shared.selectedLanguage = priorLanguage
            AppRouter.shared.pendingWidgetDay = nil
            AppRouter.shared.requestedDestination = nil
            if let priorConsent { UserDefaults.standard.set(priorConsent, forKey: "masso.aiDataSharingConsent.v2") }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        var window: UIWindow?
        defer { window?.rootViewController = nil; window?.isHidden = true; previous?.makeKeyAndVisible() }
        for (language, typeSize, slug) in [(SupportedLanguage.en, DynamicTypeSize.large, "en"),
                                           (.zhHans, .large, "zh-Hans"),
                                           (.en, .accessibility3, "en-large")] {
            let hostWindow = try freshWindow(scene, language: language, previous: window)
            window = hostWindow
            let tag = hostWindow.traitCollection.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            let data = DataStore.makeMock()
            data.settings.onboardingCompleted = true
            data.settings.hasSeenWelcomePaywall = true
            if let index = data.plans.firstIndex(where: { !$0.steps.isEmpty }) {
                data.plans[index].name = language == .zhHans ? "推力训练" : "Push Day"
            }
            let planIDs = data.plans.map(\.id)
            let planNames = data.plans.map(\.name)
            let setCount = data.sets.count
            let pages = Pages()
            pages.day = data.settings.calendar.startOfDay(for: Date())
            pages.plan = data.plans.first(where: { !$0.steps.isEmpty })
            pages.session = data.recordedWorkoutSessions().first
            if let session = pages.session {
                pages.stats = data.recordedExerciseStats(for: session)
                pages.replay = data.recordedReplayPlan(for: session)
            }
            let host = UIHostingController(rootView: Stack(pages: pages)
                .environment(data).environment(TrainingSessionStore()).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.colorScheme, .dark))
            hostWindow.rootViewController = host
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            let navigation = try XCTUnwrap(navigationController(in: host))
            let homeCount = navigation.viewControllers.count

            pages.path = ["day"]
            try await Task.sleep(for: .milliseconds(500))
            try assertPushed(navigation, homeCount: homeCount, host: host, window: hostWindow, slug: slug)
            shot(hostWindow, "\(tag)-day-pushed-\(slug)")
            pages.path = []
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(navigation.viewControllers.count, homeCount, slug)
            XCTAssertNil(pages.started, slug)
            shot(hostWindow, "\(tag)-day-returned-\(slug)")

            XCTAssertNotNil(pages.plan, slug)
            pages.path = ["workout"]
            try await Task.sleep(for: .milliseconds(500))
            try assertPushed(navigation, homeCount: homeCount, host: host, window: hostWindow, slug: slug)
            shot(hostWindow, "\(tag)-workout-detail-\(slug)")
            pages.path = []
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(navigation.viewControllers.count, homeCount, slug)
            XCTAssertEqual(data.plans.map(\.id), planIDs, slug)
            XCTAssertEqual(data.plans.map(\.name), planNames, slug)
            shot(hostWindow, "\(tag)-workout-detail-returned-\(slug)")

            XCTAssertNotNil(pages.session, "Mock has no recorded session \(slug)")
            guard pages.session != nil else { continue }
            pages.path = ["session"]
            try await Task.sleep(for: .milliseconds(500))
            try assertPushed(navigation, homeCount: homeCount, host: host, window: hostWindow, slug: slug)
            shot(hostWindow, "\(tag)-history-session-\(slug)")
            pages.path = []
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(data.sets.count, setCount, slug)
            shot(hostWindow, "\(tag)-history-session-returned-\(slug)")

            let draft = Plan(id: "unsaved-\(slug)", name: "", steps: [], createdAt: Date(), updatedAt: Date())
            let create = UIHostingController(rootView: CreateSheet(draft: draft)
                .environment(data).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.colorScheme, .dark))
            hostWindow.rootViewController = create
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertNotNil(create.presentedViewController, "Creating a routine must stay a sheet \(slug)")
            shot(hostWindow, "\(tag)-create-routine-sheet-\(slug)")
            create.presentedViewController?.dismiss(animated: false)
            XCTAssertEqual(data.plans.map(\.id), planIDs, slug)
            XCTAssertFalse(data.plans.contains { $0.id == draft.id }, slug)
        }
    }

    func testWidgetDayAndReportSurfacesCapture() async throws {
        let priorLanguage = LanguageManager.shared.selectedLanguage
        let priorConsent = UserDefaults.standard.object(forKey: "masso.aiDataSharingConsent.v2")
        AIDataConsent.shared.revoke()
        defer {
            LanguageManager.shared.selectedLanguage = priorLanguage
            AppRouter.shared.pendingWidgetDay = nil
            AppRouter.shared.requestedDestination = nil
            if let priorConsent { UserDefaults.standard.set(priorConsent, forKey: "masso.aiDataSharingConsent.v2") }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        var window: UIWindow?
        defer { window?.rootViewController = nil; window?.isHidden = true; previous?.makeKeyAndVisible() }
        let locales: [(SupportedLanguage, DynamicTypeSize, String)] = [
            (.en, .large, "en"), (.zhHans, .large, "zh-Hans"), (.en, .accessibility3, "en-large")
        ]
        for (index, item) in locales.enumerated() {
            let (language, typeSize, slug) = item
            let hostWindow = try freshWindow(scene, language: language, previous: window)
            window = hostWindow
            let tag = hostWindow.traitCollection.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            let data = DataStore.makeMock()
            data.settings.onboardingCompleted = true
            data.settings.hasSeenWelcomePaywall = true
            if let index = data.plans.firstIndex(where: { !$0.steps.isEmpty }) {
                data.plans[index].name = language == .zhHans ? "推力训练" : "Push Day"
            }
            let planIDs = data.plans.map(\.id)
            let setCount = data.sets.count
            let day = data.settings.calendar.date(byAdding: .day, value: -(index + 1), to: Date()) ?? Date()
            let root = UIHostingController(rootView: RootView()
                .environment(data).environment(TrainingSessionStore()).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.colorScheme, .dark))
            hostWindow.rootViewController = root
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(600))
            let navigation = try XCTUnwrap(navigationController(in: root))
            XCTAssertEqual(navigation.viewControllers.count, 1, "Today should be up before the widget day \(slug)")
            // A second RootView still subscribed to AppRouter would nil this date before this view reads it.
            AppRouter.shared.pendingWidgetDay = data.settings.calendar.startOfDay(for: day)
            try await Task.sleep(for: .milliseconds(700))
            XCTAssertNil(root.presentedViewController, slug)
            XCTAssertGreaterThan(navigation.viewControllers.count, 1, "Widget day did not push \(slug)")
            XCTAssertNil(navigationController(in: try XCTUnwrap(navigation.topViewController)), slug)
            XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true, slug)
            XCTAssertEqual(navigation.view.bounds.width, hostWindow.bounds.width, accuracy: 1)
            shot(hostWindow, "\(tag)-widget-day-\(slug)")
            AppRouter.shared.requestedDestination = .today
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(navigation.viewControllers.count, 1, "Widget day did not return home \(slug)")
            XCTAssertEqual(data.plans.map(\.id), planIDs, slug)
            XCTAssertEqual(data.sets.count, setCount, slug)
            shot(hostWindow, "\(tag)-widget-day-returned-\(slug)")
            let calendar = UIHostingController(rootView: DailyOverviewCard(onReplay: { _ in })
                .environment(data)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(MasoColor.background))
            hostWindow.rootViewController = calendar
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            shot(hostWindow, "\(tag)-calendar-visible-\(slug)")

            let suggestion = DataStore.RoutineSuggestion(
                id: "fixture-recovery",
                title: language == .zhHans ? "腿部训练偏少" : "Legs are undertrained",
                detail: language == .zhHans ? "最近三周腿部组数少于训练最多的部位。" : "Fewer leg sets than your top group over the last 3 weeks.",
                focusNote: "bias toward legs")
            let coach = UIHostingController(rootView: AISummaryCard(data: data, localSuggestion: suggestion)
                .environment(data).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize)
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(MasoColor.background))
            hostWindow.rootViewController = coach
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            shot(hostWindow, "\(tag)-suggestion-actions-\(slug)")

            let historySession = try XCTUnwrap(data.recordedWorkoutSessions().first, "History report capture needs a recorded session \(slug)")
            let history = UIHostingController(rootView: WorkoutHistoryRecordRow(session: historySession, onReplay: { _ in })
                .environment(data)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.colorScheme, .dark)
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(MasoColor.background))
            hostWindow.rootViewController = history
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            shot(hostWindow, "\(tag)-history-report-\(slug)")

            let store = TrainingSessionStore()
            let plan = try XCTUnwrap(data.plans.first(where: { !$0.steps.isEmpty }))
            store.start(planId: plan.id, plan: plan, segments: expandPlan(
                plan, exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds), source: "test")
            store.finishEarly()
            let player = UIHostingController(rootView: PlanPlayerScreen()
                .environment(data).environment(store).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, typeSize)
                .transaction { $0.disablesAnimations = true })
            hostWindow.rootViewController = player
            hostWindow.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500))
            shot(hostWindow, "\(tag)-completion-report-\(slug)")
            store.end()
            XCTAssertEqual(data.plans.map(\.id), planIDs, slug)
            XCTAssertEqual(data.sets.count, setCount, slug)
        }
    }

    private func freshWindow(_ scene: UIWindowScene, language: SupportedLanguage, previous: UIWindow?) throws -> UIWindow {
        LanguageManager.shared.selectedLanguage = language
        clearSharedRoutes()
        for other in scene.windows {
            other.rootViewController = nil
        }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        // Same direction as the SwiftUI environment on each capture root.
        // The window attribute alone left en/zh-Hans roots on the scene's previous direction.
        window.semanticContentAttribute = language == .ar ? .forceRightToLeft : .forceLeftToRight
        return window
    }

    private func clearSharedRoutes() {
        let router = AppRouter.shared
        router.requestedDestination = nil
        router.pendingWidgetDestination = nil
        router.pendingWidgetDay = nil
        router.pendingHomeQuickAction = nil
        router.pendingTrainingPreferencesUpdate = false
        router.pendingMuscleTraining = nil
        router.pendingSummaryFocus = nil
        router.pendingOptimizeFocus = nil
    }

    private func assertPushed(_ navigation: UINavigationController, homeCount: Int, host: UIViewController, window: UIWindow, slug: String) throws {
        XCTAssertGreaterThan(navigation.viewControllers.count, homeCount, slug)
        XCTAssertNil(host.presentedViewController, slug)
        XCTAssertNil(navigationController(in: try XCTUnwrap(navigation.topViewController)), slug)
        XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true, slug)
        XCTAssertFalse(navigation.isNavigationBarHidden, slug)
        XCTAssertEqual(navigation.view.bounds.width, window.bounds.width, accuracy: 1)
    }

    private func navigationController(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children {
            if let navigation = navigationController(in: child) { return navigation }
        }
        return nil
    }

    private func shot(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
