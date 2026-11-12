import XCTest
@testable import Maso

final class ExerciseSelectionPolicyTests: XCTestCase {
    private let policy = ExerciseSelectionPolicy.shared

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(ExerciseLibrary.byId[id], "Missing bundled exercise \(id)")
    }

    func testPinnedGenerationBeatsDefaultTierWithoutBypassingEquipmentOrSpecialists() throws {
        let pinned = try exercise("bench_press_dumbbell")
        let base = try exercise("bench_press_barbell")
        var settings = UserSettings()
        settings.favoriteExerciseIds = [pinned.id, "pull_up_one_arm"]
        let candidates = policy.generationCandidates(from: ExerciseLibrary.all, settings: settings, maxPerProgrammingGroup: 1)
        XCTAssertTrue(candidates.contains { $0.id == pinned.id })
        XCTAssertFalse(candidates.contains { $0.id == base.id })
        XCTAssertFalse(candidates.contains { $0.id == "pull_up_one_arm" })
        settings.trainingEnvironment = .bodyweight
        settings.availableEquipment = []
        XCTAssertFalse(policy.generationCandidates(from: [pinned], settings: settings).contains { $0.id == pinned.id })
    }

    func testNewLocalPlanUsesPinnedVersionAndDoesNotTransferDifferentEquipmentLoad() throws {
        let step = PlanStep(id: "s", exerciseId: "bench_press_barbell", sets: 3, reps: 10, weight: 60)
        let plan = Plan(id: "new", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        var settings = UserSettings()
        settings.favoriteExerciseIds = ["bench_press_dumbbell"]
        let result = policy.routineDefaults(plan, library: ExerciseLibrary.all, settings: settings, preferPinned: true)
        XCTAssertEqual(result.steps.first?.exerciseId, "bench_press_dumbbell")
        XCTAssertNil(result.steps.first?.weight)
        XCTAssertEqual(plan.steps.first?.weight, 60)
        XCTAssertEqual(result.preservesExerciseVariants, true)
        XCTAssertEqual(policy.routineDefaults(result, library: ExerciseLibrary.all, settings: settings).steps, result.steps)
        settings.favoriteExerciseIds = []
        XCTAssertEqual(policy.routineDefaults(result, library: ExerciseLibrary.all, settings: settings).steps.first?.exerciseId, "bench_press_dumbbell")
        XCTAssertEqual(policy.routineDefaults(plan, library: ExerciseLibrary.all, settings: settings).steps.first?.exerciseId, "bench_press_barbell")
    }

    func testVariantsPreserveAngleAndGroupEquipmentVersions() throws {
        let flat = try exercise("bench_press_barbell")
        let incline = try exercise("incline_bench_press_dumbbell")
        let settings = UserSettings()
        let variants = policy.variants(for: flat, in: ExerciseLibrary.all, settings: settings)
        XCTAssertTrue(variants.contains { $0.id == "bench_press_dumbbell" })
        XCTAssertTrue(variants.contains { $0.id == "bench_press_machine" })
        XCTAssertFalse(variants.contains { $0.id == incline.id })
        let base = policy.defaultVersion(for: incline, in: ExerciseLibrary.all, settings: settings)
        XCTAssertEqual(policy.programmingGroupID(for: base), policy.programmingGroupID(for: incline))
        XCTAssertNotEqual(policy.programmingGroupID(for: base), policy.programmingGroupID(for: flat))
    }

    func testRoutineDefaultsKeepPrescriptionAndNeverCopyDifferentEquipmentLoad() throws {
        let dumbbell = try exercise("bench_press_dumbbell")
        let step = PlanStep(id: "stable", exerciseId: dumbbell.id, sets: 3, reps: 10,
                            weight: 22, setReps: [8, 9, 10], setWeights: [20, 22, 24],
                            restBetweenSets: 90, rest: 60)
        let plan = Plan(id: "routine", name: "Workout", steps: [step], createdAt: Date(), updatedAt: Date())
        let result = policy.routineDefaults(plan, library: ExerciseLibrary.all, settings: UserSettings())
        XCTAssertEqual(result.steps.first?.exerciseId, "bench_press_barbell")
        XCTAssertEqual(result.steps.first?.id, step.id)
        XCTAssertEqual(result.steps.first?.sets, 3)
        XCTAssertEqual(result.steps.first?.setReps, [8, 9, 10])
        XCTAssertEqual(result.steps.first?.restBetweenSets, 90)
        XCTAssertNil(result.steps.first?.weight)
        XCTAssertNil(result.steps.first?.setWeights)
        XCTAssertEqual(plan.steps.first?.weight, 22, "Projection must not rewrite original records")
        var home = UserSettings()
        home.trainingEnvironment = .home
        home.availableEquipment = ["dumbbell", "bench_flat"]
        XCTAssertEqual(policy.routineDefaults(plan, library: ExerciseLibrary.all, settings: home).steps.first?.exerciseId, dumbbell.id)
        let replay = Plan(id: "session-replay-test", name: plan.name, steps: plan.steps, createdAt: plan.createdAt, updatedAt: plan.updatedAt)
        XCTAssertEqual(policy.routineDefaults(replay, library: ExerciseLibrary.all, settings: UserSettings()).steps, plan.steps)
    }

    func testLegacyOnlyExerciseIsHiddenUntilAdoptedButPersonalUseSurvives() throws {
        let exercise = try exercise("dip_machine")
        XCTAssertEqual(policy.tier(for: exercise), .supporting)
        let legacy: Set<String> = [exercise.id]
        var settings = UserSettings()
        XCTAssertTrue(policy.visibleExercises(from: [exercise], settings: settings, legacyOnlyIDs: legacy).isEmpty)
        settings.hideRareVariants = false
        XCTAssertTrue(policy.visibleExercises(from: [exercise], settings: settings, legacyOnlyIDs: legacy).isEmpty)
        XCTAssertEqual(policy.visibleExercises(from: [exercise], settings: settings, retainingIDs: [exercise.id], legacyOnlyIDs: legacy).count, 1)
        XCTAssertEqual(policy.visibleExercises(from: [exercise], settings: settings, availableMediaIDs: [exercise.id], legacyOnlyIDs: legacy).count, 1)
    }

    func testRareVariantVisibilityRetainsSelectedAndPersonalIDsAndPersists() throws {
        let rare = try exercise("pull_up_one_arm")
        var settings = UserSettings()
        XCTAssertFalse(policy.visibleExercises(from: [rare], settings: settings).contains { $0.id == rare.id })
        XCTAssertEqual(policy.visibleExercises(from: [rare], settings: settings, retainingIDs: [rare.id]).count, 1)
        XCTAssertEqual(policy.visibleExercises(from: [rare], settings: settings, availableMediaIDs: [rare.id]).count, 1)
        XCTAssertTrue(policy.browseCandidates(from: [rare], settings: settings, availableMediaIDs: [rare.id]).contains { $0.id == rare.id })
        settings.hideRareVariants = false
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.hidesRareVariants)
        XCTAssertEqual(policy.visibleExercises(from: [rare], settings: decoded).count, 1)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "hideRareVariants")
        let restored = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(restored.hidesRareVariants)
    }

    func testHomeRequiresBenchesAndEachPieceOfEquipmentExplicitly() throws {
        let bench = try exercise("bench_press_dumbbell")
        let incline = try exercise("incline_bench_press_dumbbell")
        let floor = try exercise("floor_press_dumbbell")
        let assistedPullup = try exercise("pull_up_assisted_band")
        XCTAssertTrue(policy.equipmentAllows(floor, selected: ["dumbbell"], environment: .home))
        XCTAssertFalse(policy.equipmentAllows(bench, selected: ["dumbbell"], environment: .home))
        XCTAssertTrue(policy.equipmentAllows(bench, selected: ["dumbbell", "bench_flat"], environment: .home))
        XCTAssertFalse(policy.equipmentAllows(incline, selected: ["dumbbell", "bench_flat"], environment: .home))
        XCTAssertTrue(policy.equipmentAllows(incline, selected: ["dumbbell", "adjustable_bench"], environment: .home))
        XCTAssertFalse(policy.equipmentAllows(assistedPullup, selected: ["pull_up_bar"], environment: .home))
        XCTAssertTrue(policy.equipmentAllows(assistedPullup, selected: ["pull_up_bar", "bands"], environment: .home))
        XCTAssertFalse(policy.equipmentAllows(floor, selected: [], environment: .home))
        XCTAssertFalse(policy.equipmentAllows(bench, selected: ["dumbbell", "bench_flat"], environment: .bodyweight))
        XCTAssertTrue(policy.equipmentAllows(try exercise("push_up"), selected: [], environment: .home))
        XCTAssertTrue(policy.equipmentAllows(bench, selected: ["dumbbell"]), "Legacy gym behavior remains compatible")
    }

    func testCatalogCoversOriginalIDsAndHasCompactCore() {
        let library = ExerciseLibrary.all
        XCTAssertEqual(library.count, 917)
        XCTAssertEqual(Set(library.map(\.id)).count, 917)
        XCTAssertTrue(library.allSatisfy { policy.metadata(for: $0).defaultRank < 100_000 })
        let coreCount = library.filter { policy.tier(for: $0) == .core }.count
        XCTAssertTrue((100...150).contains(coreCount))
        XCTAssertTrue(library.allSatisfy {
            let item = policy.metadata(for: $0)
            return !item.displayFamilyID.isEmpty && !item.programmingGroupID.isEmpty && !item.role.isEmpty && !item.pattern.isEmpty
        })
    }

    func testDefaultGenerationExcludesSpecialistsEvenWhenFamiliar() throws {
        let rare = try exercise("pull_up_one_arm")
        var settings = UserSettings()
        settings.favoriteExerciseIds = [rare.id]
        settings.adoptedNicheExerciseIds = [rare.id]
        let candidates = policy.generationCandidates(from: ExerciseLibrary.all, settings: settings,
                                                    preferredIDs: [rare.id])
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { policy.tier(for: $0) != .specialist })
        XCTAssertFalse(candidates.contains { $0.id == rare.id })
        let requested = policy.generationCandidates(from: [rare], settings: settings, allowSpecialistIDs: [rare.id])
        XCTAssertEqual(requested.map(\.id), [rare.id])
    }

    func testAddingFiftySpecialistVersionsDoesNotIncreaseGroupWeight() throws {
        let press = try exercise("bench_press_dumbbell")
        let row = try exercise("dumbbell_row_single_arm")
        var entries = [policy.metadata(for: press), policy.metadata(for: row)]
        let variants = (0..<50).map { index -> Exercise in
            let id = "specialty_press_\(index)"
            entries.append(.init(exerciseID: id, tier: .specialist,
                                 displayFamilyID: policy.displayFamilyID(for: press),
                                 programmingGroupID: policy.programmingGroupID(for: press),
                                 defaultRank: 50_000 + index, role: "horizontal_press", pattern: "push_horizontal"))
            return Exercise(id: id, name: id, category: .strength, tags: [],
                            primaryMuscles: press.primaryMuscles, muscleGroups: press.muscleGroups,
                            imageFolder: nil, level: .expert, force: .push, equipment: "dumbbell", instructions: [])
        }
        let extended = ExerciseSelectionPolicy(entries: entries)
        let before = extended.programmingGroups(from: [press, row]).map { Set($0.map(\.id)) }
        let after = extended.programmingGroups(from: [press, row] + variants)
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(Set(after.compactMap(\.first).map { extended.programmingGroupID(for: $0) }).count, 2)
        let ordinaryPool = extended.generationCandidates(from: [press, row] + variants)
        XCTAssertEqual(Set(ordinaryPool.map(\.id)), Set([press.id, row.id]))
        let requestedPool = extended.generationCandidates(from: [press, row] + variants,
                                                         allowSpecialistIDs: Set(variants.map(\.id)), maxPerProgrammingGroup: 1)
        XCTAssertEqual(requestedPool.count, 2)
    }

    func testEquipmentConstraintsRetainDumbbellBenchAndRequireActualSecondEquipment() throws {
        let bench = try exercise("bench_press_dumbbell")
        let cable = try exercise("cable_crossover_mid")
        let bandPullUp = try exercise("pull_up_assisted_band")
        XCTAssertTrue(policy.equipmentAllows(bench, selected: ["dumbbell"]))
        XCTAssertFalse(policy.equipmentAllows(cable, selected: ["dumbbell"]))
        XCTAssertFalse(policy.equipmentAllows(bandPullUp, selected: ["pullupBar"]))
        XCTAssertTrue(policy.equipmentAllows(bandPullUp, selected: ["pullupBar", "bands"]))
        var settings = UserSettings()
        settings.availableEquipment = ["dumbbell"]
        let candidates = policy.generationCandidates(from: ExerciseLibrary.all, settings: settings)
        XCTAssertTrue(candidates.contains { $0.id == bench.id })
        XCTAssertTrue(candidates.contains { $0.id == "rdl_dumbbell" })
        XCTAssertFalse(candidates.contains { $0.id == cable.id })
        XCTAssertTrue(candidates.allSatisfy { policy.equipmentAllows($0, selected: ["dumbbell"]) })
    }

    func testProgrammingPreservesRDLAndTraditionalDeadliftWhileDeduplicatingEquipmentVersions() throws {
        let conventional = try exercise("deadlift")
        let barbellRDL = try exercise("rdl_barbell")
        let dumbbellRDL = try exercise("rdl_dumbbell")
        XCTAssertEqual(policy.displayFamilyID(for: conventional), policy.displayFamilyID(for: barbellRDL))
        XCTAssertNotEqual(policy.programmingGroupID(for: conventional), policy.programmingGroupID(for: barbellRDL))
        XCTAssertEqual(policy.programmingGroupID(for: barbellRDL), policy.programmingGroupID(for: dumbbellRDL))
        let result = policy.sanitizedGeneratedExercises([conventional, dumbbellRDL, barbellRDL],
                                                       allowed: [conventional, dumbbellRDL, barbellRDL])
        XCTAssertEqual(result.map(\.id), [conventional.id, dumbbellRDL.id])
        let rejected = policy.sanitizedGeneratedExercises([conventional, dumbbellRDL], allowed: [dumbbellRDL])
        XCTAssertEqual(rejected.map(\.id), [dumbbellRDL.id])
        XCTAssertNotEqual(policy.programmingGroupID(for: try exercise("squat_barbell")),
                          policy.programmingGroupID(for: try exercise("squat_jump")))
        XCTAssertNotEqual(policy.programmingGroupID(for: try exercise("lunge_reverse_dumbbell")),
                          policy.programmingGroupID(for: try exercise("jumping_lunges")))
    }

    func testDefaultBrowsingRetainsPersonalSpecialistsAndFullSearchRemainsAvailable() throws {
        let rare = try exercise("pull_up_one_arm")
        var settings = UserSettings()
        XCTAssertFalse(policy.browseCandidates(from: ExerciseLibrary.all, settings: settings).contains { $0.id == rare.id })
        XCTAssertTrue(policy.browseCandidates(from: ExerciseLibrary.all, settings: settings,
                                            retainingIDs: [rare.id]).contains { $0.id == rare.id })
        settings.favoriteExerciseIds = [rare.id]
        XCTAssertEqual(policy.browseCandidates(from: ExerciseLibrary.all, settings: settings).first?.id, rare.id)
        XCTAssertEqual(policy.sorted(ExerciseLibrary.all).count, 917)
        XCTAssertFalse(policy.browseCandidates(from: ExerciseLibrary.all, settings: UserSettings()).contains { $0.id == "bayesian_curl" })
        XCTAssertTrue(policy.sorted(ExerciseLibrary.all).contains { $0.id == "bayesian_curl" })
        // The old niche flag incorrectly hid ordinary gym exercises; curated metadata overrides it.
        XCTAssertEqual(policy.tier(for: try exercise("abductor_machine")), .core)
        XCTAssertEqual(policy.tier(for: try exercise("ab_wheel_rollout_kneeling")), .core)
    }

    func testTwelveLanguagesDoNotChangeVisibleIDsOrRepresentatives() {
        let settings = UserSettings()
        let baseline = policy.browseCandidates(from: ExerciseLibrary.all, settings: settings).map(\.id)
        let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]
        for language in languages {
            let translated = ExerciseLibrary.all.map { original -> Exercise in
                var copy = original
                copy.localizedName = [language: "\(language) \(original.id)"]
                if language != "en" { copy.localizedName?["en"] = original.name }
                return copy
            }
            XCTAssertEqual(policy.browseCandidates(from: translated, settings: settings).map(\.id), baseline, language)
        }
    }

    func testReplacementUsesRoleAndLimitsFamilyOccupation() throws {
        let original = try exercise("bench_press_barbell")
        let result = policy.replacementCandidates(for: original, from: ExerciseLibrary.all, settings: UserSettings())
        XCTAssertEqual(result.count, 6)
        XCTAssertFalse(result.contains { $0.id == original.id })
        XCTAssertTrue(result.allSatisfy { policy.tier(for: $0) != .specialist })
        let counts = Dictionary(grouping: result, by: { policy.displayFamilyID(for: $0) }).mapValues(\.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 <= 2 })
        XCTAssertEqual(result.first.map { policy.metadata(for: $0).role }, "horizontal_press")
    }
}
