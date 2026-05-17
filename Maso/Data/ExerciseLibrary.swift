import Foundation

// 加载 bundled exercises.json (源: yuhonas/free-exercise-db, Unlicense)
// → 转成我们的 Exercise 模型
//
// JSON 原始字段:
//   name (英文), force, level, mechanic, equipment, primaryMuscles[], secondaryMuscles[],
//   instructions[], category (strength|stretching|cardio|...), images[], id
//
// 映射:
//   - id: 直接复用 (= 图片文件夹名)
//   - muscleGroups: primary + secondary, yuhonas 英文名 → 我们的 MuscleGroup 枚举
//   - category: yuhonas "strength" / "stretching" / 等 → 我们的 ExerciseCategory
//   - imageFolder: 跟 id 一致, 用来拼 CDN URL
//   - tags: 用 primaryMuscles 第一个的中文名作 tag

enum ExerciseLibrary {
    static let all: [Exercise] = loadFromBundle()
    static let byId: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static func loadFromBundle() -> [Exercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            assertionFailure("exercises.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode([RawExercise].self, from: data)
            return raw.map(toExercise)
        } catch {
            assertionFailure("Failed to load exercises.json: \(error)")
            return []
        }
    }
}

// MARK: - yuhonas JSON schema

private struct RawExercise: Decodable {
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

private func toExercise(_ r: RawExercise) -> Exercise {
    let primary = r.primaryMuscles.flatMap(muscleMap)
    let secondary = r.secondaryMuscles.flatMap(muscleMap)
    let allMuscles = orderedUnique(primary + secondary)
    let cat = mapCategory(r.category)
    let lvl = ExerciseLevel(rawValue: r.level ?? "")
    let force = ExerciseForce(rawValue: r.force ?? "")
    let primaryTag = r.primaryMuscles.first.map(displayMuscleName) ?? ""
    return Exercise(
        id: r.id,
        name: r.name, // 暂时用英文名; 后续可加中文翻译表
        category: cat,
        tags: primaryTag.isEmpty ? [] : [primaryTag],
        muscleGroups: allMuscles,
        imageFolder: r.id,
        level: lvl,
        force: force,
        equipment: r.equipment,
        instructions: r.instructions
    )
}

private func mapCategory(_ raw: String) -> ExerciseCategory {
    switch raw {
    case "strength", "powerlifting", "olympic weightlifting", "strongman":
        return .strength
    case "cardio":
        return .cardio
    case "stretching", "plyometrics":
        return .flexibility
    default:
        return .strength
    }
}

// yuhonas 英文肌群 → 我们的 MuscleGroup (1 个 in → 1 或多个 out)
// 例: "lats" → [.lats, .upperLats, .lowerLats]? 不展开, 只给主级别即可,
//     高亮渲染时 expandAnatomyMuscles 会自动展子级
private func muscleMap(_ raw: String) -> [MuscleGroup] {
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

// 主肌群 → 英文短标签 (用作 Exercise.tags 显示)
private func displayMuscleName(_ raw: String) -> String {
    switch raw {
    case "abdominals":   return "Abs"
    case "abductors":    return "Abductors"
    case "adductors":    return "Adductors"
    case "biceps":       return "Biceps"
    case "calves":       return "Calves"
    case "chest":        return "Chest"
    case "forearms":     return "Forearms"
    case "glutes":       return "Glutes"
    case "hamstrings":   return "Hamstrings"
    case "lats":         return "Lats"
    case "lower back":   return "Lower Back"
    case "middle back":  return "Mid Back"
    case "neck":         return "Neck"
    case "quadriceps":   return "Quads"
    case "shoulders":    return "Shoulders"
    case "traps":        return "Traps"
    case "triceps":      return "Triceps"
    default:             return raw.capitalized
    }
}

private func orderedUnique(_ arr: [MuscleGroup]) -> [MuscleGroup] {
    var seen: Set<MuscleGroup> = []
    return arr.filter { seen.insert($0).inserted }
}

// MARK: - CDN URL helper

enum ExerciseImageURL {
    /// jsdelivr GitHub CDN — 比 GitHub raw 稳定, 有边缘节点缓存
    /// 例: https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises/Barbell_Bench_Press_-_Medium-Grip/0.jpg
    static func url(folder: String, frame: Int) -> URL? {
        let base = "https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises"
        guard let escaped = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(base)/\(escaped)/\(frame).jpg")
    }
}
