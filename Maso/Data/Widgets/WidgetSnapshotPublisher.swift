import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()
    private var pending: Task<Void, Never>?
    private var revision = 0
    func schedule(_ data: DataStore, immediately: Bool = false) {
        // Screenshots/tests must never export seeded records as the user's data.
        guard data.settings.onboardingCompleted,
              ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1",
              NSClassFromString("XCTestCase") == nil, MassoWidgetStore.directory != nil else { return }
        pending?.cancel()
        revision += 1
        let token = revision
        pending = Task { [weak self, weak data] in
            if !immediately { try? await Task.sleep(for: .milliseconds(600)) }
            guard !Task.isCancelled, let self, let data, data.settings.onboardingCompleted else { return }
            let now = Date()
            let calendar = data.settings.calendar
            let dates = Self.timelineDates(now: now, calendar: calendar)
            let snapshot = Self.makeSnapshot(data: data, now: now, dates: dates)
            guard let directory = MassoWidgetStore.directory else { return }
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { return }
            guard !Task.isCancelled, self.revision == token else { return }
            do {
                try MassoWidgetStore.write(snapshot)
                Self.reload()
                Self.removeObsoleteBodyImages()
            } catch { }
        }
    }

    private static func removeObsoleteBodyImages() {
        guard let directory = MassoWidgetStore.directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("body-") && file.pathExtension == "png" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func reload() {
        ["MassoSingleMetric", "MassoDailyRings", "MassoDietProgress", "MassoSleepProgress"].forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    }

    static func timelineDates(now: Date, calendar: Calendar) -> [Date] {
        let horizon = now.addingTimeInterval(25 * 3600)
        var dates = [now]
        var day = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= horizon {
            dates.append(next); day = next
        }
        return dates
    }

    static func makeSnapshot(data: DataStore, now: Date, dates: [Date]) -> MassoWidgetSnapshot {
        let calendar = data.settings.calendar
        let today = calendar.startOfDay(for: now)
        let meals = data.wellnessMeals(on: now).filter { $0.confirmedAt <= now && $0.mealTime <= now }
        let goal = data.wellnessGoal(on: now)
        let energy = DietEnergyProgress.calculate(goal: goal, meals: meals)
        let snapshots = data.dailyRecordSnapshots(now: now)
        let slept = HealthKitService.shared.sleepMinutes[today] ?? data.settings.sleepRecords?[SleepPreferences.dayKey(today, calendar: calendar)]
        let workoutDays = data.recordedWorkoutDates(now: now)
        let recordedSets = data.sets.filter { $0.performedAt <= now }
        let sections = data.exById.mapValues { Set($0.primaryMuscles.compactMap { $0.section }) }
        var musclesByWeek: [Date: [MassoWidgetSnapshot.TrainedMuscle]] = [:]
        let moments = dates.map { date in
            let sameDay = calendar.isDate(now, inSameDayAs: date)
            let week = calendar.dateInterval(of: .weekOfYear, for: date)!
            if musclesByWeek[week.start] == nil {
                let summary = TrainingInsightsSnapshot.build(sets: recordedSets, names: [:], primarySections: sections,
                    range: .thisWeek, calendar: calendar, now: date)
                musclesByWeek[week.start] = summary.muscles.filter { $0.sets > 0 }.map {
                    .init(id: $0.group.rawValue, name: $0.group == .fullBody ? NSLocalizedString("Full body", comment: "") : $0.group.displayName, sets: $0.sets)
                }
            }
            let days = (0..<7).compactMap { offset -> MassoWidgetSnapshot.CalendarDay? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
                func value(_ kind: PerformanceCalendarSnapshot.Kind) -> Double? {
                    guard day <= now else { return nil }
                    return snapshots.first { $0.kind == kind }?.progress[day]
                }
                return .init(date: day, workout: value(.workout), diet: value(.diet), sleep: value(.sleep),
                             dietCalorieFraction: day <= now ? snapshots.first { $0.kind == .diet }?.dietCalorieFractions[day] : nil)
            }
            return MassoWidgetSnapshot.Moment(date: date,
                workoutDays: workoutDays.filter { $0 >= week.start && $0 < week.end }.count,
                workoutTarget: max(1, min(7, data.settings.weeklyTrainingDays)),
                protein: sameDay && !meals.isEmpty ? meals.reduce(0) { $0 + $1.nutrition.protein } : nil,
                proteinTarget: sameDay ? goal?.protein : nil,
                dietProgress: sameDay ? energy.fraction : nil,
                sleepMinutes: sameDay ? slept : nil,
                sleepTarget: sameDay ? data.savedSleepTarget(on: now) : nil,
                sleepProgress: sameDay ? snapshots.first { $0.kind == .sleep }?.progress[today] : nil,
                musclesTrained: musclesByWeek[week.start], calendarDays: days,
                calories: sameDay ? energy.actual : nil, calorieTarget: sameDay ? energy.target : nil)
        }
        return .init(generatedAt: now, language: LanguageManager.currentLanguageCode,
                     timeZone: calendar.timeZone.identifier, dietEnabled: data.settings.dietEnabled != false,
                     sleepEnabled: data.settings.sleepEnabled != false, moments: moments)
    }
}
