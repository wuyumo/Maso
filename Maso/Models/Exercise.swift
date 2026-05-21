import Foundation

enum ExerciseCategory: String, Codable, Hashable, Sendable {
    case strength
    case cardio
    case flexibility
}

enum ExerciseLevel: String, Codable, Hashable, Sendable {
    case beginner, intermediate, expert
}

enum ExerciseForce: String, Codable, Hashable, Sendable {
    case push, pull, `static`
}

/// 一个动作 (= web 端 Exercise type) — 跟 yuhonas/free-exercise-db 字段对齐
struct Exercise: Identifiable, Hashable, Codable, Sendable {
    let id: String
    /// 原始英文名 (yuhonas JSON 出的). 持久化 / 比较都用这个 — 用户切语言不会"丢" plan.
    let name: String
    let category: ExerciseCategory
    let tags: [String]
    /// 主练肌 — 严格筛选用 (Picker / Library "按肌肉" 过滤命中这一组).
    /// 来源: yuhonas JSON 的 `primaryMuscles` 字段, 不含 secondary.
    /// 即"做这个动作主要练什么", deadlift 只有 `lowerBack` 不会有 `core/glutes/hamstrings`.
    let primaryMuscles: [MuscleGroup]
    /// 全部肌群 = primary + secondary, 去重保留顺序.
    /// 详情页 / 协同肌计算 / 训练后肌肉状态等需要"全景"的地方用这个.
    let muscleGroups: [MuscleGroup]
    /// yuhonas 图片文件夹名 = exercise.id; 用于拼 CDN URL
    let imageFolder: String?
    /// 难度
    var level: ExerciseLevel?
    /// 主要肌群发力方向
    var force: ExerciseForce?
    /// 器械: body only / barbell / dumbbell / cable / machine / kettlebells / other
    var equipment: String?
    /// 指导步骤 (yuhonas instructions, 英文; 后续可翻)
    var instructions: [String]

    /// 本地化展示名 — UI 层都用这个, 不直接用 raw `name`.
    /// 查 `ExerciseNames.strings` (lproj 内自动按 locale 解析). 没找到 key 自动 fallback 英文 raw name.
    ///
    /// 翻译覆盖率 (zh-Hans, 2026-05): ~70% (873 个动作中 ~607 个).
    /// 长尾 30% (含品牌名 / 罕用动作变体) 自动 fallback 英文显示, 不会出现中英混杂.
    var displayName: String {
        let key = self.name
        let localized = NSLocalizedString(
            key,
            tableName: "ExerciseNames",
            bundle: .main,
            value: key,
            comment: "Exercise display name (i18n)"
        )
        return localized
    }

    /// 器械字段的 i18n 显示名. nil → nil (调用方决定空时显示什么).
    /// 之前 PlansScreen 私有维护一份, 提到 model 让所有 view (Picker / Library / Playlist / Grid) 共用.
    var equipmentDisplayName: String? {
        guard let raw = equipment else { return nil }
        return Exercise.equipmentDisplayName(for: raw)
    }

    /// raw equipment 字符串 → i18n 显示文本. 没翻译就 fallback 英文 capitalize.
    /// (e.g. "e-z curl bar" → 英文 "E-z Curl Bar" / 中文 "EZ 杠铃")
    static func equipmentDisplayName(for raw: String) -> String {
        let key = "equipment.\(raw)"
        let fallback = raw.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        return NSLocalizedString(key, value: fallback, comment: "equipment chip label")
    }

    /// 全 app 共用的"器械列表"(按 yuhonas 数据频次降序). nil 跟 "other" 合并.
    /// Picker / Library / Quick workout 共享这一份, 加新器械只改这.
    ///
    /// `stretching` 是"伪器械" — yuhonas 数据没这一项, 我们在 ExerciseLibrary.toExercise
    /// 里 post-load 覆写: 凡是 raw name 含 "stretch" 的动作 equipment 一律改成 stretching.
    /// (中文翻译里"拉伸"对应英文 "stretch", 1:1 命中, 不需要查翻译表.)
    static let knownEquipments: [String] = [
        "barbell", "dumbbell", "body only", "cable", "machine",
        "kettlebells", "bands", "e-z curl bar", "medicine ball",
        "exercise ball", "foam roll", "stretching",
        "other",
    ]

    /// 简化版动作说明 — 1-3 个关键要点, 跟着 locale 显示.
    ///
    /// 数据源 (优先级):
    ///   1. `ExerciseInstructions.strings` 表 (跟 ExerciseNames 同模式, 每语言一份 .lproj).
    ///      key = exercise.name (英文 raw), value = "\n" 分隔的 2-3 个精简步骤.
    ///      由 scripts/simplify_instructions_llm.py LLM 批量生成 → auto_translate 翻译到 12 语言.
    ///   2. Fallback: 原 instructions 前 3 条 + 每条截断到 80 字符 + "…" — 没翻译时 UI 仍能展示,
    ///      不会出现空白; 但用户看到的是原英文 (yuhonas 数据本身就是英文).
    ///
    /// 跟 `displayName` 同模式 — 设计上 LLM 翻译覆盖 80%+, 长尾用 fallback 保持可用.
    var simplifiedInstructions: [String] {
        let key = self.name
        let i18nValue = NSLocalizedString(
            key,
            tableName: "ExerciseInstructions",
            bundle: .main,
            value: "",  // 空 → 走 fallback
            comment: "Simplified exercise instructions (i18n)"
        )
        if !i18nValue.isEmpty {
            // \n 分隔 → 数组. trim 每行空白防多余空格.
            return i18nValue
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        // Fallback: 原 instructions 前 3 条 + 每条截断到 80 字符.
        // verbose 数据 (yuhonas 每条 80-250 字符) → 截断后 ≤ 80 减少视觉冲击.
        return instructions.prefix(3).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count > 80 {
                // 在 80 字符之前找最后一个空格断词, 避免单词中间截
                let cutoff = trimmed.prefix(80)
                if let lastSpace = cutoff.lastIndex(of: " ") {
                    return String(cutoff[..<lastSpace]) + "…"
                }
                return String(cutoff) + "…"
            }
            return trimmed
        }
    }
}
