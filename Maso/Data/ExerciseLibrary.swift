import Foundation

// MARK: - Exercise library loader
//
// 加载 bundled exercises.json → Exercise 模型.
//
// Schema 历史:
//   v1 (yuhonas/free-exercise-db): flat name 字符串, primaryMuscles 字符串数组, equipment 单值
//   v2 (2026-05 重做): nested name {en, zh-Hans}, muscles {primary[{major, sub}], secondary},
//       equipment 数组, 加 movementPattern/tempo/unilateral/mechanic/calories/dangerWarnings/video_url
//
// 自动 detection: 看 JSON 数组第一个 object 的 name 字段是 string 还是 dict.
//
// 兼容旧持久化: 老库 ID (e.g. "Barbell_Bench_Press") 可能存在用户的 plans / sets / favorites 里.
// 新库 ID (e.g. "bench_press_barbell") 跟旧不一样. parser 通过 fuzzy-match 阶段产出的 imageFolder
// 字段保留映射 (新库每个 exercise 的 imageFolder = 对应旧库的 id).
//
// 用户数据迁移见 DataStore.migrateExerciseIdsIfNeeded() (Phase 3c, 暂未实现).

enum ExerciseLibrary {
    static let all: [Exercise] = loadFromBundle()

    /// Lookup map. 包含新库 id (主键) + 旧库 imageFolder 作 alias.
    /// 老用户保存的 plans / sets / favorites 用的是 v1 ID (e.g. "Barbell_Bench_Press") → 透过
    /// imageFolder alias 还能 resolve 到新 Exercise. 不需要一次性 migration, 自然过渡.
    /// 多个 new exercise 可能共享同一个 imageFolder (image sharing for variants), 只取第一个.
    static let byId: [String: Exercise] = {
        var m: [String: Exercise] = [:]
        for ex in all {
            m[ex.id] = ex
        }
        // Add legacy imageFolder aliases (不覆盖已存在的真 id)
        for ex in all {
            if let folder = ex.imageFolder, m[folder] == nil {
                m[folder] = ex
            }
        }
        return m
    }()

    /// 反向 map: 旧库 imageFolder ID → 新库 Exercise. 给需要明确区分新旧 ID 的代码 (e.g. data migration).
    static let byLegacyImageFolder: [String: Exercise] = {
        var m: [String: Exercise] = [:]
        for ex in all {
            if let folder = ex.imageFolder, m[folder] == nil {
                m[folder] = ex
            }
        }
        return m
    }()

    private static func loadFromBundle() -> [Exercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            assertionFailure("exercises.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            // Sniff schema: v2 has objects with `name: {en, zh-Hans}`; v1 has `name: "string"`.
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = array.first,
               let nameField = first["name"],
               nameField is [String: Any] {
                // v2 schema
                let raw = try JSONDecoder().decode([RawExerciseV2].self, from: data)
                return raw.map(toExerciseV2)
            } else {
                // v1 schema (yuhonas legacy)
                let raw = try JSONDecoder().decode([RawExerciseV1].self, from: data)
                return raw.map(toExerciseV1)
            }
        } catch {
            assertionFailure("Failed to load exercises.json: \(error)")
            return []
        }
    }
}

// MARK: - v2 schema (2026-05 redo)

private struct RawExerciseV2: Decodable {
    let id: String
    let name: [String: String]                  // {en, zh-Hans}
    let muscles: V2Muscles
    let equipment: [String]
    let category: String                         // "strength", "stretching", etc.
    let movementPattern: String?
    let mechanic: String?                        // "compound" | "isolation"
    let unilateral: Bool
    let tempo: String
    let level: String
    let force: String                            // "push" | "pull" | "static"
    let imageFolder: String?                     // = legacy v1 id, or null
    let photoURL: String?                        // 单图缩略图完整 URL (Pexels 来源动作), 或 null
    let instructions: [String: [String]]?
    let video_url: String?
    let calories_estimate: V2Calories?
    let danger_warnings: [String: [String]]?
    /// "小众动作" 标记 — score_exercise_commonness.py 评分 < 0 的动作在 JSON 里被打了这个 flag.
    /// 主 ExercisePickerSheet 默认隐藏 niche=true, 单独"Rare exercises"入口才显示. 这样常用 picker
    /// 干净 (新手不会被 Foam Roll / Captains of Crush 之类的怪东西吓到), 又不丢数据.
    let niche: Bool?
    /// 三段式名字切割 (预生成): variation / base / equipment.
    let nameParts: RawNameParts?
}

private struct RawNameParts: Decodable {
    let variation: String?
    let base: String
    let equipment: String?
}

private struct V2Muscles: Decodable {
    let primary: [V2Muscle]
    let secondary: [V2Muscle]
}

private struct V2Muscle: Decodable {
    let major: String
    let sub: String
}

