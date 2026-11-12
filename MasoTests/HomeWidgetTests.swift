import XCTest
import SwiftUI
import UIKit
import WidgetKit
@testable import Maso

@MainActor
final class HomeWidgetTests: XCTestCase {
    func testCalorieOverTargetColorsInterpolateAndClamp() {
        func check(_ input: Double?, _ expected: (Double, Double, Double)) {
            let result = DietProgressColor.components(for: input)
            XCTAssertEqual(result.0, expected.0, accuracy: 0.0001)
            XCTAssertEqual(result.1, expected.1, accuracy: 0.0001)
            XCTAssertEqual(result.2, expected.2, accuracy: 0.0001)
        }
        check(nil, (1, 1, 0)); check(0.5, (1, 1, 0)); check(1, (1, 1, 0))
        check(1.15, (1, 0.792, 0)); check(1.3, (1, 0.584, 0))
        check(1.45, (1, 0.4075, 0.094)); check(1.6, (1, 0.231, 0.188))
        check(1.75, (0.843, 0.2765, 0.529)); check(1.9, (0.686, 0.322, 0.87))
        check(2.5, (0.686, 0.322, 0.87)); check(.nan, (1, 1, 0))
    }
    func testCalendarColorUsesUncappedCalorieRatioAndSavedGoal() throws {
        let (data, now) = fixture()
        let day = data.settings.calendar.startOfDay(for: now)
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.wellnessGoals?[key] = .init(protein: 100, carbsMinimum: 100, fatMinimum: 100, sleepMinutes: 480, mealIDs: ["a"])
        data.settings.mealCheckIns = [.init(day: day, mealID: "a", title: "Meal", photoFilename: "", foods: "Meal",
            nutrition: .init(protein: 40, carbs: 220, fat: 130), confirmedAt: now.addingTimeInterval(-100))]
        let source = try XCTUnwrap(data.dailyRecordSnapshots(now: now).first { $0.kind == .diet })
        XCTAssertEqual(try XCTUnwrap(source.dietCalorieFractions[day]), 1.3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(source.progress[day]), 36.5 / 35, accuracy: 0.0001, "Color must preserve the existing macro-progress value")
        let published = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: [now])
        let cell = try XCTUnwrap(published.moments.first?.calendarDays?.first { $0.date == day })
        XCTAssertEqual(try XCTUnwrap(cell.dietCalorieFraction), 1.3, accuracy: 0.0001)
        data.settings.wellnessGoals?.removeValue(forKey: key)
        XCTAssertNil(data.dailyRecordSnapshots(now: now).first { $0.kind == .diet }?.dietCalorieFractions[day], "Historical color must not invent a goal")
    }
    private func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2; value.minimumDaysInFirstWeek = 4
        return value
    }
    private func fixture() -> (DataStore, Date) {
        let data = DataStore.makeMock()
        data.settings.weekStartDay = .monday
        let cal = data.settings.calendar
        let now = cal.date(from: .init(year: 2026, month: 10, day: 11, hour: 23, minute: 30))!
        data.settings.weeklyTrainingDays = 3
        let exercise = data.exById.values.first { Set($0.primaryMuscles.compactMap { $0.section }) == Set([MuscleGroup.chest]) }!
        data.sets = (0..<3).map { index in
            SetRecord(id: "widget-\(index)", exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category,
                weight: 40, reps: 10, performedAt: now.addingTimeInterval(-3600 - Double(index)))
        }
        let day = data.settings.calendar.startOfDay(for: now)
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        data.settings.wellnessGoals = [key: .init(protein: 120, carbsMinimum: 200, fatMinimum: 60, sleepMinutes: 480, mealIDs: ["a"])]
        data.settings.mealCheckIns = [.init(day: day, mealID: "a", title: "Meal", photoFilename: "", foods: "Meal",
            nutrition: .init(protein: 60, carbs: 250, fat: 75), confirmedAt: now.addingTimeInterval(-100))]
        data.settings.sleepRecords = [key: 450]
        data.settings.sleepPreferences = .init()
        data.settings.sleepPreferences?.recordedGoals = [key: 480]
        return (data, now)
    }

    func testSnapshotUsesActualRecordsGoalsAndHomeCompletionSources() throws {
        let (data, now) = fixture()
        let result = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: [now])
        let moment = try XCTUnwrap(result.moment(at: now))
        XCTAssertEqual(moment.protein, 60)
        XCTAssertEqual(moment.proteinTarget, 120)
        XCTAssertEqual(moment.sleepMinutes, 450)
        XCTAssertEqual(moment.sleepTarget, 480)
        XCTAssertEqual(moment.calories, 1915)
        XCTAssertEqual(moment.calorieTarget, 1820)
        XCTAssertEqual(try XCTUnwrap(moment.dietProgress), 1915.0 / 1820, accuracy: 0.001)
        XCTAssertEqual(moment.calorieProgress, moment.dietProgress)
        let today = data.settings.calendar.startOfDay(for: now)
        XCTAssertNotEqual(moment.dietProgress, data.dailyRecordSnapshots(now: now).first { $0.kind == .diet }?.progress[today], "Energy progress must not reuse the nutrition score")
        XCTAssertEqual(moment.sleepProgress, data.dailyRecordSnapshots(now: now).first { $0.kind == .sleep }?.progress[today])
        let week = data.settings.calendar.dateInterval(of: .weekOfYear, for: now)!
        XCTAssertEqual(moment.workoutDays, data.recordedWorkoutDates(now: now).filter { $0 >= week.start && $0 < week.end }.count)
        let summary = TrainingInsightsSnapshot.build(sets: data.sets.filter { $0.performedAt <= now }, names: [:],
            primarySections: data.exById.mapValues { Set($0.primaryMuscles.compactMap { $0.section }) },
            range: .thisWeek, calendar: data.settings.calendar, now: now)
        XCTAssertEqual(moment.musclesTrained?.first?.sets, 3)
        XCTAssertEqual(moment.musclesTrained?.map(\.id), summary.muscles.filter { $0.sets > 0 }.map { $0.group.rawValue })
        XCTAssertEqual(moment.musclesTrained?.map(\.sets), summary.muscles.filter { $0.sets > 0 }.map(\.sets))
        data.settings.mealCheckIns = []
        let empty = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: [now])
        XCTAssertNil(empty.moment(at: now)?.protein, "No recorded meal is missing, not zero")
        XCTAssertNil(empty.moment(at: now)?.calories)
        XCTAssertNil(empty.moment(at: now)?.calorieProgress)
    }
    func testOldWidgetSnapshotDoesNotTreatScoreOrProteinAsCalories() throws {
        let preview = MassoWidgetEntry.preview
        let encoded = try JSONEncoder().encode(try XCTUnwrap(preview.snapshot))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var moments = try XCTUnwrap(object["moments"] as? [[String: Any]])
        moments[0].removeValue(forKey: "calories")
        moments[0].removeValue(forKey: "calorieTarget")
        object["moments"] = moments
        let legacy = try JSONDecoder().decode(MassoWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        let entry = MassoWidgetEntry(date: preview.date, snapshot: legacy)
        XCTAssertNotNil(entry.moment?.dietProgress)
        XCTAssertNil(entry.progress(.diet))
        XCTAssertNil(entry.moment?.calories)
    }

    func testMidnightClearsPreviousDayAndNewWeekResetsWorkoutCount() throws {
        let (data, now) = fixture()
        let midnight = data.settings.calendar.date(byAdding: .day, value: 1, to: data.settings.calendar.startOfDay(for: now))!
        let dates = WidgetSnapshotPublisher.timelineDates(now: now, calendar: data.settings.calendar)
        XCTAssertTrue(dates.contains(midnight))
        let result = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: dates)
        let next = try XCTUnwrap(result.moment(at: midnight))
        XCTAssertNil(next.protein); XCTAssertNil(next.dietProgress)
        XCTAssertNil(next.calories); XCTAssertNil(next.calorieTarget); XCTAssertNil(next.calorieProgress)
        XCTAssertNil(next.sleepMinutes); XCTAssertNil(next.sleepProgress)
        XCTAssertEqual(next.workoutDays, 0)
        XCTAssertEqual(next.musclesTrained, [])
        XCTAssertNil(result.moment(at: now.addingTimeInterval(25 * 3600)))
    }
    func testGroupArchiveRoundTripRejectsCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (data, now) = fixture()
        let snapshot = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: [now])
        try MassoWidgetStore.write(snapshot, to: directory)
        XCTAssertEqual(MassoWidgetStore.read(from: directory), snapshot)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        XCTAssertNil(MassoWidgetStore.read(from: directory))
        XCTAssertNil(MassoWidgetStore.read(from: directory.appendingPathComponent("missing")))
    }
    func testWidgetRoutesAndEditableConfigurations() {
        for value in MassoWidgetDestination.allCases { XCTAssertEqual(MassoWidgetDestination(url: value.url), value) }
        XCTAssertNil(MassoWidgetDestination(url: URL(string: "maso://import/workout")!))
        XCTAssertNil(MassoWidgetDestination(url: URL(string: "https://widget/start")!))
        XCTAssertNil(MassoWidgetDestination(url: URL(string: "maso://widget/unknown")!))
        let config = MetricWidgetIntent(); config.metric = .sleep
        XCTAssertEqual(config.metricChoice, .sleep)
        XCTAssertEqual(MassoDailyOverviewWidget.families, [.systemSmall, .systemMedium, .systemLarge])
        for metric in WidgetMetric.allCases {
            let selected = MassoWidgetEntry(date: Date(), snapshot: nil, metric: metric)
            XCTAssertEqual(MassoHomeWidgetView(entry: selected, layout: .single).tapURL, metric.destination.url)
            XCTAssertEqual(MassoHomeWidgetView(entry: selected, layout: .overview).tapURL, MassoWidgetDestination.workout.url)
            XCTAssertNotEqual(MassoHomeWidgetView(entry: selected, layout: .single).tapURL, MassoWidgetDestination.start.url)
        }
        var entry = MassoWidgetEntry.preview
        entry.snapshot?.dietEnabled = false
        XCTAssertFalse(entry.enabled(.diet)); XCTAssertNil(entry.progress(.diet))
        XCTAssertEqual(MassoHomeWidgetView(entry: entry, layout: .largeOverview).tapURL, MassoWidgetDestination.home.url)
    }
    func testCalendarMatchesHomeAndDayLinksRejectFutureOrMalformedDates() throws {
        let (data, now) = fixture()
        let snapshot = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: [now])
        let days = try XCTUnwrap(snapshot.moments.first?.calendarDays)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.date, data.settings.calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        let sources = data.dailyRecordSnapshots(now: now)
        for day in days {
            XCTAssertEqual(day.workout, sources.first { $0.kind == .workout }?.progress[day.date])
            XCTAssertEqual(day.diet, sources.first { $0.kind == .diet }?.progress[day.date])
            XCTAssertEqual(day.dietCalorieFraction, sources.first { $0.kind == .diet }?.dietCalorieFractions[day.date])
            XCTAssertEqual(day.sleep, sources.first { $0.kind == .sleep }?.progress[day.date])
            XCTAssertEqual(MassoWidgetDayLink.day(from: MassoWidgetDayLink.url(for: day.date), now: now), day.date)
        }
        XCTAssertNil(MassoWidgetDayLink.day(from: MassoWidgetDayLink.url(for: now.addingTimeInterval(86400)), now: now))
        for value in ["maso://widget/day?date=nan", "maso://widget/day?date=1&date=2", "https://widget/day?date=1", "maso://widget/day?date=-1"] {
            XCTAssertNil(MassoWidgetDayLink.day(from: URL(string: value)!, now: now))
        }
    }

    func testExtensionHasCompleteStringsForAllAppLanguages() throws {
        let url = try XCTUnwrap(Bundle.main.builtInPlugInsURL?.appendingPathComponent("MasoWidgets.appex"))
        let bundle = try XCTUnwrap(Bundle(url: url))
        let keys = ["Calories", "Today's calorie progress", "Sleep progress", "Progress toward your sleep goal", "Diet progress", "Today's nutrition progress", "Daily rings", "Workout, diet and sleep in one ring", "Add meal", "Daily overview", "Recovery & workout", "Single metric", "Main metric", "Body view", "Content", "Open Masso to update", "Your day at a glance", "Muscle recovery and your next workout", "One metric, your choice", "Workout", "Diet", "Sleep", "My Muscle Status", "Body front", "Body back", "This week", "Protein", "Last night", "Start workout", "Resume", "Create a routine", "Muscles trained", "No data", "sets", "Chest", "Back muscle", "Legs", "Shoulders", "Arms", "Core", "Full body"]
        for code in SupportedLanguage.allCases.map(\.rawValue) {
            let path = try XCTUnwrap(bundle.path(forResource: code, ofType: "lproj"), code)
            let localized = try XCTUnwrap(Bundle(path: path))
            for key in keys { XCTAssertNotEqual(localized.localizedString(forKey: key, value: "MISSING", table: nil), "MISSING", "\(code): \(key)") }
            var entry = MassoWidgetEntry.preview; entry.snapshot?.language = code
            XCTAssertEqual(entry.text("Diet"), localized.localizedString(forKey: "Diet", value: nil, table: nil))
        }
    }

    func testLockScreenRingUsesDailyCalendarNotWeeklyWorkoutAndExpires() throws {
        let (data, now) = fixture()
        let dates = WidgetSnapshotPublisher.timelineDates(now: now, calendar: data.settings.calendar)
        let snapshot = WidgetSnapshotPublisher.makeSnapshot(data: data, now: now, dates: dates)
        var entry = MassoWidgetEntry(date: now, snapshot: snapshot)
        let day = try XCTUnwrap(entry.moment?.calendarDays?.first { data.settings.calendar.isDate($0.date, inSameDayAs: now) })
        XCTAssertEqual(entry.todayProgress, [day.workout, day.diet, day.sleep])
        XCTAssertEqual(entry.todayProgress[0], 1)
        XCTAssertNotEqual(entry.todayProgress[0], entry.progress(.workout), "Daily workout completion must not become weekly frequency")
        XCTAssertEqual(MassoDailyRingWidget.families, [.accessoryCircular])
        XCTAssertEqual(MassoDietProgressWidget.families, [.accessoryCircular])
        XCTAssertEqual(MassoSleepProgressWidget.families, [.accessoryCircular])
        XCTAssertEqual(entry.progress(.sleep), entry.moment?.sleepProgress)
        entry.snapshot?.dietEnabled = false; entry.snapshot?.sleepEnabled = false
        XCTAssertEqual(entry.todayProgress, [day.workout, nil, nil])
        XCTAssertNil(entry.progress(.sleep))
        entry = .init(date: data.settings.calendar.date(byAdding: .day, value: 1, to: data.settings.calendar.startOfDay(for: now))!, snapshot: entry.snapshot)
        XCTAssertEqual(entry.todayProgress, [nil, nil, nil], "Tomorrow must not inherit yesterday's rings")
        entry = .init(date: now.addingTimeInterval(25 * 3600), snapshot: entry.snapshot)
        XCTAssertEqual(entry.todayProgress, [nil, nil, nil])
        entry.snapshot = nil
        XCTAssertEqual(entry.todayProgress, [nil, nil, nil])
    }

    func testLockScreenRingFitsOneCircularSlotInAllLanguages() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for language in SupportedLanguage.allCases.map(\.rawValue) {
            var entry = MassoWidgetEntry.preview; entry.snapshot?.language = language
            let content = VStack(spacing: 24) {
                HStack(spacing: 30) {
                    MassoDailyRingView(entry: entry)
                        .frame(width: 62, height: 62)
                    MassoDietProgressView(entry: entry)
                        .frame(width: 62, height: 62)
                    MassoAccessoryProgressView(entry: entry, metric: .sleep)
                        .frame(width: 62, height: 62)
                }
                HStack(spacing: 30) {
                    MassoAccessoryProgressView(entry: .init(date: entry.date, snapshot: nil), metric: .sleep)
                        .frame(width: 62, height: 62)
                    MassoAccessoryProgressView(entry: .init(date: entry.date, snapshot: nil), metric: .diet)
                        .frame(width: 62, height: 62)
                }
                Text(entry.text("Daily rings")).font(.caption)
            }
            .foregroundStyle(Color(red: 0.80, green: 1, blue: 0.65))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.04, green: 0.16, blue: 0.06))
            .environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "lock-rings-" + language; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testFullColorPaletteStaysDarkWhenSystemAppearanceChanges() throws {
        let entry = MassoWidgetEntry.preview
        let scenes: [(MassoHomeWidgetView.Layout, WidgetMetric, CGSize)] = [
            (.overview, .workout, .init(width: 330, height: 137)),
            (.largeOverview, .workout, .init(width: 330, height: 314))
        ] + WidgetMetric.allCases.map { (.single, $0, .init(width: 126, height: 137)) }
        for (layout, metric, size) in scenes {
            var selected = entry; selected.metric = metric
            func pixels(_ scheme: ColorScheme) throws -> Data {
                let renderer = ImageRenderer(content: MassoHomeWidgetView(entry: selected, layout: layout)
                    .frame(width: size.width, height: size.height).padding(16)
                    .background(OverviewPalette.surface).environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                return try XCTUnwrap(image.dataProvider?.data) as Data
            }
            XCTAssertTrue(try pixels(.light) == pixels(.dark), "\(layout) / \(metric) must keep the same dark colors")
        }
    }

    func testWidgetLayoutsFitAllThreeNativeSizes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for (language, scheme) in SupportedLanguage.allCases.map({ ($0.rawValue, ColorScheme.dark) }) + [("en", .light)] {
            var entry = MassoWidgetEntry.preview
            entry.snapshot?.language = language
            let content = VStack(spacing: 20) {
                MassoHomeWidgetView(entry: entry, layout: .overview)
                    .frame(width: 330, height: 137).padding(16).background(OverviewPalette.surface).clipShape(RoundedRectangle(cornerRadius: 24))
                MassoHomeWidgetView(entry: entry, layout: .largeOverview)
                    .frame(width: 330, height: 314).padding(16).background(OverviewPalette.surface).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack {
                    ForEach(WidgetMetric.allCases, id: \.rawValue) { metric in
                        let selected = MassoWidgetEntry(date: entry.date, snapshot: entry.snapshot, metric: metric)
                        MassoHomeWidgetView(entry: selected, layout: .single)
                            .frame(width: 126, height: 137).padding(12).background(OverviewPalette.surface).clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }.scaleEffect(0.8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, scheme)
                .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
            window.rootViewController = UIHostingController(rootView: content)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let name = "widgets-\(language)-\(scheme == .dark ? "dark" : "light")"
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png"))
        }
    }
}
