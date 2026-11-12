import XCTest
import SceneKit
@testable import Maso

@MainActor
final class OnboardingTests: XCTestCase {
    func testCoachIntroTipOnlyForNewlyCompletedOnboardingAndVisibleHome() throws {
        XCTAssertFalse(CoachIntroTipPolicy.shouldOffer(pending: nil, onboardingCompleted: true, homeAvailable: true))
        XCTAssertFalse(CoachIntroTipPolicy.shouldOffer(pending: false, onboardingCompleted: true, homeAvailable: true))
        XCTAssertFalse(CoachIntroTipPolicy.shouldOffer(pending: true, onboardingCompleted: false, homeAvailable: true))
        XCTAssertFalse(CoachIntroTipPolicy.shouldOffer(pending: true, onboardingCompleted: true, homeAvailable: false))
        XCTAssertTrue(CoachIntroTipPolicy.shouldOffer(pending: true, onboardingCompleted: true, homeAvailable: true))
        var settings = UserSettings()
        settings.coachIntroTipPending = true
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.coachIntroTipPending, true)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        old.removeValue(forKey: "coachIntroTipPending")
        let migrated = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(migrated.coachIntroTipPending, "Old users must not receive a retroactive tooltip")
    }

    func testCoachTipsWaitForReopenAndPhotoTipRequiresThreeWorkouts() {
        XCTAssertFalse(CoachIntroTipPolicy.shouldOffer(pending: true, onboardingCompleted: true, homeAvailable: true, reopened: false))
        XCTAssertTrue(CoachIntroTipPolicy.shouldOffer(pending: true, onboardingCompleted: true, homeAvailable: true, reopened: true))
        XCTAssertFalse(CoachIntroTipPolicy.shouldOfferPhoto(seen: nil, onboardingCompleted: true, homeAvailable: true, reopened: true, shownThisSession: false, workoutCount: 2))
        XCTAssertTrue(CoachIntroTipPolicy.shouldOfferPhoto(seen: nil, onboardingCompleted: true, homeAvailable: true, reopened: true, shownThisSession: false, workoutCount: 3))
        XCTAssertFalse(CoachIntroTipPolicy.shouldOfferPhoto(seen: true, onboardingCompleted: true, homeAvailable: true, reopened: true, shownThisSession: false, workoutCount: 3))
        XCTAssertFalse(CoachIntroTipPolicy.shouldOfferPhoto(seen: nil, onboardingCompleted: true, homeAvailable: true, reopened: true, shownThisSession: true, workoutCount: 3))
    }

    func testHomeEquipmentMemoryPersistenceAndOldProfilesRemainCompatible() throws {
        var draft = OnboardingDraft()
        XCTAssertEqual(draft.equipment.displayedEnvironment, .gym)
        draft.equipment.select(.home)
        XCTAssertEqual(draft.equipment.availableEquipment, ["bodyweight"])
        draft.equipment.homeEquipment = [.dumbbell, .flatBench]
        draft.equipment.select(.bodyweight)
        XCTAssertEqual(draft.equipment.availableEquipment, ["bodyweight"])
        draft.equipment.select(.gym)
        XCTAssertTrue(draft.equipment.availableEquipment.isEmpty)
        let savedGym = draft.applying(to: UserSettings())
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(savedGym))
        var edit = TrainingPreferenceDraft(settings: restored)
        edit.equipment.select(.home)
        XCTAssertEqual(edit.equipment.homeEquipment, [.dumbbell, .flatBench])
        var savedHome = restored
        edit.apply(to: &savedHome)
        XCTAssertEqual(savedHome.trainingEnvironment, .home)
        XCTAssertEqual(Set(savedHome.availableEquipment), ["dumbbell", "bench_flat"])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(savedHome)) as? [String: Any])
        legacy.removeValue(forKey: "trainingEnvironment")
        legacy.removeValue(forKey: "homeEquipment")
        legacy.removeValue(forKey: "gymEquipment")
        legacy["availableEquipment"] = ["dumbbell"]
        var old = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.trainingEnvironment)
        XCTAssertNil(old.homeEquipment)
        TrainingPreferenceDraft(settings: old).apply(to: &old)
        XCTAssertEqual(old.availableEquipment, ["dumbbell"])
        XCTAssertNil(old.trainingEnvironment, "Editing unrelated fields must not invent a location for old profiles")
    }

    func testHomePreviewAndCoachUseOnlyDeclaredEquipment() throws {
        let policy = ExerciseSelectionPolicy.shared
        let combinations: [Set<HomeTrainingEquipment>] = [[], [.dumbbell], [.dumbbell, .flatBench], [.pullupBar, .bands]]
        for equipment in combinations {
            var draft = OnboardingDraft()
            draft.equipment.select(.home)
            draft.equipment.homeEquipment = equipment
            let settings = draft.applying(to: UserSettings())
            let plans = draft.preview(settings: UserSettings(), exercises: ExerciseLibrary.byId)
            XCTAssertFalse(plans.isEmpty)
            for step in plans.flatMap(\.steps) {
                let exercise = try XCTUnwrap(ExerciseLibrary.byId[step.exerciseId])
                XCTAssertTrue(policy.equipmentAllows(exercise, selected: Set(settings.availableEquipment), environment: .home), exercise.id)
            }
            let payload = DataStore(exercises: [], plans: [], sets: [], settings: settings).buildAIPayload()
            XCTAssertEqual(payload.trainingEnvironment, .home)
            XCTAssertEqual(payload.selectionEquipment, settings.availableEquipment)
            XCTAssertTrue(payload.equipmentLine.contains("at home"))
            XCTAssertFalse(payload.equipmentLine.contains("no restriction"))
            if equipment.isEmpty { XCTAssertTrue(payload.equipmentLine.contains("bodyweight only")) }
        }
    }

    func testWeekdaySelectionCountPersistenceAndCoachStayInSync() throws {
        var draft = OnboardingDraft()
        XCTAssertEqual(draft.weekdays, [1, 3, 5])
        draft.weekdays = [2, 4]
        XCTAssertEqual(draft.days, 2)
        draft.days = 2
        XCTAssertEqual(draft.weekdays, [2, 4], "Committing an unchanged count must preserve manually chosen weekdays")
        let settings = draft.applying(to: UserSettings())
        XCTAssertEqual(settings.weeklyTrainingDays, 2)
        XCTAssertEqual(settings.trainingWeekdays, [2, 4])
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.trainingWeekdays, [2, 4])
        let payload = DataStore(exercises: [], plans: [], sets: [], settings: settings).buildAIPayload()
        XCTAssertTrue(payload.trainingScheduleLine.contains("Tuesday, Thursday"))
        var updated = settings
        updated.weeklyTrainingDays = 4
        XCTAssertEqual(updated.trainingWeekdays, TrainingWeekSchedule.automatic(days: 4))
        for count in 1...7 {
            draft.days = count
            XCTAssertEqual(draft.weekdays.count, count)
            XCTAssertTrue(draft.weekdays.allSatisfy { (1...7).contains($0) })
        }
        draft.weekdays = []
        XCTAssertEqual(draft.days, 0)
        XCTAssertTrue(draft.preview(settings: settings, exercises: [:]).isEmpty)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        old.removeValue(forKey: "trainingWeekdays")
        XCTAssertNil(try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: old)).trainingWeekdays)
    }

    func testSixAndSevenDaySchedulesReuseThreeCompleteRoutinesWithinFreeLimit() {
        for count in [6, 7] {
            var draft = OnboardingDraft()
            draft.days = count
            let plans = draft.preview(settings: UserSettings(), exercises: ExerciseLibrary.byId)
            XCTAssertEqual(plans.count, 3)
            XCTAssertTrue(plans.allSatisfy { !$0.steps.isEmpty })
            XCTAssertEqual(draft.applying(to: UserSettings()).trainingWeekdays?.count, count)
        }
    }

    func testOnboardingOffersFourWordsAndLeavesStoredGoalsUntouched() throws {
        XCTAssertEqual(OnboardingDraft.Goal.allCases.map(\.kind), [.buildMuscle, .getStronger, .loseFat, .generalFitness])
        XCTAssertEqual(OnboardingDraft().goal.kind, .buildMuscle)
        XCTAssertFalse(OnboardingDraft.Goal.allCases.contains { $0.kind == .endurance })
        XCTAssertEqual(TrainingGoalKind.allCases, [.buildMuscle, .getStronger, .loseFat, .generalFitness, .endurance])
        let prior = LanguageManager.shared.selectedLanguage
        defer { LanguageManager.shared.selectedLanguage = prior }
        let words: [SupportedLanguage: [String]] = [
            .en: ["Build muscle", "Get stronger", "Lose fat", "Stay fit & healthy"],
            .zhHans: ["增肌", "增强力量", "减脂", "保持健康"],
            .zhHant: ["增肌", "增強力量", "減脂", "保持健康"],
        ]
        for (language, expected) in words {
            LanguageManager.shared.selectedLanguage = language
            let labels = OnboardingDraft.Goal.allCases.map { NSLocalizedString($0.titleKey, comment: "") }
            XCTAssertEqual(labels, expected, language.rawValue)
        }
        LanguageManager.shared.selectedLanguage = .zhHans
        XCTAssertEqual(NSLocalizedString("Get stronger", comment: ""), "增力")
        XCTAssertEqual(NSLocalizedString("Lose fat / get lean", comment: ""), "减脂塑形")
        var stored = UserSettings()
        stored.trainingGoalKind = .endurance
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(decoded.trainingGoalKind, .endurance)
        XCTAssertEqual(OnboardingDraft().applying(to: stored).trainingGoalKind, .buildMuscle)
    }

    func testThreeGoalsAndDraftKeepUncollectedAndUnrelatedPreferences() throws {
        var original = UserSettings()
        original.coachMemory = "existing restriction"
        original.weight = 62
        original.age = 41
        original.gender = .female
        original.weightUnit = .lb
        var draft = OnboardingDraft()
        XCTAssertEqual(draft.goal, .buildMuscle)
        XCTAssertTrue(draft.focus.isEmpty, "Empty focus is the selected Full body option")
        draft.goal = .generalFitness
        draft.toggle(.upperChest)
        draft.toggle(.lats)
        XCTAssertEqual(draft.focus, [.chest, .back])
        draft.toggle(.midChest)
        XCTAssertEqual(draft.focus, [.back], "Any second hit within the same displayed group deselects it")
        draft.equipment.select(.bodyweight)
        draft.days = 5
        draft.minutes = 30
        let settings = draft.applying(to: original)
        XCTAssertEqual(settings.wantStrengthen, [.back])
        XCTAssertEqual(settings.trainingGoalKind, .generalFitness)
        XCTAssertEqual(settings.defaultSetsPerExercise, 2)
        XCTAssertEqual(settings.trainingSessionMinutes, 30)
        XCTAssertEqual(settings.availableEquipment, ["bodyweight"])
        XCTAssertEqual(settings.weeklyTrainingDays, 5)
        XCTAssertEqual(settings.age, original.age)
        XCTAssertEqual(settings.weight, original.weight)
        XCTAssertEqual(settings.gender, original.gender)
        XCTAssertEqual(settings.weightUnit, .lb)
        XCTAssertEqual(settings.coachMemory, original.coachMemory)
        let fresh = draft.applying(to: UserSettings())
        XCTAssertNil(fresh.weight)
        XCTAssertNil(fresh.age)
        XCTAssertNil(fresh.gender)
    }

    func testSameProfileGoalsChangeTheOfflinePlan() throws {
        let library = ExerciseLibrary.byId
        func plans(for goal: OnboardingDraft.Goal, minutes: Int = 45, environment: TrainingEnvironment = .gym) -> [Plan] {
            var draft = OnboardingDraft()
            draft.goal = goal
            draft.minutes = minutes
            draft.equipment.select(environment)
            return draft.preview(settings: UserSettings(), exercises: library)
        }
        let muscle = plans(for: .buildMuscle)
        let strong = plans(for: .getStronger)
        let fat = plans(for: .loseFat)
        let fit = plans(for: .generalFitness)
        func compoundReps(_ plans: [Plan]) -> Set<Int> {
            Set(plans.flatMap(\.steps).compactMap { step in
                guard library[step.exerciseId]?.mechanic == .compound else { return nil }
                return step.reps
            })
        }
        XCTAssertEqual(compoundReps(strong), [5])
        XCTAssertEqual(compoundReps(muscle), [8])
        XCTAssertEqual(compoundReps(fat), [8])
        XCTAssertEqual(compoundReps(fit), [8])
        func rests(_ plans: [Plan]) -> Set<Int> { Set(plans.flatMap(\.steps).map(\.restBetweenSets)) }
        XCTAssertEqual(rests(strong), [180])
        XCTAssertEqual(rests(muscle), [90])
        XCTAssertEqual(rests(fat), [60])
        XCTAssertEqual(rests(fit), [75])
        XCTAssertTrue(fit.flatMap(\.steps).allSatisfy { $0.sets <= 2 })
        XCTAssertTrue(muscle.flatMap(\.steps).allSatisfy { $0.sets >= 3 })
        func isolations(_ plans: [Plan]) -> Int {
            plans.flatMap(\.steps).filter { library[$0.exerciseId]?.mechanic == .isolation }.count
        }
        XCTAssertLessThan(isolations(fat), isolations(muscle))
        XCTAssertTrue(fat.flatMap(\.steps).contains { library[$0.exerciseId]?.mechanic == .compound })
        XCTAssertTrue([muscle, strong, fat, fit].flatMap { $0.flatMap(\.steps) }.allSatisfy { $0.weight == nil && $0.setWeights == nil })
        var fatDraft = OnboardingDraft()
        fatDraft.goal = .loseFat
        let payload = DataStore(exercises: [], plans: [], sets: [], settings: fatDraft.applying(to: UserSettings())).buildAIPayload()
        XCTAssertTrue(payload.acsmGuideline.contains("spot reduction"))
        XCTAssertFalse(payload.acsmGuideline.contains("cardio circuit"))
        XCTAssertNil(payload.weightKg)
    }

    func testSameGoalFollowsEquipmentAndDurationWithoutInventingExperience() throws {
        let library = ExerciseLibrary.byId
        func ids(minutes: Int, environment: TrainingEnvironment) -> [String] {
            var draft = OnboardingDraft()
            draft.goal = .buildMuscle
            draft.minutes = minutes
            draft.equipment.select(environment)
            return draft.preview(settings: UserSettings(), exercises: library).flatMap { $0.steps.map(\.exerciseId) }
        }
        XCTAssertLessThan(Set(ids(minutes: 30, environment: .gym)).count, Set(ids(minutes: 90, environment: .gym)).count)
        let gym = Set(ids(minutes: 45, environment: .gym))
        let body = Set(ids(minutes: 45, environment: .bodyweight))
        XCTAssertNotEqual(gym, body)
        let policy = ExerciseSelectionPolicy.shared
        var draft = OnboardingDraft()
        draft.goal = .loseFat
        draft.equipment.select(.bodyweight)
        let settings = draft.applying(to: UserSettings())
        XCTAssertNil(settings.weight)
        XCTAssertNil(settings.age)
        for id in ids(minutes: 45, environment: .bodyweight) {
            let exercise = try XCTUnwrap(library[id])
            XCTAssertTrue(policy.equipmentAllows(exercise, selected: Set(settings.availableEquipment), environment: .bodyweight), id)
        }
    }

    func testPreviewIsOfflineRespectsEquipmentAndHasNoInventedLoads() throws {
        let library = Dictionary(uniqueKeysWithValues: ExerciseLibrary.all.map { ($0.id, $0) })
        for environment in TrainingEnvironment.allCases {
            for goal in OnboardingDraft.Goal.allCases {
                var draft = OnboardingDraft()
                draft.goal = goal
                draft.equipment.select(environment)
                draft.minutes = 30
                let plans = draft.preview(settings: UserSettings(), exercises: library)
                XCTAssertFalse(plans.isEmpty)
                XCTAssertLessThanOrEqual(plans.count, draft.days)
                for plan in plans {
                    XCTAssertEqual(plan.resolvedSource, .builtIn)
                    XCTAssertLessThanOrEqual(plan.steps.count, 3)
                    for step in plan.steps {
                        XCTAssertNil(step.weight)
                        XCTAssertNil(step.setWeights)
                        XCTAssertNotNil(library[step.exerciseId])
                        XCTAssertEqual(step.restBetweenSets, goal.kind.recommendedRestSeconds())
                        XCTAssertTrue(ExerciseSelectionPolicy.shared.equipmentAllows(try XCTUnwrap(library[step.exerciseId]), selected: Set(draft.equipment.availableEquipment), environment: environment))
                    }
                }
            }
        }
    }

    func testSessionLengthPersistsIntoPreviewAndCoachWithLongerWorkouts() throws {
        let library = ExerciseLibrary.byId
        XCTAssertEqual(OnboardingDraft().minutes, 45)
        var counts: [Int: Int] = [:]
        for minutes in [30, 45, 60, 90] {
            var draft = OnboardingDraft()
            draft.minutes = minutes
            let settings = draft.applying(to: UserSettings())
            let restored = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(restored.trainingSessionMinutes, minutes)
            let payload = DataStore(exercises: [], plans: [], sets: [], settings: restored).buildAIPayload()
            XCTAssertEqual(payload.trainingSessionMinutes, minutes)
            XCTAssertTrue(payload.trainingSessionLengthLine.contains("\(minutes) minutes"))
            let preview = draft.preview(settings: UserSettings(), exercises: library)
            XCTAssertFalse(preview.isEmpty)
            XCTAssertTrue(preview.allSatisfy { !$0.steps.isEmpty && $0.steps.count <= settings.exercisesPerSession })
            counts[minutes] = preview.map { $0.steps.count }.max()
        }
        XCTAssertGreaterThan(try XCTUnwrap(counts[90]), try XCTUnwrap(counts[60]))
        let old = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings()).buildAIPayload()
        XCTAssertTrue(old.trainingSessionLengthLine.isEmpty)
        for minutes in [25, 40] {
            XCTAssertTrue(TrainingSessionLength.options(including: minutes).contains(minutes))
            var original = UserSettings()
            original.trainingSessionMinutes = minutes
            let draft = TrainingPreferenceDraft(settings: original)
            var updated = original
            draft.apply(to: &updated)
            XCTAssertEqual(updated.trainingSessionMinutes, minutes)
        }
    }

    func testOptionalDurationMigratesAndRoundTripsWithoutChangingOldProfiles() throws {
        let settings = UserSettings()
        let encoded = try JSONEncoder().encode(settings)
        let roundTrip = try JSONDecoder().decode(UserSettings.self, from: encoded)
        XCTAssertNil(roundTrip.trainingSessionMinutes)
        var changed = settings
        changed.trainingSessionMinutes = 40
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(changed)).trainingSessionMinutes, 40)
        var draft = TrainingPreferenceDraft(settings: changed)
        draft.trainingSessionMinutes = 60
        draft.apply(to: &changed)
        XCTAssertEqual(changed.trainingSessionMinutes, 60)
    }
}
