import XCTest
@testable import Maso

@MainActor
final class WorkoutSaveFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_849_600)
    private func plan(_ id: String, source: PlanSource = .classics) -> Plan {
        Plan(id: id, name: id, steps: [PlanStep(id: "step-" + id, exerciseId: id, reps: 10, weight: 20, duration: nil)],
             createdAt: now, updatedAt: now, source: source)
    }
    private func store(_ plans: [Plan] = []) -> DataStore {
        var settings = UserSettings()
        settings.appStoreCountry = "USA"
        return DataStore(exercises: [], plans: plans, sets: [], settings: settings)
    }
    func testSourceAnchorOnlyBelongsToItsPendingRequest() {
        let data = store([plan("existing")])
        let flow = WorkoutSaveFlow()
        let incoming = [plan("day1")]
        flow.request(incoming, anchorID: "batch-button", data: data) { XCTFail("Unexpected limit") }
        XCTAssertEqual(flow.confirmationAnchorID, "batch-button")
        XCTAssertEqual(data.plans.count, 1)
        flow.commit(incoming, replacing: false, data: data) { XCTFail("Unexpected limit") }
        XCTAssertNil(flow.confirmationAnchorID)
        flow.request([plan("day2")], data: data) { XCTFail("Unexpected limit") }
        XCTAssertNil(flow.confirmationAnchorID, "Deferred requests must not reuse a vanished button anchor")
        XCTAssertNotNil(flow.candidate)
    }

    func testExistingWorkoutsRequireConfirmationWithoutSavingEarly() {
        for source in [PlanSource.ai, .classics] {
            let data = store([plan("existing")])
            let incoming = [plan("new", source: source)]
            let flow = WorkoutSaveFlow()
            flow.request(incoming, data: data) { XCTFail("Unexpected limit") }
            XCTAssertEqual(flow.candidate?.map(\.id), ["new"])
            XCTAssertEqual(data.plans.map(\.id), ["existing"])
        }
    }
    func testAppendKeepsExistingAndSavedStateIsIdempotent() {
        let data = store([plan("existing")])
        let incoming = [plan("day1"), plan("day2")]
        let flow = WorkoutSaveFlow()
        flow.commit(incoming, replacing: false, data: data) { XCTFail("Unexpected limit") }
        XCTAssertEqual(data.plans.map(\.name), ["existing", "day1", "day2"])
        XCTAssertTrue(data.areCoachPlansSaved(incoming))
        XCTAssertEqual(data.plans.last?.resolvedSource, .classics)
        flow.request(incoming, data: data) { XCTFail("Unexpected limit") }
        XCTAssertNil(flow.candidate)
        XCTAssertEqual(data.plans.count, 3)
    }
    func testReplacementSavesCompleteBatchAndPreservesItsSource() {
        let data = store([plan("existing")])
        let incoming = [plan("day1"), plan("day2")]
        WorkoutSaveFlow().commit(incoming, replacing: true, data: data) { XCTFail("Unexpected limit") }
        XCTAssertEqual(data.plans.map(\.name), ["day1", "day2"])
        XCTAssertTrue(data.areCoachPlansSaved(incoming))
        XCTAssertTrue(data.plans.allSatisfy { $0.resolvedSource == .classics })
    }
    func testOversizedBatchNeverClearsOrPartiallyAppends() {
        for replacing in [true, false] {
            let data = store([plan("existing")])
            let incoming = (0...DataStore.freeSavedPlansLimit).map { plan("day\($0)") }
            var limited = false
            WorkoutSaveFlow().commit(incoming, replacing: replacing, data: data) { limited = true }
            XCTAssertTrue(limited)
            XCTAssertEqual(data.plans.map(\.id), ["existing"])
        }
    }
    func testEmptyLibrarySavesImmediatelyAndPartialBatchOnlyAddsMissing() {
        let data = store()
        let incoming = [plan("day1"), plan("day2")]
        let flow = WorkoutSaveFlow()
        flow.request([incoming[0]], data: data) { XCTFail("Unexpected limit") }
        XCTAssertNil(flow.candidate)
        XCTAssertTrue(data.isCoachPlanSaved(incoming[0]))
        flow.commit(incoming, replacing: false, data: data) { XCTFail("Unexpected limit") }
        XCTAssertEqual(data.plans.count, 2)
        XCTAssertTrue(data.areCoachPlansSaved(incoming))
    }
}

