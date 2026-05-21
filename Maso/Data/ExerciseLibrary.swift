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

// MARK: - 维护提示
//
// 这个文件是 yuhonas/free-exercise-db → app 内 Exercise 模型 的"映射 + 兜底推断"层.
// 上游 JSON 是只读快照, 这里两类后处理让数据能贴合 app 的需求:
//
// 1. equipment 覆写 (Task 1 / future):
//    - raw name 含 "stretch" → equipment 强制 "stretching" (不管 yuhonas 原标的什么器械)
//
// 2. muscleGroups 增强 (Task 5 / future):
//    - yuhonas 只有 17 个 muscle 词, 没 "obliques" / "rotator cuff" / etc.
//    - 用 name 关键词 (oblique, twist, rotation, side bend, side plank) 推断 obliques
//    - 关键词分两档:
//        - "Primary" 候选 → 加进 primaryMuscles + muscleGroups 前部
//          (oblique / side plank / side bend / russian twist / wood chop)
//        - "Secondary" 候选 → 加进 muscleGroups 末尾 (作为辅助肌)
//          (twist / rotation, 但限"abdominal" 已经是 primary 的, 避免误判肩关节内外旋)
//    - 推断规则集中写在 inferExtraMuscles() 里, 改维护规则只改这一处.
//
// 想新增"keyword → muscle" 规则: 在 inferExtraMuscles() 加 case, 跑一次 build, 在
// Library 浏览页验证肌群标签是否符合预期. 详见 docs/exercise-data-mapping.md.

private func toExercise(_ r: RawExercise) -> Exercise {
    var primary = r.primaryMuscles.flatMap(muscleMap)
    var secondary = r.secondaryMuscles.flatMap(muscleMap)

    // ── Muscle inference (post-load) ──
    // yuhonas 原数据没分 obliques (它把所有腹肌都标 "abdominals" 而我们的 .obliques 是独立 enum).
    // 用 name 关键词推断给一些被低估的动作补 .obliques (Russian Twist / Side Plank / Wood Chop ...).
    let (extraPrimary, extraSecondary) = inferExtraMuscles(name: r.name, existingPrimary: primary)
    primary.append(contentsOf: extraPrimary)
    secondary.append(contentsOf: extraSecondary)

    let allMuscles = orderedUnique(primary + secondary)
    let cat = mapCategory(r.category)
    let lvl = ExerciseLevel(rawValue: r.level ?? "")
    let force = ExerciseForce(rawValue: r.force ?? "")
    let primaryTag = r.primaryMuscles.first.map(displayMuscleName) ?? ""

    // ── Equipment 覆写 (post-load) ──
    // raw name 含 "stretch" → 视为拉伸器械 (即使 yuhonas 给的是 nil / body only / other).
    // 让 UI 上"拉伸"成为一个独立筛选项, 用户能一键过滤所有拉伸动作.
    let inferredEquipment: String? = {
        let lower = r.name.lowercased()
        if lower.contains("stretch") { return "stretching" }
        return r.equipment
    }()

    return Exercise(
        id: r.id,
        name: r.name, // 暂时用英文名; 后续可加中文翻译表
        category: cat,
        tags: primaryTag.isEmpty ? [] : [primaryTag],
        primaryMuscles: orderedUnique(primary),  // 严格筛选用 — 只保留 yuhonas 标的 primary
        muscleGroups: allMuscles,                // 全景 (primary + secondary) — 详情页/协同肌用
        imageFolder: r.id,
        level: lvl,
        force: force,
        equipment: inferredEquipment,
        instructions: r.instructions
    )
}

// MARK: - Muscle inference rules
//
// 兜底规则: 看动作 raw English name 含的关键词, 补一些 yuhonas 缺标的肌群.
// 目前只针对 obliques (上游 yuhonas 词汇表里没 "obliques", 只有 "abdominals").
// 其他肌肉以后再加规则.
//
// 设计权衡:
//   - "primary" 关键词 (oblique / side plank / side bend / russian twist / wood chop):
//     这些动作 obliques 是主动力, 必须当 primary, 让 picker 严格筛选能命中.
//   - "secondary" 关键词 (twist / rotation):
//     需要做"是否相关"门控 — "internal/external rotation" 是肩袖动作, 不是核心.
//     兜底: 只对 raw primary 已含 abdominals (yuhonas 词) 的动作, twist/rotation
//     才追加 obliques 当 secondary. 这样肩关节旋转动作不会被误判.
//
// 返回值: (extraPrimary, extraSecondary)
private func inferExtraMuscles(
    name: String,
    existingPrimary: [MuscleGroup]
) -> (primary: [MuscleGroup], secondary: [MuscleGroup]) {
    let lower = name.lowercased()
    var extraPrimary: [MuscleGroup] = []
    var extraSecondary: [MuscleGroup] = []

    let strongObliquesKeywords = [
        "oblique",      // "Oblique Crunches" / "Decline Oblique Crunch" / ...
        "side plank",   // "Push Up to Side Plank"
        "side bend",    // "Barbell Side Bend" / "Dumbbell Side Bend"
        "russian twist",
        "wood chop",
    ]
    let weakObliquesKeywords = ["twist", "rotation"]

    // Primary: 强信号 → 直接当主动肌
    if strongObliquesKeywords.contains(where: { lower.contains($0) }) {
        extraPrimary.append(.obliques)
    } else if weakObliquesKeywords.contains(where: { lower.contains($0) }) {
        // Secondary: 弱信号 — 只有已经在练 abs/core 的动作才追加 (避免肩袖旋转误判)
        let trainsAbs = existingPrimary.contains(.core) || existingPrimary.contains(.abs)
        if trainsAbs {
            extraSecondary.append(.obliques)
        }
    }

    return (extraPrimary, extraSecondary)
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
