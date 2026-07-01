import Foundation

// AI Insight Summary — Progress → Insights 顶部"AI 教练小结"卡的数据模型.
//
// 设计原则 (见 docs/ai-insight-summary-design.md §2–§3):
//   - 每个数字都由 DataStore 的既有 helper 确定性算好、"喂给"模型 — LLM 从不自己算/编数字.
//   - Payload 无 PII: 无姓名、无绝对日期 (用 daysAgo)、年龄发送 age band、只发 enum/number 摘要.
//   - 输出 schema 固定; 未知 action.type 从 JSON 降级成 .none (不崩、不误 apply).

// MARK: - 发给 Worker 的确定性 payload (§2)

/// 无 PII 的训练摘要 — 所有数字预先算好. 序列化成 JSON 塞进 prompt.
struct AISummaryPayload: Codable, Sendable {
    struct Profile: Codable, Sendable {
        let goal: String          // 目标 enum, e.g. "hypertrophy"
        let daysPerWeekGoal: Int
        let equipment: String     // 器械 enum, e.g. "full_gym" / "limited"
        let ageBand: String       // e.g. "25-34" / "unknown"
    }
    struct Signal: Codable, Sendable {
        let weeksOfHistory: Int
        let sessions14d: Int
        let thin: Bool            // true → prompt 强制"信号薄, 明确 hedge"
    }
    struct Trend: Codable, Sendable {
        let volumeWoWPct: Int?    // 本周 vs 上周容量 %; nil = 新用户/无对比周
        let volume8wkKg: [Int]    // 近 8 周容量 (kg, 取整), 连续
        let trend: String         // "ramping" / "flat" / "dropping"
        let adherencePct: Int

        enum CodingKeys: String, CodingKey {
            case volumeWoWPct = "volumeWoW_pct"
            case volume8wkKg = "volume8wk_kg"
            case trend
            case adherencePct = "adherence_pct"
        }
    }
    struct TopLift: Codable, Sendable {
        let name: String
        let e1rmNowKg: Int
        let e1rm4wkKg: Int
        let trend: String         // "up" / "flat" / "down"

        enum CodingKeys: String, CodingKey {
            case name
            case e1rmNowKg = "e1rm_now_kg"
            case e1rm4wkKg = "e1rm_4wk_kg"
            case trend
        }
    }
    struct Muscle: Codable, Sendable {
        let section: String       // "legs" / "chest" / ...
        let sets7d: Int
        let band: String          // "underMEV" / "inBand" / "overMAV"
        let daysPerWeek: Double
    }
    struct PR: Codable, Sendable {
        let exercise: String
        let daysAgo: Int
    }
    struct Diagnosis: Codable, Sendable {
        let title: String
        let detail: String
        let focusNote: String     // 机器可读 apply 指令, e.g. "bias the split toward legs"
    }

    let profile: Profile
    let signal: Signal
    let trend: Trend
    let topLift: TopLift?
    let muscles: [Muscle]
    let lagging: String?          // 最欠练部位 label, 或 nil
    let recentPRs: [PR]
    let diagnosis: Diagnosis?     // routineSuggestion() 的预烘诊断; 可能 nil
}

// MARK: - 解析后的 summary (§3 output schema)

/// LLM 返回并解析后的教练小结 — 卡片直接渲染这个.
struct AISummary: Codable, Sendable {
    let tldr: String
    let recommendations: [AIRecommendation]
}

/// 一条建议行 — 标题 + 一句 why + 一个 apply action.
struct AIRecommendation: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let action: AISummaryAction
}

/// 建议的 apply 路径. 未知 type → .none (advice-only, 无按钮).
///
/// v1 只实现 regenerateRoutines + addCoachNote; 模型若返回 add_sets (Phase 3),
/// 解析时折叠成 regenerateRoutines(focusNote: 该肌群) — 见 init(from:).
enum AISummaryAction: Codable, Sendable, Equatable {
    case regenerateRoutines(focusNote: String)
    case addCoachNote(note: String)
    case none

    // JSON 形状: { "type": "...", "focusNote": ..., "muscle": ..., "note": ... }
    private enum CodingKeys: String, CodingKey {
        case type, focusNote, muscle, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? c.decode(String.self, forKey: .type)) ?? "none"
        switch type {
        case "regenerate_routines":
            // focusNote 缺失时容错: 退回空串 (由 caller 兜底成通用重生成).
            let note = (try? c.decode(String.self, forKey: .focusNote)) ?? ""
            self = .regenerateRoutines(focusNote: note)
        case "add_sets":
            // Phase 3 未实现的 in-place add_sets → 折叠成 regenerate_routines,
            // 把 muscle 当 focusNote. 保证 v1 只有一条稳健 apply 路径.
            let muscle = (try? c.decode(String.self, forKey: .muscle)) ?? ""
            let note = muscle.isEmpty ? "" : "add more \(muscle) volume"
            self = .regenerateRoutines(focusNote: note)
        case "add_coach_note":
            let note = (try? c.decode(String.self, forKey: .note)) ?? ""
            self = note.isEmpty ? .none : .addCoachNote(note: note)
        default:
            // 未知/幻觉 type → advice-only, 不崩不误 apply.
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regenerateRoutines(let focusNote):
            try c.encode("regenerate_routines", forKey: .type)
            try c.encode(focusNote, forKey: .focusNote)
        case .addCoachNote(let note):
            try c.encode("add_coach_note", forKey: .type)
            try c.encode(note, forKey: .note)
        case .none:
            try c.encode("none", forKey: .type)
        }
    }
}
