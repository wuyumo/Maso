import XCTest
@testable import Maso

/// Hosted by the Maso app target. Launch only with scheme MasoCoachSwapTests, which
/// sets MASO_COACH_SWAP_TEST=1 before MasoApp.init. That DEBUG path does not call
/// bootstrap(), does not build RootView, and does not start StoreKit. Chat checks
/// call DataStore.handleEquipmentSwapUtterance, the method CoachScreen.performSend
/// uses, and write only to PersistenceController(storageURL:) temp files.
@MainActor
final class CoachEquipmentSwapTests: XCTestCase {
    private let request = "把所有练胸的杠铃器械都换成machine"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCTAssertEqual(
            ProcessInfo.processInfo.environment["MASO_COACH_SWAP_TEST"], "1",
            "Refusing to run. Scheme Maso does not set the host guard, so MasoApp would call bootstrap() before this method.")
    }

    func testHostStorageIsNotTheUserSnapshot() {
        let url = PersistenceController().currentURL
        XCTAssertEqual(url?.lastPathComponent, "maso-coach-swap-test.json")
        XCTAssertNotEqual(url?.lastPathComponent, "maso-data.json")
    }

    func testBundledCatalogDecodes917Entries() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "exercises", withExtension: "json"),
            "MasoTests must run with the Maso app as TEST_HOST so exercises.json is Bundle.main")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let rows = try XCTUnwrap(raw as? [Any])
        XCTAssertEqual(rows.count, 917)
        XCTAssertEqual(ExerciseLibrary.all.count, 917)
    }

    func testChatConfirmsPersistsReloadsAndUndoes() throws {
        let library = ExerciseLibrary.all
        let source = try chestBarbell(in: library)
        let other = try nonChest(in: library, excluding: source.id)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let chest = PlanStep(
            id: "chest-1", exerciseId: source.id, sets: 4, reps: 8, weight: 60,
            setWeights: [60, 62.5, nil, 65], restBetweenSets: 120, rest: 15)
        let duplicate = PlanStep(
            id: "chest-2", exerciseId: source.id, sets: 3, reps: 10, weight: 40,
            restBetweenSets: 90, rest: 0)
        let kept = PlanStep(id: "other", exerciseId: other.id, sets: 2, reps: 12, weight: 20, restBetweenSets: 60)
        let focused = Plan(
            id: "plan-open", name: "Open",
            steps: [kept, chest, duplicate], createdAt: now, updatedAt: now,
            preservesExerciseVariants: true)
        let elsewhere = Plan(
            id: "plan-other", name: "Elsewhere",
            steps: [chest], createdAt: now, updatedAt: now,
            preservesExerciseVariants: true)
        let history = SetRecord(
            id: "history-1", exerciseId: source.id, exerciseName: source.name,
            category: source.category, weight: 60, reps: 8, duration: nil,
            performedAt: now, planId: focused.id)
        let store = DataStore(exercises: library, plans: [focused, elsewhere], sets: [history], settings: UserSettings())
        let isolated = try isolatedStore()
        store.equipmentSwapSaveOverride = { [weak store] in
            guard let store else { return false }
            return isolated.save(Self.snapshot(of: store))
        }

        let original = store.plans.map { $0.steps.map(\.exerciseId) }
        XCTAssertFalse(store.handleEquipmentSwapUtterance("今天练什么", onlyModify: nil, focusedPlanId: focused.id))
        XCTAssertTrue(store.coachSession.messages.isEmpty)

        let lang = LanguageManager.currentLanguageCode
        XCTAssertTrue(store.handleEquipmentSwapUtterance(
            "把练胸的杠铃器械换成machine", onlyModify: nil, focusedPlanId: nil))
        XCTAssertEqual(
            store.coachSession.messages.last?.text,
            CoachEquipmentSwap.text(for: .clarify(.ambiguousScope), languageCode: lang))
        XCTAssertNil(store.coachSession.pendingEquipmentSwap)
        XCTAssertEqual(store.plans.map { $0.steps.map(\.exerciseId) }, original)

        store.coachSession.messages.removeAll()
        XCTAssertTrue(store.handleEquipmentSwapUtterance(request, onlyModify: nil, focusedPlanId: focused.id))
        let proposal = try XCTUnwrap(store.coachSession.pendingEquipmentSwap)
        XCTAssertEqual(Set(proposal.lines.map(\.planId)), [focused.id])
        XCTAssertEqual(proposal.lines.map(\.stepId), ["chest-1", "chest-2"])
        XCTAssertTrue(proposal.lines.allSatisfy { line in library.contains { $0.id == line.toExerciseId } })
        XCTAssertNotEqual(store.plans[0].steps[1].exerciseId, proposal.lines[0].toExerciseId, "preview must not write")

        XCTAssertFalse(store.handleEquipmentSwapUtterance("确认，但是只改第一个动作", onlyModify: nil, focusedPlanId: focused.id))
        XCTAssertEqual(store.coachSession.pendingEquipmentSwap?.id, proposal.id)

        XCTAssertTrue(store.handleEquipmentSwapUtterance("就这样改", onlyModify: nil, focusedPlanId: focused.id))
        XCTAssertNil(store.coachSession.pendingEquipmentSwap)
        XCTAssertEqual(
            store.coachSession.messages.last?.text,
            CoachEquipmentSwap.textApplied(stepCount: 2, routineCount: 1, clearedWeight: true, languageCode: lang))
        let written = store.plans[0]
        XCTAssertEqual(written.preservesExerciseVariants, true)
        XCTAssertEqual(written.steps.map(\.id), ["other", "chest-1", "chest-2"])
        XCTAssertEqual(written.steps[0].exerciseId, original[0][0])
        XCTAssertEqual(written.steps[0].weight, 20)
        for step in written.steps.dropFirst() {
            let replacement = try XCTUnwrap(library.first { $0.id == step.exerciseId })
            XCTAssertEqual(CoachEquipmentSwap.primaryCategory(replacement), .machine)
            XCTAssertTrue(CoachEquipmentSwap.matchesMuscle(replacement, target: .chest))
            XCTAssertNil(step.weight)
            XCTAssertNil(step.setWeights)
        }
        XCTAssertEqual(written.steps[1].sets, 4)
        XCTAssertEqual(written.steps[1].reps, 8)
        XCTAssertEqual(written.steps[1].restBetweenSets, 120)
        XCTAssertEqual(written.steps[1].rest, 15)
        XCTAssertEqual(written.steps[2].sets, 3)
        XCTAssertEqual(written.steps[2].reps, 10)
        XCTAssertEqual(store.plans[1].steps[0].exerciseId, original[1][0])
        XCTAssertEqual(store.plans[1].steps[0].weight, 60)
        XCTAssertEqual(store.sets.map(\.exerciseId), [original[1][0]])
        XCTAssertEqual(store.sets.map(\.weight), [60])

        let reloaded = try reload(isolated, library: library)
        XCTAssertEqual(reloaded.plans[0].steps[1].exerciseId, written.steps[1].exerciseId)
        XCTAssertEqual(reloaded.plans[1].steps[0].exerciseId, original[1][0])
        XCTAssertEqual(reloaded.sets.map(\.exerciseId), [original[1][0]])

        XCTAssertTrue(store.handleEquipmentSwapUtterance("撤销", onlyModify: nil, focusedPlanId: focused.id))
        XCTAssertEqual(store.plans[0].steps.map(\.exerciseId), original[0])
        XCTAssertEqual(store.plans[0].steps[1].weight, 60)
        XCTAssertEqual(store.plans[0].steps[1].setWeights, [60, 62.5, nil, 65])
        XCTAssertEqual(
            store.coachSession.messages.last?.text,
            CoachEquipmentSwap.textUndone(languageCode: lang))
        let restored = try reload(isolated, library: library)
        XCTAssertEqual(restored.plans[0].steps.map(\.exerciseId), original[0])
        XCTAssertEqual(restored.plans[0].steps[1].setWeights, [60, 62.5, nil, 65])
    }

    func testChatCancelLeavesPlansAndWritesNothing() throws {
        let library = ExerciseLibrary.all
        let source = try chestBarbell(in: library)
        let plan = try onePlan(source)
        let store = DataStore(exercises: library, plans: [plan], sets: [], settings: UserSettings())
        let before = store.plans[0].steps[0].exerciseId
        let isolated = try isolatedStore()
        var writes = 0
        store.equipmentSwapSaveOverride = {
            writes += 1
            return isolated.save(Self.snapshot(of: store))
        }
        XCTAssertTrue(store.handleEquipmentSwapUtterance(request, onlyModify: nil, focusedPlanId: plan.id))
        XCTAssertTrue(store.handleEquipmentSwapUtterance("取消", onlyModify: nil, focusedPlanId: plan.id))
        XCTAssertNil(store.coachSession.pendingEquipmentSwap)
        XCTAssertEqual(writes, 0)
        XCTAssertNil(isolated.load())
        XCTAssertEqual(store.plans[0].steps[0].exerciseId, before)
        XCTAssertEqual(store.plans[0].steps[0].weight, 60)
        XCTAssertEqual(
            store.coachSession.messages.last?.text,
            CoachEquipmentSwap.textCancelled(languageCode: LanguageManager.currentLanguageCode))

        let pendingUndo = DataStore(exercises: library, plans: [plan], sets: [], settings: UserSettings())
        let pendingBefore = pendingUndo.plans[0].steps[0].exerciseId
        pendingUndo.equipmentSwapSaveOverride = { false }
        XCTAssertTrue(pendingUndo.handleEquipmentSwapUtterance(request, onlyModify: nil, focusedPlanId: plan.id))
        XCTAssertTrue(pendingUndo.handleEquipmentSwapUtterance("撤销", onlyModify: nil, focusedPlanId: plan.id))
        XCTAssertNil(pendingUndo.coachSession.pendingEquipmentSwap)
        XCTAssertEqual(pendingUndo.plans[0].steps[0].exerciseId, pendingBefore)
        XCTAssertEqual(
            pendingUndo.coachSession.messages.last?.text,
            CoachEquipmentSwap.textCancelled(languageCode: LanguageManager.currentLanguageCode))
    }

    func testChatPersistFailureDoesNotClaimSuccess() throws {
        let library = ExerciseLibrary.all
        let source = try chestBarbell(in: library)
        let plan = try onePlan(source)
        let store = DataStore(exercises: library, plans: [plan], sets: [], settings: UserSettings())
        let before = store.plans[0].steps[0].exerciseId
        let isolated = try isolatedStore()
        store.equipmentSwapSaveOverride = { false }
        XCTAssertTrue(store.handleEquipmentSwapUtterance(request, onlyModify: nil, focusedPlanId: plan.id))
        let pending = try XCTUnwrap(store.coachSession.pendingEquipmentSwap?.id)
        XCTAssertTrue(store.handleEquipmentSwapUtterance("好的", onlyModify: nil, focusedPlanId: plan.id))
        XCTAssertEqual(store.plans[0].steps[0].exerciseId, before)
        XCTAssertEqual(store.plans[0].steps[0].weight, 60)
        XCTAssertEqual(store.coachSession.pendingEquipmentSwap?.id, pending)
        let text = try XCTUnwrap(store.coachSession.messages.last?.text)
        XCTAssertEqual(text, CoachEquipmentSwap.textPersistFailed(languageCode: LanguageManager.currentLanguageCode))
        XCTAssertFalse(text.contains("已替换"))
        XCTAssertFalse(text.contains("Replaced"))
        XCTAssertNil(isolated.load())

        let blocked = PersistenceController(storageURL: isolated.currentURL!.deletingLastPathComponent())
        let sample = PersistenceController.Snapshot(
            version: PersistenceController.schemaVersion, plans: store.plans, sets: [],
            settings: UserSettings(), aiTodayPlan: nil, lastAIRefreshAt: nil, updatedAt: Date())
        XCTAssertFalse(blocked.save(sample))
    }

    func testShortRepliesAreWholeUtterancesOnly() {
        XCTAssertEqual(CoachEquipmentSwap.chatFollowUp("就这样改"), .confirm)
        XCTAssertEqual(CoachEquipmentSwap.chatFollowUp("取消"), .cancel)
        XCTAssertEqual(CoachEquipmentSwap.chatFollowUp("撤销"), .undo)
        XCTAssertNil(CoachEquipmentSwap.chatFollowUp("确认，但是只改第一个动作"))
        XCTAssertNil(CoachEquipmentSwap.chatFollowUp("今天练什么"))
    }

    /// The bundled catalog's lexicographically first non-niche chest barbell is
    /// Pullover (Barbell). It is a real chest-barbell row and the matcher correctly
    /// refuses it: no machine exercise shares that movement. Pick the first row for
    /// which the chat entry itself returns a preview, still from ExerciseLibrary.all.
    private func chestBarbell(in library: [Exercise]) throws -> Exercise {
        let hits = library.filter {
            !$0.isNiche
                && CoachEquipmentSwap.matchesMuscle($0, target: .chest)
                && CoachEquipmentSwap.primaryCategory($0) == .barbell
        }.sorted { $0.id < $1.id }
        for source in hits {
            let plan = try onePlan(source)
            let store = DataStore(exercises: library, plans: [plan], sets: [], settings: UserSettings())
            guard store.handleEquipmentSwapUtterance(request, onlyModify: nil, focusedPlanId: plan.id),
                  store.coachSession.pendingEquipmentSwap != nil else { continue }
            let storedId = store.plans[0].steps[0].exerciseId
            return try XCTUnwrap(library.first { $0.id == storedId })
        }
        XCTFail("Bundled catalog has no non-niche chest barbell the chat can replace with a real machine exercise")
        throw CocoaError(.fileNoSuchFile)
    }

    private func nonChest(in library: [Exercise], excluding id: String) throws -> Exercise {
        try XCTUnwrap(library.first {
            $0.id != id && !$0.isNiche && !CoachEquipmentSwap.matchesMuscle($0, target: .chest)
        })
    }

    private func onePlan(_ source: Exercise) throws -> Plan {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Plan(
            id: "plan-one", name: "One",
            steps: [PlanStep(id: "only", exerciseId: source.id, sets: 4, reps: 8, weight: 60, restBetweenSets: 90)],
            createdAt: now, updatedAt: now, preservesExerciseVariants: true)
    }

    private func isolatedStore() throws -> PersistenceController {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("maso-coach-swap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PersistenceController(storageURL: dir.appendingPathComponent("snapshot.json"))
    }

    private static func snapshot(of store: DataStore) -> PersistenceController.Snapshot {
        PersistenceController.Snapshot(
            version: PersistenceController.schemaVersion,
            plans: store.plans, sets: store.sets, settings: store.settings,
            aiTodayPlan: store.aiTodayPlan, lastAIRefreshAt: store.lastAIRefreshAt,
            aiTodayPlanEditedAt: store.aiTodayPlanEditedAt, updatedAt: Date())
    }

    private func reload(_ isolated: PersistenceController, library: [Exercise]) throws -> DataStore {
        let loaded = try XCTUnwrap(isolated.load())
        return DataStore(exercises: library, plans: loaded.plans, sets: loaded.sets, settings: loaded.settings)
    }
}
