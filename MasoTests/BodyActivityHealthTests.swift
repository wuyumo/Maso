import XCTest
import HealthKit
import SwiftUI
import UIKit
@testable import Maso

@MainActor
final class BodyActivityHealthTests: XCTestCase {
    private func fixture() -> (BodyActivityHealthSnapshot, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: .init(year: 2026, month: 10, day: 25, hour: 15))!
        return (.init(refreshedAt: now, timeZone: calendar.timeZone.identifier,
            weights: [.init(id: "old", date: now.addingTimeInterval(-400 * 86400), value: 76, source: "Scale"),
                      .init(id: "latest", date: now.addingTimeInterval(-3600), value: 72.5, source: "Scale")],
            heights: [.init(id: "height", date: now.addingTimeInterval(-500 * 86400), value: 178, source: "Health")],
            activity: [.init(day: calendar.startOfDay(for: now), steps: 6000, activeEnergy: 420, restingEnergy: 1100)]), calendar)
    }
    func testAdoptionPreservesManualWeightAndUsesMissingHeight() {
        let (snapshot, _) = fixture()
        var settings = DataStore.makeMock().settings
        settings.weight = 80
        settings.bodyActivityHealth = .init(enabled: true)
        settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(settings.weight, 80)
        XCTAssertEqual(settings.heightCentimeters, 178)
        XCTAssertEqual(settings.bodyActivityHealth?.useWeight, false)
        XCTAssertEqual(settings.weightForAI, 80)
        settings.bodyActivityHealth?.useWeight = true
        settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(settings.weight, 72.5)
        XCTAssertNil(settings.weightForAI, "Imported weight is not sent to AI")
        settings.weight = 81
        settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(settings.weight, 81)
        XCTAssertEqual(settings.bodyActivityHealth?.useWeight, false)
        XCTAssertEqual(settings.weightForAI, 81)
    }
    func testExplicitManualMeasurementsStopFollowingEvenAtSameValue() {
        let (snapshot, _) = fixture()
        var settings = DataStore.makeMock().settings
        settings.weight = nil; settings.heightCentimeters = nil
        settings.bodyActivityHealth = .init(enabled: true)
        settings.applyBodyActivityHealth(snapshot)
        settings.setManualBodyMeasurement(72.5, weight: true)
        settings.setManualBodyMeasurement(180, weight: false)
        settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(settings.weight, 72.5)
        XCTAssertEqual(settings.heightCentimeters, 180)
        XCTAssertFalse(settings.bodyActivityHealth?.useWeight ?? true)
        XCTAssertFalse(settings.bodyActivityHealth?.useHeight ?? true)
        XCTAssertNil(settings.bodyActivityHealth?.appliedWeight)
        XCTAssertNil(settings.bodyActivityHealth?.appliedHeight)
        XCTAssertEqual(settings.excludingBodyHealthData.weight, 72.5)
        settings.setManualBodyMeasurement(.nan, weight: true)
        settings.setManualBodyMeasurement(10, weight: false)
        XCTAssertEqual(settings.weight, 72.5)
        XCTAssertEqual(settings.heightCentimeters, 180)
    }
    func testMissingProfileFillsAndDisconnectedOrFutureDataDoesNotApply() {
        var (snapshot, _) = fixture()
        var settings = DataStore.makeMock().settings
        settings.weight = nil; settings.heightCentimeters = nil
        settings.bodyActivityHealth = .init(enabled: true)
        snapshot.weights.append(.init(id: "future", date: snapshot.refreshedAt.addingTimeInterval(1), value: 90, source: "Invalid"))
        snapshot.weights.append(.init(id: "invalid", date: snapshot.refreshedAt, value: .nan, source: "Invalid"))
        settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(settings.weight, 72.5)
        XCTAssertEqual(settings.heightCentimeters, 178)
        settings.bodyActivityHealth?.enabled = false
        snapshot.weights.append(.init(id: "new", date: snapshot.refreshedAt, value: 70, source: "Scale"))
        settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(settings.weight, 72.5)
    }
    func testActualEnergyNeedsBothComponentsAndCannotCarryAcrossMidnight() throws {
        let (snapshot, calendar) = fixture()
        let today = try XCTUnwrap(snapshot.today(calendar: calendar, now: snapshot.refreshedAt))
        XCTAssertEqual(today.totalEnergy, 1520)
        XCTAssertNil(HealthActivityDay(day: today.day, steps: nil, activeEnergy: -1, restingEnergy: 100).totalEnergy)
        XCTAssertNil(HealthActivityDay(day: today.day, steps: 0, activeEnergy: 0, restingEnergy: nil).totalEnergy)
        XCTAssertEqual(HealthActivityDay(day: today.day, steps: 0, activeEnergy: 0, restingEnergy: 0).totalEnergy, 0)
        XCTAssertNil(snapshot.today(calendar: calendar, now: snapshot.refreshedAt.addingTimeInterval(86400)))
        var other = calendar; other.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertNil(snapshot.today(calendar: other, now: snapshot.refreshedAt))
    }
    func testFullHistoryAndPartialMissingDataRoundTripWithoutNewRequiredFields() throws {
        let (snapshot, _) = fixture()
        let decoded = try JSONDecoder().decode(BodyActivityHealthSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertGreaterThan(snapshot.refreshedAt.timeIntervalSince(snapshot.weights[0].date), 365 * 86400)
        var settings = DataStore.makeMock().settings
        settings.bodyActivityHealth = nil; settings.heightCentimeters = nil
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        object.removeValue(forKey: "bodyActivityHealth"); object.removeValue(forKey: "heightCentimeters")
        let legacy = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.bodyActivityHealth); XCTAssertNil(legacy.heightCentimeters)
        XCTAssertEqual(HealthKitService.bodyActivityReadTypes.count, 5)
    }
    func testHealthWeightUpdatesOnlyCurrentAutomaticTargetsAndStaysOutOfAIPayload() throws {
        let (snapshot, calendar) = fixture()
        let data = DataStore.makeMock()
        data.settings.weight = 80
        data.settings.bodyActivityHealth = .init(enabled: true, useWeight: true)
        data.settings.dietPreferences = .init()
        let before = try XCTUnwrap(DietNutritionTargets.build(settings: data.settings))
        let day = data.settings.calendar.date(byAdding: .day, value: -1, to: Date())!
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.wellnessGoals = [key: .init(protein: 199, carbsMinimum: 299, fatMinimum: 99, sleepMinutes: 480, mealIDs: [])]
        data.settings.applyBodyActivityHealth(snapshot)
        data.captureWellnessGoal(updateDiet: true)
        XCTAssertEqual(data.settings.wellnessGoals?[key]?.protein, 199)
        XCTAssertEqual(data.settings.wellnessGoals?[key]?.carbsMinimum, 299)
        let after = try XCTUnwrap(DietNutritionTargets.build(settings: data.settings))
        XCTAssertNotEqual(before.protein, after.protein)
        XCTAssertNil(data.buildAIPayload().weightKg)
        data.settings.dietPreferences?.proteinTarget = 130
        data.settings.dietPreferences?.carbohydrateTarget = 220
        data.settings.dietPreferences?.fatTarget = 60
        let fixed = try XCTUnwrap(DietNutritionTargets.build(settings: data.settings, preferences: data.settings.dietPreferences!))
        XCTAssertEqual(fixed.protein, 130); XCTAssertEqual(fixed.carbohydrate, 220); XCTAssertEqual(fixed.fat, 60)
        _ = calendar
    }
}

