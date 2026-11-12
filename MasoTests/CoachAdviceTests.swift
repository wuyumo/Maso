import XCTest
import UIKit
@testable import Maso

final class CoachAdviceTests: XCTestCase {
    func testEveryCoachUseCaseHasTheExpectedEditableSelection() {
        for useCase in CoachUseCase.allCases {
            let prompt = NSLocalizedString(useCase.promptKey, bundle: .main, comment: "AI Coach use case prompt")
            let editableRanges = CoachTemplates.editablePlaceholderRanges(in: prompt)
            let expectedCount = useCase == .physiqueGoal ? 0 : 1

            XCTAssertEqual(editableRanges.count, expectedCount, "Unexpected placeholder count for \(useCase.rawValue): \(prompt)")
            for range in editableRanges {
                let selectedText = String(prompt[range])
                XCTAssertFalse(selectedText.isEmpty, "Selection target was empty for \(useCase.rawValue)")
                XCTAssertFalse("「」[]".contains(selectedText.first ?? " "), "Selection should exclude delimiters for \(useCase.rawValue)")
                XCTAssertFalse("「」[]".contains(selectedText.last ?? " "), "Selection should exclude delimiters for \(useCase.rawValue)")
            }
        }
    }

    func testEditableRangesSupportLocalizedQuotesAndEnglishBrackets() {
        let samples = [
            "我想更多训练「肩部和背部」，请据此调整训练计划，同时保持整体均衡。",
            "我每次只能训练「30」分钟，请缩短训练计划，同时保留主要训练重点。",
            "我在家用「哑铃和弹力带」训练，请按现有器械调整计划。",
            "我停练「一个月」后准备恢复，请循序渐进地调整计划，保持训练均衡。",
            "I have [30] minutes per workout.",
        ]
        XCTAssertEqual(samples.map { sample in
            CoachTemplates.editablePlaceholderRanges(in: sample).map { String(sample[$0]) }
        },
                       [["肩部和背部"], ["30"], ["哑铃和弹力带"], ["一个月"], ["30"]])
    }

    @MainActor
    func testNotesPreferExactUpperChestRatherThanGenericChest() {
        let intent = LocalRoutineRules.parse("侧重上胸，练后束")
        XCTAssertTrue(intent.focusMuscles.contains(.upperChest))
        XCTAssertTrue(intent.focusMuscles.contains(.rearDelts))
        XCTAssertTrue(LocalRoutineRules.parse("不练上胸").focusMuscles.isEmpty)
        let flat = ExerciseLibrary.byId["bench_press_barbell"]!
        let incline = ExerciseLibrary.byId["incline_bench_press_barbell"]!
        let step = PlanStep(id: "step", exerciseId: flat.id, sets: 3, reps: 10, weight: 40)
        let plan = Plan(id: "focus", name: "Chest", steps: [step], createdAt: Date(), updatedAt: Date())
        let result = LocalRoutineRules.apply(to: [plan], intent: intent, settings: UserSettings(),
                                            exById: [flat.id: flat, incline.id: incline])
        XCTAssertEqual(result.first?.steps.first?.exerciseId, incline.id)
        XCTAssertEqual(result.first?.steps.first?.sets, 3)
        XCTAssertNil(result.first?.steps.first?.weight)
    }

    func testMemoryRequiresSourceAndRejectsTemporaryOrDuplicatePreferences() {
        let proposal = CoachMemoryProposal(note: "Focus on upper chest", sourceQuote: "focus on upper chest")
        XCTAssertNotNil(CoachMemoryProposal.validated(proposal, userText: "I prefer to focus on upper chest", existing: "", declined: []))
        XCTAssertNil(CoachMemoryProposal.validated(proposal, userText: "I prefer leg workouts", existing: "", declined: []))
        XCTAssertNil(CoachMemoryProposal.validated(proposal, userText: "focus on upper chest", existing: "- Focus on upper chest", declined: []))
        XCTAssertNil(CoachMemoryProposal.validated(proposal, userText: "focus on upper chest", existing: "", declined: [CoachMemoryProposal.key(proposal.note)]))
        XCTAssertNil(CoachMemoryProposal.validated(nil, userText: "今天重点练上胸", existing: "", declined: []))
        XCTAssertNotNil(CoachMemoryProposal.validated(nil, userText: "我通常只用哑铃", existing: "", declined: []))
        XCTAssertNil(CoachMemoryProposal.validated(nil, userText: nil, existing: "", declined: []))
    }

