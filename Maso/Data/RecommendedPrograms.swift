import Foundation

// 训练计划科学分类 — 跟 web 端 lib/recommendedPlans.ts 1:1
//   - full-body (1-3 练/周): 3 张全身卡, 覆盖 上/中/下胸 · 上/中/下背 · 股四头/腘绳/臀 · 全部小肌群
//   - balanced (4-5 练/周): 胸/背/腿三选二 × 3 天, 加 1 天补肩/臂/核心 (5 天再加全身轻量)
//   - split (6+ 练/周): 推 / 拉 / 腿 × 2 轮 — 主要肌群周频率 = 2
//
// iOS port 用 yuhonas/free-exercise-db 的真实 exercise ID, 命名跟 ExerciseLibrary 一致.

extension ProgramStyle {
    static func forDays(_ days: Int) -> ProgramStyle {
        if days <= 3 { return .fullBody }
        if days <= 5 { return .balanced }
        return .split
    }
}

enum RecommendedPrograms {
    /// 根据用户的 weeklyTrainingDays 生成对应 program 的 plan 列表
    /// 仅返回库里实际能匹配到 exercise 的 step; 全部 step 缺失则跳过这个 plan
    static func plans(forDays days: Int, now: Date, byId: [String: Exercise]) -> [Plan] {
        switch ProgramStyle.forDays(days) {
        case .fullBody: return fullBodyPlans(days: days, now: now, byId: byId)
        case .balanced: return balancedPlans(days: days, now: now, byId: byId)
        case .split:    return splitPlans(now: now, byId: byId)
        }
    }
}

// MARK: - step helpers

private func step(_ id: String, _ idx: Int, sets: Int, reps: Int, weight: Double, rest: Int,
                  byId: [String: Exercise]) -> PlanStep? {
    guard byId[id] != nil else { return nil }
    return PlanStep(
        id: "step-\(id)-\(idx)",
        exerciseId: id,
        sets: sets, reps: reps, weight: weight,
        restBetweenSets: rest, rest: 0
    )
}

private func timed(_ id: String, _ idx: Int, sets: Int, duration: Int, rest: Int,
                   byId: [String: Exercise]) -> PlanStep? {
    guard byId[id] != nil else { return nil }
    return PlanStep(
        id: "step-\(id)-\(idx)",
        exerciseId: id,
        sets: sets, reps: nil, weight: nil, duration: duration,
        restBetweenSets: rest, rest: 0
    )
}

/// 模板保留全部 step (最多 6). 动作数上限交给 DataStore.tunedRecommendedPlans 按
/// settings.exercisesPerSession 统一裁 —— 单一真相, 不在这里预裁 (否则用户设 6 也只能拿到 4).
private func makePlan(id: String, name: String, steps: [PlanStep?],
                      now: Date, daysAgo: Int) -> Plan? {
    let valid = steps.compactMap { $0 }
    guard !valid.isEmpty else { return nil }
    return Plan(
        id: id,
        // 推荐/种子计划名本地化 — 否则中文用户的 Today 主卡标题是英文 (e.g. "Day C · Legs + Glutes").
        // key = 英文原名; en 走 fallback (= key), zh 在 Localizable.strings 提供译名.
        name: NSLocalizedString(name, comment: "recommended plan name"),
        steps: valid,
        createdAt: now.addingTimeInterval(-Double(daysAgo) * 86400),
        updatedAt: now.addingTimeInterval(-Double(daysAgo) * 86400)
    )
}

// MARK: - Full-body × 3 (1-3 练/周)