@MainActor
final class CoachPreferenceChangeTests: XCTestCase {
    func testConfirmationOnlyUpdatesRequestedField() {
        var settings = UserSettings()
        settings.weeklyTrainingDays = 2
        settings.coachMemory = "Keep my notes"
        let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        var message = CoachMessage(role: .assistant, text: "")
        message.preferenceProposal = .init(changes: [.init(field: .weeklyTrainingDays, values: ["3"], sourceQuote: "three", previous: ["2"])])
        data.coachSession.messages.append(message)
        XCTAssertEqual(data.settings.weeklyTrainingDays, 2)
        data.resolveCoachPreferences(messageID: message.id, accept: true)
        XCTAssertEqual(data.settings.weeklyTrainingDays, 3)
        XCTAssertEqual(data.settings.coachMemory, "Keep my notes")
        data.resolveCoachPreferences(messageID: message.id, accept: true)
        XCTAssertEqual(data.settings.weeklyTrainingDays, 3)
    }
    func testDeclineAndStaleProposalDoNotOverwriteSettings() {
        for accept in [false, true] {
            var settings = UserSettings(); settings.weeklyTrainingDays = 4
            let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
            var message = CoachMessage(role: .assistant, text: "")
            message.preferenceProposal = .init(changes: [.init(field: .weeklyTrainingDays, values: ["3"], sourceQuote: "three", previous: ["2"])])
            data.coachSession.messages.append(message)
            data.resolveCoachPreferences(messageID: message.id, accept: accept)
            XCTAssertEqual(data.settings.weeklyTrainingDays, 4)
        }
    }
    func testInvalidValuesAndGoalSideEffects() {
        XCTAssertFalse(CoachPreferenceChange.Field.weeklyTrainingDays.valid(["8"]))
        XCTAssertFalse(CoachPreferenceChange.Field.defaultRestSeconds.valid(["16"]))
        XCTAssertFalse(CoachPreferenceChange.Field.keepScreenAwakeDuringWorkout.valid(["yes"]))
        XCTAssertFalse(CoachPreferenceChange.Field.availableEquipment.valid(["invented"]))
        var settings = UserSettings(); settings.defaultRestSeconds = 75
        CoachPreferenceChange(field: .trainingGoalKind, values: ["getStronger"], sourceQuote: "stronger").apply(to: &settings)
        XCTAssertEqual(settings.trainingGoalKind, .getStronger)
        XCTAssertEqual(settings.defaultRestSeconds, 75)
    }
}

@MainActor
final class MuscleRegionRecoveryTests: XCTestCase {
    func testRegionUsesSameExpandedMusclesAsRecoveryTimeline() {
        let map: [MuscleGroup: Double] = [.upperAbs: 0.42, .lowerAbs: 0.2, .obliques: 0.42, .serratus: 0.1]
        let abs = MuscleBodyRegion(node: "abs_center", muscles: [.abs], fatigueEligible: true)
        let obliques = MuscleBodyRegion(node: "obliques_left", muscles: [.obliques, .serratus], fatigueEligible: true)
        XCTAssertEqual(abs.fatigue(in: map), 0.42, accuracy: 0.0001)
        XCTAssertEqual(abs.fatigue(in: map), obliques.fatigue(in: map), accuracy: 0.0001)
        XCTAssertEqual(MuscleBodyRegion(node: "head", muscles: [.abs], fatigueEligible: false).fatigue(in: map), 0)
    }
}

