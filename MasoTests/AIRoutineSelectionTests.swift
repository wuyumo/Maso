import XCTest
@testable import Maso

@MainActor
final class AIRoutineSelectionTests: XCTestCase {
    private var service: AIWorkoutService { .shared }

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(ExerciseLibrary.byId[id])
    }

    private func payload() -> AIPayload {
        DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings()).buildAIPayload()
    }

    func testPinnedPreferenceReachesDailyWeeklyPromptsAndSurvivesAIParsing() async throws {
        var p = payload()
        p.selectionFavoriteIDs = ["bench_press_dumbbell"]
        let candidates = service.routineCandidates(payload: p, library: ExerciseLibrary.all)
        XCTAssertTrue(candidates.contains { $0.id == "bench_press_dumbbell" })
        XCTAssertTrue(service.buildPrompt(payload: p, library: candidates).contains("PINNED EXERCISE PRIORITY: bench_press_dumbbell"))
        XCTAssertTrue(service.routineContractProbe(payload: p, count: 3, maxExercises: 4).contains("PINNED EXERCISE PRIORITY: bench_press_dumbbell"))
        let plans = try await service.requestValidatedPlans(candidates: [try exercise("bench_press_barbell"), try exercise("bench_press_dumbbell")], expectedCount: 1, maxExercises: 1, single: true, preferredIDs: p.selectionFavoriteIDs) { _ in
            #"{"name":"Pinned","steps":[{"exercise_id":"bench_press_dumbbell","sets":3,"reps":10,"weight_kg":20}]}"#
        }
        XCTAssertEqual(plans.first?.steps.first?.exerciseId, "bench_press_dumbbell")
        XCTAssertEqual(plans.first?.steps.first?.weight, 20)
    }

    func testQuickWorkoutDraftKeepsOneOffConstraintsAndFiltersTrainingType() throws {
        var draft = CoachQuickWorkoutDraft()
        draft.kind = "cardio"
        draft.minutes = 15
        draft.equipment = "bodyweight"
        draft.requirements = "Avoid jumping; not my weekly plan"
        let request = draft.request
        XCTAssertEqual(request.durationMinutes, 15)
        XCTAssertEqual(request.equipmentOverride, ["body_only"])
        XCTAssertTrue(request.sourceQuote.contains(draft.requirements))
        XCTAssertFalse(request.matches(try exercise("bench_press_barbell")))
        let cardio = try XCTUnwrap(ExerciseLibrary.all.first { $0.category == .cardio })
        XCTAssertTrue(request.matches(cardio))
        draft.kind = "mobility"
        XCTAssertFalse(draft.request.matches(cardio))
    }

    func testSingleWorkoutRequestsInAllTwelveLanguagesDoNotBecomeWeeklyPreferences() throws {
        let requests = ["Give me a 30-minute abs workout", "给我一个30分钟的腹肌训练", "給我一個30分鐘的腹肌訓練",
            "30分の腹筋トレーニングを作って", "30분 복근 운동을 만들어 줘", "Dame un entrenamiento abdominal de 30 minutos",
            "Une séance abdos de 30 minutes", "Ein Bauchtraining für 30 Minuten", "Un allenamento addominale di 30 minuti",
            "Um treino abdominal de 30 minutos", "Тренировка на пресс на 30 минут", "أريد تمرين البطن لمدة ٣٠ دقيقة"]
        for text in requests {
            let request = try XCTUnwrap(CoachSessionRequest.local(in: text), text)
            XCTAssertEqual(request.durationMinutes, 30, text)
            XCTAssertEqual(request.focusMuscles, [.core], text)
            XCTAssertEqual(request.sourceQuote, text)
        }
        for text in ["Create my weekly routines", "一周练三次", "Usually train for 30 minutes", "30分钟腹肌训练够不够？", "不要给我30分钟腹肌训练"] {
            XCTAssertNil(CoachSessionRequest.local(in: text), text)
        }
        XCTAssertEqual(CoachSessionRequest.minutes(in: "一个半小时"), 90)
        XCTAssertEqual(CoachSessionRequest.minutes(in: "1.5 hours"), 90)
    }

    func testSingleWorkoutPromptAndCandidatePoolKeepFocusedTraining() throws {
        var p = payload()
        p.focusNote = "给我一个30分钟的腹肌训练"
        p.trainingSessionMinutes = 30
        p.sessionSetRestSeconds = 60
        p.sessionTransitionRestSeconds = 90
        let request = try XCTUnwrap(CoachSessionRequest.local(in: p.focusNote!))
        let candidates = service.routineCandidates(payload: p, library: ExerciseLibrary.all.filter(request.matches), query: p.focusNote!)
        XCTAssertGreaterThan(service.routineStepCount(candidates, requested: 5), 2)
        XCTAssertTrue(candidates.allSatisfy(request.matches))
        XCTAssertTrue(candidates.allSatisfy { ExerciseSelectionPolicy.shared.tier(for: $0) != .specialist })
        let prompt = service.buildPrompt(payload: p, library: candidates, maxExercises: 5, sessionRequest: request)
        XCTAssertTrue(prompt.contains("SINGLE WORKOUT"))
        XCTAssertTrue(prompt.contains("Set rest is 60s; exercise transition rest is 90s"))
        XCTAssertTrue(prompt.contains("30 minutes"))
        XCTAssertFalse(prompt.contains("At 1-3 days/wk make this a full-body session"))
        XCTAssertFalse(prompt.contains("MUSCLE BALANCE: no more than 2"))
        XCTAssertTrue(service.buildPrompt(payload: p, library: candidates).contains("MUSCLE BALANCE: no more than 2"))
    }

    func testSingleWorkoutKeepsWeeklyDraftPreferencesAndSavedPlansAndCanStartUnsaved() throws {
        let weekly = RecommendedPrograms.plans(forDays: 3, now: Date(), byId: ExerciseLibrary.byId)
        var settings = UserSettings(); settings.weeklyTrainingDays = 3; settings.trainingSessionMinutes = 60
        let data = DataStore(exercises: ExerciseLibrary.all, plans: weekly, sets: [], settings: settings)
        data.coachSession.currentRoutines = weekly
        data.coachSession.versionStack = [weekly]
        let request = CoachSessionRequest(sourceQuote: "30-minute abs workout", durationMinutes: 30, focusMuscles: [.core])
        let ids = ["crunch", "plank", "dead_bug", "leg_raise_lying"]
        let plan = Plan(id: "plan-ai-single-test", name: "Core", steps: ids.enumerated().map {
            PlanStep(id: "single-\($0.offset)", exerciseId: $0.element, sets: 3, reps: 12)
        }, createdAt: Date(), updatedAt: Date(), autoGenerated: true, source: .ai)
        data.finishCoachSession(plan: plan, request: request)
        let result = try XCTUnwrap(data.coachSession.currentSessionPlan)
        XCTAssertEqual(result.steps.count, 4) // no weekly same-muscle cap
        XCTAssertEqual(data.plans, weekly)
        XCTAssertEqual(data.coachSession.currentRoutines, weekly)
        XCTAssertEqual(data.coachSession.versionStack, [weekly])
        XCTAssertEqual(data.settings.weeklyTrainingDays, 3)
        XCTAssertEqual(data.settings.trainingSessionMinutes, 60)
        XCTAssertEqual(result.constraints?.first(where: { $0.kind == .duration })?.value, "30")
        XCTAssertTrue(data.coachSession.messages.last?.isSingleWorkout == true)
        XCTAssertNil(data.coachSession.messages.last?.memoryProposal)
        XCTAssertFalse(data.coachSession.isGenerating)
        XCTAssertTrue(result.steps.allSatisfy { $0.weight == nil })
        let player = TrainingSessionStore(completionSound: {})
        player.start(planId: result.id, plan: result, segments: expandPlan(result, exById: data.exById), source: "ai")
        XCTAssertEqual(player.session?.planId, result.id)
        XCTAssertEqual(player.plan, result)
        XCTAssertFalse(player.segments.isEmpty)
        XCTAssertEqual(data.plans, weekly)
        player.end()
    }

    func testFailedOrWrongFocusSingleWorkoutNeverSubstitutesWeeklyCards() throws {
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
        let request = CoachSessionRequest(sourceQuote: "abs workout", focusMuscles: [.core])
        let wrong = Plan(id: "wrong-focus", name: "Chest", steps: [.init(id: "s", exerciseId: "bench_press_barbell", sets: 3)], createdAt: Date(), updatedAt: Date())
        for plan in [wrong, nil] {
            data.finishCoachSession(plan: plan, request: request)
            XCTAssertNil(data.coachSession.currentSessionPlan)
            XCTAssertNil(data.coachSession.messages.last?.plans)
            XCTAssertTrue(data.coachSession.currentRoutines.isEmpty)
            XCTAssertNotNil(data.coachSession.fallbackNote)
            XCTAssertFalse(data.coachSession.isGenerating)
        }
    }

    func testHomeAndBodyweightProfilesConstrainTheActualAICandidatePool() {
        var profile = payload()
        profile.trainingEnvironment = .home
        profile.selectionEquipment = ["dumbbell"]
        let home = service.routineCandidates(payload: profile, library: ExerciseLibrary.all)
        XCTAssertFalse(home.isEmpty)
        XCTAssertTrue(home.contains { $0.id == "floor_press_dumbbell" })
        XCTAssertFalse(home.contains { $0.id == "bench_press_dumbbell" })
        profile.trainingEnvironment = .bodyweight
        profile.selectionEquipment = ["bodyweight"]
        let bodyweight = service.routineCandidates(payload: profile, library: ExerciseLibrary.all)
        XCTAssertFalse(bodyweight.isEmpty)
        XCTAssertFalse(bodyweight.contains { $0.id == "bench_press_dumbbell" })
        let requested = service.routineCandidates(payload: profile, library: ExerciseLibrary.all, query: "Only dumbbells")
        XCTAssertTrue(requested.contains { $0.id == "floor_press_dumbbell" })
        XCTAssertFalse(requested.contains { $0.id == "bench_press_dumbbell" })
    }

    func testDefaultAICatalogUsesFamiliarVariantsAndRespectsEquipment() throws {
        var profile = payload()
        profile.selectionEquipment = ["dumbbell"]
        let candidates = service.routineCandidates(payload: profile, library: ExerciseLibrary.all)
        let policy = ExerciseSelectionPolicy.shared
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { policy.tier(for: $0) != .specialist })
        XCTAssertTrue(candidates.allSatisfy { policy.equipmentAllows($0, selected: ["dumbbell"]) })
        XCTAssertTrue(candidates.contains { $0.id == "bench_press_dumbbell" })
        XCTAssertTrue(candidates.contains { $0.id == "rdl_dumbbell" })
        XCTAssertFalse(candidates.contains { $0.id == "pull_up_one_arm" })
        let groupCounts = Dictionary(grouping: candidates, by: policy.programmingGroupID).mapValues(\.count)
        XCTAssertTrue(groupCounts.values.allSatisfy { $0 <= 2 })
    }

    func testRevisionPreservesOnlyTheExistingSpecialistID() throws {
        let id = "pull_up_one_arm"
        let normal = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all)
        XCTAssertFalse(normal.contains { $0.id == id })
        let revised = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all, preservingIDs: [id])
        XCTAssertTrue(revised.contains { $0.id == id })
        XCTAssertTrue(revised.filter { ExerciseSelectionPolicy.shared.tier(for: $0) == .specialist }.allSatisfy { $0.id == id })
        let thirdVersion = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all,
            preservingIDs: ["bench_press_smith"])
        XCTAssertTrue(thirdVersion.contains { $0.id == "bench_press_smith" })
    }

    func testDirectNoEquipmentRequestsAndMixedEquipmentStayDistinct() {
        let policy = ExerciseSelectionPolicy.shared
        for request in ["no equipment", "徒手训练", "无器械", "ohne Geräte", "sin equipo", "sans matériel", "senza attrezzi", "sem equipamento", "без оборудования", "器具なし", "맨몸", "بدون معدات"] {
            let candidates = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all, query: request)
            XCTAssertFalse(candidates.isEmpty, request)
            XCTAssertTrue(candidates.allSatisfy { policy.equipmentAllows($0, selected: ["body_only"]) }, request)
        }
        let mixed = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all,
                                             query: "Only dumbbells and bodyweight")
        XCTAssertTrue(mixed.contains { $0.id == "bench_press_dumbbell" })
        XCTAssertTrue(mixed.allSatisfy { policy.equipmentAllows($0, selected: ["dumbbell"]) })
        let smith = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all,
                                             query: "Only Smith machine")
        XCTAssertTrue(smith.allSatisfy { policy.equipmentAllows($0, selected: ["smith"]) })
    }

    func testExactLocalizedRequestDoesNotUnlockOtherSpecialists() throws {
        let rare = try exercise("pull_up_one_arm")
        let localizedNames = try XCTUnwrap(rare.localizedName)
        let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]
        for language in languages {
            let name = try XCTUnwrap(localizedNames[language], language)
            let candidates = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all, query: name)
            XCTAssertTrue(candidates.contains { $0.id == rare.id }, name)
            XCTAssertTrue(candidates.filter { ExerciseSelectionPolicy.shared.tier(for: $0) == .specialist }.allSatisfy { $0.id == rare.id }, name)
        }
        let excluded = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all, query: "Avoid \(rare.name)")
        XCTAssertFalse(excluded.contains { $0.id == rare.id })
    }

    func testLocalizedNameBoundariesRejectArabicPrefixesAndPartialIDs() throws {
        let rare = try exercise("pull_up_one_arm")
        let arabic = try XCTUnwrap(rare.localizedName?["ar"])
        let requested = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all,
                                                query: "أضف \(arabic) إلى التمرين")
        XCTAssertTrue(requested.contains { $0.id == rare.id })
        // These three existing translations are "اسحب", a word prefix of "اسحبه".
        let unrelated: Set<String> = ["clean_pull", "pull_up_kipping", "snatch_pull"]
        XCTAssertTrue(Set(requested.map(\.id)).isDisjoint(with: unrelated))
        for query in ["اسحبه", "prefix_\(rare.id)", "\(rare.id)_suffix", "تجنب \(arabic)"] {
            let candidates = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all, query: query)
            XCTAssertFalse(candidates.contains { $0.id == rare.id }, query)
            XCTAssertTrue(Set(candidates.map(\.id)).isDisjoint(with: unrelated), query)
        }
    }

    func testExactNameCanAppearInUnspacedChineseOrJapaneseRequests() throws {
        let rare = try exercise("pull_up_one_arm")
        let chinese = try XCTUnwrap(rare.localizedName?["zh-Hans"])
        let japanese = try XCTUnwrap(rare.localizedName?["ja"])
        for query in ["今天加入\(chinese)，做三组", "今日は\(japanese)を追加"] {
            let candidates = service.routineCandidates(payload: payload(), library: ExerciseLibrary.all, query: query)
            XCTAssertTrue(candidates.contains { $0.id == rare.id }, query)
            XCTAssertTrue(candidates.filter { ExerciseSelectionPolicy.shared.tier(for: $0) == .specialist }.allSatisfy { $0.id == rare.id }, query)
        }
    }

    func testShortLocalizedNamesRequireACompleteStandaloneRequest() throws {
        var dragonFlag = try exercise("dragon_flag")
        // Keep a deliberately short-name fixture independent of equipment-qualified catalog names.
        dragonFlag.localizedName?["zh-Hans"] = "龙旗"
        let library = ExerciseLibrary.all.map { $0.id == dragonFlag.id ? dragonFlag : $0 }
        for query in ["龙旗", " \n龙旗\t"] {
            let candidates = service.routineCandidates(payload: payload(), library: library, query: query)
            XCTAssertTrue(candidates.contains { $0.id == dragonFlag.id }, query)
            XCTAssertTrue(candidates.filter { ExerciseSelectionPolicy.shared.tier(for: $0) == .specialist }.allSatisfy { $0.id == dragonFlag.id }, query)
        }
        // Some existing translations are just 上 or 手; neither a sentence containing them
        // nor a one-character request should promote unrelated specialist exercises.
        for query in ["今天练上肢和手臂", "上", "手", "今天龙旗做三组"] {
            let candidates = service.routineCandidates(payload: payload(), library: library, query: query)
            XCTAssertTrue(candidates.allSatisfy { ExerciseSelectionPolicy.shared.tier(for: $0) != .specialist }, query)
        }
    }

    func testRemoteIDsMustBelongToTheActualCandidatePool() throws {
        let bench = try exercise("bench_press_dumbbell")
        let row = try exercise("dumbbell_row_single_arm")
        let raw = #"{"name":"Workout","steps":[{"exercise_id":"bench_press_dumbbell","sets":"3","reps":"8-12"},{"exercise_id":"dumbbell_row_single_arm","sets":3,"reps":10}]}"#
        let plan = try XCTUnwrap(service.validatedPlan(fromJSON: raw, candidates: [bench, row], maxExercises: 2))
        XCTAssertEqual(plan.steps.map(\.exerciseId), [bench.id, row.id])
        XCTAssertEqual(plan.steps.first?.reps, 8)

        let wrongEquipment = #"{"name":"Workout","steps":[{"exercise_id":"bench_press_barbell","exercise_name":"Bench Press (Dumbbell)","sets":3},{"exercise_id":"dumbbell_row_single_arm","sets":3}]}"#
        XCTAssertNil(try service.validatedPlan(fromJSON: wrongEquipment, candidates: [bench, row], maxExercises: 2))
    }

    func testRepeatedIDAndEquipmentVersionsCannotFillTwoWorkoutSlots() throws {
        let bench = try exercise("bench_press_dumbbell")
        let barbell = try exercise("bench_press_barbell")
        let row = try exercise("dumbbell_row_single_arm")
        for second in [bench.id, barbell.id] {
            let raw = "{\"name\":\"Workout\",\"steps\":[{\"exercise_id\":\"\(bench.id)\",\"sets\":3},{\"exercise_id\":\"\(second)\",\"sets\":3}]}"
            XCTAssertNil(try service.validatedPlan(fromJSON: raw, candidates: [bench, barbell, row], maxExercises: 2))
        }
    }

    func testLegacyNamesAreAcceptedOnlyWhenExactAndUnambiguous() throws {
        let bench = try exercise("bench_press_dumbbell")
        let raw = #"{"name":"Workout","steps":[{"exercise_name":"Bench Press (Dumbbell)","sets":3,"reps":10}]}"#
        XCTAssertEqual(try service.validatedPlan(fromJSON: raw, candidates: [bench], maxExercises: 1)?.steps.first?.exerciseId, bench.id)
        let guessed = #"{"name":"Workout","steps":[{"exercise_name":"bench press","sets":3}]}"#
        XCTAssertNil(try service.validatedPlan(fromJSON: guessed, candidates: [bench], maxExercises: 1))
    }
}