@MainActor
final class BodyHealthMissingDataTests: XCTestCase {
    func testEmptyHealthDoesNotReserveAProfileFieldAgainstLaterManualEntry() {
        let data = DataStore.makeMock()
        data.settings.weight = nil
        data.settings.bodyActivityHealth = .init(enabled: true)
        let now = Date()
        var snapshot = BodyActivityHealthSnapshot(refreshedAt: now, timeZone: TimeZone.current.identifier,
            weights: [.init(id: "childhood", date: now, value: 2.5, source: "Health")], heights: [], activity: [], incomplete: true)
        data.settings.applyBodyActivityHealth(snapshot)
        XCTAssertNil(data.settings.bodyActivityHealth?.useWeight)
        data.settings.weight = 82
        snapshot.weights = [.init(id: "new", date: now, value: 70, source: "Scale")]
        data.settings.applyBodyActivityHealth(snapshot)
        XCTAssertEqual(data.settings.weight, 82)
        XCTAssertEqual(data.settings.bodyActivityHealth?.useWeight, false)
    }
}

@MainActor
final class BodyHealthRenderingTests: XCTestCase {
    func testHealthPageRendersAcrossAllLanguages() async throws {
        let previousLanguage = LanguageManager.currentLanguageCode
        setenv("MASO_HEALTH_BODY_FIXTURE", "1", 1)
        defer { unsetenv("MASO_HEALTH_BODY_FIXTURE"); LocalizedBundle.applyLanguage(previousLanguage) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for language in SupportedLanguage.allCases {
            LocalizedBundle.applyLanguage(language.rawValue)
            let data = DataStore.makeMock()
            let now = Date()
            data.settings.bodyActivityHealth = .init(enabled: true, snapshot: .init(refreshedAt: now,
                timeZone: data.settings.calendar.timeZone.identifier,
                weights: [.init(id: "weight", date: now, value: 72.5, source: "Scale")],
                heights: [.init(id: "height", date: now, value: 178, source: "Health")],
                activity: [.init(day: data.settings.calendar.startOfDay(for: now), steps: 6000, activeEnergy: 420, restingEnergy: 1100)]))
            let content = NavigationStack { BodyProfileScreen() }.environment(data)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language.rawValue == "ar" ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "health-body-profile-" + language.rawValue; attachment.lifetime = .keepAlways; add(attachment)
            for key in ["Read body & activity", "Body measurements", "Use Health weight", "Use Health height", "Steps", "Height", "Health history"] {
                XCTAssertNotEqual(NSLocalizedString(key, comment: ""), "MISSING")
                let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
                let bundle = try XCTUnwrap(Bundle(path: path))
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "MISSING", table: nil), "MISSING")
            }
        }
    }
}

