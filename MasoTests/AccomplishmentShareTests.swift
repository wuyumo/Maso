import XCTest
@testable import Maso

final class AccomplishmentShareTests: XCTestCase {
    func testRhythmAveragesOnlyRecordedDaysAndExcludesFuture() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let tuesday = cal.date(byAdding: .day, value: 1, to: monday)!
        let future = cal.date(byAdding: .day, value: 4, to: monday)!
        let rhythm = AccomplishmentShare.rhythm(sets: [], focus: now, monthly: false, calendar: cal, now: now,
            diet: [monday: 0.8, tuesday: 1.0, future: 0.2], sleep: [monday: 420, tuesday: 480, future: 100])
        XCTAssertEqual(rhythm.averageDiet!, 0.9, accuracy: 0.0001)
        XCTAssertEqual(rhythm.averageSleep!, 450, accuracy: 0.0001)
        XCTAssertNil(rhythm.days.first { $0.date == future }?.sleepMinutes)
        let empty = AccomplishmentShare.rhythm(sets: [], focus: now, monthly: false, calendar: cal, now: now)
        XCTAssertNil(empty.averageSleep)
        XCTAssertNil(empty.averageDiet)
    }
    private func calendar(monday: Bool = true) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = monday ? 2 : 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 8, _ minute: Int = 0, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func set(_ id: String, at date: Date, plan: String = "push", session: String? = nil, exercise: String = "bench_press_barbell",
                     weight: Double? = 60, reps: Int? = 8, name: String = "Bench Press") -> SetRecord {
        var record = SetRecord(id: id, exerciseId: exercise, exerciseName: name, category: .strength,
                               weight: weight, reps: reps, duration: nil, performedAt: date, planId: plan, planName: name)
        record.workoutSessionID = session
        return record
    }

    func testSameDaySessionsCountAsOneTrainingDayAndDoNotSplitLegacyRows() {
        let calendar = calendar()
        let now = date(2026, 11, 9, 15, 0, calendar)
        let sets = [
            set("a", at: date(2026, 11, 5, 7, 30, calendar), session: "push|am"),
            set("b", at: date(2026, 11, 5, 18, 20, calendar), session: "push|pm", exercise: "squat", name: "Squat"),
            set("legacy-1", at: date(2026, 11, 2, 8, 0, calendar)),
            set("legacy-2", at: date(2026, 11, 2, 18, 0, calendar)),
            set("other", at: date(2026, 11, 3, 9, 0, calendar), plan: "legs"),
            set("future", at: date(2026, 11, 20, 9, 0, calendar), session: "future")
        ]
        let month = AccomplishmentShare.rhythm(sets: sets, focus: now, monthly: true, calendar: calendar, now: now)
        XCTAssertEqual(month.trainingDays, 3)
        XCTAssertEqual(month.sessions, 4)
        XCTAssertNotNil(month.asOf)
        XCTAssertEqual(month.days.count, 30)
        let fifth = month.days.first { calendar.component(.day, from: $0.date) == 5 }!
        XCTAssertEqual(fifth.sessions, 2)
        XCTAssertFalse(fifth.isFuture)
        let second = month.days.first { calendar.component(.day, from: $0.date) == 2 }!
        XCTAssertEqual(second.sessions, 1, "Legacy plan/day rows stay one session")
        let later = month.days.first { calendar.component(.day, from: $0.date) == 20 }!
        XCTAssertTrue(later.isFuture)
        XCTAssertEqual(later.sessions, 0)
        XCTAssertEqual(month.days.filter(\.isFuture).count, 21)
    }

    func testWeekBoundaryPartialRangeAndEmptyPeriodStayHonest() {
        let calendar = calendar()
        let now = date(2026, 11, 9, 15, 0, calendar)
        let sunday = set("sun", at: date(2026, 11, 8, 9, 0, calendar), session: "sun")
        let monday = set("mon", at: date(2026, 11, 9, 9, 0, calendar), session: "mon")
        let week = AccomplishmentShare.rhythm(sets: [sunday, monday], focus: now, monthly: false, calendar: calendar, now: now)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: week.start), 2)
        XCTAssertFalse(week.days.contains { calendar.isDate($0.date, inSameDayAs: date(2026, 11, 8, 9, 0, calendar)) })
        XCTAssertEqual(week.trainingDays, 1)
        XCTAssertEqual(week.sessions, 1)
        XCTAssertNotNil(week.asOf)
        XCTAssertEqual(week.days.filter { !$0.isFuture }.count, 1)

        let past = AccomplishmentShare.rhythm(sets: [], focus: date(2026, 10, 15, 12, 0, calendar), monthly: true, calendar: calendar, now: now)
        XCTAssertTrue(past.isEmpty)
        XCTAssertNil(past.asOf)
        XCTAssertEqual(past.trainingDays, 0)
        XCTAssertEqual(past.sessions, 0)
        XCTAssertTrue(past.days.allSatisfy { $0.sessions == 0 && !$0.isFuture })
    }

    func testCrossMidnightSessionIsOneSessionOnTwoTrainingDays() {
        let calendar = calendar()
        let now = date(2026, 11, 9, 15, 0, calendar)
        let sets = [
            set("late", at: date(2026, 11, 8, 23, 30, calendar), session: "night"),
            set("early", at: date(2026, 11, 9, 0, 20, calendar), session: "night")
        ]
        let month = AccomplishmentShare.rhythm(sets: sets, focus: now, monthly: true, calendar: calendar, now: now)
        XCTAssertEqual(month.sessions, 1)
        XCTAssertEqual(month.trainingDays, 2)
    }

    func testSelectedSessionDoesNotIncludeTheOtherWorkoutOnThatDay() {
        let calendar = calendar()
        let morning = date(2026, 11, 5, 7, 30, calendar)
        let evening = date(2026, 11, 5, 18, 20, calendar)
        let sets = [
            set("m", at: morning, session: "push|am", name: "Morning Push"),
            set("e", at: evening, session: "push|pm", exercise: "squat", name: "Evening Push")
        ]
        XCTAssertEqual(AccomplishmentShare.records(sessionID: "push|am", in: sets).map(\.id), ["m"])
        let single = AccomplishmentShare.sessionFact(records: AccomplishmentShare.records(sessionID: "push|am", in: sets),
                                                     name: "Morning Push", calendar: calendar)
        let morningSession: AccomplishmentShare.SessionKind = .single(id: "push|am")
        let morningPart: AccomplishmentShare.DayPart? = .morning
        XCTAssertEqual(single.kind, morningSession)
        XCTAssertEqual(single.setCount, 1)
        XCTAssertEqual(single.dayPart, morningPart)
        let mixed = AccomplishmentShare.sessionFact(records: sets, name: "Push", calendar: calendar)
        XCTAssertTrue(mixed.isAggregate)
        XCTAssertNil(mixed.dayPart)
        var privacy = AccomplishmentShare.Privacy()
        privacy.includeExactTime = true
        privacy.select(.coach)
        XCTAssertEqual(privacy.audience, AccomplishmentShare.Privacy.Audience.coach)
        XCTAssertTrue(privacy.includeExactTime, "Selecting coach must not clear an explicit choice")
        privacy.includeExactTime = false
        privacy.select(.coach)
        XCTAssertFalse(privacy.includeExactTime)
        let shown = AccomplishmentShare.present(mixed, privacy: privacy)
        XCTAssertFalse(shown.showsExactTime)
        XCTAssertFalse(shown.includesHeartRate)
        XCTAssertFalse(shown.includesBodyWeight)
        XCTAssertFalse(shown.includesLocation)
        XCTAssertFalse(shown.includesDisplayName)
        privacy.includePhoto = true
        XCTAssertTrue(AccomplishmentShare.present(single, privacy: privacy).includesPhoto)
        XCTAssertFalse(AccomplishmentShare.present(single, privacy: AccomplishmentShare.Privacy()).showsExactTime)
    }

    func testLegacyRowsAreLabeledAggregateInsteadOfAPretendSession() {
        let calendar = calendar()
        let sets = [
            set("a", at: date(2026, 11, 2, 8, 0, calendar)),
            set("b", at: date(2026, 11, 2, 18, 0, calendar))
        ]
        let fact = AccomplishmentShare.sessionFact(records: sets, name: "Push", calendar: calendar)
        XCTAssertTrue(fact.isAggregate)
        XCTAssertNil(fact.dayPart)
        XCTAssertEqual(fact.setCount, 2)
        XCTAssertFalse(AccomplishmentShare.present(fact, privacy: .init(includeExactTime: true)).showsExactTime)
    }

    func testComparableProgressRequiresSameExerciseSameRepsAndARealBaseline() {
        let calendar = calendar()
        let earlier = date(2026, 11, 1, 9, 0, calendar)
        let later = date(2026, 11, 8, 9, 0, calendar)
        let gain = [
            set("old", at: earlier, weight: 60, reps: 8),
            set("new", at: later, weight: 62.5, reps: 8)
        ]
        let progress = try! XCTUnwrap(AccomplishmentShare.bestProgress(sets: gain, names: ["bench_press_barbell": "Barbell Bench Press"], perDumbbell: [:]))
        XCTAssertEqual(progress.previousKg, 60)
        XCTAssertEqual(progress.currentKg, 62.5)
        XCTAssertEqual(progress.reps, 8)
        XCTAssertFalse(progress.perDumbbell)
        XCTAssertEqual(progress.previousDate, earlier)
        XCTAssertEqual(progress.currentDate, later)

        let fewerReps = [
            set("heavy-short", at: earlier, weight: 80, reps: 3),
            set("lighter-long", at: later, weight: 60, reps: 8)
        ]
        XCTAssertNil(AccomplishmentShare.bestProgress(sets: fewerReps, names: [:], perDumbbell: [:]))
        XCTAssertNil(AccomplishmentShare.bestProgress(sets: [gain[0]], names: [:], perDumbbell: [:]))

        let bells = [
            set("d1", at: earlier, exercise: "bench_press_dumbbell", weight: 20, reps: 10, name: "Dumbbell Bench Press"),
            set("d2", at: later, exercise: "bench_press_dumbbell", weight: 22.5, reps: 10, name: "Dumbbell Bench Press")
        ]
        let dumbbell = try! XCTUnwrap(AccomplishmentShare.bestProgress(sets: bells, names: [:], perDumbbell: ["bench_press_dumbbell": true]))
        XCTAssertEqual(dumbbell.previousKg, 20)
        XCTAssertEqual(dumbbell.currentKg, 22.5)
        XCTAssertTrue(dumbbell.perDumbbell)
    }
}