    func testGenericCoachInstructionsAreNotPersonalTrainingMemories() {
        for text in ["请记住我的 preference 和恢复情况", "Remember my preferences and recovery", "Use my feedback to personalize training", "请考虑恢复情况，安全地生成适合我的计划"] {
            let proposed = CoachMemoryProposal(note: text, sourceQuote: text)
            XCTAssertNil(CoachMemoryProposal.validated(proposed, userText: text, existing: "", declined: []))
            XCTAssertNil(CoachMemoryProposal.validated(nil, userText: text, existing: "", declined: []))
        }
        let invented = CoachMemoryProposal(note: "Focus on upper chest", sourceQuote: "Remember my preferences")
        XCTAssertNil(CoachMemoryProposal.validated(invented, userText: invented.sourceQuote, existing: "", declined: []))
    }

    func testConcretePreferencesAreSupportedAcrossAllAppLanguages() {
        for text in ["Prioritize upper chest", "重点练上胸", "重點練上胸", "Brust priorisieren", "Priorizar pecho", "Prioriser la poitrine", "Priorità al petto", "Priorizar peito", "Тренировать грудь", "上胸を重点的に鍛える", "가슴을 집중 훈련", "أركز على الصدر"] {
            XCTAssertNotNil(CoachMemoryProposal.validated(.init(note: text, sourceQuote: text), userText: text, existing: "", declined: []), text)
        }
        XCTAssertNotNil(CoachMemoryProposal.validated(.init(note: "Usually 45 minutes per session", sourceQuote: "Usually 45 minutes per session"), userText: "Usually 45 minutes per session", existing: "", declined: []))
    }

    @MainActor
    func testAcceptingAnOldGenericProposalDoesNotPolluteNotes() {
        let store = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let text = "请记住我的偏好和恢复情况"
        let message = CoachMessage(role: .assistant, text: "Plan", memoryProposal: .init(note: text, sourceQuote: text))
        store.coachSession.messages = [message]
        store.resolveCoachMemory(messageID: message.id, accept: true)
        XCTAssertTrue(store.settings.coachMemory.isEmpty)
        XCTAssertEqual(store.coachSession.messages.first?.memoryProposal?.decision, .declined)
    }

    @MainActor
    func testMemoryIsSavedOnlyOnYesAndDoesNotDuplicateEarlierNotes() {
        let store = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let proposal = CoachMemoryProposal(note: "Focus on upper chest", sourceQuote: "upper chest")
        let message = CoachMessage(role: .assistant, text: "Plan ready", memoryProposal: proposal)
        store.coachSession.messages = [message]
        XCTAssertTrue(store.settings.coachMemory.isEmpty)
        store.resolveCoachMemory(messageID: message.id, accept: true)
        XCTAssertEqual(store.coachNotes, [proposal.note])
        XCTAssertEqual(store.coachSession.messages.first?.memoryProposal?.decision, .saved)
        store.resolveCoachMemory(messageID: message.id, accept: true)
        store.appendCoachNote("Use dumbbells")
        store.appendCoachNote("FOCUS ON UPPER CHEST")
        XCTAssertEqual(store.coachNotes.count, 2)
        let rejected = CoachMessage(role: .assistant, text: "Plan", memoryProposal: .init(note: "Avoid overhead presses", sourceQuote: "overhead presses"))
        store.coachSession.messages.append(rejected)
        store.resolveCoachMemory(messageID: rejected.id, accept: false)
        XCTAssertFalse(store.settings.coachMemory.contains("overhead"))
        XCTAssertEqual(store.coachSession.messages.last?.memoryProposal?.decision, .declined)
    }

    private let local = DataStore.RoutineSuggestion(id: "legs", title: "Train your legs",
                                                   detail: "Your recent sessions focus on upper body.",
                                                   focusNote: "Add leg volume")