@MainActor
final class BodyHealthStorageTests: XCTestCase {
    func testCacheIsExcludedFromBackupAndNormalSettingsExportIsRedacted() throws {
        var settings = DataStore.makeMock().settings
        settings.weight = 80; settings.heightCentimeters = nil
        settings.bodyActivityHealth = .init(enabled: true, useWeight: true)
        let now = Date()
        settings.applyBodyActivityHealth(.init(refreshedAt: now, timeZone: TimeZone.current.identifier,
            weights: [.init(id: "private-sample", date: now, value: 72.5, source: "Private scale")],
            heights: [.init(id: "private-height", date: now, value: 178, source: "Health")], activity: []))
        let state = try XCTUnwrap(settings.bodyActivityHealth)
        let clean = settings.excludingBodyHealthData
        XCTAssertEqual(clean.weight, 80)
        XCTAssertNil(clean.heightCentimeters)
        XCTAssertNil(clean.bodyActivityHealth?.snapshot)
        XCTAssertNil(clean.bodyActivityHealth?.appliedWeight)
        let encoded = String(decoding: try JSONEncoder().encode(clean), as: UTF8.self)
        XCTAssertFalse(encoded.contains("private-sample"))
        XCTAssertFalse(encoded.contains("Private scale"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("health.json")
        try BodyHealthLocalStore.write(state, to: url)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(BodyHealthLocalStore.read(from: url), state)
        var restored = clean
        restored.restoreLocalBodyHealth(state)
        XCTAssertEqual(restored.weight, 72.5)
        XCTAssertEqual(restored.heightCentimeters, 178)
        XCTAssertNil(restored.weightForAI)
        var frozen = clean; frozen.bodyActivityHealth?.enabled = false
        frozen.restoreLocalBodyHealth(state)
        XCTAssertEqual(frozen.weight, 72.5)
        XCTAssertNil(frozen.bodyActivityHealth?.snapshot)
        var manual = clean; manual.weight = 85
        manual.restoreLocalBodyHealth(state)
        XCTAssertEqual(manual.weight, 85)
        XCTAssertEqual(manual.bodyActivityHealth?.useWeight, false)
    }
}