private struct V2Calories: Decodable {
    let low: Int
    let med: Int
    let high: Int
}

private func toExerciseV2(_ r: RawExerciseV2) -> Exercise {
    let primaryMuscles = r.muscles.primary.compactMap(muscleFromV2Pair)
    let secondaryMuscles = r.muscles.secondary.compactMap(muscleFromV2Pair)
    let allMuscles = orderedUnique(primaryMuscles + secondaryMuscles)

    let category = mapCategoryV2(r.category)
    let level = ExerciseLevel(rawValue: r.level)?.normalized
    let force = ExerciseForce(rawValue: r.force)
    let movement = r.movementPattern.flatMap(MovementPattern.init(rawValue:))
    let mechanic = r.mechanic.flatMap(ExerciseMechanic.init(rawValue:))
    let tempo = Tempo(rawValue: r.tempo)
    let videoURL = r.video_url.flatMap(URL.init(string:))

    let primaryEquipment = r.equipment.first
    let calories = r.calories_estimate.map { CaloriesEstimate(low: $0.low, med: $0.med, high: $0.high) }

    let englishName = r.name["en"] ?? r.id

    return Exercise(
        id: r.id,
        name: englishName,
        category: category,
        tags: primaryMuscles.first.map { [$0.displayName] } ?? [],
        primaryMuscles: orderedUnique(primaryMuscles),
        muscleGroups: allMuscles,
        imageFolder: r.imageFolder,
        photoURL: r.photoURL,
        level: level,
        force: force,
        equipment: primaryEquipment,
        equipmentAll: r.equipment,
        instructions: r.instructions?["en"] ?? [],
        movementPattern: movement,
        mechanic: mechanic,
        unilateral: r.unilateral,
        tempo: tempo,
        videoURL: videoURL,
        caloriesEstimate: calories,
        dangerWarnings: r.danger_warnings?["en"],
        localizedInstructions: r.instructions,
        localizedName: r.name,
        localizedDangerWarnings: r.danger_warnings,
        isNiche: r.niche ?? false,
        nameParts: r.nameParts.map { NameParts(variation: $0.variation, base: $0.base, equipment: $0.equipment) }
    )
}

private func mapCategoryV2(_ raw: String) -> ExerciseCategory {
    switch raw {
    case "strength":         return .strength
    case "hypertrophy_focus": return .hypertrophyFocus
    case "cardio":           return .cardio
    case "stretching":       return .stretching
    case "mobility":         return .mobility
    case "plyometric":       return .plyometric
    case "calisthenics":     return .calisthenics
    default:                 return .strength
    }
}

/// 把新 schema 的 (major, sub) pair 映射到现有 MuscleGroup enum.
/// 现有 enum 已经覆盖了大部分 sub-muscle, 这里是 string → enum 的字符串映射.
private func muscleFromV2Pair(_ p: V2Muscle) -> MuscleGroup? {
    // 优先 sub 匹配, 没有 fallback 到 major
    switch p.sub {
    // Chest
    case "upper_chest":     return .upperChest
    case "middle_chest":    return .midChest
    case "lower_chest":     return .lowerChest
    // Back
    case "lats":            return .lats
    case "upper_back":      return .upperLats   // proxy: upper back = upper lats region
    case "lower_back":      return .lowerBack
    case "rear_delt":       return .rearDelts
    case "traps_upper":     return .upperTraps
    case "traps_middle":    return .midTraps
    case "traps_lower":     return .lowerTraps
    case "rhomboids":       return .rhomboids
    case "neck":            return .neck
    // Shoulders
    case "front_delt":      return .frontDelts
    case "side_delt":       return .sideDelts
    case "rotator_cuff":    return .rotatorCuff
    // Arms
    case "biceps":          return .biceps
    case "triceps":         return .triceps
    case "forearms":        return .forearms
    case "brachialis":      return .brachialis
    // Core
    case "abs_upper":       return .upperAbs
    case "abs_lower":       return .lowerAbs
    case "obliques":        return .obliques
    case "transverse":      return .serratus    // proxy: 腹横肌没独立 polygon, 用 serratus 占位
    case "serratus":        return .serratus
    // Legs
    case "quads":           return .quads
    case "hamstrings":      return .hamstrings
    case "glutes":          return .glutes
    case "glutes_med":      return .gluteusMedius
    case "calves":          return .calves
    case "adductors":       return .adductors
    case "abductors":       return .gluteusMedius  // proxy: 髋外展主要靠 glute med
    case "tibialis":        return .tibialisAnterior
    case "hip_flexors":     return .legs           // proxy: 髂腰肌没独立 enum, 归 legs
    default: break
    }
    // sub 没命中 → 用 major 顶级
    switch p.major {
    case "chest":     return .chest
    case "back":      return .back
    case "shoulders": return .shoulders
    case "arms":      return .arms
    case "legs":      return .legs
    case "core":      return .core
    default:          return nil
    }
}

