import Foundation

/// Familiarity is editorial metadata, separate from exercise difficulty and a user's history.
enum ExerciseSelectionTier: String, Codable, CaseIterable, Sendable {
    case core, supporting, specialist

    var isSpecialist: Bool { self == .specialist }
    fileprivate var order: Int {
        switch self { case .core: return 0; case .supporting: return 1; case .specialist: return 2 }
    }
}

/// Stable IDs group browsing and programming without merging the exercise or its records.
struct ExerciseSelectionMetadata: Codable, Hashable, Sendable {
    let exerciseID: String
    let tier: ExerciseSelectionTier
    let displayFamilyID: String
    let programmingGroupID: String
    let defaultRank: Int
    let role: String
    let pattern: String
}

struct ExerciseSelectionPolicy: Sendable {
    private struct Catalog: Decodable {
        let schemaVersion: Int
        let entries: [ExerciseSelectionMetadata]
    }

    static let shared: ExerciseSelectionPolicy = {
        guard let url = Bundle.main.url(forResource: "exercise-selection", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.schemaVersion == 1 else {
            assertionFailure("exercise-selection.json missing or invalid")
            return ExerciseSelectionPolicy(entries: [])
        }
        return ExerciseSelectionPolicy(entries: catalog.entries)
    }()

    private let entriesByID: [String: ExerciseSelectionMetadata]

    init(entries: [ExerciseSelectionMetadata]) {
        entriesByID = Dictionary(entries.map { ($0.exerciseID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Unknown/custom exercises stay searchable, but require an explicit request for generation.
    func metadata(for exercise: Exercise) -> ExerciseSelectionMetadata {
        entriesByID[exercise.id] ?? ExerciseSelectionMetadata(
            exerciseID: exercise.id, tier: .specialist,
            displayFamilyID: "custom.\(exercise.id)", programmingGroupID: "custom.\(exercise.id)",
            defaultRank: 100_000, role: "custom", pattern: exercise.movementPattern?.rawValue ?? "other"
        )
    }

    func tier(for exercise: Exercise) -> ExerciseSelectionTier { metadata(for: exercise).tier }
    func displayFamilyID(for exercise: Exercise) -> String { metadata(for: exercise).displayFamilyID }
    func programmingGroupID(for exercise: Exercise) -> String { metadata(for: exercise).programmingGroupID }

    /// Fold specialist entries without removing concrete IDs or personal selections.
    func visibleExercises(from exercises: [Exercise], settings: UserSettings, retainingIDs: Set<String> = [], availableMediaIDs: Set<String> = [], legacyOnlyIDs: Set<String> = []) -> [Exercise] {
        let retained = retainingIDs.union(settings.favoriteExerciseIds)
            .union(settings.adoptedNicheExerciseIds).union(settings.customExercises.map(\.id))
        return exercises.filter { exercise in
            let personal = retained.contains(exercise.id)
            let modern = availableMediaIDs.contains(exercise.id)
            if legacyOnlyIDs.contains(exercise.id) && !modern && !personal { return false }
            return !settings.hidesRareVariants || tier(for: exercise) != .specialist || personal || modern
        }
    }

    private func compatibleCategory(_ exercise: Exercise, with original: Exercise) -> Bool {
        let resistance: Set<ExerciseCategory> = [.strength, .hypertrophyFocus, .calisthenics]
        return exercise.category.normalized == original.category.normalized ||
            (resistance.contains(exercise.category.normalized) && resistance.contains(original.category.normalized))
    }

    /// Variants share training intent: flat and incline presses are separate groups.
    func variants(for original: Exercise, in library: [Exercise], settings: UserSettings) -> [Exercise] {
        let group = programmingGroupID(for: original)
        let members = library.filter { programmingGroupID(for: $0) == group && compatibleCategory($0, with: original) }
        let visible = visibleExercises(from: members, settings: settings, retainingIDs: [original.id])
        return sorted(visible)
    }

    /// Stable ordinary form, independent of favorites and translations. Equipment constraints
    /// apply before ranking; a home profile never receives unavailable gym equipment.
    func defaultVersion(for original: Exercise, in library: [Exercise], settings: UserSettings,
                        preserveProgrammingGroup: Bool = true, preferredIDs: Set<String> = []) -> Exercise {
        let family = displayFamilyID(for: original)
        let members = library.filter {
            displayFamilyID(for: $0) == family && compatibleCategory($0, with: original) &&
            (!preserveProgrammingGroup || programmingGroupID(for: $0) == programmingGroupID(for: original)) &&
            equipmentAllows($0, selected: Set(settings.availableEquipment), environment: settings.trainingEnvironment)
        }
        if let pinned = sorted(members.filter { preferredIDs.contains($0.id) && tier(for: $0) != .specialist }).first { return pinned }
        let preferred: [String: String] = ["squat": "squat_barbell", "bench_press": "bench_press_barbell", "row": "barbell_row"]
        if let id = preferred[family], let base = members.first(where: { $0.id == id }) { return base }
        return sorted(members).first ?? original
    }

    /// Defaults are a plan projection; actual historical records and restored live sessions
    /// are never rewritten. When identity changes, its load cannot be copied blindly.
    func routineDefaults(_ plan: Plan, library: [Exercise], settings: UserSettings,
                         preserveProgrammingGroup: Bool = true, preferPinned: Bool = false) -> Plan {
        if plan.preservesExerciseVariants == true || plan.id.hasPrefix("qw-") || plan.id.hasPrefix("session-replay-") { return plan }
        let lookup = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let equipment = Set((plan.constraints ?? []).filter { $0.kind == .equipment }.map(\.value))
        let eligible = library.filter {
            equipment.isEmpty || equipmentAllows($0, selected: equipment)
        }
        var effectiveSettings = settings
        if !equipment.isEmpty {
            effectiveSettings.availableEquipment = Array(equipment)
            effectiveSettings.trainingEnvironment = TrainingEnvironment.forEquipmentOverride(Array(equipment), current: settings.trainingEnvironment)
        }
        var result = plan
        result.steps = plan.steps.map { step in
            guard let original = lookup[step.exerciseId] ?? ExerciseLibrary.byId[step.exerciseId].flatMap({ lookup[$0.id] }) else { return step }
            let base = defaultVersion(for: original, in: eligible, settings: effectiveSettings,
                                      preserveProgrammingGroup: preserveProgrammingGroup,
                                      preferredIDs: preferPinned ? Set(settings.favoriteExerciseIds) : [])
            guard base.id != original.id else { return step }
            return PlanStep(id: step.id, exerciseId: base.id, sets: step.sets, reps: step.reps,
                            weight: nil, setReps: step.setReps, setWeights: nil,
                            setDurations: step.setDurations, duration: step.duration,
                            restBetweenSets: step.restBetweenSets, rest: step.rest,
                            parameterSuggestions: step.parameterSuggestions?.filter { $0.key != "weight" })
        }
        if preferPinned && result.steps.contains(where: { settings.favoriteExerciseIds.contains($0.exerciseId) }) {
            result.preservesExerciseVariants = true
        }
        return result
    }

    /// Language-independent ordering; localization never changes membership or representative IDs.
    func sorted(_ exercises: [Exercise], favoriteIDs: Set<String> = [], recentIDs: [String] = []) -> [Exercise] {
        let recency = Dictionary(recentIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return unique(exercises).sorted { lhs, rhs in
            let lf = favoriteIDs.contains(lhs.id), rf = favoriteIDs.contains(rhs.id)
            if lf != rf { return lf }
            let lr = recency[lhs.id] ?? Int.max, rr = recency[rhs.id] ?? Int.max
            if lr != rr { return lr < rr }
            return editoriallyPrecedes(lhs, rhs)
        }
    }

    /// The default view is the compact core plus personal exercises. Supporting/specialist versions
    /// remain in full search and "all versions", without occupying rows in ordinary browsing.
    func browseCandidates(from exercises: [Exercise], settings: UserSettings, retainingIDs: Set<String> = [], availableMediaIDs: Set<String> = []) -> [Exercise] {
        let personal = Set(settings.favoriteExerciseIds + settings.adoptedNicheExerciseIds + settings.customExercises.map(\.id))
            .union(retainingIDs)
        return sorted(exercises.filter { tier(for: $0) == .core || personal.contains($0.id) || (tier(for: $0) == .specialist && availableMediaIDs.contains($0.id)) },
                      favoriteIDs: Set(settings.favoriteExerciseIds))
    }

    /// Apply constraints before grouping, so a dumbbell-only profile receives its dumbbell version.
    /// Familiarity can rank eligible versions, but never grants specialist eligibility by itself.
    func generationCandidates(
        from exercises: [Exercise], settings: UserSettings? = nil, maximumLevel: ExerciseLevel? = nil,
        allowSpecialistIDs: Set<String> = [], maxPerProgrammingGroup: Int = 2,
        limit: Int? = nil, preferredIDs: Set<String> = []
    ) -> [Exercise] {
        let equipment = Set(settings?.availableEquipment ?? [])
        let filtered = unique(exercises).filter { exercise in
            (tier(for: exercise) != .specialist || allowSpecialistIDs.contains(exercise.id))
                && equipmentAllows(exercise, selected: equipment, environment: settings?.trainingEnvironment)
                && levelAllows(exercise, maximum: maximumLevel)
        }.sorted { lhs, rhs in
            let lf = settings?.favoriteExerciseIds.contains(lhs.id) == true
            let rf = settings?.favoriteExerciseIds.contains(rhs.id) == true
            if lf != rf { return lf }
            let lt = tier(for: lhs).order, rt = tier(for: rhs).order
            if lt != rt { return lt < rt }
            let lp = preferredIDs.contains(lhs.id), rp = preferredIDs.contains(rhs.id)
            if lp != rp { return lp }
            return editoriallyPrecedes(lhs, rhs)
        }
        return limited(filtered, key: programmingGroupID, maximumPerGroup: maxPerProgrammingGroup, limit: limit)
    }

    /// Pick groups before versions. Adding variants cannot increase a movement group's draw weight.
    func programmingGroups(from exercises: [Exercise]) -> [[Exercise]] {
        var result: [[Exercise]] = []
        var positions: [String: Int] = [:]
        for exercise in unique(exercises).sorted(by: editoriallyPrecedes) {
            let key = programmingGroupID(for: exercise)
            if let position = positions[key] { result[position].append(exercise) }
            else { positions[key] = result.count; result.append([exercise]) }
        }
        return result
    }

    /// Replacements preserve the training role first, then primary muscles and familiar equipment.
    func replacementCandidates(
        for original: Exercise, from exercises: [Exercise], settings: UserSettings,
        recentIDs: [String] = [], excludingIDs: Set<String> = [], limit: Int = 6
    ) -> [Exercise] {
        let source = metadata(for: original)
        let personal = Set(settings.favoriteExerciseIds + settings.adoptedNicheExerciseIds + recentIDs)
        let pool = unique(exercises).filter { exercise in
            guard exercise.id != original.id, !excludingIDs.contains(exercise.id),
                  equipmentAllows(exercise, selected: Set(settings.availableEquipment), environment: settings.trainingEnvironment),
                  tier(for: exercise) != .specialist || personal.contains(exercise.id) else { return false }
            let candidate = metadata(for: exercise)
            // Never substitute stretching/cardio for a loaded strength exercise solely on a shared muscle.
            return candidate.role == source.role ||
                (exercise.category.normalized == original.category.normalized &&
                 !Set(exercise.primaryMuscles).isDisjoint(with: original.primaryMuscles))
        }.sorted { lhs, rhs in
            let ls = replacementScore(lhs, original: original, source: source, personalIDs: personal)
            let rs = replacementScore(rhs, original: original, source: source, personalIDs: personal)
            return ls == rs ? editoriallyPrecedes(lhs, rhs) : ls > rs
        }
        return limited(pool, key: displayFamilyID, maximumPerGroup: 2, limit: limit)
    }

    /// Exact-ID allowlist validation and programming deduplication for remote/local generation.
    func sanitizedGeneratedExercises(
        _ generated: [Exercise], allowed: [Exercise], settings: UserSettings? = nil,
        allowSpecialistIDs: Set<String> = []
    ) -> [Exercise] {
        let eligible = generationCandidates(from: allowed, settings: settings,
                                            allowSpecialistIDs: allowSpecialistIDs, maxPerProgrammingGroup: .max)
        let allowedByID = Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return limited(unique(generated).compactMap { allowedByID[$0.id] },
                       key: programmingGroupID, maximumPerGroup: 1, limit: nil)
    }

    /// Benches/racks/plates are attachments in the existing equipment-preference contract.
    /// A second actual resistance source (for example a pull-up band) must also be available.
    func equipmentAllows(_ exercise: Exercise, selected: Set<String>, environment: TrainingEnvironment? = nil) -> Bool {
        let equipment = exercise.equipmentAll ?? exercise.equipment.map { [$0] } ?? []
        let unweighted: Set<String> = ["", "body_only", "bodyweight", "none"]
        if environment == .home || environment == .bodyweight {
            let home = environment == .bodyweight ? [] : HomeTrainingEquipment.allCases.filter {
                selected.contains($0.rawValue) || ($0 == .pullupBar && selected.contains("pullupBar"))
            }
            // Require every actual item. A bench or rack is never implicit at home.
            return equipment.allSatisfy { raw in
                let item = raw.lowercased()
                return unweighted.contains(item) || home.contains { $0.provides(item) }
            }
        }
        guard !selected.isEmpty else { return true }
        let attachments: Set<String> = ["bench_flat", "bench_incline", "bench_decline", "bench", "rack", "power_rack", "squat_rack", "platform", "weight_plate", "plates", "dip_belt", "towel", "push_up_handles", "preacher_bench"]
        for (index, raw) in equipment.enumerated() {
            let item = raw.lowercased()
            if unweighted.contains(item) || (index > 0 && attachments.contains(item)) { continue }
            if attachments.contains(item) { continue }
            guard let category = EquipmentCategory.category(for: item), selected.contains(category.rawValue) else { return false }
        }
        return true
    }

    private func levelAllows(_ exercise: Exercise, maximum: ExerciseLevel?) -> Bool {
        guard let maximum else { return true }
        func rank(_ level: ExerciseLevel) -> Int {
            switch level.normalized { case .beginner: return 0; case .intermediate: return 1; default: return 2 }
        }
        return exercise.level.map { rank($0) <= rank(maximum) } ?? true
    }

    private func editoriallyPrecedes(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        let l = metadata(for: lhs), r = metadata(for: rhs)
        if l.tier.order != r.tier.order { return l.tier.order < r.tier.order }
        if l.defaultRank != r.defaultRank { return l.defaultRank < r.defaultRank }
        return lhs.id < rhs.id
    }

    private func replacementScore(_ exercise: Exercise, original: Exercise, source: ExerciseSelectionMetadata, personalIDs: Set<String>) -> Int {
        let item = metadata(for: exercise)
        var score = 0
        if item.programmingGroupID == source.programmingGroupID { score += 160 }
        if item.role == source.role { score += 80 }
        if item.pattern == source.pattern { score += 30 }
        score += Set(exercise.primaryMuscles).intersection(original.primaryMuscles).count * 12
        if exercise.equipment == original.equipment { score += 8 }
        if personalIDs.contains(exercise.id) { score += 12 }
        score += (2 - item.tier.order) * 10
        return score
    }

    private func unique(_ exercises: [Exercise]) -> [Exercise] {
        var seen = Set<String>()
        return exercises.filter { seen.insert($0.id).inserted }
    }

    private func limited(_ exercises: [Exercise], key: (Exercise) -> String, maximumPerGroup: Int, limit: Int?) -> [Exercise] {
        guard maximumPerGroup > 0, limit.map({ $0 > 0 }) ?? true else { return [] }
        var counts: [String: Int] = [:]
        var result: [Exercise] = []
        for exercise in exercises {
            let group = key(exercise)
            guard counts[group, default: 0] < maximumPerGroup else { continue }
            counts[group, default: 0] += 1
            result.append(exercise)
            if let limit, result.count >= limit { break }
        }
        return result
    }
}
