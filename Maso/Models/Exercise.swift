import Foundation

// MARK: - Top-level Category (扩展为 7 类, 跟新 DB schema 对齐)

enum ExerciseCategory: String, Codable, Hashable, Sendable {
    case strength
    case hypertrophyFocus = "hypertrophy_focus"
    case cardio
    case stretching
    case mobility
    case plyometric
    case calisthenics
    // Legacy compatibility (old DB had .flexibility → maps to .stretching when loading)
    case flexibility       // ⚠️ Legacy — present in old DataStore-persisted plans. New DB never emits this.
}

extension ExerciseCategory {
    /// Normalize legacy category → modern. Use this in UI / filter logic.
    var normalized: ExerciseCategory {
        if self == .flexibility { return .stretching }
        return self
    }

    /// Backwards compat helper — old code that branches on `.flexibility` (e.g. stretching detection)
    /// should keep working. Returns true for both `.flexibility` (legacy) and `.stretching` (new).
    var isStretching: Bool { self == .flexibility || self == .stretching }
}

enum ExerciseLevel: String, Codable, Hashable, Sendable {
    case beginner, intermediate, expert
    /// New DB uses `advanced`; old DB used `expert`. Map both.
    case advanced
}

extension ExerciseLevel {
    /// Normalize advanced → expert (legacy plans use expert).
    var normalized: ExerciseLevel {
        if self == .advanced { return .expert }
        return self
    }
}

enum ExerciseForce: String, Codable, Hashable, Sendable {
    case push, pull, `static`
}

// MARK: - New fields introduced with the 2026-05-23 exercise DB overhaul

/// Biomechanical movement pattern. nil for isolation movements that don't fit.
enum MovementPattern: String, Codable, Hashable, Sendable {
    case pushHorizontal = "push_horizontal"   // Bench press, push-up
    case pushVertical = "push_vertical"       // OHP, pike push-up
    case pullHorizontal = "pull_horizontal"   // Bent-over row
    case pullVertical = "pull_vertical"       // Pull-up, lat pulldown
    case hinge                                 // Deadlift, RDL
    case squat                                 // Squat, lunge
    case lunge                                 // Split-stance (treated separately from squat)
    case rotation                              // Wood chop, med ball throw
}

enum Tempo: String, Codable, Hashable, Sendable {
    case strength       // 1-5 reps, max effort
    case hypertrophy    // 6-12 reps
    case endurance      // 15+ reps
    case explosive      // plyometric speed
    case isometric      // hold
}

enum ExerciseMechanic: String, Codable, Hashable, Sendable {
    case compound, isolation
}

/// Per-bodyweight tier kcal/10min estimate.
struct CaloriesEstimate: Codable, Hashable, Sendable {
    let low: Int    // ~60kg
    let med: Int    // ~75kg
    let high: Int   // ~90kg+
}

// MARK: - Exercise

/// 一个动作 — 跟 2026-05 重做的 schema 1:1 (见 docs/exercise-db-overhaul-plan.md §0.1).
/// 新字段全部 optional, 老 schema 数据也能 decode (向后兼容).
struct Exercise: Identifiable, Hashable, Codable, Sendable {
    let id: String

    /// 原始英文名 (Hevy 命名: 'Bench Press (Dumbbell)'). 持久化 / 比较都用这个.
    let name: String

    /// 顶层类别. 老库 strength/cardio/flexibility 仍兼容 (decode 时映射).
    let category: ExerciseCategory

    /// 显示用 tags (= primaryMuscles 第一个 + 关键词).
    let tags: [String]

    /// 主练肌 — 严格筛选用. 来源新库 `muscles.primary[].sub` 映射成 MuscleGroup.
    let primaryMuscles: [MuscleGroup]

    /// 全部肌群 = primary + secondary, 去重保留顺序.
    let muscleGroups: [MuscleGroup]

    /// jsdelivr CDN 的 image folder. 来源新库 fuzzy match (preserve old) 或 nil (新动作无图).
    let imageFolder: String?

    /// 难度
    var level: ExerciseLevel?

    /// 主要肌群发力方向
    var force: ExerciseForce?

    /// 器械: barbell / dumbbell / cable / machine / kettlebell / ... 老库单值, 新库多值取首.
    var equipment: String?

    /// 完整 equipment 数组 (新 schema). 老库自动包装成 [equipment]. UI 可以筛选多器械动作.
    var equipmentAll: [String]? = nil

    /// 指导步骤 (英文). UI 通过 simplifiedInstructions / localizedInstructions 取本地化.
    var instructions: [String]

    // --- 2026-05 新字段 (全 optional, 向后兼容) ---

    /// 动作模式. nil = isolation / 不分类的动作.
    var movementPattern: MovementPattern? = nil

    /// 复合 / 孤立动作.
    var mechanic: ExerciseMechanic? = nil

    /// true = 单边动作 (Bulgarian Split Squat, Single-Arm Row 等).
    var unilateral: Bool? = nil

    /// 节奏 / 强度 profile (跟 reps 区间挂钩).
    var tempo: Tempo? = nil

    /// YouTube / 在线演示视频 URL. nil = 无.
    var videoURL: URL? = nil

    /// 每 10 分钟热量估算 (按体重 3 档).
    var caloriesEstimate: CaloriesEstimate? = nil

    /// 安全提示 (英文 raw, UI 通过 i18n 查 zh-Hans / 其它).
    var dangerWarnings: [String]? = nil