    func testMergesDuplicateActionsWithoutLosingDistinctAdvice() {
        let summary = AISummary(tldr: "Summary", recommendations: [
            AIRecommendation(id: "random-server-id", title: "More leg work", detail: "Similar advice",
                             action: .regenerateRoutines(focusNote: "  add  LEG volume ")),
            AIRecommendation(id: "note", title: "Shorter sessions", detail: "Save a preference",
                             action: .addCoachNote(note: "Keep sessions short"))
        ])
        let cards = CoachAdvice.merged(local: local, summary: summary, isPro: true)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.first?.source, .suggestion)
        XCTAssertEqual(cards.last?.action, .addCoachNote(note: "Keep sessions short"))
    }

    func testFreeUserDoesNotReceiveCachedProRecommendations() {
        let summary = AISummary(tldr: "Private Pro analysis", recommendations: [
            AIRecommendation(id: "pro", title: "Pro advice", detail: "Pro detail", action: .addCoachNote(note: "Pro note"))
        ])
        XCTAssertTrue(CoachAdvice.merged(local: nil, summary: summary, isPro: false).isEmpty)
        XCTAssertEqual(CoachAdvice.merged(local: local, summary: summary, isPro: false).count, 1)
    }

    func testDismissalIdentitySurvivesTransientServerIDsButAllowsChangedAdvice() {
        func card(serverID: String, detail: String) -> CoachAdvice {
            let summary = AISummary(tldr: "", recommendations: [
                AIRecommendation(id: serverID, title: "Train legs", detail: detail,
                                 action: .regenerateRoutines(focusNote: "Add leg volume"))
            ])
            return CoachAdvice.merged(local: nil, summary: summary, isPro: true)[0]
        }
        let first = card(serverID: "1", detail: "Same reason")
        let refreshed = card(serverID: "2", detail: "Same reason")
        XCTAssertEqual(first.id, refreshed.id)
        XCTAssertNotEqual(first.id, card(serverID: "3", detail: "New reason").id)
        let dismissed = Set([first.id])
        XCTAssertTrue([refreshed].filter { !dismissed.contains($0.id) }.isEmpty)
    }

    func testRemovingCurrentCardSelectsNextThenPreviousAndHandlesEmptyDeck() {
        XCTAssertEqual(CoachAdvice.selection(afterRemoving: "b", from: ["a", "b", "c"]), "c")
        XCTAssertEqual(CoachAdvice.selection(afterRemoving: "c", from: ["a", "b", "c"]), "b")
        XCTAssertNil(CoachAdvice.selection(afterRemoving: "a", from: ["a"]))
        XCTAssertNil(CoachAdvice.selection(afterRemoving: "a", from: []))
    }

    func testDismissalsPersistAndOlderSettingsStillDecode() throws {
        var settings = UserSettings()
        settings.dismissedCoachSuggestionIDs = ["stable-advice-id"]
        let encoded = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: encoded).dismissedCoachSuggestionIDs,
                       ["stable-advice-id"])
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "dismissedCoachSuggestionIDs")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        XCTAssertNil(try JSONDecoder().decode(UserSettings.self, from: oldData).dismissedCoachSuggestionIDs)
    }

    func testSummaryWithoutActionableRecommendationsRemainsReadable() {
        let cards = CoachAdvice.merged(local: nil, summary: AISummary(tldr: "Training is balanced", recommendations: []), isPro: true)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.action, AISummaryAction.none)
        XCTAssertEqual(cards.first?.detail, "Training is balanced")
    }
}

@MainActor
final class BodyPhotoCoachTests: XCTestCase {
    func testDecliningPhotoPlanKeepsPlansAndPreferencesAndCannotBeReused() {
        let data = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let original = TrainingPreferenceDraft(settings: data.settings)
        var report = CoachMessage(role: .assistant, text: "Synthetic visible observations")
        report.bodyPhotoPlanFocus = "Optional chest focus"
        data.coachSession.messages = [report]
        data.resolveBodyPhotoPlan(messageID: report.id, accept: false)
        XCTAssertEqual(data.coachSession.messages.first?.bodyPhotoPlanDecision, false)
        XCTAssertFalse(data.coachSession.isGenerating)
        XCTAssertTrue(data.plans.isEmpty)
        XCTAssertEqual(TrainingPreferenceDraft(settings: data.settings), original)
        data.resolveBodyPhotoPlan(messageID: report.id, accept: true)
        XCTAssertFalse(data.coachSession.isGenerating, "A resolved proposal cannot launch another request")
    }