@MainActor
final class WeeklyRoutineCountTests: XCTestCase {
    func testFallbackHasOneDistinctCardPerTrainingDay() {
        for days in 1...7 {
            let plans = RecommendedPrograms.plans(forDays: days, now: Date(), byId: ExerciseLibrary.byId)
            XCTAssertEqual(plans.count, days)
            XCTAssertEqual(Set(plans.map(\.id)).count, days)
            XCTAssertTrue(plans.allSatisfy { !$0.steps.isEmpty })
            let stepIDs = plans.flatMap { $0.steps.map(\.id) }
            XCTAssertEqual(Set(stepIDs).count, stepIDs.count)
        }
    }

    func testEquipmentFilteringPreservesTheWeeklyCardCount() {
        for days in 1...7 {
            for environment in [TrainingEnvironment.gym, .home, .bodyweight] {
                var settings = UserSettings()
                settings.weeklyTrainingDays = days
                settings.trainingEnvironment = environment
                settings.availableEquipment = environment == .gym ? EquipmentCategory.allCases.map(\.rawValue) : [environment == .home ? "dumbbell" : "bodyweight"]
                let plans = DataStore.tunedRecommendedPlans(forDays: days, settings: settings, exById: ExerciseLibrary.byId, sets: [], now: Date())
                XCTAssertEqual(plans.count, days, "\(environment) \(days)")
                XCTAssertTrue(plans.allSatisfy { !$0.steps.isEmpty }, "\(environment) \(days)")
                XCTAssertTrue(plans.flatMap(\.steps).allSatisfy { step in
                    guard let ex = ExerciseLibrary.byId[step.exerciseId] else { return false }
                    return ExerciseSelectionPolicy.shared.equipmentAllows(ex, selected: Set(settings.availableEquipment), environment: environment)
                }, "\(environment) \(days): fallback must respect equipment")
            }
        }
    }

