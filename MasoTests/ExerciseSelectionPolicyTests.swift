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

    func testCatalogIDsStayUniqueAndLegacyAbductorFolderResolves() {
        let ids = ExerciseLibrary.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(Set(ids).count, policy.sorted(ExerciseLibrary.all).count)
        XCTAssertEqual(ExerciseLibrary.byId["Thigh_Abductor"]?.id, "abductor_machine")
        XCTAssertEqual(ExerciseLibrary.byId["abductor_machine"]?.id, "abductor_machine")
        XCTAssertEqual(ExerciseLibrary.byId["abduction_cable"]?.id, "abduction_cable")
    }

    func testHipAbductionVariantsStayDistinctFromAdduction() throws {
        let machine = try exercise("abductor_machine")
        let cable = try exercise("abduction_cable")
        let adduction = try exercise("adductor_machine")
        XCTAssertEqual(machine.name, "Hip Abduction (Machine)")
        XCTAssertEqual(cable.name, "Hip Abduction (Cable)")
        XCTAssertEqual(machine.localizedName?["zh-Hans"], "髋外展（器械）")
        XCTAssertEqual(cable.localizedName?["zh-Hans"], "髋外展（绳索）")
        XCTAssertNotEqual(machine.localizedName?["zh-Hans"], cable.localizedName?["zh-Hans"])
        XCTAssertEqual(machine.equipment, "abductor_machine")
        XCTAssertEqual(cable.equipment, "cable")
        XCTAssertTrue(machine.instructions.contains { $0.localizedCaseInsensitiveContains("outward") })
        XCTAssertTrue(cable.instructions.contains { $0.localizedCaseInsensitiveContains("out") })
        XCTAssertEqual(policy.metadata(for: machine).pattern, "hip_abduction")
        XCTAssertEqual(policy.metadata(for: cable).pattern, "hip_abduction")
        XCTAssertEqual(policy.metadata(for: adduction).pattern, "hip_adduction")
        XCTAssertEqual(adduction.localizedName?["zh-Hans"], "髋内收（器械）")

        let visible = policy.visibleExercises(from: ExerciseLibrary.all, settings: UserSettings())
        let namedAbduction = visible.filter { $0.name.hasPrefix("Hip Abduction") }
        XCTAssertEqual(Set(namedAbduction.map(\.id)), ["abductor_machine", "abduction_cable"])

        for query in ["hip abduction", "髋外展"] {
            let hits = ExerciseLibrary.all.filter { $0.matchesSearch(exerciseSearchWords(query)) }
            XCTAssertTrue(hits.contains { $0.id == machine.id }, query)
            XCTAssertTrue(hits.contains { $0.id == cable.id }, query)
            XCTAssertTrue(hits.allSatisfy { policy.metadata(for: $0).pattern == "hip_abduction" }, query)
        }
        for query in ["hip adduction", "髋内收"] {
            let hits = ExerciseLibrary.all.filter { $0.matchesSearch(exerciseSearchWords(query)) }
            XCTAssertTrue(hits.contains { $0.id == adduction.id }, query)
            XCTAssertTrue(hits.contains { $0.id == "adduction_cable" }, query)
            XCTAssertTrue(hits.allSatisfy { policy.metadata(for: $0).pattern == "hip_adduction" }, query)
            XCTAssertFalse(hits.contains { $0.id == machine.id }, query)
            XCTAssertFalse(hits.contains { $0.id == cable.id }, query)
        }
    }

    func testHipExtensionSearchUsesReviewedPatternWithoutRenamingOrMixing() throws {
        let expected = Set(ExerciseLibrary.all.filter { policy.metadata(for: $0).pattern == "hip_extension" }.map(\.id))
        XCTAssertTrue(expected.contains("hip_thrust_barbell"))
        XCTAssertTrue(expected.contains("glute_bridge"))
        XCTAssertTrue(expected.contains("cable_kickback"))
        XCTAssertFalse(expected.contains("abductor_machine"))
        XCTAssertFalse(expected.contains("abduction_cable"))
        XCTAssertFalse(expected.contains("adductor_machine"))
        XCTAssertFalse(expected.contains("reverse_hyperextension"))
        for query in ["hip extension", "髋伸展", "髖伸展"] {
            let hits = Set(ExerciseLibrary.all.filter { $0.matchesSearch(exerciseSearchWords(query)) }.map(\.id))
            XCTAssertEqual(hits, expected, query)
        }
        let cable = ExerciseLibrary.all.filter { $0.matchesSearch(exerciseSearchWords("cable hip extension")) }
        XCTAssertTrue(cable.contains { $0.id == "cable_kickback" })
        XCTAssertFalse(cable.contains { $0.id == "hip_thrust_barbell" })
        XCTAssertFalse(cable.contains { $0.id == "abduction_cable" })
        XCTAssertTrue(cable.allSatisfy { policy.metadata(for: $0).pattern == "hip_extension" })

        let reverse = try exercise("reverse_hyperextension")
        XCTAssertEqual(policy.metadata(for: reverse).role, "hip_hinge")
        XCTAssertEqual(policy.metadata(for: reverse).pattern, "hinge")
        XCTAssertFalse(reverse.matchesSearch(exerciseSearchWords("hip extension")))
        XCTAssertFalse(reverse.matchesSearch(exerciseSearchWords("hip")))
        XCTAssertTrue(reverse.matchesSearch(exerciseSearchWords("hyperextension")))
        let thrust = try exercise("hip_thrust_barbell")
        XCTAssertEqual(thrust.name, "Hip Thrust (Barbell)")
        XCTAssertTrue(thrust.matchesSearch(exerciseSearchWords("hip")))
        XCTAssertFalse(thrust.matchesSearch(exerciseSearchWords("extension")))
        XCTAssertTrue(try exercise("leg_extension_machine").matchesSearch(exerciseSearchWords("extension")))
    }

    func testHipReplacementCandidatesKeepMovementAndEquipment() throws {
        let machine = try exercise("abductor_machine")
        let abductionReplacements = policy.replacementCandidates(for: machine, from: ExerciseLibrary.all, settings: UserSettings())
        XCTAssertTrue(abductionReplacements.contains { $0.id == "abduction_cable" })
        XCTAssertFalse(abductionReplacements.contains { $0.id == machine.id })
        XCTAssertFalse(abductionReplacements.contains { policy.metadata(for: $0).pattern == "hip_extension" })
        XCTAssertFalse(abductionReplacements.contains { policy.metadata(for: $0).pattern == "hip_adduction" })

        var cableOnly = UserSettings()
        cableOnly.availableEquipment = ["cable"]
        let cableReplacements = policy.replacementCandidates(for: machine, from: ExerciseLibrary.all, settings: cableOnly)
        XCTAssertTrue(cableReplacements.contains { $0.id == "abduction_cable" })
        XCTAssertTrue(cableReplacements.allSatisfy { policy.equipmentAllows($0, selected: ["cable"]) })
        XCTAssertFalse(cableReplacements.contains { $0.equipment == "abductor_machine" })

        let thrust = try exercise("hip_thrust_barbell")
        let extensionReplacements = policy.replacementCandidates(for: thrust, from: ExerciseLibrary.all, settings: UserSettings())
        XCTAssertTrue(extensionReplacements.contains { $0.id == "glute_bridge" })
        XCTAssertTrue(extensionReplacements.contains { $0.id == "cable_kickback" })
        XCTAssertFalse(extensionReplacements.contains { $0.id == "abductor_machine" || $0.id == "abduction_cable" })
        XCTAssertFalse(extensionReplacements.contains { $0.id == "adductor_machine" || $0.id == "adduction_cable" })
        XCTAssertTrue(extensionReplacements.allSatisfy { policy.metadata(for: $0).pattern == "hip_extension" })

        var machineOnly = UserSettings()
        machineOnly.availableEquipment = ["machine"]
        let machineReplacements = policy.replacementCandidates(for: try exercise("abduction_cable"), from: ExerciseLibrary.all, settings: machineOnly)
        XCTAssertTrue(machineReplacements.contains { $0.id == "abductor_machine" })
        XCTAssertTrue(machineReplacements.allSatisfy { policy.equipmentAllows($0, selected: ["machine"]) })
        XCTAssertFalse(machineReplacements.contains { $0.id == "abduction_cable" })
    }

    @MainActor func testHipAbductionEquipmentVersionsShareOneGroupAndKeepSeparateIDs() throws {
        let machine = try exercise("abductor_machine")
        let cable = try exercise("abduction_cable")
        let lean = try exercise("abductor_machine_lean_forward")
        let side = try exercise("side_leg_raise")
        let sideCable = try exercise("side_leg_raise_cable")
        let adduction = try exercise("adductor_machine")
        XCTAssertEqual(policy.programmingGroupID(for: machine), "hip_abduction")
        XCTAssertEqual(policy.programmingGroupID(for: cable), policy.programmingGroupID(for: machine))
        XCTAssertEqual(policy.displayFamilyID(for: cable), policy.displayFamilyID(for: machine))
        XCTAssertNotEqual(policy.programmingGroupID(for: side), policy.programmingGroupID(for: machine))
        XCTAssertEqual(policy.programmingGroupID(for: sideCable), policy.programmingGroupID(for: side))
        XCTAssertEqual(policy.programmingGroupID(for: adduction), "hip_adduction")

        let members = [machine, cable, lean, side, sideCable, adduction]
        for groupByName in [true, false] {
            let groups = ExerciseGrouping.group(members, groupByName: groupByName)
            let hip = try XCTUnwrap(groups.first { $0.all.contains { $0.id == machine.id } })
            XCTAssertEqual(groups.filter { $0.all.contains { $0.id == machine.id } }.count, 1)
            XCTAssertEqual(Set(hip.all.map(\.id)), [machine.id, cable.id, lean.id], "groupByName \(groupByName)")
            XCTAssertEqual(hip.canonical.id, machine.id)
            XCTAssertEqual(hip.canonical.nameParts?.localizedBase?["en"], "Hip Abduction")
            XCTAssertEqual(hip.canonical.nameParts?.localizedBase?["zh-Hans"], "髋外展")
            XCTAssertTrue(hip.equipmentVariants.contains { $0.id == cable.id })
            XCTAssertEqual(cable.equipment, "cable")
            XCTAssertEqual(machine.equipment, "abductor_machine")
            XCTAssertFalse(hip.all.contains { $0.id == side.id || $0.id == sideCable.id || $0.id == adduction.id })
        }
        XCTAssertEqual(ExerciseLibrary.byId["Thigh_Abductor"]?.id, machine.id)
        XCTAssertEqual(ExerciseLibrary.byId[cable.id]?.id, cable.id)

        let step = PlanStep(id: "hip-load", exerciseId: machine.id, sets: 3, reps: 12,
                            weight: 40, setWeights: [40, 45, 50])
        let plan = Plan(id: "hip-plan", name: "Hip", steps: [step], createdAt: Date(), updatedAt: Date())
        var cableOnly = UserSettings()
        cableOnly.availableEquipment = ["cable"]
        let projected = policy.routineDefaults(plan, library: ExerciseLibrary.all, settings: cableOnly)
        XCTAssertEqual(projected.steps.first?.exerciseId, cable.id)
        XCTAssertNil(projected.steps.first?.weight)
        XCTAssertNil(projected.steps.first?.setWeights)
        XCTAssertEqual(plan.steps.first?.exerciseId, machine.id)
        XCTAssertEqual(plan.steps.first?.weight, 40)
        XCTAssertEqual(plan.steps.first?.setWeights, [40, 45, 50])

        let store = TrainingSessionStore(completionSound: {})
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: ExerciseLibrary.byId))
        defer { store.end() }
        store.replaceStepExercise(step.id, newExerciseId: cable.id, exById: ExerciseLibrary.byId,
                                  defaultRest: 60, defaultBetweenExerciseRest: 90)
        XCTAssertEqual(store.plan?.steps.first?.exerciseId, cable.id)
        XCTAssertNil(store.plan?.steps.first?.weight)
        XCTAssertNil(store.plan?.steps.first?.setWeights)
        XCTAssertEqual(ExerciseLibrary.byId[machine.id]?.name, "Hip Abduction (Machine)")
    }

    func testWorkoutVariantMenuKeepsDefaultInsideTheVariantListOnce() throws {
        let machine = try exercise("abductor_machine")
        let cable = try exercise("abduction_cable")
        let lean = try exercise("abductor_machine_lean_forward")
        let settings = UserSettings()
        let visible = policy.variants(for: machine, in: ExerciseLibrary.all, settings: settings)
        XCTAssertTrue(visible.contains { $0.id == machine.id })
        XCTAssertTrue(visible.contains { $0.id == cable.id })
        XCTAssertFalse(visible.contains { $0.id == lean.id })

        let currentIsDefault = ExerciseGrouping.variantMenuRows(defaultVersion: machine, candidates: visible, current: machine)
        XCTAssertEqual(currentIsDefault.map(\.id).filter { $0 == machine.id }.count, 1)
        XCTAssertEqual(currentIsDefault.map(\.id).filter { $0 == cable.id }.count, 1)
        XCTAssertEqual(currentIsDefault.first?.id, machine.id)
        XCTAssertFalse(currentIsDefault.contains { $0.id == lean.id })

        let currentIsCable = ExerciseGrouping.variantMenuRows(defaultVersion: machine, candidates: visible, current: cable)
        XCTAssertEqual(currentIsCable.map(\.id), currentIsDefault.map(\.id))

        let currentIsFilteredSpecialist = ExerciseGrouping.variantMenuRows(defaultVersion: machine, candidates: visible, current: lean)
        XCTAssertEqual(currentIsFilteredSpecialist.filter { $0.id == lean.id }.count, 1)
        XCTAssertEqual(currentIsFilteredSpecialist.last?.id, lean.id)
        XCTAssertEqual(currentIsFilteredSpecialist.filter { $0.id == machine.id }.count, 1)

        let onlyDefault = ExerciseGrouping.variantMenuRows(defaultVersion: machine, candidates: [machine], current: machine)
        XCTAssertEqual(onlyDefault.map(\.id), [machine.id])
        let filteredDefaultStillShown = ExerciseGrouping.variantMenuRows(defaultVersion: machine, candidates: [cable], current: cable)
        XCTAssertEqual(filteredDefaultStillShown.map(\.id), [machine.id, cable.id])
        let cableOnlyCandidates = visible.filter { $0.equipment == "cable" }
        let cableRows = ExerciseGrouping.variantMenuRows(defaultVersion: policy.defaultVersion(for: cable, in: cableOnlyCandidates + [cable], settings: settings),
                                                         candidates: cableOnlyCandidates, current: cable)
        XCTAssertFalse(cableRows.contains { $0.equipment == "abductor_machine" })
        XCTAssertEqual(cableRows.filter { $0.id == cable.id }.count, 1)
    }

    @MainActor func testExplicitVariantPreferenceDrivesLaterCardsWithoutRecordingItself() throws {
        let barbell = try exercise("bench_press_barbell")
        let machine = try exercise("bench_press_machine")
        let dumbbell = try exercise("bench_press_dumbbell")
        let incline = try exercise("incline_bench_press_barbell")
        let close = try exercise("bench_press_close_grip")
        let squat = try exercise("squat_barbell")
        let library = ExerciseLibrary.all
        XCTAssertEqual(policy.programmingGroupID(for: barbell), policy.programmingGroupID(for: machine))
        XCTAssertEqual(policy.programmingGroupID(for: dumbbell), policy.programmingGroupID(for: barbell))
        XCTAssertNotEqual(policy.programmingGroupID(for: incline), policy.programmingGroupID(for: barbell))
        XCTAssertNotEqual(policy.programmingGroupID(for: close), policy.programmingGroupID(for: barbell))

        var settings = UserSettings()
        let unchanged = policy.explicitVariantPreference(recording: machine, replacing: machine, in: settings)
        XCTAssertNil(unchanged.preferredVariantByProgrammingGroup)
        let otherFamily = policy.explicitVariantPreference(recording: squat, replacing: barbell, in: settings)
        XCTAssertNil(otherFamily.preferredVariantByProgrammingGroup)
        settings = policy.explicitVariantPreference(recording: machine, replacing: barbell, in: settings)
        XCTAssertEqual(settings.preferredVariantByProgrammingGroup, ["bench_press.flat": machine.id])
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.preferredVariantByProgrammingGroup, settings.preferredVariantByProgrammingGroup)
        var otherAccount = UserSettings()
        XCTAssertNil(otherAccount.preferredVariantByProgrammingGroup)
        settings = policy.explicitVariantPreference(recording: dumbbell, replacing: machine, in: settings)
        XCTAssertEqual(settings.preferredVariantByProgrammingGroup?["bench_press.flat"], dumbbell.id)
        XCTAssertNil(otherAccount.preferredVariantByProgrammingGroup)
        settings = policy.explicitVariantPreference(recording: machine, replacing: dumbbell, in: settings)

        let step = PlanStep(id: "bench", exerciseId: barbell.id, sets: 3, reps: 8, weight: 80, setWeights: [80, 80, 80])
        let existing = Plan(id: "saved-bench", name: "Saved", steps: [step], createdAt: Date(), updatedAt: Date())
        let displayed = policy.routineDefaults(existing, library: library, settings: settings)
        XCTAssertEqual(displayed.steps.first?.exerciseId, barbell.id)
        XCTAssertEqual(displayed.steps.first?.weight, 80)
        var preserved = existing
        preserved.preservesExerciseVariants = true
        let imported = policy.routineDefaults(preserved, library: library, settings: settings, useSavedVariantPreference: true)
        XCTAssertEqual(imported.steps.first?.exerciseId, barbell.id)
        XCTAssertEqual(imported.steps.first?.weight, 80)

        let before = settings
        let generated = policy.routineDefaults(existing, library: library, settings: settings, useSavedVariantPreference: true)
        XCTAssertEqual(generated.steps.first?.exerciseId, machine.id)
        XCTAssertNil(generated.steps.first?.weight)
        XCTAssertNil(generated.steps.first?.setWeights)
        XCTAssertEqual(existing.steps.first?.exerciseId, barbell.id)
        XCTAssertEqual(existing.steps.first?.weight, 80)
        XCTAssertEqual(settings.preferredVariantByProgrammingGroup, before.preferredVariantByProgrammingGroup)

        let requested = policy.defaultVersion(for: barbell, in: library, settings: settings,
                                              preferredIDs: [dumbbell.id], useSavedVariantPreference: true)
        XCTAssertEqual(requested.id, dumbbell.id)
        var dumbbellOnly = settings
        dumbbellOnly.availableEquipment = ["dumbbell"]
        let fallback = policy.defaultVersion(for: barbell, in: library, settings: dumbbellOnly, useSavedVariantPreference: true)
        XCTAssertEqual(fallback.id, dumbbell.id)
        XCTAssertEqual(dumbbellOnly.preferredVariantByProgrammingGroup?[policy.programmingGroupID(for: barbell)], machine.id)
        let inclineVersion = policy.defaultVersion(for: incline, in: library, settings: settings, useSavedVariantPreference: true)
        XCTAssertEqual(policy.programmingGroupID(for: inclineVersion), policy.programmingGroupID(for: incline))
        let closeVersion = policy.defaultVersion(for: close, in: library, settings: settings, useSavedVariantPreference: true)
        XCTAssertEqual(policy.programmingGroupID(for: closeVersion), policy.programmingGroupID(for: close))

        var missing = settings
        missing.preferredVariantByProgrammingGroup = ["bench_press.flat": "deleted-bench"]
        let recovered = policy.defaultVersion(for: barbell, in: library, settings: missing, useSavedVariantPreference: true)
        XCTAssertEqual(recovered.id, barbell.id)
        XCTAssertEqual(missing.preferredVariantByProgrammingGroup?["bench_press.flat"], "deleted-bench")
        let canonical = ExerciseLibrary.canonicalSettings(missing, using: ExerciseLibrary.byId)
        XCTAssertEqual(canonical.preferredVariantByProgrammingGroup?["bench_press.flat"], "deleted-bench")

        let ranked = policy.generationCandidates(from: [barbell, machine, dumbbell], settings: settings, maxPerProgrammingGroup: 1)
        XCTAssertEqual(ranked.map(\.id), [machine.id])
        let legs = policy.generationCandidates(from: [squat], settings: settings, maxPerProgrammingGroup: 1)
        XCTAssertFalse(legs.contains { policy.programmingGroupID(for: $0) == policy.programmingGroupID(for: barbell) })

        let data = DataStore(exercises: library, plans: [existing], sets: [
            SetRecord(id: "history", exerciseId: barbell.id, exerciseName: barbell.name, category: barbell.category,
                      weight: 80, reps: 8, duration: nil, performedAt: Date(), planId: existing.id)
        ], settings: UserSettings())
        data.rememberExplicitVariantChoice(from: barbell.id, to: machine.id)
        XCTAssertEqual(data.settings.preferredVariantByProgrammingGroup?[policy.programmingGroupID(for: barbell)], machine.id)
        XCTAssertEqual(data.plans.first?.steps.first?.exerciseId, barbell.id)
        XCTAssertEqual(data.sets.first?.exerciseId, barbell.id)
        XCTAssertEqual(data.sets.first?.weight, 80)
        data.rememberExplicitVariantChoice(from: machine.id, to: machine.id)
        data.rememberExplicitVariantChoice(from: barbell.id, to: squat.id)
        XCTAssertEqual(data.settings.preferredVariantByProgrammingGroup, [policy.programmingGroupID(for: barbell): machine.id])

        var payload = data.buildAIPayload()
        payload.savedVariantByProgrammingGroup = ["bench_press.flat": "pref-secret-not-for-model"]
        let prompt = AIWorkoutService.shared.buildPrompt(payload: payload, library: [barbell])
        XCTAssertFalse(prompt.contains("pref-secret-not-for-model"))
        let json = #"{"name":"Push","steps":[{"exercise_id":"bench_press_barbell","sets":3,"reps":8,"weight_kg":80}]}"#
        let ai = try AIWorkoutService.shared.validatedPlan(fromJSON: json, candidates: [barbell, machine, dumbbell], maxExercises: 4, settings: settings)
        XCTAssertEqual(ai?.steps.first?.exerciseId, machine.id)
        XCTAssertNil(ai?.steps.first?.weight)
        let locked = try AIWorkoutService.shared.validatedPlan(fromJSON: json, candidates: [barbell, machine, dumbbell], maxExercises: 4, settings: settings, lockedIDs: [barbell.id])
        XCTAssertEqual(locked?.steps.first?.exerciseId, barbell.id)
        XCTAssertEqual(locked?.steps.first?.weight, 80)
        XCTAssertEqual(settings.preferredVariantByProgrammingGroup?[policy.programmingGroupID(for: barbell)], machine.id)
    }
}
