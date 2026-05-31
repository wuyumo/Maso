import Foundation

// 社区精选训练计划 (Community Plans) — MVP seed 数据
//
// 设计哲学:
//   - 不是用户自动生成的 plan (那是 RecommendedPrograms 的活儿), 而是"图书馆精选"
//   - 用户在 Plans tab 底部点 "Browse community plans" → 进 CommunityScreen → "Add to my plans"
//   - 添加时给 plan 一个新 id (plan-community-<UUID>), clone 进 data.plans
//
// 8 张精选 plan 覆盖常见 split:
//   1. Beginner Full Body 3-day — 新手
//   2. 5x5 Strength (Madcow-style) — 力量
//   3. Push / Pull / Legs 6-day — 进阶
//   4. Upper / Lower 4-day — 中级
//   5. Bro Split 5-day — 健美
//   6. Calisthenics Foundations — 自重 (无器械)
//   7. Powerlifting Prep — 三大项
//   8. Push / Pull 4-day — 简化分化
//
// exercise id 全部用 exercises.json 里已存在的 (已 Python 验证).

struct CommunityPlan: Identifiable, Hashable, Sendable {
    let id: String
    /// 标题 i18n key (会 NSLocalizedString)
    let nameKey: String
    /// 描述 i18n key
    let descKey: String
    /// 训练频率 chip — e.g. "3 days/wk"
    let frequencyDaysPerWeek: Int
    /// 难度 i18n key — "Beginner" / "Intermediate" / "Advanced"
    let levelKey: String
    /// 分类 kicker (英文大写; 不本地化, 是健身界通用术语)
    let kicker: String
    /// 计划包含的 session — 每个 session 是一张 plan, "Add" 会把所有 session 都 clone 进 data.plans
    let sessions: [CommunitySession]

    /// 动作总数 (跨所有 session 求和)
    var totalExerciseCount: Int { sessions.reduce(0) { $0 + $1.steps.count } }
}

/// 一张 session = 将来生成的一个 Plan
struct CommunitySession: Hashable, Sendable {
    /// session 名 i18n key (单独本地化 — e.g. "Push Day", "Pull Day")
    let nameKey: String
    let steps: [CommunityStep]
}

struct CommunityStep: Hashable, Sendable {
    let exerciseId: String
    let sets: Int
    let reps: Int?
    let weight: Double?
    let duration: Int?
    let restBetweenSets: Int

    init(_ id: String, sets: Int, reps: Int, weight: Double, rest: Int) {
        self.exerciseId = id
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.duration = nil
        self.restBetweenSets = rest
    }

    init(timed id: String, sets: Int, duration: Int, rest: Int) {
        self.exerciseId = id
        self.sets = sets
        self.reps = nil
        self.weight = nil
        self.duration = duration
        self.restBetweenSets = rest
    }
}

enum CommunityPlans {
    /// 全部精选 plan, 顺序固定 (列表展示顺序).
    static let all: [CommunityPlan] = [
        beginnerFullBody3Day,
        fiveByFiveStrength,
        pushPullLegs6Day,
        upperLower4Day,
        broSplit5Day,
        calisthenicsFoundations,
        powerliftingPrep,
        pushPull4Day,
    ]

    // MARK: - 1. Beginner Full Body 3-day