    /// 本地化 instructions (新库 schema 直接带 en + zh-Hans). UI 优先用这个; 没有 fallback 到
    /// 英文 instructions[] (老 schema).
    var localizedInstructions: [String: [String]]? = nil

    /// 本地化名 (新库 schema 直接带 en + zh-Hans). UI 用 displayName 自动按 locale 选.
    var localizedName: [String: String]? = nil

    /// 本地化 danger warnings.
    var localizedDangerWarnings: [String: [String]]? = nil

    /// "小众动作" flag — JSON `niche: true` 触发. 主 ExercisePickerSheet 默认隐藏这些;
    /// 单独的"Rare exercises" 入口才显示它们 (Foam Roll 全家 / Battle Rope / Hip Abduction
    /// machine / Grip Crusher / Thor's Hammer 等). 默认 false (普通动作).
    var isNiche: Bool = false

    // MARK: - Display helpers

    /// 本地化展示名 — UI 都用这个, 不直接用 raw `name`.
    /// 优先级:
    ///   1. `localizedName` 新库 schema 自带的 zh-Hans / en (locale-aware)
    ///   2. 老查表机制 (ExerciseNames.strings)
    ///   3. fallback 到英文 raw name
    var displayName: String {
        if let map = localizedName {
            // ⚠️ 不能用 Bundle.main.preferredLocalizations — 这是 app launch 缓存, 用户在
            // 应用内切换语言 (LanguageManager) 不会更新. 走 LanguageManager 才能跟随 in-app pick.
            let preferredLang = LanguageManager.currentLanguageCode
            if let localized = map[preferredLang] ?? map["en"] {
                return localized
            }
        }
        // Old fallback path — ExerciseNames.strings lookup
        let key = self.name
        let localized = NSLocalizedString(
            key, tableName: "ExerciseNames", bundle: .main,
            value: key, comment: "Exercise display name (i18n)"
        )
        return localized
    }

    var equipmentDisplayName: String? {
        guard let raw = equipment else { return nil }
        return Exercise.equipmentDisplayName(for: raw)
    }

    static func equipmentDisplayName(for raw: String) -> String {
        let key = "equipment.\(raw)"
        // 数据里 equipment 大量用 snake_case (ez_curl_bar / smith_machine / pull_up_bar / ab_wheel ...).
        // localization key 没全覆盖 → 走 fallback 时, 下划线先变空格再 cap, 不然 chip 上会出现
        // "Ez_curl_bar" / "Smith_machine" 这种丑标签.
        let pretty = raw.replacingOccurrences(of: "_", with: " ")
        let fallback = pretty.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        return NSLocalizedString(key, value: fallback, comment: "equipment chip label")
    }

    /// 全 app 共用的"器械列表" — 新库扩展了不少, 这里只列高频显示用. UI 筛选用 equipmentAll.
    static let knownEquipments: [String] = [
        "barbell", "dumbbell", "body_only", "cable", "machine",
        "kettlebell", "ez_curl_bar", "trap_bar", "smith_machine",
        "bench_flat", "bench_incline", "bench_decline",
        "pull_up_bar", "dip_station", "rings", "trx",
        "medicine_ball", "exercise_ball", "foam_roller",
        "resistance_band", "plyo_box", "sled", "battle_rope",
        "jump_rope", "rowing_machine", "treadmill", "stationary_bike",
        "stretching", "other",
    ]

    /// 简化版动作说明.
    /// 优先级:
    ///   1. 新库 schema localizedInstructions (zh-Hans / en, 直接简短的 2-4 条 form cue)
    ///   2. 老库 ExerciseInstructions.strings 查表
    ///   3. fallback 截断英文 instructions[]
    var simplifiedInstructions: [String] {
        // 新库优先
        if let map = localizedInstructions {
            // ⚠️ 不能用 Bundle.main.preferredLocalizations — 这是 app launch 缓存, 用户在
            // 应用内切换语言 (LanguageManager) 不会更新. 走 LanguageManager 才能跟随 in-app pick.
            let preferredLang = LanguageManager.currentLanguageCode
            if let arr = map[preferredLang] ?? map["en"], !arr.isEmpty {
                return arr
            }
        }
        // 老查表
        let key = self.name
        let i18nValue = NSLocalizedString(
            key, tableName: "ExerciseInstructions", bundle: .main,
            value: "", comment: "Simplified exercise instructions (i18n)"
        )
        if !i18nValue.isEmpty {
            return i18nValue
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        // Fallback: 老库截断
        return instructions.prefix(3).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 80 {
                let cutoff = trimmed.prefix(80)
                if let lastSpace = cutoff.lastIndex(of: " ") {
                    return String(cutoff[..<lastSpace]) + "…"
                }
                return String(cutoff) + "…"
            }
            return trimmed
        }
    }

    /// 本地化的危险提示. 没有就空数组.
    var localizedDangers: [String] {
        if let map = localizedDangerWarnings {
            // ⚠️ 不能用 Bundle.main.preferredLocalizations — 这是 app launch 缓存, 用户在
            // 应用内切换语言 (LanguageManager) 不会更新. 走 LanguageManager 才能跟随 in-app pick.
            let preferredLang = LanguageManager.currentLanguageCode
            if let arr = map[preferredLang] ?? map["en"] {
                return arr
            }
        }
        return dangerWarnings ?? []
    }
}