    func testWeeklyChangeRecognizesAllTwelveLanguagesAndRejectsAmbiguity() {
        var settings = UserSettings(); settings.weeklyTrainingDays = 2
        for text in ["Train three times per week", "一周练三次", "每週練三次", "週に三回", "주 세 회", "tres veces por semana", "trois fois par semaine", "drei mal pro Woche", "tre volte a settimana", "três vezes por semana", "три раза в неделю", "٣ مرات في الأسبوع"] {
            let change = WeeklyRoutineRequest.change(in: text, settings: settings)
            XCTAssertEqual(change?.values, ["3"], text)
            XCTAssertEqual(change?.previous, ["2"], text)
        }
        for text in ["Train three times per week?", "如果一周练三次", "暂时一周练三次", "Don't train three times per week", "Train three times per week or four times per week"] {
            XCTAssertNil(WeeklyRoutineRequest.change(in: text, settings: settings), text)
        }
    }

    func testFrequencyProposalStopsBeforeGenerationAndDeclineKeepsPreferences() async throws {
        var settings = UserSettings(); settings.weeklyTrainingDays = 2
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: settings)
        await data.coachGenerate(feedback: "一周练三次")
        XCTAssertEqual(data.settings.weeklyTrainingDays, 2)
        XCTAssertTrue(data.coachSession.currentRoutines.isEmpty)
        XCTAssertFalse(data.coachSession.isGenerating)
        let message = try XCTUnwrap(data.coachSession.messages.last)
        XCTAssertEqual(message.preferenceProposal?.changes.first?.values, ["3"])
        data.resolveCoachPreferences(messageID: message.id, accept: false)
        XCTAssertEqual(data.settings.weeklyTrainingDays, 2)
        XCTAssertEqual(data.coachSession.messages.last?.preferenceProposal?.decision, .declined)
        XCTAssertFalse(data.coachSession.isGenerating)
    }

    func testStaleConfirmationCannotOverwriteNewerPreferences() async throws {
        var settings = UserSettings(); settings.weeklyTrainingDays = 2
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: settings)
        await data.coachGenerate(feedback: "一周练三次")
        let message = try XCTUnwrap(data.coachSession.messages.last)
        data.settings.weeklyTrainingDays = 4
        data.resolveCoachPreferences(messageID: message.id, accept: true)
        XCTAssertEqual(data.settings.weeklyTrainingDays, 4)
        XCTAssertFalse(data.coachSession.isGenerating)
    }
}