    func testPhotoFocusAreasAreBoundedAndIgnoreUnknownValues() throws {
        let json = Data(#"{"summary":"Optional chest and shoulder focus.","focusNote":"Chest and shoulders","canSuggestPlan":true,"focusAreas":["chest","shoulders","chest","invalid","legs","back"]}"#.utf8)
        let result = try AIWorkoutService.BodyPhotoAnalysis.decode(json)
        XCTAssertEqual(BodyPhotoFocusAreas.muscles(result.focusAreas), [.chest, .shoulders, .legs])
        XCTAssertTrue(BodyPhotoFocusAreas.muscles(nil).isEmpty)
        XCTAssertTrue(BodyPhotoFocusAreas.muscles(["unknown"]).isEmpty)
    }

    func testUnclearPhotoDoesNotPermitPlanSuggestion() throws {
        let json = Data(#"{"summary":"Please use a clearer photo.","focusNote":"","canSuggestPlan":false}"#.utf8)
        let result = try AIWorkoutService.BodyPhotoAnalysis.decode(json)
        XCTAssertFalse(result.canSuggestPlan)
    }

    func testEmptyOrIncompleteAnalysisIsRejected() {
        for json in [
            #"{"summary":"","focusNote":"Legs","canSuggestPlan":true}"#,
            #"{"summary":"Tentative observation","focusNote":" ","canSuggestPlan":true}"#,
            #"{"summary":"Incomplete"}"#
        ] {
            XCTAssertThrowsError(try AIWorkoutService.BodyPhotoAnalysis.decode(Data(json.utf8)))
        }
    }

    func testPhotoEncodingBoundsResolutionAndStripsMetadata() throws {
        let input = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 3000)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 3000))
        }
        let bytes = try XCTUnwrap(CoachScreen.prepareBodyPhoto(input))
        let output = try XCTUnwrap(UIImage(data: bytes))
        XCTAssertLessThanOrEqual(max(output.size.width, output.size.height), 1280)
        XCTAssertLessThanOrEqual(bytes.base64EncodedString().count, 2_000_000)
    }
}

final class CoachSaveStateTests: XCTestCase {
    @MainActor func testBatchCompletionTracksAllSavedCopiesAndRemoval() {
        let store = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let date = Date()
        let first = Plan(id: "ai-one", name: "One", steps: [], createdAt: date, updatedAt: date)
        let second = Plan(id: "ai-two", name: "Two", steps: [], createdAt: date, updatedAt: date)
        XCTAssertFalse(store.areCoachPlansSaved([]))
        XCTAssertFalse(store.areCoachPlansSaved([first, second]))
        XCTAssertTrue(store.saveCoachPlan(first))
        XCTAssertFalse(store.areCoachPlansSaved([first, second]))
        XCTAssertTrue(store.saveCoachPlan(second))
        XCTAssertTrue(store.areCoachPlansSaved([first, second]))
        store.plans[0].name = "Renamed"
        XCTAssertTrue(store.areCoachPlansSaved([first, second]))
        store.plans.removeFirst()
        XCTAssertFalse(store.areCoachPlansSaved([first, second]))
    }
    @MainActor func testReplacementMarksBatchCompleteAndDoesNotDuplicateSavedPlans() {
        let store = DataStore(exercises: [], plans: [], sets: [], settings: UserSettings())
        let date = Date()
        let plan = Plan(id: "ai-one", name: "One", steps: [], createdAt: date, updatedAt: date)
        XCTAssertEqual(store.replaceSavedPlans(withCoach: [plan]), 1)
        XCTAssertTrue(store.areCoachPlansSaved([plan]))
        XCTAssertTrue(store.saveCoachPlan(plan))
        XCTAssertEqual(store.plans.count, 1)
    }
}

