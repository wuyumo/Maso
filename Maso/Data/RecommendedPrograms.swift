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
        name: name,
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
            step("Barbell_Incline_Bench_Press_-_Medium_Grip", 1, sets: 3, reps: 8,  weight: 45, rest: 120, byId: byId),
            step("Barbell_Squat",                              2, sets: 3, reps: 8,  weight: 80, rest: 150, byId: byId),
            step("Pullups",                                    3, sets: 3, reps: 8,  weight: 0,  rest: 90,  byId: byId),
            step("Side_Lateral_Raise",                         4, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("Dumbbell_Bicep_Curl",                        5, sets: 3, reps: 10, weight: 12, rest: 60,  byId: byId),
            timed("Plank",                                     6, sets: 3, duration: 45, rest: 45, byId: byId),
        ], now: now, daysAgo: 7),
        // 全身 B — 中胸 + 腘绳 + 下阔背 + 前束 + 三头 + 小腿
        makePlan(id: "plan-fullB", name: "Full Body B · Push / Hamstrings / Pull (Lower)", steps: [
            step("Dumbbell_Bench_Press",                       1, sets: 3, reps: 10, weight: 24, rest: 90,  byId: byId),
            step("Romanian_Deadlift",                          2, sets: 3, reps: 8,  weight: 70, rest: 120, byId: byId),
            step("Bent_Over_Barbell_Row",                      3, sets: 3, reps: 10, weight: 50, rest: 90,  byId: byId),
            step("Seated_Dumbbell_Press",                      4, sets: 3, reps: 8,  weight: 18, rest: 90,  byId: byId),
            step("Triceps_Pushdown",                           5, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
            step("Standing_Calf_Raises",                       6, sets: 3, reps: 15, weight: 50, rest: 60,  byId: byId),
        ], now: now, daysAgo: 5),
        // 全身 C — 下胸 + 臀 + 中背 + 后束 + 肱桡 + 腹
        makePlan(id: "plan-fullC", name: "Full Body C · Push / Glutes / Pull (Mid)", steps: [
            step("Decline_Barbell_Bench_Press",                1, sets: 3, reps: 8,  weight: 55, rest: 120, byId: byId),
            step("Barbell_Hip_Thrust",                         2, sets: 3, reps: 10, weight: 80, rest: 90,  byId: byId),
            step("Seated_Cable_Rows",                          3, sets: 3, reps: 10, weight: 50, rest: 90,  byId: byId),
            step("Face_Pull",                                  4, sets: 3, reps: 12, weight: 15, rest: 60,  byId: byId),
            step("Cross_Body_Hammer_Curl",                     5, sets: 3, reps: 10, weight: 10, rest: 60,  byId: byId),
            step("Cable_Crunch",                               6, sets: 3, reps: 12, weight: 30, rest: 60,  byId: byId),
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
            step("Barbell_Bench_Press_-_Medium_Grip",      1, sets: 4, reps: 6,  weight: 60, rest: 150, byId: byId),
            step("Barbell_Incline_Bench_Press_-_Medium_Grip", 2, sets: 3, reps: 8, weight: 45, rest: 120, byId: byId),
            step("Dumbbell_Bench_Press",                   3, sets: 3, reps: 10, weight: 24, rest: 90,  byId: byId),
            step("Flat_Bench_Cable_Flyes",                 4, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("Close-Grip_Barbell_Bench_Press",         5, sets: 3, reps: 8,  weight: 50, rest: 90,  byId: byId),
            step("Triceps_Pushdown",                       6, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
        ], now: now, daysAgo: 10),

        // Day B — 背 + 二头 (拉日)
        makePlan(id: "plan-balB", name: "Day B · Back + Biceps", steps: [
            step("Pullups",                       1, sets: 4, reps: 8,  weight: 0,  rest: 120, byId: byId),
            step("Bent_Over_Barbell_Row",         2, sets: 4, reps: 8,  weight: 55, rest: 120, byId: byId),
            step("Wide-Grip_Lat_Pulldown",        3, sets: 3, reps: 10, weight: 45, rest: 90,  byId: byId),
            step("Seated_Cable_Rows",             4, sets: 3, reps: 10, weight: 50, rest: 90,  byId: byId),
            step("Barbell_Curl",                  5, sets: 3, reps: 10, weight: 25, rest: 60,  byId: byId),
            step("Dumbbell_Bicep_Curl",           6, sets: 3, reps: 10, weight: 12, rest: 60,  byId: byId),
        ], now: now, daysAgo: 8),

        // Day C — 腿 + 臀 + 小腿 (腿日)
        makePlan(id: "plan-balC", name: "Day C · Legs + Glutes", steps: [
            step("Barbell_Squat",            1, sets: 4, reps: 6,  weight: 85, rest: 150, byId: byId),
            step("Romanian_Deadlift",        2, sets: 3, reps: 8,  weight: 70, rest: 120, byId: byId),
            step("Leg_Press",                3, sets: 3, reps: 10, weight: 120, rest: 90, byId: byId),
            step("Barbell_Hip_Thrust",       4, sets: 3, reps: 10, weight: 80, rest: 90,  byId: byId),
            step("Lying_Leg_Curls",          5, sets: 3, reps: 12, weight: 30, rest: 75,  byId: byId),
            step("Standing_Calf_Raises",     6, sets: 4, reps: 15, weight: 50, rest: 60,  byId: byId),
        ], now: now, daysAgo: 6),

        // Day D — 肩 + 上斜方 + 前臂 (肩日)
        makePlan(id: "plan-balD", name: "Day D · Shoulders + Traps", steps: [
            step("Standing_Military_Press",  1, sets: 4, reps: 8,  weight: 40, rest: 120, byId: byId),
            step("Arnold_Dumbbell_Press",    2, sets: 3, reps: 10, weight: 14, rest: 90,  byId: byId),
            step("Side_Lateral_Raise",       3, sets: 4, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("Front_Dumbbell_Raise",     4, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("Face_Pull",                5, sets: 3, reps: 12, weight: 15, rest: 60,  byId: byId),
            step("Barbell_Shrug",            6, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
        ], now: now, daysAgo: 4),
    ]
    if days >= 5 {
        // Day E — 手臂 (二头/三头) + 核心 — 给小肌群第二次刺激
        sessions.append(
            makePlan(id: "plan-balE", name: "Day E · Arms + Core", steps: [
                step("Preacher_Curl",            1, sets: 3, reps: 10, weight: 20, rest: 75, byId: byId),
                step("Cross_Body_Hammer_Curl",   2, sets: 3, reps: 10, weight: 10, rest: 60, byId: byId),
                step("Seated_Triceps_Press",     3, sets: 3, reps: 10, weight: 16, rest: 75, byId: byId),
                step("Triceps_Pushdown",         4, sets: 3, reps: 12, weight: 25, rest: 60, byId: byId),
                step("Cable_Crunch",             5, sets: 3, reps: 12, weight: 30, rest: 60, byId: byId),
                timed("Plank",                   6, sets: 3, duration: 50, rest: 45, byId: byId),
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
            step("Barbell_Bench_Press_-_Medium_Grip", 1, sets: 4, reps: 6,  weight: 60, rest: 150, byId: byId),
            step("Incline_Dumbbell_Press",            2, sets: 3, reps: 10, weight: 22, rest: 90,  byId: byId),
            step("Standing_Military_Press",           3, sets: 3, reps: 8,  weight: 40, rest: 120, byId: byId),
            step("Side_Lateral_Raise",                4, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("Close-Grip_Barbell_Bench_Press",    5, sets: 3, reps: 8,  weight: 50, rest: 90,  byId: byId),
            step("Triceps_Pushdown",                  6, sets: 3, reps: 12, weight: 25, rest: 60,  byId: byId),
        ], now: now, daysAgo: 12),
        // 拉 A · 重 (deadlift focus)
        makePlan(id: "plan-pullA", name: "Pull A · Heavy", steps: [
            step("Barbell_Deadlift",       1, sets: 4, reps: 5,  weight: 100, rest: 180, byId: byId),
            step("Pullups",                2, sets: 4, reps: 8,  weight: 0,   rest: 120, byId: byId),
            step("Bent_Over_Barbell_Row",  3, sets: 3, reps: 8,  weight: 50,  rest: 90,  byId: byId),
            step("Face_Pull",              4, sets: 3, reps: 12, weight: 15,  rest: 60,  byId: byId),
            step("Barbell_Curl",           5, sets: 3, reps: 10, weight: 25,  rest: 60,  byId: byId),
            step("Cross_Body_Hammer_Curl", 6, sets: 3, reps: 10, weight: 10,  rest: 60,  byId: byId),
        ], now: now, daysAgo: 10),
        // 腿 A · 股四头主导
        makePlan(id: "plan-legsA", name: "Legs A · Quads", steps: [
            step("Barbell_Squat",         1, sets: 4, reps: 6,  weight: 85,  rest: 150, byId: byId),
            step("Leg_Press",             2, sets: 3, reps: 10, weight: 120, rest: 90,  byId: byId),
            step("Dumbbell_Lunges",       3, sets: 3, reps: 10, weight: 16,  rest: 90,  byId: byId),
            step("Leg_Extensions",        4, sets: 3, reps: 12, weight: 40,  rest: 75,  byId: byId),
            step("Standing_Calf_Raises",  5, sets: 4, reps: 12, weight: 60,  rest: 60,  byId: byId),
            timed("Plank",                6, sets: 3, duration: 50, rest: 45, byId: byId),
        ], now: now, daysAgo: 8),
        // 推 B · 量 (上胸 / 侧束)
        makePlan(id: "plan-pushB", name: "Push B · Volume", steps: [
            step("Barbell_Incline_Bench_Press_-_Medium_Grip", 1, sets: 3, reps: 8,  weight: 45, rest: 120, byId: byId),
            step("Dumbbell_Bench_Press",                       2, sets: 3, reps: 10, weight: 24, rest: 90,  byId: byId),
            step("Flat_Bench_Cable_Flyes",                                   3, sets: 3, reps: 12, weight: 40, rest: 60,  byId: byId),
            step("Arnold_Dumbbell_Press",                      4, sets: 3, reps: 10, weight: 14, rest: 75,  byId: byId),
            step("Front_Dumbbell_Raise",                       5, sets: 3, reps: 12, weight: 8,  rest: 60,  byId: byId),
            step("Seated_Triceps_Press",                       6, sets: 3, reps: 10, weight: 16, rest: 60,  byId: byId),
        ], now: now, daysAgo: 6),
        // 拉 B · 量 (lat focus + 上斜方)
        makePlan(id: "plan-pullB", name: "Pull B · Volume", steps: [
            step("Wide-Grip_Lat_Pulldown", 1, sets: 4, reps: 10, weight: 45, rest: 90, byId: byId),
            step("Seated_Cable_Rows",      2, sets: 3, reps: 10, weight: 50, rest: 90, byId: byId),
            step("T-Bar_Row_with_Handle",  3, sets: 3, reps: 10, weight: 30, rest: 90, byId: byId),
            step("Barbell_Shrug",          4, sets: 3, reps: 12, weight: 40, rest: 60, byId: byId),
            step("Reverse_Flyes",  5, sets: 3, reps: 12, weight: 8,  rest: 60, byId: byId),
            step("Preacher_Curl",          6, sets: 3, reps: 10, weight: 20, rest: 60, byId: byId),
        ], now: now, daysAgo: 4),
        // 腿 B · 腘绳 / 臀主导
        makePlan(id: "plan-legsB", name: "Legs B · Hamstrings / Glutes", steps: [
            step("Romanian_Deadlift",       1, sets: 4, reps: 6,  weight: 75, rest: 150, byId: byId),
            step("Barbell_Hip_Thrust",      2, sets: 4, reps: 8,  weight: 90, rest: 120, byId: byId),
            step("Lying_Leg_Curls",         3, sets: 3, reps: 12, weight: 30, rest: 75,  byId: byId),
            step("Hyperextensions_Back_Extensions",         4, sets: 3, reps: 12, weight: 0,  rest: 60,  byId: byId),
            step("Seated_Calf_Raise",       5, sets: 4, reps: 15, weight: 40, rest: 60,  byId: byId),
            step("Russian_Twist",           6, sets: 3, reps: 16, weight: 0,  rest: 60,  byId: byId),
        ], now: now, daysAgo: 2),
    ]
    return sessions.compactMap { $0 }
}

// MARK: - pickTodayPlan — 选今日推荐
//
// 设计原则 (改自 web 的 lib/todayPlan.ts):
//   主键: **LRU** — 最久没练那张优先 (lastUsedAt 早的优先) → 形成 A→B→C→A→B→C 循环
//   次键: wantStrengthen 覆盖度 (越多越靠前) → LRU 相同时优先用户想加强的
//   末键: createdAt 早的优先 (兜底)
//
// 跟 web 的差别: web 是"覆盖度优先"(同一张永远占据顶部), iOS 改成"LRU 优先"(强制轮转).
// 用户的"今天 A → 几天后 B → 再几天后 C"诉求, LRU 主导才能真正实现.

func pickTodayPlan(plans: [Plan], settings: UserSettings, exById: [String: Exercise]) -> Plan? {
    guard !plans.isEmpty else { return nil }
    let strengthen = Set(settings.wantStrengthen)

    // 给每张 plan 算 wantStrengthen 覆盖分
    let scored: [(plan: Plan, coverage: Int, recency: Date, created: Date)] = plans.map { plan in
        var coverage = 0
        if !strengthen.isEmpty {
            var seen: Set<MuscleGroup> = []
            for s in plan.steps {
                guard let ex = exById[s.exerciseId] else { continue }
                // Plan-level去重: 同一肌群在一张卡里只算一次
                for mg in expandAnatomyMuscles(ex.muscleGroups) where !seen.contains(mg) {
                    seen.insert(mg)
                    if strengthen.contains(mg) { coverage += 1 }
                }
            }
        }
        return (plan, coverage, plan.lastUsedAt ?? .distantPast, plan.createdAt)
    }
    // 排序: LRU 主键 (早的优先), 同 LRU 用覆盖度 (高的优先), 都同用 createdAt
    let sorted = scored.sorted { a, b in
        if a.recency != b.recency { return a.recency < b.recency }
        if a.coverage != b.coverage { return a.coverage > b.coverage }
        return a.created < b.created
    }
    return sorted.first?.plan
}