@MainActor
final class WorkoutHistoryDeletionTests: XCTestCase {
    func testDeletingOneWorkoutPreservesOtherDaysAndPlans() {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86400)
        let plan = Plan(id: "keep", name: "Keep", steps: [], createdAt: day, updatedAt: day)
        let records = [
            SetRecord(id: "delete", exerciseId: "x", exerciseName: "X", category: .strength, reps: 8, performedAt: day.addingTimeInterval(3600), planId: "keep"),
            SetRecord(id: "other-plan", exerciseId: "x", exerciseName: "X", category: .strength, reps: 8, performedAt: day, planId: "other"),
            SetRecord(id: "other-day", exerciseId: "x", exerciseName: "X", category: .strength, reps: 8, performedAt: day.addingTimeInterval(-86400), planId: "keep")
        ]
        let data = DataStore(exercises: [], plans: [plan], sets: records, settings: UserSettings())
        data.deleteSession(planId: "keep", day: day.addingTimeInterval(7200))
        XCTAssertEqual(Set(data.sets.map(\.id)), ["other-plan", "other-day"])
        XCTAssertEqual(data.plans.map(\.id), ["keep"])
    }

    func testDeletedHealthRecordDoesNotReturnOnRefresh() throws {
        let now = Date()
        let record = ExternalWorkout(id: "health", activity: .walking, startedAt: now.addingTimeInterval(-3600), endedAt: now.addingTimeInterval(-1800), duration: 1800, distanceMeters: nil, kilocalories: nil, sourceBundleID: "com.apple.health", sourceName: "Health")
        var settings = UserSettings()
        settings.externalWorkoutImportEnabled = true
        let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
        data.replaceExternalWorkoutSnapshot([record], now: now)
        XCTAssertEqual(data.recordedExternalWorkouts(now: now).count, 1)
        data.deleteExternalWorkout(id: record.id)
        data.replaceExternalWorkoutSnapshot([record], now: now)
        XCTAssertTrue(data.recordedExternalWorkouts(now: now).isEmpty)
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(data.settings))
        XCTAssertEqual(restored.deletedExternalWorkoutIDs, [record.id])
    }
}

@MainActor
final class NotificationLanguageTests: XCTestCase {
    private let keys = ["Recovered and ready", "Your muscles miss you", "Let's get back to it",
                        "You're recovered — a quick session keeps your momentum going.",
                        "Time to eat", "Fuel your muscles with a balanced meal",
                        "Your muscles are off duty. Put your phone down and sleep well.",
                        "Time's up", "Time to switch exercise", "Rest's up — next set"]

    func testNotificationCopyFollowsEachOfTheTwelveAppLanguages() throws {
        let manager = LanguageManager.shared
        let original = manager.selectedLanguage
        defer { manager.selectedLanguage = original }
        XCTAssertEqual(SupportedLanguage.shipped.count, 12)
        for language in SupportedLanguage.allCases {
            manager.selectedLanguage = language
            XCTAssertEqual(LanguageManager.currentLanguageCode, language.rawValue)
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let text = AppNotificationText.string(key)
                XCTAssertEqual(text, bundle.localizedString(forKey: key, value: nil, table: "Localizable"), "\(language): \(key)")
                XCTAssertFalse(text.isEmpty)
                if language != .en { XCTAssertNotEqual(text, key, "Missing translation: \(language) \(key)") }
            }
        }
    }

    func testEnglishSelectionOverridesStalePersistedChineseSetting() {
        let manager = LanguageManager.shared
        let original = manager.selectedLanguage
        defer { manager.selectedLanguage = original }
        var settings = UserSettings()
        settings.language = "zh-Hans"
        manager.selectedLanguage = .en
        XCTAssertEqual(AppNotificationText.string("Time to eat"), "Time to eat")
        XCTAssertEqual(AppNotificationText.string("Your muscles are off duty. Put your phone down and sleep well."),
                       "Your muscles are off duty. Put your phone down and sleep well.")
        manager.selectedLanguage = .ja
        XCTAssertEqual(AppNotificationText.string("Time to eat"), "食事の時間です")
        manager.selectedLanguage = .en
        XCTAssertEqual(AppNotificationText.string("Rest's up — next set"), "Rest's up — next set")
        XCTAssertEqual(settings.language, "zh-Hans")
    }
}