    static let beginnerFullBody3Day = CommunityPlan(
        id: "community-beginner-fb-3day",
        nameKey: "community_plan_beginner_fb_3day_name",
        descKey: "community_plan_beginner_fb_3day_desc",
        frequencyDaysPerWeek: 3,
        levelKey: "Beginner",
        kicker: "FULL BODY",
        sessions: [
            CommunitySession(
                nameKey: "community_session_full_body_a",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 3, reps: 8,  weight: 40, rest: 120),
                    CommunityStep("bench_press_barbell",          sets: 3, reps: 8,  weight: 40, rest: 120),
                    CommunityStep("barbell_row",                      sets: 3, reps: 8,  weight: 40, rest: 90),
                    CommunityStep("overhead_press_barbell",                    sets: 3, reps: 10, weight: 30, rest: 90),
                    CommunityStep("bicep_curl_dumbbell",                        sets: 2, reps: 12, weight: 8,  rest: 60),
                    CommunityStep(timed: "Plank",                               sets: 3, duration: 30, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_full_body_b",
                steps: [
                    CommunityStep("rdl_barbell",                          sets: 3, reps: 8,  weight: 50, rest: 120),
                    CommunityStep("bench_press_dumbbell",                       sets: 3, reps: 10, weight: 18, rest: 90),
                    CommunityStep("lat_pulldown",                     sets: 3, reps: 10, weight: 35, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated",                      sets: 3, reps: 10, weight: 12, rest: 90),
                    CommunityStep("triceps_pushdown_rope",                           sets: 2, reps: 12, weight: 20, rest: 60),
                    CommunityStep(timed: "Plank",                               sets: 3, duration: 30, rest: 45),
                ]
            ),
        ]
    )

    // MARK: - 2. 5x5 Strength (Madcow-style)

    static let fiveByFiveStrength = CommunityPlan(
        id: "community-5x5-strength",
        nameKey: "community_plan_5x5_strength_name",
        descKey: "community_plan_5x5_strength_desc",
        frequencyDaysPerWeek: 3,
        levelKey: "Intermediate",
        kicker: "STRENGTH",
        sessions: [
            CommunitySession(
                nameKey: "community_session_strength_a",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 5, reps: 5, weight: 80,  rest: 180),
                    CommunityStep("bench_press_barbell",          sets: 5, reps: 5, weight: 60,  rest: 180),
                    CommunityStep("barbell_row",                      sets: 5, reps: 5, weight: 55,  rest: 180),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_strength_b",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 5, reps: 5, weight: 70,  rest: 180),
                    CommunityStep("overhead_press_barbell",                    sets: 5, reps: 5, weight: 40,  rest: 180),
                    CommunityStep("deadlift",                           sets: 3, reps: 5, weight: 100, rest: 240),
                ]
            ),
        ]
    )

    // MARK: - 3. Push / Pull / Legs 6-day

    static let pushPullLegs6Day = CommunityPlan(
        id: "community-ppl-6day",
        nameKey: "community_plan_ppl_6day_name",
        descKey: "community_plan_ppl_6day_desc",
        frequencyDaysPerWeek: 6,
        levelKey: "Advanced",
        kicker: "PUSH / PULL / LEGS",
        sessions: [
            CommunitySession(
                nameKey: "community_session_push_heavy",
                steps: [
                    CommunityStep("bench_press_barbell",          sets: 4, reps: 6,  weight: 60, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell",                     sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("overhead_press_barbell",                    sets: 3, reps: 8,  weight: 40, rest: 120),
                    CommunityStep("lateral_raise_dumbbell",                         sets: 3, reps: 12, weight: 8,  rest: 60),
                    CommunityStep("bench_press_close_grip",             sets: 3, reps: 8,  weight: 50, rest: 90),
                    CommunityStep("triceps_pushdown_rope",                           sets: 3, reps: 12, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_pull_heavy",
                steps: [
                    CommunityStep("deadlift",                           sets: 4, reps: 5,  weight: 100, rest: 180),
                    CommunityStep("pull_up",                                    sets: 4, reps: 8,  weight: 0,   rest: 120),
                    CommunityStep("barbell_row",                      sets: 3, reps: 8,  weight: 50,  rest: 90),
                    CommunityStep("face_pull",                                  sets: 3, reps: 12, weight: 15,  rest: 60),
                    CommunityStep("bicep_curl_barbell",                               sets: 3, reps: 10, weight: 25,  rest: 60),
                    CommunityStep("cross_body_hammer_curl",                     sets: 3, reps: 10, weight: 10,  rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_legs_quads",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 4, reps: 6,  weight: 85,  rest: 150),
                    CommunityStep("leg_press_45",                                  sets: 3, reps: 10, weight: 120, rest: 90),
                    CommunityStep("lunge_dumbbell_alternating",                            sets: 3, reps: 10, weight: 16,  rest: 90),
                    CommunityStep("leg_extension_machine",                             sets: 3, reps: 12, weight: 40,  rest: 75),
                    CommunityStep("calf_raise_standing",                       sets: 4, reps: 12, weight: 60,  rest: 60),
                ]
            ),
        ]
    )

    // MARK: - 4. Upper / Lower 4-day

    static let upperLower4Day = CommunityPlan(
        id: "community-upper-lower-4day",
        nameKey: "community_plan_upper_lower_4day_name",
        descKey: "community_plan_upper_lower_4day_desc",
        frequencyDaysPerWeek: 4,
        levelKey: "Intermediate",
        kicker: "UPPER / LOWER",
        sessions: [
            CommunitySession(
                nameKey: "community_session_upper",
                steps: [
                    CommunityStep("bench_press_barbell",          sets: 4, reps: 6,  weight: 55, rest: 150),
                    CommunityStep("barbell_row",                      sets: 4, reps: 8,  weight: 50, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated",                      sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("lat_pulldown",                     sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_dumbbell",                        sets: 3, reps: 10, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope",                           sets: 3, reps: 12, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_lower",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 4, reps: 6,  weight: 80, rest: 150),
                    CommunityStep("rdl_barbell",                          sets: 3, reps: 8,  weight: 70, rest: 120),
                    CommunityStep("leg_press_45",                                  sets: 3, reps: 10, weight: 120, rest: 90),
                    CommunityStep("leg_curl_lying",                            sets: 3, reps: 12, weight: 30, rest: 75),
                    CommunityStep("calf_raise_standing",                       sets: 4, reps: 15, weight: 50, rest: 60),
                    CommunityStep(timed: "Plank",                               sets: 3, duration: 45, rest: 45),
                ]
            ),
        ]
    )

    // MARK: - 5. Bro Split 5-day

    static let broSplit5Day = CommunityPlan(
        id: "community-bro-split-5day",
        nameKey: "community_plan_bro_split_5day_name",
        descKey: "community_plan_bro_split_5day_desc",
        frequencyDaysPerWeek: 5,
        levelKey: "Intermediate",
        kicker: "BODY PART SPLIT",
        sessions: [
            CommunitySession(
                nameKey: "community_session_chest_day",
                steps: [
                    CommunityStep("bench_press_barbell",          sets: 4, reps: 6,  weight: 60, rest: 150),
                    CommunityStep("incline_bench_press_barbell",  sets: 3, reps: 8,  weight: 45, rest: 120),
                    CommunityStep("bench_press_dumbbell",                       sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("cable_fly_flat",                     sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("decline_bench_press_barbell",                sets: 3, reps: 10, weight: 50, rest: 90),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_back_day",
                steps: [
                    CommunityStep("pull_up",                                    sets: 4, reps: 8,  weight: 0,  rest: 120),
                    CommunityStep("barbell_row",                      sets: 4, reps: 8,  weight: 55, rest: 120),
                    CommunityStep("lat_pulldown",                     sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated",                          sets: 3, reps: 10, weight: 50, rest: 90),
                    CommunityStep("shrug_barbell",                              sets: 3, reps: 12, weight: 40, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_leg_day",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 4, reps: 6,  weight: 85, rest: 150),
                    CommunityStep("rdl_barbell",                          sets: 3, reps: 8,  weight: 70, rest: 120),
                    CommunityStep("leg_press_45",                                  sets: 3, reps: 10, weight: 120, rest: 90),
                    CommunityStep("leg_curl_lying",                            sets: 3, reps: 12, weight: 30, rest: 75),
                    CommunityStep("calf_raise_standing",                       sets: 4, reps: 15, weight: 50, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_shoulder_day",
                steps: [
                    CommunityStep("overhead_press_barbell",                    sets: 4, reps: 8,  weight: 40, rest: 120),
                    CommunityStep("arnold_press",                      sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell",                         sets: 4, reps: 12, weight: 8,  rest: 60),
                    CommunityStep("front_raise_dumbbell",                       sets: 3, reps: 12, weight: 8,  rest: 60),
                    CommunityStep("face_pull",                                  sets: 3, reps: 12, weight: 15, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_arm_day",
                steps: [
                    CommunityStep("bicep_curl_barbell",                               sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("preacher_curl",                              sets: 3, reps: 10, weight: 20, rest: 75),
                    CommunityStep("cross_body_hammer_curl",                     sets: 3, reps: 10, weight: 10, rest: 60),
                    CommunityStep("bench_press_close_grip",             sets: 3, reps: 8,  weight: 50, rest: 90),
                    CommunityStep("triceps_pushdown_rope",                           sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_cable_rope",                       sets: 3, reps: 10, weight: 16, rest: 75),
                ]
            ),
        ]
    )

    // MARK: - 6. Calisthenics Foundations (自重 — 无器械)

    static let calisthenicsFoundations = CommunityPlan(
        id: "community-calisthenics-foundations",
        nameKey: "community_plan_calisthenics_name",
        descKey: "community_plan_calisthenics_desc",
        frequencyDaysPerWeek: 3,
        levelKey: "Beginner",
        kicker: "BODYWEIGHT",
        sessions: [
            CommunitySession(
                nameKey: "community_session_push_day",
                steps: [
                    CommunityStep("push_up",                                    sets: 4, reps: 10, weight: 0, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps",                     sets: 3, reps: 8,  weight: 0, rest: 90),
                    CommunityStep("push_up",      sets: 3, reps: 8,  weight: 0, rest: 60),
                    CommunityStep(timed: "Plank",                               sets: 3, duration: 45, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_pull_day",
                steps: [
                    CommunityStep("pull_up",                                    sets: 4, reps: 6,  weight: 0, rest: 90),
                    CommunityStep("pull_up_narrow_grip",                                    sets: 3, reps: 6,  weight: 0, rest: 90),
                    CommunityStep("inverted_row",                               sets: 3, reps: 10, weight: 0, rest: 75),
                    CommunityStep("leg_raise_hanging",                          sets: 3, reps: 8,  weight: 0, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_legs_core_day",
                steps: [
                    CommunityStep("squat_bodyweight",                           sets: 4, reps: 20, weight: 0, rest: 60),
                    CommunityStep("lunge_dumbbell_alternating",                            sets: 3, reps: 12, weight: 0, rest: 75),
                    CommunityStep("calf_raise_standing",                       sets: 3, reps: 20, weight: 0, rest: 45),
                    CommunityStep("russian_twist",                              sets: 3, reps: 20, weight: 0, rest: 45),
                    CommunityStep(timed: "Plank",                               sets: 3, duration: 60, rest: 45),
                ]
            ),
        ]
    )

    // MARK: - 7. Powerlifting Prep (三大项)

    static let powerliftingPrep = CommunityPlan(
        id: "community-powerlifting-prep",
        nameKey: "community_plan_powerlifting_name",
        descKey: "community_plan_powerlifting_desc",
        frequencyDaysPerWeek: 4,
        levelKey: "Advanced",
        kicker: "POWERLIFTING",
        sessions: [
            CommunitySession(
                nameKey: "community_session_squat_day",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 5, reps: 3, weight: 100, rest: 240),
                    CommunityStep("rdl_barbell",                          sets: 3, reps: 6, weight: 80,  rest: 150),
                    CommunityStep("leg_press_45",                                  sets: 3, reps: 8, weight: 140, rest: 90),
                    CommunityStep("calf_raise_standing",                       sets: 4, reps: 10, weight: 60, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_bench_day",
                steps: [
                    CommunityStep("bench_press_barbell",          sets: 5, reps: 3, weight: 80,  rest: 240),
                    CommunityStep("bench_press_close_grip",             sets: 3, reps: 6, weight: 65,  rest: 150),
                    CommunityStep("overhead_press_barbell",                    sets: 3, reps: 6, weight: 45,  rest: 120),
                    CommunityStep("triceps_pushdown_rope",                           sets: 3, reps: 10, weight: 30, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_deadlift_day",
                steps: [
                    CommunityStep("deadlift",                           sets: 5, reps: 3, weight: 120, rest: 240),
                    CommunityStep("barbell_row",                      sets: 4, reps: 6, weight: 60,  rest: 120),
                    CommunityStep("pull_up",                                    sets: 4, reps: 6, weight: 0,   rest: 90),
                    CommunityStep("shrug_barbell",                              sets: 3, reps: 10, weight: 50, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_accessory_day",
                steps: [
                    CommunityStep("squat_barbell",                              sets: 4, reps: 5, weight: 70,  rest: 150),
                    CommunityStep("bench_press_barbell",          sets: 4, reps: 5, weight: 55,  rest: 150),
                    CommunityStep("bicep_curl_barbell",                               sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep(timed: "Plank",                               sets: 3, duration: 60, rest: 45),
                ]
            ),
        ]
    )

    // MARK: - 8. Push / Pull 4-day (简化分化)

    static let pushPull4Day = CommunityPlan(
        id: "community-push-pull-4day",
        nameKey: "community_plan_push_pull_4day_name",
        descKey: "community_plan_push_pull_4day_desc",
        frequencyDaysPerWeek: 4,
        levelKey: "Intermediate",
        kicker: "PUSH / PULL",
        sessions: [
            CommunitySession(
                nameKey: "community_session_push_simple",
                steps: [
                    CommunityStep("bench_press_barbell",          sets: 4, reps: 8,  weight: 55, rest: 120),
                    CommunityStep("squat_barbell",                              sets: 4, reps: 8,  weight: 75, rest: 150),
                    CommunityStep("overhead_press_barbell",                    sets: 3, reps: 10, weight: 35, rest: 90),
                    CommunityStep("lunge_dumbbell_alternating",                            sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("triceps_pushdown_rope",                           sets: 3, reps: 12, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "community_session_pull_simple",
                steps: [
                    CommunityStep("deadlift",                           sets: 4, reps: 6,  weight: 90, rest: 180),
                    CommunityStep("pull_up",                                    sets: 4, reps: 8,  weight: 0,  rest: 120),
                    CommunityStep("barbell_row",                      sets: 3, reps: 10, weight: 50, rest: 90),
                    CommunityStep("face_pull",                                  sets: 3, reps: 12, weight: 15, rest: 60),
                    CommunityStep("bicep_curl_barbell",                               sets: 3, reps: 10, weight: 25, rest: 60),
                ]
            ),
        ]
    )
}

// MARK: - Materialization — community plan → 真正的 Plan 数组 (加进 data.plans)

extension CommunityPlan {
    /// 把 community plan 的所有 session 实例化成具体 Plan 数组.
    /// 每张 Plan 一个独立 id (plan-community-<short uuid>-<idx>), 名字是
    /// "<community plan name> · <session name>".
    /// 调用者: CommunityScreen tap "Add to my plans" → data.plans.append(contentsOf:) → save()
    func materialize(now: Date = Date(), byId: [String: Exercise]) -> [Plan] {
        let shortUUID = UUID().uuidString.prefix(8)
        let planNameBase = NSLocalizedString(nameKey, comment: "")
        return sessions.enumerated().compactMap { (idx, session) -> Plan? in
            let validSteps: [PlanStep] = session.steps.enumerated().compactMap { (sIdx, cs) in
                guard byId[cs.exerciseId] != nil else { return nil }
                return PlanStep(
                    id: "step-\(cs.exerciseId)-\(sIdx)-\(shortUUID)",
                    exerciseId: cs.exerciseId,
                    sets: cs.sets,
                    reps: cs.reps,
                    weight: cs.weight,
                    duration: cs.duration,
                    restBetweenSets: cs.restBetweenSets,
                    rest: 0
                )
            }
            guard !validSteps.isEmpty else { return nil }
            let sessionName = NSLocalizedString(session.nameKey, comment: "")
            // session 数 = 1 时, 名字直接用 planNameBase; >1 时拼 "<base> · <session>"
            let displayName = sessions.count == 1
                ? planNameBase
                : "\(planNameBase) · \(sessionName)"
            // 不同 session 用不同 idx 让 createdAt 错开 (排序时按 createdAt 也好看)
            let createdAt = now.addingTimeInterval(Double(idx))
            return Plan(
                id: "plan-community-\(shortUUID)-\(idx)",
                name: displayName,
                steps: validSteps,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }
    }
}