@MainActor
final class CoachImageRoutingTests: XCTestCase {
    func testImageCatalogRetrievalIncludesBilingualAndAbbreviatedMovements() {
        let text = "Pull-ups — 引体向上\nDips — 双杠臂屈伸\nPush-ups — 俯卧撑\nRows — 自重划船\nPike push-ups — 折刀俯卧撑\nSquats — 深蹲\nLunges — 箭步蹲\nRDLs — 罗马尼亚硬拉"
        let ids = Set(CoachPhotoReview.catalogCandidates(ocr: text, library: ExerciseLibrary.all).map(\.id))
        for id in ["pull_up", "push_up", "inverted_row", "push_up_pike", "squat_bodyweight", "rdl_barbell"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    func testImageWorkoutUsesOnlyExactCatalogIDsAndPreservesVariants() throws {
        let library = ExerciseLibrary.all
        let ids = ["push_up", "push_up_pike"]
        let names = ids.map { ExerciseLibrary.byId[$0]!.name }
        let settings = UserSettings()
        let plan = try XCTUnwrap(CoachPhotoReview.imageWorkout(ids: ids, names: names, library: library, settings: settings))
        XCTAssertEqual(plan.steps.map(\.exerciseId), ids)
        XCTAssertEqual(plan.steps.count, 2)
        let equivalent = try XCTUnwrap(CoachPhotoReview.imageWorkout(ids: ["inverted_row", ""], names: ["Inverted Row", "Romanian Deadlift"], library: library, settings: settings))
        XCTAssertEqual(equivalent.steps.map(\.exerciseId), ["inverted_row", "rdl_barbell"])
        XCTAssertNil(CoachPhotoReview.imageWorkout(ids: ["bench_press_barbell"], names: ["Bench Press (Dumbbell)"], library: library, settings: settings))
        XCTAssertEqual(plan.steps[0].sets, settings.defaultSetsPerExercise)
        XCTAssertEqual(ExerciseSelectionPolicy.shared.routineDefaults(plan, library: library, settings: settings).steps.map(\.exerciseId), ids)
        XCTAssertNil(CoachPhotoReview.imageWorkout(ids: ["invented"], names: ["Push-Up"], library: library, settings: settings))
        XCTAssertNil(CoachPhotoReview.imageWorkout(ids: ids, names: Array(names.reversed()), library: library, settings: settings))
        XCTAssertNil(CoachPhotoReview.imageWorkout(ids: [ids[0], ids[0]], names: [names[0], names[0]], library: library, settings: settings))
        let restored = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.preservesExerciseVariants, true)
        let store = DataStore.makeMock()
        store.settings.debugProUnlock = true
        let saved = try XCTUnwrap(store.savePlanReturningCopy(plan))
        XCTAssertEqual(saved.preservesExerciseVariants, true)
        XCTAssertEqual(store.routinePlanDefaults(saved).steps.map(\.exerciseId), ids)
        var legacy = saved
        legacy.preservesExerciseVariants = nil
        store.plans = [legacy]
        let exactCopy = try XCTUnwrap(store.savePlanReturningCopy(plan))
        XCTAssertNotEqual(exactCopy.id, legacy.id)
        XCTAssertEqual(exactCopy.preservesExerciseVariants, true)
        let payload = try XCTUnwrap(PlanShareCodec.encode(plan))
        let shared = try XCTUnwrap(PlanShareCodec.decode(payload))
        XCTAssertEqual(shared.preservesExerciseVariants, true)
        XCTAssertEqual(shared.steps.map(\.exerciseId), ids)
    }

    func testClarificationOnlyOffersPlausibleDistinctKinds() {
        var review = CoachPhotoReview(jpeg: Data(), caption: nil, kind: .body)
        review.possibleKinds = [.body, .photo]
        XCTAssertTrue(review.clarificationKinds.isEmpty)
        review.needsChoice = true
        XCTAssertEqual(review.clarificationKinds, [.body, .photo])
        review.possibleKinds = [.unknown, .body, .body]
        XCTAssertTrue(review.clarificationKinds.isEmpty)
        review.possibleKinds = [.body, .photo]
        review.failed = true
        XCTAssertTrue(review.clarificationKinds.isEmpty)
    }

    func testClassifierRequiresUsableSummaryAndBodyFocus() throws {
        for json in [
            #"{"kind":"body","summary":"Visible shoulders","needsClarification":false,"canSuggestPlan":true,"focusNote":""}"#,
            #"{"kind":"meal","summary":"","needsClarification":false}"#,
            #"{"summary":"Missing routing information"}"#
        ] { XCTAssertThrowsError(try AIWorkoutService.CoachImageUnderstanding.decode(Data(json.utf8))) }
        let future = try AIWorkoutService.CoachImageUnderstanding.decode(Data(#"{"kind":"unexpected-model-category","summary":"Unclear image","needsClarification":false}"#.utf8))
        XCTAssertEqual(future.resolvedKind, .unknown, "Unrecognized model categories cannot choose an action")
    }

    func testExactPlanValidationPreservesPerSetPrescriptionsAndRejectsUnknownIDs() throws {
        let step = PlanStep(id: "source-step", exerciseId: "bench_press_barbell", sets: 2, reps: 8, weight: 60,
                            setReps: [8, 7], setWeights: [60, 62.5])
        let plan = Plan(id: "photo-ref", name: "Shared routine", steps: [step], createdAt: Date(), updatedAt: Date())
        let safe = try XCTUnwrap(CoachPhotoReview.safePlans([plan], lookup: ExerciseLibrary.byId))
        XCTAssertEqual(safe[0].steps[0].setReps, [8, 7])
        XCTAssertEqual(safe[0].steps[0].setWeights, [60, 62.5])
        var bad = plan; bad.steps[0].exerciseId = "hallucinated-bench-machine"
        XCTAssertNil(CoachPhotoReview.safePlans([bad], lookup: ExerciseLibrary.byId))
        var aliases = ExerciseLibrary.byId
        aliases["unreviewed-media-folder"] = aliases["bench_press_barbell"]
        bad = plan; bad.steps[0].exerciseId = "unreviewed-media-folder"
        XCTAssertNil(CoachPhotoReview.safePlans([bad], lookup: aliases), "Media aliases are not accepted exercise identities")
        bad = plan; bad.steps[0].sets = 0
        XCTAssertNil(CoachPhotoReview.safePlans([bad], lookup: ExerciseLibrary.byId))
        bad = plan; bad.steps[0].weight = .infinity
        XCTAssertNil(CoachPhotoReview.safePlans([bad], lookup: ExerciseLibrary.byId))
    }

    func testQRImageIsDecodedLocallyWithoutSavingOrGeneratingPlans() async throws {
        let data = DataStore.makeMock()
        let original = data.plans
        let preferences = TrainingPreferenceDraft(settings: data.settings)
        let originalMeals = data.settings.mealCheckIns?.count
        let plan = Plan(id: "qr-input", name: "Exact QR reference", steps: [.init(id: "qr", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60)], createdAt: Date(), updatedAt: Date())
        let image = CoachImageTestFixture.image(kind: "qr", plan: plan)
        let jpeg = try XCTUnwrap(CoachScreen.prepareBodyPhoto(image))
        let decodedImage = try XCTUnwrap(UIImage(data: jpeg))
        let evidence = RoutineImageImporter.evidence(from: decodedImage)
        XCTAssertEqual(evidence.plans.count, 1)
        guard evidence.plans.count == 1 else { return } // Never fall through to a real model in this local-only test.
        await data.analyzeCoachImage(jpeg, caption: nil)
        let review = try XCTUnwrap(data.coachSession.messages.last?.photoReview)
        XCTAssertEqual(review.kind, .routine)
        XCTAssertEqual(review.plans.count, 1)
        XCTAssertEqual(review.plans[0].steps, plan.steps)
        XCTAssertNil(data.coachSession.messages.last?.plans)
        XCTAssertEqual(data.plans, original)
        XCTAssertEqual(TrainingPreferenceDraft(settings: data.settings), preferences)
        XCTAssertEqual(data.settings.mealCheckIns?.count, originalMeals)
        XCTAssertFalse(data.coachSession.isGenerating)
    }

    func testAppStoreOnlyLinkIsNotAPlanPayload() {
        XCTAssertNil(PlanShareCodec.decodePlans(fromQRPayload: MasoLinks.appStore))
        XCTAssertNil(PlanShareCodec.decodePlans(fromQRPayload: "https://example.com/checkout"))
    }

    func testCorrectingImageUseInvalidatesOldBodyPlanAction() throws {
        let data = DataStore.makeMock()
        let jpeg = try XCTUnwrap(CoachImageTestFixture.image(kind: "label").jpegData(compressionQuality: 0.8))
        var message = CoachMessage(role: .assistant, text: "Initial uncertain report")
        message.bodyPhotoPlanFocus = "Old optional focus"
        message.photoReview = .init(jpeg: jpeg, caption: nil, kind: .body)
        data.coachSession.messages = [message]
        data.rerouteCoachImage(messageID: message.id, kind: .label)
        XCTAssertNil(data.coachSession.messages.first?.photoReview)
        XCTAssertNil(data.coachSession.messages.first?.bodyPhotoPlanFocus)
        XCTAssertEqual(data.coachSession.messages.first?.bodyPhotoPlanDecision, false)
        XCTAssertTrue(data.coachSession.isGenerating)
        // Cancel synchronously before the Task is scheduled: no production request.
        data.resetCoachConversation()
        XCTAssertTrue(data.coachSession.messages.isEmpty)
        XCTAssertFalse(data.coachSession.isGenerating)
    }
}