// MARK: - v1 schema (yuhonas legacy)

private struct RawExerciseV1: Decodable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String
    let images: [String]
}

// MARK: - 维护提示 (legacy)
//
// 这个文件是 yuhonas/free-exercise-db → app 内 Exercise 模型 的"映射 + 兜底推断"层.
// 跟新 v2 schema 共存, 由 loadFromBundle() 的 schema 嗅探决定走哪一条路径.

private func toExerciseV1(_ r: RawExerciseV1) -> Exercise {
    var primary = r.primaryMuscles.flatMap(muscleMapV1)
    var secondary = r.secondaryMuscles.flatMap(muscleMapV1)

    let (extraPrimary, extraSecondary) = inferExtraMusclesV1(name: r.name, existingPrimary: primary)
    primary.append(contentsOf: extraPrimary)
    secondary.append(contentsOf: extraSecondary)

    let allMuscles = orderedUnique(primary + secondary)
    let cat = mapCategoryV1(r.category)
    let lvl = ExerciseLevel(rawValue: r.level ?? "")
    let force = ExerciseForce(rawValue: r.force ?? "")
    let primaryTag = r.primaryMuscles.first.map(displayMuscleName) ?? ""

    let inferredEquipment: String? = {
        let lower = r.name.lowercased()
        if lower.contains("stretch") { return "stretching" }
        return r.equipment
    }()

    return Exercise(
        id: r.id,
        name: r.name,
        category: cat,
        tags: primaryTag.isEmpty ? [] : [primaryTag],
        primaryMuscles: orderedUnique(primary),
        muscleGroups: allMuscles,
        imageFolder: r.id,
        level: lvl,
        force: force,
        equipment: inferredEquipment,
        equipmentAll: inferredEquipment.map { [$0] },
        instructions: r.instructions
    )
}

private func inferExtraMusclesV1(
    name: String,
    existingPrimary: [MuscleGroup]
) -> (primary: [MuscleGroup], secondary: [MuscleGroup]) {
    let lower = name.lowercased()
    var extraPrimary: [MuscleGroup] = []
    var extraSecondary: [MuscleGroup] = []

    let strongObliquesKeywords = ["oblique", "side plank", "side bend", "russian twist", "wood chop"]
    let weakObliquesKeywords = ["twist", "rotation"]

    if strongObliquesKeywords.contains(where: { lower.contains($0) }) {
        extraPrimary.append(.obliques)
    } else if weakObliquesKeywords.contains(where: { lower.contains($0) }) {
        let trainsAbs = existingPrimary.contains(.core) || existingPrimary.contains(.abs)
        if trainsAbs {
            extraSecondary.append(.obliques)
        }
    }

    return (extraPrimary, extraSecondary)
}

private func mapCategoryV1(_ raw: String) -> ExerciseCategory {
    switch raw {
    case "strength", "powerlifting", "olympic weightlifting", "strongman":
        return .strength
    case "cardio":
        return .cardio
    case "stretching", "plyometrics":
        return .stretching
    default:
        return .strength
    }
}

private func muscleMapV1(_ raw: String) -> [MuscleGroup] {
    switch raw {
    case "abdominals": return [.core, .abs]
    case "abductors":  return [.gluteusMedius]
    case "adductors":  return [.adductors]
    case "biceps":     return [.biceps]
    case "calves":     return [.calves]
    case "chest":      return [.chest]
    case "forearms":   return [.forearms]
    case "glutes":     return [.glutes, .gluteusMaximus]
    case "hamstrings": return [.hamstrings]
    case "lats":       return [.lats]
    case "lower back": return [.lowerBack]
    case "middle back": return [.midTraps, .rhomboids]
    case "neck":       return [.neck]
    case "quadriceps": return [.quads]
    case "shoulders":  return [.shoulders]
    case "traps":      return [.upperTraps]
    case "triceps":    return [.triceps]
    default:           return []
    }
}

// MARK: - CDN URL helper

enum ExerciseImageURL {
    /// jsdelivr GitHub CDN — 比 GitHub raw 稳定, 有边缘节点缓存.
    /// 例: https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises/Barbell_Bench_Press_-_Medium-Grip/0.jpg
    /// (新 DB 仍引用 yuhonas 旧 image folder; folder 来源 fuzzy match.)
    static func url(folder: String, frame: Int) -> URL? {
        let base = "https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises"
        guard let escaped = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(base)/\(escaped)/\(frame).jpg")
    }
}

// MARK: - Shared helpers

private func orderedUnique<T: Hashable>(_ array: [T]) -> [T] {
    var seen = Set<T>()
    var result: [T] = []
    for item in array {
        if seen.insert(item).inserted {
            result.append(item)
        }
    }
    return result
}

private func displayMuscleName(_ raw: String) -> String {
    raw.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
}
