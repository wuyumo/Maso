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
        // 扩充: 经典公开训练法, 配合每日轮播让 Community 每次看到不同精选.
        fiveThreeOne4Day,
        phul4Day,
        arnoldSplit6Day,
        dumbbellHome3Day,
        gluteHam3Day,
        athleticPower3Day,
        minimalistStrength3Day,
        hypertrophyPPL3Day,
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

    static let fiveThreeOne4Day = CommunityPlan(
        id: "community-531-4day",
        nameKey: "5/3/1 Strength",
        descKey: "Wendler-style 4-day strength block — one main barbell lift per day, progressive overload, light accessory work.",
        frequencyDaysPerWeek: 4,
        levelKey: "Advanced",
        kicker: "STRENGTH",
        sessions: [
            CommunitySession(
                nameKey: "Press Day",
                steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 5, weight: 40, rest: 180),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 8, weight: 22, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 8, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Deadlift Day",
                steps: [
                    CommunityStep("deadlift", sets: 4, reps: 5, weight: 100, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 70, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 30, rest: 75),
                    CommunityStep("back_extension", sets: 3, reps: 12, weight: 0, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Bench Day",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 22, rest: 90),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 50, rest: 90),
                    CommunityStep("cable_fly_flat", sets: 3, reps: 12, weight: 40, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Squat Day",
                steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 85, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 120, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 50, rest: 60),
                ]
            ),
        ]
    )

    static let phul4Day = CommunityPlan(
        id: "community-phul-4day",
        nameKey: "PHUL — Power Hypertrophy",
        descKey: "Two power days (heavy, low reps) + two hypertrophy days (moderate, higher reps), split upper/lower.",
        frequencyDaysPerWeek: 4,
        levelKey: "Intermediate",
        kicker: "UPPER / LOWER",
        sessions: [
            CommunitySession(
                nameKey: "Upper Power",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 60, rest: 150),
                    CommunityStep("barbell_row", sets: 4, reps: 5, weight: 55, rest: 120),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 40, rest: 120),
                    CommunityStep("pull_up", sets: 3, reps: 6, weight: 0, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 8, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Lower Power",
                steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 85, rest: 150),
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 100, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 120, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 50, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Upper Hypertrophy",
                steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 22, rest: 75),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 50, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 8, rest: 60),
                    CommunityStep("cable_fly_flat", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 10, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Lower Hypertrophy",
                steps: [
                    CommunityStep("rdl_barbell", sets: 4, reps: 10, weight: 60, rest: 90),
                    CommunityStep("hip_thrust_barbell", sets: 4, reps: 12, weight: 80, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 30, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                ]
            ),
        ]
    )

    static let arnoldSplit6Day = CommunityPlan(
        id: "community-arnold-6day",
        nameKey: "Arnold Split — Volume",
        descKey: "High-volume bodybuilding split: chest+back, shoulders+arms, legs — each twice a week.",
        frequencyDaysPerWeek: 6,
        levelKey: "Advanced",
        kicker: "BODYBUILDING",
        sessions: [
            CommunitySession(
                nameKey: "Chest + Back",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 55, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 22, rest: 75),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 50, rest: 75),
                    CommunityStep("cable_fly_flat", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                ]
            ),
            CommunitySession(
                nameKey: "Shoulders + Arms",
                steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 40, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 4, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 10, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Legs",
                steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 80, rest: 120),
                    CommunityStep("rdl_barbell", sets: 4, reps: 10, weight: 60, rest: 90),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 120, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 30, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 50, rest: 45),
                ]
            ),
        ]
    )

    static let dumbbellHome3Day = CommunityPlan(
        id: "community-db-home-3day",
        nameKey: "Dumbbell-Only (Home)",
        descKey: "Full-body training with just a pair of dumbbells — perfect for home or a packed gym.",
        frequencyDaysPerWeek: 3,
        levelKey: "Beginner",
        kicker: "HOME / MINIMAL",
        sessions: [
            CommunitySession(
                nameKey: "Full Body A",
                steps: [
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 18, rest: 90),
                    CommunityStep("lunge_dumbbell_alternating", sets: 3, reps: 10, weight: 14, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 7, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 10, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 40, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Full Body B",
                steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("lunge_dumbbell_alternating", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 12, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 10, rest: 60),
                    CommunityStep("russian_twist", sets: 3, reps: 20, weight: 0, rest: 45),
                ]
            ),
        ]
    )

    static let gluteHam3Day = CommunityPlan(
        id: "community-glute-ham-3day",
        nameKey: "Glute & Hamstring Focus",
        descKey: "Posterior-chain emphasis — hip thrusts, RDLs and curls to build glutes and hamstrings.",
        frequencyDaysPerWeek: 3,
        levelKey: "Intermediate",
        kicker: "LOWER BODY",
        sessions: [
            CommunitySession(
                nameKey: "Glute Day",
                steps: [
                    CommunityStep("hip_thrust_barbell", sets: 4, reps: 10, weight: 80, rest: 90),
                    CommunityStep("rdl_barbell", sets: 4, reps: 10, weight: 60, rest: 90),
                    CommunityStep("lunge_dumbbell_alternating", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 15, weight: 30, rest: 60),
                    CommunityStep("back_extension", sets: 3, reps: 15, weight: 0, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Hamstring Day",
                steps: [
                    CommunityStep("rdl_barbell", sets: 4, reps: 8, weight: 70, rest: 120),
                    CommunityStep("hip_thrust_barbell", sets: 3, reps: 12, weight: 80, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 30, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("russian_twist", sets: 3, reps: 20, weight: 0, rest: 45),
                ]
            ),
        ]
    )

    static let athleticPower3Day = CommunityPlan(
        id: "community-athletic-3day",
        nameKey: "Athletic Power",
        descKey: "Compound, explosive lifts for whole-body strength and athleticism — 3 efficient sessions.",
        frequencyDaysPerWeek: 3,
        levelKey: "Intermediate",
        kicker: "ATHLETIC",
        sessions: [
            CommunitySession(
                nameKey: "Lower Power",
                steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 80, rest: 150),
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 100, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 120, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 12, weight: 50, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Upper Power",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 60, rest: 150),
                    CommunityStep("pull_up", sets: 4, reps: 6, weight: 0, rest: 120),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 40, rest: 120),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 50, rest: 90),
                ]
            ),
        ]
    )

    static let minimalistStrength3Day = CommunityPlan(
        id: "community-minimalist-3day",
        nameKey: "Minimalist Strength",
        descKey: "Just the big lifts, 3 days a week. Maximum results, minimum time in the gym.",
        frequencyDaysPerWeek: 3,
        levelKey: "Beginner",
        kicker: "TIME-EFFICIENT",
        sessions: [
            CommunitySession(
                nameKey: "Day A",
                steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 80, rest: 150),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 55, rest: 150),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 50, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Day B",
                steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 100, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 40, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 30, rest: 45),
                ]
            ),
        ]
    )

    static let hypertrophyPPL3Day = CommunityPlan(
        id: "community-hyp-ppl-3day",
        nameKey: "Hypertrophy Push/Pull/Legs",
        descKey: "A 3-day push/pull/legs you can run once or twice a week — balanced volume for muscle growth.",
        frequencyDaysPerWeek: 3,
        levelKey: "Intermediate",
        kicker: "PUSH / PULL / LEGS",
        sessions: [
            CommunitySession(
                nameKey: "Push",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 55, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 8, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Pull",
                steps: [
                    CommunityStep("deadlift", sets: 3, reps: 6, weight: 100, rest: 150),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 50, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 15, rest: 45),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Legs",
                steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 80, rest: 120),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 60, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 120, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 50, rest: 45),
                ]
            ),
        ]
    )

    // MARK: - 教练署名 (id → "Coach X · 专长"). 给精选计划一点"达人"感; 都是 app 内编辑团队的虚拟教练人设, 不冒充真实网红.
    static let coaches: [String: String] = [
        "community-beginner-fb-3day": "Coach Theo · Beginner",
        "community-5x5-strength": "Coach Leo · Strength",
        "community-ppl-6day": "Coach Devin · Hypertrophy",
        "community-upper-lower-4day": "Coach Mara · Bodybuilding",
        "community-bro-split-5day": "Coach Mara · Bodybuilding",
        "community-calisthenics-foundations": "Coach Sam · Calisthenics",
        "community-powerlifting-prep": "Coach Leo · Powerlifting",
        "community-push-pull-4day": "Coach Devin · Hypertrophy",
        "community-531-4day": "Coach Leo · Powerlifting",
        "community-phul-4day": "Coach Devin · Hypertrophy",
        "community-arnold-6day": "Coach Mara · Bodybuilding",
        "community-db-home-3day": "Coach Sam · Home Training",
        "community-glute-ham-3day": "Coach Nina · Lower Body",
        "community-athletic-3day": "Coach Leo · Athletic",
        "community-minimalist-3day": "Coach Theo · Strength",
        "community-hyp-ppl-3day": "Coach Devin · Hypertrophy",
    ]
    static func coach(for plan: CommunityPlan) -> String { coaches[plan.id] ?? "Maso Coach" }

    /// 每日精选 — 用日期 seed 稳定打乱 all, 取前 count 个. 同一天不变, 隔天换新 → "每次来都有新达人计划".
    static func featured(on date: Date = Date(), count: Int = 6) -> [CommunityPlan] {
        let day = Int(date.timeIntervalSince1970 / 86_400)
        return all.sorted { seededHash($0.id, day) < seededHash($1.id, day) }.prefix(count).map { $0 }
    }
    /// 稳定 FNV-1a hash (String.hashValue 每次启动随机, 不能用来做"当天稳定"的排序).
    private static func seededHash(_ s: String, _ seed: Int) -> UInt64 {
        var h: UInt64 = 1_469_598_103_934_665_603 ^ UInt64(bitPattern: Int64(seed &* 2_654_435_761))
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return h
    }

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