private func fullBodyPlans(days: Int, now: Date, byId: [String: Exercise]) -> [Plan] {
    let sessions: [Plan?] = [
        // 全身 A — 上胸 + 股四头 + 上阔背 + 侧束 + 二头 + 核心
        makePlan(id: "plan-fullA", name: "Full Body A · Push / Quads / Pull (Upper)", steps: [
            step("incline_bench_press_barbell", 1, sets: 3, reps: 8,  weight: 45, rest: 120, byId: byId),
            step("squat_barbell",               2, sets: 3, reps: 8,  weight: 80, rest: 150, byId: byId),
            step("pull_up",                     3, sets: 3, reps: 8,  weight: 0,  rest: 90,  byId: byId),
            step("lateral_raise_dumbbell",      4, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("bicep_curl_dumbbell",         5, sets: 3, reps: 10, weight: 12, rest: 60,  byId: byId),
            timed("plank",                      6, sets: 3, duration: 45, rest: 45, byId: byId),
            step("triceps_pushdown_rope",       7, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
            step("leg_curl_lying",              8, sets: 3, reps: 12, weight: 30, rest: 75,  byId: byId),
        ], now: now, daysAgo: 7),
        // 全身 B — 中胸 + 腘绳 + 下阔背 + 前束 + 三头 + 小腿 (+二头 +股四头)
        makePlan(id: "plan-fullB", name: "Full Body B · Push / Hamstrings / Pull (Lower)", steps: [
            step("bench_press_dumbbell",            1, sets: 3, reps: 10, weight: 24, rest: 90,  byId: byId),
            step("rdl_barbell",                     2, sets: 3, reps: 8,  weight: 70, rest: 120, byId: byId),
            step("barbell_row",                     3, sets: 3, reps: 10, weight: 50, rest: 90,  byId: byId),
            step("overhead_press_dumbbell_seated",  4, sets: 3, reps: 8,  weight: 18, rest: 90,  byId: byId),
            step("triceps_pushdown_rope",           5, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
            step("calf_raise_standing",             6, sets: 3, reps: 15, weight: 50, rest: 60,  byId: byId),
            step("bicep_curl_barbell",              7, sets: 3, reps: 10, weight: 25, rest: 60,  byId: byId),
            step("leg_extension_machine",           8, sets: 3, reps: 12, weight: 40, rest: 75,  byId: byId),
        ], now: now, daysAgo: 5),
        // 全身 C — 下胸 + 臀 + 中背 + 后束 + 肱桡 + 腹 (+股四头 +三头)
        makePlan(id: "plan-fullC", name: "Full Body C · Push / Glutes / Pull (Mid)", steps: [
            step("decline_bench_press_barbell", 1, sets: 3, reps: 8,  weight: 55, rest: 120, byId: byId),
            step("hip_thrust_barbell",          2, sets: 3, reps: 10, weight: 80, rest: 90,  byId: byId),
            step("cable_row_seated",            3, sets: 3, reps: 10, weight: 50, rest: 90,  byId: byId),
            step("face_pull",                   4, sets: 3, reps: 12, weight: 15, rest: 60,  byId: byId),
            step("hammer_curl",                 5, sets: 3, reps: 10, weight: 10, rest: 60,  byId: byId),
            step("crunch_cable",                6, sets: 3, reps: 12, weight: 30, rest: 60,  byId: byId),
            step("leg_press_45",                7, sets: 3, reps: 10, weight: 120, rest: 90, byId: byId),
            step("triceps_pushdown_rope",       8, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
        ], now: now, daysAgo: 3),
    ]
    let valid = sessions.compactMap { $0 }
    let capped = Array(valid.prefix(max(1, min(days, 3))))
    return capped
}

// MARK: - Bro Split × 4-5 (4-5 练/周)
//
// 设计哲学 (跟用户要求一致 + 健身房最常见的 4-5 天分化):
//   "每次练 1-2 个大肌群, 附带相应小肌群"
//
// 标准 Bro Split 安排 (Schoenfeld 等研究者也承认这是普通健身房一致的练法):
//   Day A — 推日 (胸 + 三头) — 同 muscle group: pushing
//   Day B — 拉日 (背 + 二头) — 同 muscle group: pulling
//   Day C — 腿日 (股四头 + 腘绳 + 臀 + 小腿)
//   Day D — 肩日 (前/中/后束 + 上斜方 + 前臂)
//   Day E — 手臂 + 核心 (5 天加; 给手臂第二次刺激)
//
// 跟"4 天 Upper/Lower"或"PPL"不同 — Bro Split 把每个 big 肌群单独成日, frequency 1/wk,
// 适合喜欢"每次专注一两块"+ 训练时间长一点的人.

private func balancedPlans(days: Int, now: Date, byId: [String: Exercise]) -> [Plan] {
    var sessions: [Plan?] = [
        // Day A — 胸 + 三头 (推日)
        makePlan(id: "plan-balA", name: "Day A · Chest + Triceps", steps: [
            step("bench_press_barbell",          1, sets: 4, reps: 6,  weight: 60, rest: 150, byId: byId),
            step("incline_bench_press_barbell",  2, sets: 3, reps: 8,  weight: 45, rest: 120, byId: byId),
            step("bench_press_dumbbell",         3, sets: 3, reps: 10, weight: 24, rest: 90,  byId: byId),
            step("cable_fly_flat",               4, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("bench_press_close_grip",       5, sets: 3, reps: 8,  weight: 50, rest: 90,  byId: byId),
            step("triceps_pushdown_rope",        6, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
            step("decline_bench_press_barbell",  7, sets: 3, reps: 8,  weight: 55, rest: 90,  byId: byId),
            step("overhead_extension_cable_rope", 8, sets: 3, reps: 12, weight: 20, rest: 60, byId: byId),
        ], now: now, daysAgo: 10),

        // Day B — 背 + 二头 (拉日) (+上斜方 +二头第二刺激)
        makePlan(id: "plan-balB", name: "Day B · Back + Biceps", steps: [
            step("pull_up",             1, sets: 4, reps: 8,  weight: 0,  rest: 120, byId: byId),
            step("barbell_row",         2, sets: 4, reps: 8,  weight: 55, rest: 120, byId: byId),
            step("lat_pulldown",        3, sets: 3, reps: 10, weight: 45, rest: 90,  byId: byId),
            step("cable_row_seated",    4, sets: 3, reps: 10, weight: 50, rest: 90,  byId: byId),
            step("bicep_curl_barbell",  5, sets: 3, reps: 10, weight: 25, rest: 60,  byId: byId),
            step("bicep_curl_dumbbell", 6, sets: 3, reps: 10, weight: 12, rest: 60,  byId: byId),
            step("shrug_barbell",       7, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("preacher_curl",       8, sets: 3, reps: 10, weight: 20, rest: 75,  byId: byId),
        ], now: now, daysAgo: 8),

        // Day C — 腿 + 臀 + 小腿 (腿日) (+股四头 +单侧)
        makePlan(id: "plan-balC", name: "Day C · Legs + Glutes", steps: [
            step("squat_barbell",               1, sets: 4, reps: 6,  weight: 85, rest: 150, byId: byId),
            step("rdl_barbell",                 2, sets: 3, reps: 8,  weight: 70, rest: 120, byId: byId),
            step("leg_press_45",                3, sets: 3, reps: 10, weight: 120, rest: 90, byId: byId),
            step("hip_thrust_barbell",          4, sets: 3, reps: 10, weight: 80, rest: 90,  byId: byId),
            step("leg_curl_lying",              5, sets: 3, reps: 12, weight: 30, rest: 75,  byId: byId),
            step("calf_raise_standing",         6, sets: 4, reps: 15, weight: 50, rest: 60,  byId: byId),
            step("leg_extension_machine",       7, sets: 3, reps: 12, weight: 40, rest: 75,  byId: byId),
            step("lunge_dumbbell_alternating",  8, sets: 3, reps: 10, weight: 16, rest: 75,  byId: byId),
        ], now: now, daysAgo: 6),

        // Day D — 肩 + 上斜方 + 前臂 (肩日) (+后束 +上斜方)
        makePlan(id: "plan-balD", name: "Day D · Shoulders + Traps", steps: [
            step("overhead_press_barbell",  1, sets: 4, reps: 8,  weight: 40, rest: 120, byId: byId),
            step("arnold_press",            2, sets: 3, reps: 10, weight: 14, rest: 90,  byId: byId),
            step("lateral_raise_dumbbell",  3, sets: 4, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("front_raise_dumbbell",    4, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("face_pull",               5, sets: 3, reps: 12, weight: 15, rest: 60,  byId: byId),
            step("shrug_barbell",           6, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("rear_delt_fly_dumbbell",  7, sets: 3, reps: 14, weight: 8,  rest: 60,  byId: byId),
            step("upright_row_barbell",     8, sets: 3, reps: 12, weight: 30, rest: 60,  byId: byId),
        ], now: now, daysAgo: 4),
    ]
    if days >= 5 {
        // Day E — 手臂 (二头/三头) + 核心 — 给小肌群第二次刺激
        sessions.append(
            makePlan(id: "plan-balE", name: "Day E · Arms + Core", steps: [
                step("preacher_curl",                 1, sets: 3, reps: 10, weight: 20, rest: 75, byId: byId),
                step("hammer_curl",                   2, sets: 3, reps: 10, weight: 10, rest: 60, byId: byId),
                step("overhead_extension_cable_rope", 3, sets: 3, reps: 10, weight: 16, rest: 75, byId: byId),
                step("triceps_pushdown_rope",         4, sets: 3, reps: 12, weight: 25, rest: 60, byId: byId),
                step("crunch_cable",                  5, sets: 3, reps: 12, weight: 30, rest: 60, byId: byId),
                timed("plank",                        6, sets: 3, duration: 50, rest: 45, byId: byId),
                step("bicep_curl_barbell",            7, sets: 3, reps: 10, weight: 25, rest: 60, byId: byId),
                step("russian_twist",                 8, sets: 3, reps: 16, weight: 0,  rest: 60, byId: byId),
            ], now: now, daysAgo: 2)
        )
    }
    return sessions.compactMap { $0 }
}

// MARK: - Split (Push / Pull / Legs × 2) — 6+ 练/周

private func splitPlans(now: Date, byId: [String: Exercise]) -> [Plan] {
    let sessions: [Plan?] = [
        // 推 A · 重 (bench focus)
        makePlan(id: "plan-pushA", name: "Push A · Heavy", steps: [
            step("bench_press_barbell",           1, sets: 4, reps: 6,  weight: 60, rest: 150, byId: byId),
            step("incline_bench_press_dumbbell",  2, sets: 3, reps: 10, weight: 22, rest: 90,  byId: byId),
            step("overhead_press_barbell",        3, sets: 3, reps: 8,  weight: 40, rest: 120, byId: byId),
            step("lateral_raise_dumbbell",        4, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("bench_press_close_grip",        5, sets: 3, reps: 8,  weight: 50, rest: 90,  byId: byId),
            step("triceps_pushdown_rope",         6, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
            step("cable_fly_flat",                7, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("overhead_extension_cable_rope", 8, sets: 3, reps: 12, weight: 20, rest: 60,  byId: byId),
        ], now: now, daysAgo: 12),
        // 拉 A · 重 (deadlift focus) (+阔背 +上斜方)
        makePlan(id: "plan-pullA", name: "Pull A · Heavy", steps: [
            step("deadlift",           1, sets: 4, reps: 5,  weight: 100, rest: 180, byId: byId),
            step("pull_up",            2, sets: 4, reps: 8,  weight: 0,   rest: 120, byId: byId),
            step("barbell_row",        3, sets: 3, reps: 8,  weight: 50,  rest: 90,  byId: byId),
            step("face_pull",          4, sets: 3, reps: 12, weight: 15,  rest: 60,  byId: byId),
            step("bicep_curl_barbell", 5, sets: 3, reps: 10, weight: 25,  rest: 60,  byId: byId),
            step("hammer_curl",        6, sets: 3, reps: 10, weight: 10,  rest: 60,  byId: byId),
            step("lat_pulldown",       7, sets: 3, reps: 10, weight: 45,  rest: 90,  byId: byId),
            step("shrug_barbell",      8, sets: 3, reps: 12, weight: 40,  rest: 60,  byId: byId),
        ], now: now, daysAgo: 10),
        // 腿 A · 股四头主导 (+腘绳后链)
        makePlan(id: "plan-legsA", name: "Legs A · Quads", steps: [
            step("squat_barbell",               1, sets: 4, reps: 6,  weight: 85,  rest: 150, byId: byId),
            step("leg_press_45",                2, sets: 3, reps: 10, weight: 120, rest: 90,  byId: byId),
            step("lunge_dumbbell_alternating",  3, sets: 3, reps: 10, weight: 16,  rest: 90,  byId: byId),
            step("leg_extension_machine",       4, sets: 3, reps: 12, weight: 40,  rest: 75,  byId: byId),
            step("calf_raise_standing",         5, sets: 4, reps: 12, weight: 60,  rest: 60,  byId: byId),
            timed("plank",                      6, sets: 3, duration: 50, rest: 45, byId: byId),
            step("leg_curl_lying",              7, sets: 3, reps: 12, weight: 30,  rest: 75,  byId: byId),
            step("rdl_barbell",                 8, sets: 3, reps: 8,  weight: 70,  rest: 120, byId: byId),
        ], now: now, daysAgo: 8),
        // 推 B · 量 (上胸 / 侧束) (+侧束 +三头)
        makePlan(id: "plan-pushB", name: "Push B · Volume", steps: [
            step("incline_bench_press_barbell",   1, sets: 3, reps: 8,  weight: 45, rest: 120, byId: byId),
            step("bench_press_dumbbell",          2, sets: 3, reps: 10, weight: 24, rest: 90,  byId: byId),
            step("cable_fly_flat",                3, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("arnold_press",                  4, sets: 3, reps: 10, weight: 14, rest: 75,  byId: byId),
            step("front_raise_dumbbell",          5, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("overhead_extension_cable_rope", 6, sets: 3, reps: 10, weight: 16, rest: 60,  byId: byId),
            step("lateral_raise_dumbbell",        7, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("triceps_pushdown_rope",         8, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
        ], now: now, daysAgo: 6),
        // 拉 B · 量 (lat focus + 上斜方) (+后束 +二头)
        makePlan(id: "plan-pullB", name: "Pull B · Volume", steps: [
            step("lat_pulldown",            1, sets: 4, reps: 10, weight: 45, rest: 90, byId: byId),
            step("cable_row_seated",        2, sets: 3, reps: 10, weight: 50, rest: 90, byId: byId),
            step("t_bar_row",               3, sets: 3, reps: 10, weight: 30, rest: 90, byId: byId),
            step("shrug_barbell",           4, sets: 3, reps: 12, weight: 40, rest: 60, byId: byId),
            step("rear_delt_fly_dumbbell",  5, sets: 3, reps: 12, weight: 8,  rest: 60, byId: byId),
            step("preacher_curl",           6, sets: 3, reps: 10, weight: 20, rest: 60, byId: byId),
            step("face_pull",               7, sets: 3, reps: 12, weight: 15, rest: 60, byId: byId),
            step("hammer_curl",             8, sets: 3, reps: 10, weight: 10, rest: 60, byId: byId),
        ], now: now, daysAgo: 4),
        // 腿 B · 腘绳 / 臀主导 (+股四头 +单侧)
        makePlan(id: "plan-legsB", name: "Legs B · Hamstrings / Glutes", steps: [
            step("rdl_barbell",                 1, sets: 4, reps: 6,  weight: 75, rest: 150, byId: byId),
            step("hip_thrust_barbell",          2, sets: 4, reps: 8,  weight: 90, rest: 120, byId: byId),
            step("leg_curl_lying",              3, sets: 3, reps: 12, weight: 30, rest: 75,  byId: byId),
            step("back_extension",              4, sets: 3, reps: 12, weight: 0,  rest: 60,  byId: byId),
            step("calf_raise_seated",           5, sets: 4, reps: 15, weight: 40, rest: 60,  byId: byId),
            step("russian_twist",               6, sets: 3, reps: 16, weight: 0,  rest: 60,  byId: byId),
            step("leg_press_45",                7, sets: 3, reps: 10, weight: 120, rest: 90, byId: byId),
            step("lunge_dumbbell_alternating",  8, sets: 3, reps: 10, weight: 16, rest: 75,  byId: byId),
        ], now: now, daysAgo: 2),
    ]
    return sessions.compactMap { $0 }
}

// MARK: - pickTodayPlan — 选今日推荐
//
// 设计原则 (改自 web 的 lib/todayPlan.ts):
//   主键: **恢复档位** — 目标肌群还在疲劳的 plan 沉底 (兑现首屏恢复模型: 推荐真的"按恢复来")
//   次键: **LRU** — 最久没练那张优先 (lastUsedAt 早的优先) → 形成 A→B→C→A→B→C 循环
//   再次: wantStrengthen 覆盖度 (越多越靠前) → 同档同 LRU 时优先用户想加强的
//   末键: createdAt 早的优先 (兜底)
//
// 恢复档位刻意用粗档 (0/1/2) 而不是连续分: 连续分会让推荐天天跳来跳去不可预测;
// 粗档只在"这张卡的主肌群明显没恢复"时才把它往后推, 全员恢复时完全退化成原 LRU 轮转.
//   avgFatigue < 0.25 → 档 0 (随便练)  /  0.25..<0.5 → 档 1 (有点疲劳)  /  ≥0.5 → 档 2 (别练这组)
//
// 跟 web 的差别: web 是"覆盖度优先"(同一张永远占据顶部), iOS 改成"恢复+LRU 优先"(强制轮转).

func pickTodayPlan(plans: [Plan], settings: UserSettings, exById: [String: Exercise],
                   fatigueMap: [MuscleGroup: Double] = [:]) -> Plan? {
    guard !plans.isEmpty else { return nil }
    let strengthen = Set(settings.wantStrengthen)

    // 给每张 plan 算 wantStrengthen 覆盖分 + 主肌群平均疲劳档
    let scored: [(plan: Plan, fatigueTier: Int, coverage: Int, recency: Date, created: Date)] = plans.map { plan in
        var coverage = 0
        var primaryMuscles: Set<MuscleGroup> = []
        var seen: Set<MuscleGroup> = []
        for s in plan.steps {
            guard let ex = exById[s.exerciseId] else { continue }
            primaryMuscles.formUnion(expandAnatomyMuscles(ex.primaryMuscles))
            // Plan-level去重: 同一肌群在一张卡里只算一次
            for mg in expandAnatomyMuscles(ex.muscleGroups) where !seen.contains(mg) {
                seen.insert(mg)
                if strengthen.contains(mg) { coverage += 1 }
            }
        }
        // 主肌群平均疲劳 → 粗档. 只看 primary (synergist 疲劳不该拦住一张卡).
        var tier = 0
        if !fatigueMap.isEmpty, !primaryMuscles.isEmpty {
            let avg = primaryMuscles.reduce(0.0) { $0 + (fatigueMap[$1] ?? 0) } / Double(primaryMuscles.count)
            tier = avg >= 0.5 ? 2 : (avg >= 0.25 ? 1 : 0)
        }
        return (plan, tier, coverage, plan.lastUsedAt ?? .distantPast, plan.createdAt)
    }
    // 排序: 恢复档 (低=更恢复 优先) → LRU (早的优先) → 覆盖度 (高的优先) → createdAt
    let sorted = scored.sorted { a, b in
        if a.fatigueTier != b.fatigueTier { return a.fatigueTier < b.fatigueTier }
        if a.recency != b.recency { return a.recency < b.recency }
        if a.coverage != b.coverage { return a.coverage > b.coverage }
        return a.created < b.created
    }
    return sorted.first?.plan
}
