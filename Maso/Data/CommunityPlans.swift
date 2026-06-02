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
        // 扩充 (online 常见公开训练法): 覆盖 2~6 天/周 + 各难度, 配合顶部 filter 让用户按维度筛.
        barbell5x5Linear,
        noviceBarbellStrength,
        gzclp4Day,
        pplReddit6Day,
        phat5Day,
        germanVolume,
        twoDayFullBody,
        texasMethod,
    ] + extraPrograms

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

    // MARK: - 17. Barbell 5×5 — Linear (StrongLifts-style)

    static let barbell5x5Linear = CommunityPlan(
        id: "community-barbell-5x5-linear",
        nameKey: "Barbell 5×5 — Linear",
        descKey: "The classic beginner barbell program (StrongLifts-style): alternate Workout A and B three times a week and add a little weight every session.",
        frequencyDaysPerWeek: 3,
        levelKey: "Beginner",
        kicker: "STRENGTH",
        sessions: [
            CommunitySession(
                nameKey: "Workout A",
                steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 5, reps: 5, weight: 40, rest: 150),
                ]
            ),
            CommunitySession(
                nameKey: "Workout B",
                steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 5, weight: 35, rest: 180),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 90, rest: 240),
                ]
            ),
        ]
    )

    // MARK: - 18. Novice Barbell Strength (Starting Strength-style)

    static let noviceBarbellStrength = CommunityPlan(
        id: "community-novice-barbell-3day",
        nameKey: "Novice Barbell Strength",
        descKey: "A minimalist novice plan (Starting Strength-style): squat every session plus a press and a pull. Three full-body workouts a week, linear progression.",
        frequencyDaysPerWeek: 3,
        levelKey: "Beginner",
        kicker: "STRENGTH",
        sessions: [
            CommunitySession(
                nameKey: "Workout A",
                steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 90, rest: 240),
                ]
            ),
            CommunitySession(
                nameKey: "Workout B",
                steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 35, rest: 180),
                    CommunityStep("dumbbell_row", sets: 5, reps: 5, weight: 22, rest: 150),
                ]
            ),
        ]
    )

    // MARK: - 19. GZCLP — Linear Progression 4-day

    static let gzclp4Day = CommunityPlan(
        id: "community-gzclp-4day",
        nameKey: "GZCLP — Linear Progression",
        descKey: "A structured 4-day linear program (GZCLP): a heavy T1 main lift, a T2 secondary, and high-rep T3 accessory volume each day. A great first step after a novice plan.",
        frequencyDaysPerWeek: 4,
        levelKey: "Intermediate",
        kicker: "STRENGTH",
        sessions: [
            CommunitySession(
                nameKey: "Day 1 · Squat / Bench",
                steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 80, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 15, weight: 40, rest: 75),
                ]
            ),
            CommunitySession(
                nameKey: "Day 2 · OHP / Deadlift",
                steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 3, weight: 40, rest: 180),
                    CommunityStep("deadlift", sets: 3, reps: 10, weight: 90, rest: 150),
                    CommunityStep("dumbbell_row", sets: 3, reps: 15, weight: 18, rest: 75),
                ]
            ),
            CommunitySession(
                nameKey: "Day 3 · Bench / Squat",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 60, rest: 180),
                    CommunityStep("squat_barbell", sets: 3, reps: 10, weight: 60, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 15, weight: 40, rest: 75),
                ]
            ),
            CommunitySession(
                nameKey: "Day 4 · Deadlift / OHP",
                steps: [
                    CommunityStep("deadlift", sets: 5, reps: 3, weight: 110, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 10, weight: 35, rest: 120),
                    CommunityStep("dumbbell_row", sets: 3, reps: 15, weight: 18, rest: 75),
                ]
            ),
        ]
    )

    // MARK: - 20. Push Pull Legs — 6-day (Reddit-style high frequency)

    static let pplReddit6Day = CommunityPlan(
        id: "community-ppl-reddit-6day",
        nameKey: "Push Pull Legs — 6-Day",
        descKey: "A popular high-frequency push/pull/legs split run six days a week: heavy compound work up top, then hypertrophy volume to finish each session.",
        frequencyDaysPerWeek: 6,
        levelKey: "Intermediate",
        kicker: "PUSH / PULL / LEGS",
        sessions: [
            CommunitySession(
                nameKey: "Push",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 60, rest: 150),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 18, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 75),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_cable_rope", sets: 3, reps: 12, weight: 20, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 8, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Pull",
                steps: [
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 100, rest: 180),
                    CommunityStep("pull_up", sets: 3, reps: 8, weight: 0, rest: 120),
                    CommunityStep("dumbbell_row", sets: 3, reps: 8, weight: 24, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 4, reps: 15, weight: 15, rest: 45),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 10, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Legs",
                steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 85, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 70, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 120, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 35, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                ]
            ),
        ]
    )

    // MARK: - 21. Power Hypertrophy — PHAT (Layne Norton-style)

    static let phat5Day = CommunityPlan(
        id: "community-phat-5day",
        nameKey: "Power Hypertrophy — PHAT",
        descKey: "A PHAT-style split: two heavy power days plus three high-volume hypertrophy days for both strength and size. Demanding — best for advanced lifters.",
        frequencyDaysPerWeek: 5,
        levelKey: "Advanced",
        kicker: "POWER + HYPERTROPHY",
        sessions: [
            CommunitySession(
                nameKey: "Upper Power",
                steps: [
                    CommunityStep("barbell_row", sets: 4, reps: 5, weight: 60, rest: 150),
                    CommunityStep("pull_up", sets: 3, reps: 6, weight: 0, rest: 120),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 70, rest: 150),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 18, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 8, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 8, weight: 30, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Lower Power",
                steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 90, rest: 180),
                    CommunityStep("deadlift", sets: 4, reps: 5, weight: 110, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 140, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 35, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Back & Shoulders Hypertrophy",
                steps: [
                    CommunityStep("barbell_row", sets: 4, reps: 10, weight: 50, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 3, reps: 15, weight: 7, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Lower Hypertrophy",
                steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_barbell", sets: 3, reps: 12, weight: 60, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 40, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 15, weight: 30, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Chest & Arms Hypertrophy",
                steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("cable_fly_flat", sets: 3, reps: 12, weight: 15, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 4, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 10, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_cable_rope", sets: 3, reps: 12, weight: 20, rest: 60),
                ]
            ),
        ]
    )

    // MARK: - 22. German Volume Training — 10×10

    static let germanVolume = CommunityPlan(
        id: "community-gvt-10x10",
        nameKey: "German Volume Training — 10×10",
        descKey: "The classic 10 sets of 10 hypertrophy method on the main lifts. Brutally simple, brutally effective for size — keep the weight light and the rest short.",
        frequencyDaysPerWeek: 4,
        levelKey: "Advanced",
        kicker: "HYPERTROPHY",
        sessions: [
            CommunitySession(
                nameKey: "Chest & Back",
                steps: [
                    CommunityStep("bench_press_barbell", sets: 10, reps: 10, weight: 45, rest: 90),
                    CommunityStep("dumbbell_row", sets: 10, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_fly_flat", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 40, rest: 60),
                ]
            ),
            CommunitySession(
                nameKey: "Legs & Abs",
                steps: [
                    CommunityStep("squat_barbell", sets: 10, reps: 10, weight: 60, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 10, reps: 10, weight: 25, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 50, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 20, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Arms & Shoulders",
                steps: [
                    CommunityStep("dip_parallel_bar_triceps", sets: 10, reps: 10, weight: 0, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 10, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 7, rest: 45),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 12, rest: 60),
                ]
            ),
        ]
    )

    // MARK: - 23. 2-Day Full Body (busy schedule)

    static let twoDayFullBody = CommunityPlan(
        id: "community-2day-fullbody",
        nameKey: "2-Day Full Body",
        descKey: "Only two sessions a week, full-body each time — built for busy schedules without giving up real progress. Hit it hard, recover well.",
        frequencyDaysPerWeek: 2,
        levelKey: "Beginner",
        kicker: "FULL BODY",
        sessions: [
            CommunitySession(
                nameKey: "Workout A",
                steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 150),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("dumbbell_row", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 2, reps: 10, weight: 14, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 40, rest: 45),
                ]
            ),
            CommunitySession(
                nameKey: "Workout B",
                steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 90, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 18, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("lunge_dumbbell_alternating", sets: 3, reps: 10, weight: 14, rest: 75),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 10, rest: 60),
                ]
            ),
        ]
    )

    // MARK: - 24. Texas Method (intermediate strength)

    static let texasMethod = CommunityPlan(
        id: "community-texas-method-3day",
        nameKey: "Texas Method",
        descKey: "An intermediate strength template: a high-volume day, a light recovery day, and a heavy intensity day each week to keep adding weight past the novice stage.",
        frequencyDaysPerWeek: 3,
        levelKey: "Intermediate",
        kicker: "STRENGTH",
        sessions: [
            CommunitySession(
                nameKey: "Volume Day",
                steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 80, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 55, rest: 180),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 100, rest: 240),
                ]
            ),
            CommunitySession(
                nameKey: "Recovery Day",
                steps: [
                    CommunityStep("squat_barbell", sets: 2, reps: 5, weight: 55, rest: 120),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 35, rest: 150),
                    CommunityStep("chin_up", sets: 3, reps: 8, weight: 0, rest: 90),
                ]
            ),
            CommunitySession(
                nameKey: "Intensity Day",
                steps: [
                    CommunityStep("squat_barbell", sets: 1, reps: 5, weight: 95, rest: 240),
                    CommunityStep("bench_press_barbell", sets: 1, reps: 5, weight: 65, rest: 240),
                    CommunityStep("dumbbell_row", sets: 4, reps: 8, weight: 24, rest: 90),
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
        "community-barbell-5x5-linear": "Coach Leo · Strength",
        "community-novice-barbell-3day": "Coach Leo · Strength",
        "community-gzclp-4day": "Coach Leo · Strength",
        "community-ppl-reddit-6day": "Coach Devin · Hypertrophy",
        "community-phat-5day": "Coach Devin · Hypertrophy",
        "community-gvt-10x10": "Coach Mara · Bodybuilding",
        "community-2day-fullbody": "Coach Theo · Beginner",
        "community-texas-method-3day": "Coach Leo · Strength",
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

    // MARK: - Generated science-based programs (validated exercise ids)
    static let extraPrograms: [CommunityPlan] = [
        CommunityPlan(
            id: "community-gen-01",
            nameKey: "Starting Strength",
            descKey: "Rippetoe's classic novice barbell program: three compound lifts per session, add weight every workout. Alternate A/B three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Workout A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 80, rest: 240),
                ]),
                CommunitySession(nameKey: "Workout B", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-02",
            nameKey: "StrongLifts 5×5",
            descKey: "The most popular beginner barbell routine. Five sets of five on the big lifts, alternating two full-body workouts; deadlift one set.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Workout A", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 5, reps: 5, weight: 45, rest: 150),
                ]),
                CommunitySession(nameKey: "Workout B", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 5, weight: 30, rest: 180),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 80, rest: 240),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-03",
            nameKey: "Greyskull LP",
            descKey: "A beginner LP with an AMRAP final set on presses for faster upper-body progress, plus light arm work.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Day A", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Day B", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 180),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 80, rest: 240),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-04",
            nameKey: "Basic Beginner Routine",
            descKey: "r/Fitness recommended starter: full-body, three days a week, simple compound lifts plus a little curl and core.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 150),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 80, rest: 240),
                    CommunityStep("lat_pulldown", sets: 2, reps: 12, weight: 45, rest: 75),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-05",
            nameKey: "Dumbbell Beginner Full Body",
            descKey: "No barbell needed — a complete dumbbell full-body plan for home or hotel gyms, three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "DUMBBELL",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_goblet", sets: 3, reps: 10, weight: 24, rest: 120),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 12, weight: 22, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 12, weight: 24, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-06",
            nameKey: "Machine Circuit — Beginner",
            descKey: "Friendly machine-and-cable circuit for first-timers: guided movement patterns, low injury risk, three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "MACHINE",
            sessions: [
                CommunitySession(nameKey: "Circuit A", steps: [
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("chest_press_machine_hammer_strength", sets: 3, reps: 12, weight: 40, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 3, reps: 15, weight: 40, rest: 45),
                ]),
                CommunitySession(nameKey: "Circuit B", steps: [
                    CommunityStep("hack_squat_machine", sets: 3, reps: 12, weight: 70, rest: 90),
                    CommunityStep("pec_deck", sets: 3, reps: 15, weight: 40, rest: 60),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_cable", sets: 3, reps: 15, weight: 12, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 15, weight: 25, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-07",
            nameKey: "Beginner Full Body — 2 Day",
            descKey: "Minimal-time starter: two full-body sessions a week hit every major muscle with the core barbell lifts.",
            frequencyDaysPerWeek: 2,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 150),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 2, reps: 12, weight: 14, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 2, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-08",
            nameKey: "Beginner Upper / Lower",
            descKey: "A 4-day upper/lower split for novices ready to add volume past pure linear progression.",
            frequencyDaysPerWeek: 4,
            levelKey: "Beginner",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 150),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 2, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("hammer_curl", sets: 2, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 3, reps: 15, weight: 40, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-09",
            nameKey: "GZCLP",
            descKey: "Cody Lemons' beginner GZCL program: a top T1 compound, a T2 back-off compound, and T3 accessory work, four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Beginner",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "T1 Squat", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 15, weight: 45, rest: 75),
                ]),
                CommunitySession(nameKey: "T1 OHP", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 3, weight: 30, rest: 180),
                    CommunityStep("deadlift", sets: 3, reps: 10, weight: 80, rest: 150),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 15, weight: 24, rest: 75),
                ]),
                CommunitySession(nameKey: "T1 Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 180),
                    CommunityStep("squat_barbell", sets: 3, reps: 10, weight: 60, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 15, weight: 45, rest: 75),
                ]),
                CommunitySession(nameKey: "T1 Deadlift", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 3, weight: 80, rest: 210),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 10, weight: 30, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 15, weight: 45, rest: 75),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-10",
            nameKey: "Strength Foundations — 3 Day",
            descKey: "Build a base of strength with paused compounds and balanced push/pull/leg volume, three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Day 1 — Squat", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("cable_row_seated", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 2 — Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 2, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 3 — Deadlift", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-11",
            nameKey: "Madcow 5×5",
            descKey: "The classic intermediate 5×5: ramping sets to a top weekly PR, with a light and medium day. A logical step up from StrongLifts.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Monday — Heavy", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 5, reps: 5, weight: 45, rest: 150),
                ]),
                CommunitySession(nameKey: "Wednesday — Light", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 5, weight: 30, rest: 150),
                    CommunityStep("deadlift", sets: 4, reps: 5, weight: 80, rest: 180),
                ]),
                CommunitySession(nameKey: "Friday — PR", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 3, weight: 60, rest: 210),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 3, weight: 45, rest: 210),
                    CommunityStep("barbell_row", sets: 3, reps: 3, weight: 45, rest: 180),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-12",
            nameKey: "Texas Method",
            descKey: "Volume Monday, recovery Wednesday, intensity Friday — the textbook intermediate weekly progression.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Volume Day", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                ]),
                CommunitySession(nameKey: "Recovery Day", steps: [
                    CommunityStep("squat_barbell", sets: 2, reps: 5, weight: 60, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 150),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                ]),
                CommunitySession(nameKey: "Intensity Day", steps: [
                    CommunityStep("squat_barbell", sets: 1, reps: 5, weight: 60, rest: 240),
                    CommunityStep("bench_press_barbell", sets: 1, reps: 5, weight: 45, rest: 240),
                    CommunityStep("deadlift", sets: 1, reps: 5, weight: 80, rest: 240),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-13",
            nameKey: "5/3/1 Boring But Big",
            descKey: "Wendler's 5/3/1 main lift followed by 5×10 of the same movement for hypertrophy. Four days, one main lift each.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Press Day", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 10, weight: 30, rest: 90),
                    CommunityStep("lat_pulldown", sets: 5, reps: 10, weight: 45, rest: 75),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift Day", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("deadlift", sets: 5, reps: 10, weight: 80, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 5, reps: 12, weight: 40, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Bench Day", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 10, weight: 45, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 5, reps: 10, weight: 24, rest: 75),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Squat Day", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("squat_barbell", sets: 5, reps: 10, weight: 60, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 5, reps: 12, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-14",
            nameKey: "5/3/1 Triumvirate",
            descKey: "5/3/1 main work plus two targeted assistance lifts per day — lean, effective, four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("dip_chest", sets: 5, reps: 15, weight: 0, rest: 75),
                    CommunityStep("dumbbell_row_single_arm", sets: 5, reps: 10, weight: 24, rest: 75),
                ]),
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 5, reps: 15, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 5, reps: 10, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Press", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 180),
                    CommunityStep("dip_parallel_bar_triceps", sets: 5, reps: 15, weight: 0, rest: 75),
                    CommunityStep("chin_up", sets: 5, reps: 8, weight: 0, rest: 90),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("good_morning", sets: 5, reps: 12, weight: 35, rest: 90),
                    CommunityStep("leg_raise_hanging", sets: 5, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-15",
            nameKey: "nSuns 5-Day LP",
            descKey: "A high-volume 5/3/1 derivative with a 9-set main-lift wave and heavy secondary work. Fast strength gains for intermediates.",
            frequencyDaysPerWeek: 5,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Bench / OHP", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 4, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 6, reps: 6, weight: 30, rest: 120),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Squat / Sumo", steps: [
                    CommunityStep("squat_barbell", sets: 8, reps: 4, weight: 60, rest: 180),
                    CommunityStep("deadlift_sumo", sets: 4, reps: 5, weight: 80, rest: 180),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "OHP / Incline", steps: [
                    CommunityStep("overhead_press_barbell", sets: 8, reps: 4, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 6, reps: 8, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift / Front", steps: [
                    CommunityStep("deadlift", sets: 8, reps: 4, weight: 80, rest: 180),
                    CommunityStep("squat_front", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Bench / CG", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 4, weight: 45, rest: 150),
                    CommunityStep("bench_press_close_grip", sets: 6, reps: 8, weight: 42, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-16",
            nameKey: "nSuns 4-Day",
            descKey: "The four-day version of nSuns for those who can't train five times a week — same main-lift volume, condensed.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 4, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 6, reps: 6, weight: 30, rest: 120),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 8, reps: 4, weight: 60, rest: 180),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 40, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "OHP", steps: [
                    CommunityStep("overhead_press_barbell", sets: 8, reps: 4, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 5, reps: 8, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 8, reps: 4, weight: 80, rest: 180),
                    CommunityStep("squat_front", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-17",
            nameKey: "GZCL Jacked & Tan 2.0",
            descKey: "A flexible GZCL hypertrophy-strength program: heavy T1 singles to a top set, T2 volume, and rep-max T3 accessories.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 180),
                    CommunityStep("squat_front", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 15, weight: 40, rest: 60),
                ]),
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 3, weight: 80, rest: 210),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "OHP", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 3, weight: 30, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 20, weight: 10, rest: 45),
                    CommunityStep("lat_pulldown", sets: 3, reps: 15, weight: 45, rest: 75),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-18",
            nameKey: "The Bridge",
            descKey: "Stronger by Science's free intermediate program: a balanced bridge from beginner LP to specialized training, three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 6, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 6, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 6, weight: 30, rest: 150),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("squat_front", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 8, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-19",
            nameKey: "Average to Savage",
            descKey: "Powerbuilding blocks blending heavy main lifts with hypertrophy accessories — strength and size together, four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Upper Power", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 4, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 8, weight: 5, rest: 90),
                ]),
                CommunitySession(nameKey: "Lower Power", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 4, weight: 60, rest: 180),
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 90, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper Volume", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Volume", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 12, weight: 70, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-20",
            nameKey: "Bullmastiff — Intro",
            descKey: "A GZCL-style powerbuilding block: rep-PR main work plus heavy back-off and pump accessories, four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 4, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 4, reps: 10, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 4, weight: 45, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 4, weight: 80, rest: 210),
                    CommunityStep("rdl_barbell", sets: 4, reps: 10, weight: 55, rest: 120),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "OHP", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 4, weight: 30, rest: 180),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 18, weight: 10, rest: 45),
                    CommunityStep("lat_pulldown", sets: 4, reps: 12, weight: 45, rest: 75),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-21",
            nameKey: "Push Pull Legs — 6 Day",
            descKey: "Train each muscle twice a week with the most popular high-frequency split: heavy compounds then hypertrophy volume.",
            frequencyDaysPerWeek: 6,
            levelKey: "Intermediate",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push (Heavy)", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull (Heavy)", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 6, weight: 5, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("shrug_barbell", sets: 3, reps: 12, weight: 60, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs (Heavy)", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("squat_front", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                ]),
                CommunitySession(nameKey: "Push (Volume)", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull (Volume)", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 6, weight: 50, rest: 150),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs (Volume)", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-22",
            nameKey: "Push Pull Legs — 3 Day",
            descKey: "One round of push/pull/legs a week — efficient full coverage for busy lifters or those new to the split.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-23",
            nameKey: "Arnold Split — 6 Day",
            descKey: "Arnold's chest/back, shoulders/arms, legs split run twice a week — old-school high-volume bodybuilding.",
            frequencyDaysPerWeek: 6,
            levelKey: "Advanced",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest & Back", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("decline_bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("deadlift", sets: 4, reps: 6, weight: 80, rest: 180),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("barbell_row", sets: 4, reps: 8, weight: 45, rest: 120),
                ]),
                CommunitySession(nameKey: "Shoulders & Arms", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 30, rest: 120),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Chest & Back", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("decline_bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("deadlift", sets: 4, reps: 6, weight: 80, rest: 180),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("barbell_row", sets: 4, reps: 8, weight: 45, rest: 120),
                ]),
                CommunitySession(nameKey: "Shoulders & Arms", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 30, rest: 120),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-24",
            nameKey: "Bro Split — 5 Day",
            descKey: "One muscle group a day, maximum volume per session — the classic bodybuilding 'bro split'.",
            frequencyDaysPerWeek: 5,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("decline_bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("dip_chest", sets: 3, reps: 12, weight: 0, rest: 75),
                    CommunityStep("push_up", sets: 2, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Back", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 6, weight: 80, rest: 180),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("barbell_row", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                ]),
                CommunitySession(nameKey: "Shoulders", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 30, rest: 120),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 4, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("preacher_curl", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-25",
            nameKey: "Upper / Lower — 4 Day Hypertrophy",
            descKey: "Balanced 4-day upper/lower with moderate-rep hypertrophy work and progressive overload.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 8, weight: 90, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-26",
            nameKey: "Full Body — 3 Day Hypertrophy",
            descKey: "Hit every major muscle three times a week — high frequency, great for naturals chasing size.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Full Body C", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-27",
            nameKey: "PHUL",
            descKey: "Power Hypertrophy Upper Lower: two heavy power days and two higher-rep hypertrophy days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Upper Power", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 5, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Power", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("leg_press_45", sets: 4, reps: 10, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper Hypertrophy", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_row_seated", sets: 4, reps: 12, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 4, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 4, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Hypertrophy", steps: [
                    CommunityStep("squat_front", sets: 4, reps: 12, weight: 45, rest: 90),
                    CommunityStep("rdl_barbell", sets: 4, reps: 12, weight: 55, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 18, weight: 40, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-28",
            nameKey: "PHAT",
            descKey: "Layne Norton's Power Hypertrophy Adaptive Training: two power days plus three body-part hypertrophy days.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Upper Power", steps: [
                    CommunityStep("barbell_row", sets: 4, reps: 5, weight: 45, rest: 150),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 6, weight: 5, rest: 120),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 8, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Power", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Back & Shoulders", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 3, reps: 15, weight: 8, rest: 45),
                ]),
                CommunitySession(nameKey: "Chest & Arms", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 5, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 4, reps: 15, weight: 12, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 4, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_front", sets: 5, reps: 10, weight: 45, rest: 90),
                    CommunityStep("rdl_barbell", sets: 4, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-29",
            nameKey: "German Volume Training",
            descKey: "Ten sets of ten on one big lift per muscle — brutal hypertrophy overload. Four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "HYPERTROPHY",
            sessions: [
                CommunitySession(nameKey: "Chest & Back", steps: [
                    CommunityStep("bench_press_barbell", sets: 10, reps: 10, weight: 45, rest: 90),
                    CommunityStep("barbell_row", sets: 10, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs & Abs", steps: [
                    CommunityStep("squat_barbell", sets: 10, reps: 10, weight: 60, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 10, reps: 10, weight: 40, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Arms & Shoulders", steps: [
                    CommunityStep("dip_parallel_bar_triceps", sets: 10, reps: 10, weight: 0, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 10, reps: 10, weight: 25, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 3, reps: 15, weight: 8, rest: 45),
                ]),
                CommunitySession(nameKey: "Rest-Pause Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 10, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 10, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-30",
            nameKey: "Jeff Nippard — Fundamentals",
            descKey: "An evidence-based 3-day full-body program emphasizing the highest-return compound lifts with smart accessory volume.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 150),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 45, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Full Body C", steps: [
                    CommunityStep("squat_front", sets: 3, reps: 8, weight: 45, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("pendlay_row", sets: 3, reps: 10, weight: 50, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-31",
            nameKey: "Jeff Nippard — Upper / Lower",
            descKey: "Science-based 4-day upper/lower with a strength emphasis up top and metabolite work to finish.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 6, weight: 30, rest: 150),
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_cable", sets: 3, reps: 18, weight: 12, rest: 45),
                    CommunityStep("bicep_curl_cable", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("squat_front", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 18, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-32",
            nameKey: "Fierce 5 — Full Body",
            descKey: "A beginner-friendly full-body alternative to 5×5 with built-in accessory volume for balanced development.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Workout A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("cable_row_seated", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 2, reps: 10, weight: 14, rest: 75),
                    CommunityStep("leg_curl_lying", sets: 2, reps: 12, weight: 40, rest: 60),
                ]),
                CommunitySession(nameKey: "Workout B", steps: [
                    CommunityStep("rdl_barbell", sets: 3, reps: 5, weight: 55, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 150),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 2, reps: 10, weight: 20, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 2, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-33",
            nameKey: "Lyle's Generic Bulking",
            descKey: "A simple, proven 4-day upper/lower hypertrophy template from Lyle McDonald — 3–5 sets of moderate reps.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 2, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 2, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 2, reps: 15, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("dip_chest", sets: 3, reps: 10, weight: 0, rest: 90),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 2, reps: 15, weight: 8, rest: 45),
                    CommunityStep("hammer_curl", sets: 2, reps: 12, weight: 12, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 2, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 6, weight: 80, rest: 180),
                    CommunityStep("squat_front", sets: 3, reps: 10, weight: 45, rest: 120),
                    CommunityStep("leg_curl_seated", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("leg_extension_machine", sets: 2, reps: 15, weight: 45, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 3, reps: 18, weight: 40, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-34",
            nameKey: "FST-7 Hypertrophy",
            descKey: "Hany Rambod's FST-7 finishes each muscle with seven short-rest sets to maximize fascia stretch and pump. Five days.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "HYPERTROPHY",
            sessions: [
                CommunitySession(nameKey: "Chest", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 7, reps: 12, weight: 12, rest: 40),
                ]),
                CommunitySession(nameKey: "Back", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 10, weight: 50, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 7, reps: 12, weight: 45, rest: 40),
                ]),
                CommunitySession(nameKey: "Shoulders", steps: [
                    CommunityStep("overhead_press_dumbbell_seated", sets: 4, reps: 10, weight: 14, rest: 90),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 3, reps: 12, weight: 8, rest: 60),
                    CommunityStep("lateral_raise_cable", sets: 7, reps: 15, weight: 12, rest: 40),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 10, weight: 60, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 7, reps: 12, weight: 45, rest: 40),
                ]),
                CommunitySession(nameKey: "Arms", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("bicep_curl_cable", sets: 7, reps: 12, weight: 15, rest: 40),
                    CommunityStep("triceps_pushdown_rope", sets: 7, reps: 12, weight: 25, rest: 40),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-35",
            nameKey: "Blood & Guts",
            descKey: "Dorian Yates' high-intensity training: one all-out working set to failure per exercise after warm-ups. Four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "HYPERTROPHY",
            sessions: [
                CommunitySession(nameKey: "Chest, Shoulders & Tri", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 1, reps: 8, weight: 20, rest: 120),
                    CommunityStep("cable_crossover_mid", sets: 1, reps: 10, weight: 12, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 1, reps: 8, weight: 14, rest: 120),
                    CommunityStep("lateral_raise_dumbbell", sets: 1, reps: 12, weight: 10, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 1, reps: 8, weight: 0, rest: 90),
                ]),
                CommunitySession(nameKey: "Back & Rear Delt", steps: [
                    CommunityStep("lat_pulldown", sets: 1, reps: 8, weight: 45, rest: 120),
                    CommunityStep("pendlay_row", sets: 1, reps: 8, weight: 50, rest: 120),
                    CommunityStep("cable_row_seated", sets: 1, reps: 10, weight: 45, rest: 90),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 1, reps: 12, weight: 8, rest: 60),
                    CommunityStep("deadlift", sets: 1, reps: 6, weight: 80, rest: 180),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("leg_extension_machine", sets: 1, reps: 12, weight: 45, rest: 90),
                    CommunityStep("leg_press_45", sets: 1, reps: 12, weight: 90, rest: 120),
                    CommunityStep("hack_squat_machine", sets: 1, reps: 10, weight: 70, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 1, reps: 10, weight: 40, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 2, reps: 12, weight: 60, rest: 60),
                ]),
                CommunitySession(nameKey: "Shoulders & Arms", steps: [
                    CommunityStep("overhead_press_barbell", sets: 1, reps: 8, weight: 30, rest: 120),
                    CommunityStep("lateral_raise_dumbbell", sets: 1, reps: 12, weight: 10, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 1, reps: 8, weight: 25, rest: 75),
                    CommunityStep("preacher_curl", sets: 1, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 1, reps: 10, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-36",
            nameKey: "Push / Pull — 4 Day",
            descKey: "An upper-body-biased push/pull split run twice weekly — simple to recover from and easy to progress.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "PUSH / PULL",
            sessions: [
                CommunitySession(nameKey: "Push A", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull A", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Push B", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull B", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 6, weight: 5, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("shrug_barbell", sets: 3, reps: 12, weight: 60, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-37",
            nameKey: "Powerbuilding PPL — 6 Day",
            descKey: "Strength rep-ranges on the first exercise of each day, hypertrophy volume after — twice-weekly push/pull/legs.",
            frequencyDaysPerWeek: 6,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Push (Strength)", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 4, weight: 45, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull (Strength)", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 4, weight: 80, rest: 210),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs (Strength)", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 4, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Push (Pump)", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull (Pump)", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 6, weight: 50, rest: 150),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs (Pump)", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-38",
            nameKey: "Glute Focus — 3 Day",
            descKey: "Glute-emphasis lower programming with heavy hip thrusts and hinge volume, balanced upper work to round it out.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "GLUTES",
            sessions: [
                CommunitySession(nameKey: "Glutes & Hams", steps: [
                    CommunityStep("hip_thrust_barbell", sets: 4, reps: 8, weight: 60, rest: 120),
                    CommunityStep("rdl_barbell", sets: 4, reps: 10, weight: 55, rest: 120),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("abductor_machine", sets: 3, reps: 20, weight: 35, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Glutes & Quads", steps: [
                    CommunityStep("hip_thrust_barbell", sets: 4, reps: 10, weight: 60, rest: 120),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 12, weight: 14, rest: 90),
                    CommunityStep("abductor_machine", sets: 4, reps: 20, weight: 35, rest: 45),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-39",
            nameKey: "Arm Specialization",
            descKey: "A 4-day plan with extra biceps and triceps volume for lagging arms, built on an upper/lower base.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Upper + Arms", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Upper + Arms", steps: [
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("preacher_curl", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 4, reps: 10, weight: 0, rest: 75),
                    CommunityStep("bicep_curl_cable", sets: 3, reps: 15, weight: 15, rest: 45),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 8, weight: 90, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-40",
            nameKey: "Minimalist Strength — 3 Day",
            descKey: "Just the squat, bench, deadlift and a pull — for lifters who want maximum return on minimum exercises.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Squat & Bench", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 45, rest: 90),
                ]),
                CommunitySession(nameKey: "Deadlift & Press", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 5, weight: 30, rest: 180),
                    CommunityStep("chin_up", sets: 3, reps: 8, weight: 0, rest: 90),
                ]),
                CommunitySession(nameKey: "Squat & Bench", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 8, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-41",
            nameKey: "Dumbbell Power — 4 Day",
            descKey: "A complete dumbbell-only upper/lower split — no barbell or machines required, ideal for home gyms.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "DUMBBELL",
            sessions: [
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_dumbbell", sets: 4, reps: 10, weight: 22, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("squat_goblet", sets: 4, reps: 12, weight: 24, rest: 90),
                    CommunityStep("rdl_dumbbell", sets: 4, reps: 10, weight: 22, rest: 90),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("step_up_dumbbell", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 12, weight: 24, rest: 75),
                    CommunityStep("arnold_press", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("dumbbell_fly_flat", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("lunge_walking_dumbbell", sets: 4, reps: 12, weight: 16, rest: 90),
                    CommunityStep("rdl_dumbbell", sets: 4, reps: 12, weight: 22, rest: 90),
                    CommunityStep("squat_goblet", sets: 3, reps: 12, weight: 24, rest: 90),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 18, weight: 40, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-42",
            nameKey: "Calisthenics Strength",
            descKey: "Bodyweight-first strength: weighted pull-ups and dips, with progressions toward harder skills. Three days.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "CALISTHENICS",
            sessions: [
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("dip_chest", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("push_up", sets: 4, reps: 12, weight: 0, rest: 75),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("pull_up_weighted", sets: 4, reps: 6, weight: 5, rest: 120),
                    CommunityStep("chin_up", sets: 4, reps: 8, weight: 0, rest: 90),
                    CommunityStep("barbell_row", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 4, reps: 10, weight: 16, rest: 90),
                    CommunityStep("step_up_dumbbell", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("nordic_curl", sets: 3, reps: 8, weight: 0, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 20, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-43",
            nameKey: "Athletic Power — 3 Day",
            descKey: "Explosive lower-body strength plus pulling and pressing power for sport — heavy, low-rep, long rests.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "ATHLETIC",
            sessions: [
                CommunitySession(nameKey: "Lower Power", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("deadlift_trap_bar", sets: 4, reps: 4, weight: 80, rest: 180),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 8, weight: 16, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 12, weight: 60, rest: 60),
                ]),
                CommunitySession(nameKey: "Upper Power", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 210),
                    CommunityStep("pendlay_row", sets: 4, reps: 5, weight: 50, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 150),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 6, weight: 5, rest: 120),
                ]),
                CommunitySession(nameKey: "Total Body", steps: [
                    CommunityStep("squat_front", sets: 4, reps: 4, weight: 45, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-44",
            nameKey: "Time-Crunch Full Body — 3 Day",
            descKey: "Three compound supersets per session for people training 30 minutes — efficient, full coverage.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 90),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 2, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 75),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 75),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 75),
                    CommunityStep("triceps_pushdown_rope", sets: 2, reps: 12, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-45",
            nameKey: "Back & Width Focus",
            descKey: "A pull-heavy 4-day plan for a wider, thicker back, with supporting push and leg work.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Back Width", steps: [
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                ]),
                CommunitySession(nameKey: "Chest & Tri", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("decline_bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Back Thickness", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 120),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("t_bar_row", sets: 3, reps: 10, weight: 40, rest: 90),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs & Shoulders", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-46",
            nameKey: "Shoulder Builder",
            descKey: "A delt-emphasis 4-day plan with overhead pressing and high-volume lateral and rear-delt work.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Shoulders", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 30, rest: 120),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 4, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Push + Delts", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 6, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lateral_raise_cable", sets: 4, reps: 18, weight: 12, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-47",
            nameKey: "Leg Specialization — 4 Day",
            descKey: "Two demanding leg days a week plus maintenance upper-body work — for bringing up lagging legs.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Quads", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 8, weight: 60, rest: 150),
                    CommunityStep("hack_squat_machine", sets: 4, reps: 12, weight: 70, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 15, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Hams & Glutes", steps: [
                    CommunityStep("rdl_barbell", sets: 5, reps: 8, weight: 55, rest: 150),
                    CommunityStep("hip_thrust_barbell", sets: 4, reps: 10, weight: 60, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 40, rest: 75),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 18, weight: 40, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-48",
            nameKey: "Core & Conditioning Strength — 3 Day",
            descKey: "Compound strength paired with dedicated core and carry work for a rock-solid midsection.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 6, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("leg_raise_hanging", sets: 4, reps: 12, weight: 0, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 6, weight: 45, rest: 180),
                    CommunityStep("cable_woodchopper", sets: 3, reps: 15, weight: 15, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("squat_front", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("pendlay_row", sets: 3, reps: 8, weight: 50, rest: 120),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-49",
            nameKey: "Hypertrophy PPL — 5 Day",
            descKey: "A five-day push/pull/legs/upper/lower hybrid for high weekly volume without daily training.",
            frequencyDaysPerWeek: 5,
            levelKey: "Intermediate",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-50",
            nameKey: "Powerlifting Peak — 4 Day",
            descKey: "A strength block built around squat, bench and deadlift with competition-style top sets and back-offs.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Squat Focus", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("squat_front", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Bench Focus", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 210),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 6, weight: 42, rest: 120),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 8, weight: 24, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift Focus", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 2, weight: 80, rest: 240),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Bench Volume", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-51",
            nameKey: "Conjugate — Max Effort / Dynamic",
            descKey: "Westside-style: rotating max-effort lifts and speed work, with high-rep accessories. Four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Max Effort Lower", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("good_morning", sets: 3, reps: 8, weight: 35, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 90, rest: 90),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Max Effort Upper", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 210),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 120),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Dynamic Lower", steps: [
                    CommunityStep("squat_barbell", sets: 8, reps: 2, weight: 60, rest: 90),
                    CommunityStep("deadlift", sets: 6, reps: 2, weight: 80, rest: 120),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Dynamic Upper", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 3, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 4, reps: 8, weight: 14, rest: 90),
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 90),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 3, reps: 15, weight: 8, rest: 45),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-52",
            nameKey: "Smolov Jr — Bench",
            descKey: "A four-week, four-day bench specialization peaking program. Add weight each week; expect a big bench PR.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Day 1 — 6×6", steps: [
                    CommunityStep("bench_press_barbell", sets: 6, reps: 6, weight: 45, rest: 180),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 2 — 7×5", steps: [
                    CommunityStep("bench_press_barbell", sets: 7, reps: 5, weight: 45, rest: 180),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 3 — 8×4", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 4, weight: 45, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
                CommunitySession(nameKey: "Day 4 — 10×3", steps: [
                    CommunityStep("bench_press_barbell", sets: 10, reps: 3, weight: 45, rest: 180),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-53",
            nameKey: "Beginner Glute & Lower",
            descKey: "A lower-emphasis beginner plan centered on glute and hamstring development with simple progression.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "GLUTES",
            sessions: [
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("hip_thrust_barbell", sets: 3, reps: 10, weight: 60, rest: 120),
                    CommunityStep("squat_goblet", sets: 3, reps: 12, weight: 24, rest: 90),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 12, weight: 22, rest: 90),
                    CommunityStep("abductor_machine", sets: 3, reps: 20, weight: 35, rest: 45),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("hip_thrust_barbell", sets: 3, reps: 12, weight: 60, rest: 120),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 12, weight: 14, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("abductor_machine", sets: 3, reps: 20, weight: 35, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-54",
            nameKey: "Recomp Upper / Lower — 4 Day",
            descKey: "Moderate volume and intensity for body recomposition — build muscle while staying lean, four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 8, weight: 90, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-55",
            nameKey: "Strength + Size — 5 Day",
            descKey: "Two strength days and three hypertrophy body-part days for the lifter who wants to get both strong and big.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Upper Strength", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Strength", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 8, weight: 90, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Chest & Arms", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Back & Rear Delt", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-56",
            nameKey: "Kettlebell & Dumbbell Hybrid — 3 Day",
            descKey: "Free-weight full-body conditioning for minimal equipment: swings, presses, carries and hinges.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "DUMBBELL",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_goblet", sets: 3, reps: 12, weight: 24, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 75),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 75),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 12, weight: 22, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 12, weight: 24, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Full Body C", steps: [
                    CommunityStep("lunge_walking_dumbbell", sets: 3, reps: 12, weight: 16, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 40, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-57",
            nameKey: "High-Frequency Bench — 5 Day",
            descKey: "Bench every other day with rotating intensities for a fast bench press peak, plus balanced pulling.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Heavy Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 180),
                    CommunityStep("cable_row_seated", sets: 4, reps: 8, weight: 45, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Volume Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 8, weight: 45, rest: 120),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 4, weight: 80, rest: 210),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Speed Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 3, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 4, reps: 8, weight: 14, rest: 90),
                    CommunityStep("pendlay_row", sets: 3, reps: 10, weight: 50, rest: 90),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-58",
            nameKey: "Full Body — 4 Day",
            descKey: "Four full-body sessions hit each lift twice weekly at varied rep ranges — efficient and balanced.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 2, reps: 8, weight: 30, rest: 120),
                    CommunityStep("rdl_barbell", sets: 2, reps: 8, weight: 55, rest: 150),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body C", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 2, reps: 8, weight: 30, rest: 120),
                    CommunityStep("rdl_barbell", sets: 2, reps: 8, weight: 55, rest: 150),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Full Body D", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-59",
            nameKey: "Beginner Bench & Squat Focus",
            descKey: "A 3-day plan that prioritizes bench and squat technique and volume for new lifters chasing those numbers.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Squat Priority", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 2, reps: 12, weight: 40, rest: 60),
                ]),
                CommunitySession(nameKey: "Bench Priority", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 2, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Mixed", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 6, weight: 60, rest: 150),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 120),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-60",
            nameKey: "PPL Strength — 6 Day",
            descKey: "Push/pull/legs with a powerlifting backbone: low-rep main lifts twice weekly plus targeted accessories.",
            frequencyDaysPerWeek: 6,
            levelKey: "Advanced",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push (Bench)", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 4, weight: 45, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull (Deadlift)", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 4, weight: 80, rest: 210),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs (Squat)", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 4, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Push (OHP)", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 5, weight: 30, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull (Row)", steps: [
                    CommunityStep("pendlay_row", sets: 5, reps: 5, weight: 50, rest: 150),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs (Front)", steps: [
                    CommunityStep("squat_front", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-61",
            nameKey: "5/3/1 — First Set Last",
            descKey: "After the 5/3/1 top set, repeat the first work set for several back-off sets to add volume without grinding.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Press", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 5, weight: 30, rest: 120),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("deadlift", sets: 5, reps: 5, weight: 80, rest: 150),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 40, rest: 75),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 120),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-62",
            nameKey: "5/3/1 — Big But Strong",
            descKey: "Heavier 3×5 supplemental work after the main lift — a strength-biased BBB variant. Four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("squat_front", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 5, weight: 42, rest: 150),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Press", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 5, weight: 30, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-63",
            nameKey: "Candito 6-Week Strength",
            descKey: "Jonnie Candito's alternating volume and strength weeks built around the big three. Four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Upper Volume", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Volume", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 4, reps: 8, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Upper Strength", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 4, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 5, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 120),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 90),
                ]),
                CommunitySession(nameKey: "Lower Strength", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 4, weight: 60, rest: 180),
                    CommunityStep("deadlift", sets: 3, reps: 4, weight: 80, rest: 210),
                    CommunityStep("squat_front", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-64",
            nameKey: "Juggernaut Method",
            descKey: "Chad Wesley Smith's wave-loading strength program over 10s, 8s, 5s and 3s waves. Four days a week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Bench Wave", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Squat Wave", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Press Wave", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 5, weight: 30, rest: 150),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift Wave", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 3, weight: 80, rest: 210),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-65",
            nameKey: "Cube Method",
            descKey: "Brandon Lilly's rotating heavy, explosive and rep days for each of the big three. Powerbuilding, four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Heavy Squat", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Explosive Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 8, reps: 3, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 4, reps: 8, weight: 14, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Rep Deadlift", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 8, weight: 80, rest: 180),
                    CommunityStep("good_morning", sets: 3, reps: 10, weight: 35, rest: 120),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Heavy Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 210),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 6, weight: 42, rest: 120),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-66",
            nameKey: "Sheiko-Style Volume",
            descKey: "High-frequency, high-volume Russian powerlifting work on squat, bench and deadlift technique. Four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 150),
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 120),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 150),
                    CommunityStep("good_morning", sets: 3, reps: 8, weight: 35, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 4, weight: 80, rest: 210),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 4, weight: 45, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 90, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 4", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-67",
            nameKey: "Russian Squat Routine",
            descKey: "A three-day squat peaking block — progressive volume and intensity for a big squat in six weeks.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Squat Volume", steps: [
                    CommunityStep("squat_barbell", sets: 6, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Light Squat", steps: [
                    CommunityStep("squat_barbell", sets: 6, reps: 3, weight: 60, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                ]),
                CommunitySession(nameKey: "Squat Intensity", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-68",
            nameKey: "Smolov Jr — Squat",
            descKey: "A four-week, four-day squat specialization peaking program. Brutal but effective for a squat PR.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "6×6", steps: [
                    CommunityStep("squat_barbell", sets: 6, reps: 6, weight: 60, rest: 180),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "7×5", steps: [
                    CommunityStep("squat_barbell", sets: 7, reps: 5, weight: 60, rest: 180),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 15, weight: 45, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "8×4", steps: [
                    CommunityStep("squat_barbell", sets: 8, reps: 4, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                ]),
                CommunitySession(nameKey: "10×3", steps: [
                    CommunityStep("squat_barbell", sets: 10, reps: 3, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-69",
            nameKey: "Ice Cream Fitness 5×5",
            descKey: "A popular beginner 5×5 with extra accessory work for arms and shoulders. Three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Workout A", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 5, reps: 5, weight: 45, rest: 150),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 8, weight: 26, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 8, weight: 25, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 8, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Workout B", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 5, weight: 60, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 5, weight: 30, rest: 150),
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 8, weight: 25, rest: 60),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-70",
            nameKey: "GZCL UHF — 9 Week",
            descKey: "GZCL's Universal Hypertrophy Framework: heavy T1, moderate T2 and high-rep T3 across five days.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 4, weight: 60, rest: 180),
                    CommunityStep("squat_front", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 4, weight: 45, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 4, reps: 15, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 4, reps: 15, weight: 25, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 3, weight: 80, rest: 210),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 4, reps: 15, weight: 0, rest: 60),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "OHP", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 4, weight: 30, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 18, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("lat_pulldown", sets: 4, reps: 12, weight: 45, rest: 75),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 6, weight: 50, rest: 120),
                    CommunityStep("lat_pulldown_close_grip", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("bicep_curl_dumbbell", sets: 4, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-71",
            nameKey: "Coolcicada PPL",
            descKey: "A widely shared free 6-day push/pull/legs routine for size, balancing compounds and isolation.",
            frequencyDaysPerWeek: 6,
            levelKey: "Intermediate",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 12, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("face_pull", sets: 3, reps: 12, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 12, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 10, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 12, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 6, weight: 50, rest: 150),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-72",
            nameKey: "PHUL — Hypertrophy Bias",
            descKey: "A higher-volume PHUL variation that trims the power work and adds isolation for size. Four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Upper Power", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Power", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 6, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 10, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Upper Pump", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Pump", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-73",
            nameKey: "Bro Split — 6 Day",
            descKey: "Six high-volume sessions: chest, back, legs, shoulders, arms and a weak-point day.",
            frequencyDaysPerWeek: 6,
            levelKey: "Advanced",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("decline_bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("dip_chest", sets: 3, reps: 12, weight: 0, rest: 75),
                    CommunityStep("push_up", sets: 2, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Back", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 6, weight: 80, rest: 180),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("barbell_row", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Shoulders", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 30, rest: 120),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 4, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("preacher_curl", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Weak Points", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 12, weight: 20, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 18, weight: 10, rest: 45),
                    CommunityStep("preacher_curl", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 20, weight: 60, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-74",
            nameKey: "Arnold's Golden Six",
            descKey: "Arnold's recommended starter routine of six fundamental movements, three days a week.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Golden Six", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 10, weight: 60, rest: 150),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 120),
                    CommunityStep("chin_up", sets: 3, reps: 10, weight: 0, rest: 90),
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 10, weight: 30, rest: 120),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("crunch", sets: 3, reps: 15, weight: 0, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-75",
            nameKey: "Upper / Lower — 5 Day",
            descKey: "An undulating five-day upper/lower with one extra weak-point session for advanced lifters.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper Strength", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Strength", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 8, weight: 90, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper Hypertrophy", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower Hypertrophy", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms & Delts", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 18, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-76",
            nameKey: "Full Body — 5 Day",
            descKey: "Five short full-body sessions for maximum frequency — each lift trained nearly every day at submaximal loads.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 2, reps: 8, weight: 30, rest: 120),
                    CommunityStep("rdl_barbell", sets: 2, reps: 8, weight: 55, rest: 150),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 2, reps: 8, weight: 30, rest: 120),
                    CommunityStep("rdl_barbell", sets: 2, reps: 8, weight: 55, rest: 150),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 4", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 5", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-77",
            nameKey: "Push Pull Legs Push — 4 Day",
            descKey: "A four-day push/pull/legs/push rotation that prioritizes upper-body pressing for chest and shoulders.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-78",
            nameKey: "Hypertrophy Upper / Lower — Volume",
            descKey: "Maximum hypertrophy volume across four upper/lower days — 15–20 sets per muscle weekly.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-79",
            nameKey: "Antagonist Supersets — 4 Day",
            descKey: "Pair opposing muscles (chest/back, biceps/triceps) for a time-efficient, high-pump upper/lower week.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest & Back", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("pendlay_row", sets: 4, reps: 10, weight: 50, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms & Delts", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                ]),
                CommunitySession(nameKey: "Back & Chest", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 10, weight: 24, rest: 90),
                    CommunityStep("dip_chest", sets: 4, reps: 10, weight: 0, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("pec_deck", sets: 3, reps: 15, weight: 40, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-80",
            nameKey: "Beginner Dumbbell Upper / Lower",
            descKey: "A four-day dumbbell-only upper/lower for novices training at home with adjustable dumbbells.",
            frequencyDaysPerWeek: 4,
            levelKey: "Beginner",
            kicker: "DUMBBELL",
            sessions: [
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 2, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("squat_goblet", sets: 3, reps: 12, weight: 24, rest: 90),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 12, weight: 22, rest: 90),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 12, weight: 24, rest: 75),
                    CommunityStep("arnold_press", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("dumbbell_fly_flat", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 2, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 12, weight: 22, rest: 90),
                    CommunityStep("step_up_dumbbell", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("calf_raise_seated", sets: 3, reps: 18, weight: 40, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-81",
            nameKey: "Posterior Chain Focus",
            descKey: "Hinge-heavy four-day training for hamstrings, glutes and back — great for deadlift and athleticism.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 3, weight: 80, rest: 210),
                    CommunityStep("rdl_barbell", sets: 4, reps: 8, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Upper Pull", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 120),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Glutes & Hams", steps: [
                    CommunityStep("hip_thrust_barbell", sets: 4, reps: 8, weight: 60, rest: 120),
                    CommunityStep("good_morning", sets: 3, reps: 10, weight: 35, rest: 120),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 12, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Press & Core", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 6, weight: 30, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-82",
            nameKey: "Quad-Dominant Hypertrophy",
            descKey: "Front-squat and leg-press heavy lower work for bigger quads, with balanced upper sessions. Four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Quads", steps: [
                    CommunityStep("squat_front", sets: 5, reps: 8, weight: 45, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("hack_squat_machine", sets: 3, reps: 12, weight: 70, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 5, reps: 15, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 12, weight: 20, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Quads & Hams", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 10, weight: 60, rest: 150),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 12, weight: 16, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 12, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 18, weight: 40, rest: 45),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 15, weight: 26, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-83",
            nameKey: "Bench Specialization",
            descKey: "A four-day block to bring up the bench: heavy, volume and speed pressing plus targeted triceps and back.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Heavy Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 3, weight: 45, rest: 180),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 6, weight: 42, rest: 120),
                    CommunityStep("dumbbell_row_single_arm", sets: 4, reps: 8, weight: 24, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 8, weight: 90, rest: 120),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 12, weight: 60, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Volume Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Press & Arms", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 6, weight: 30, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                    CommunityStep("pendlay_row", sets: 3, reps: 10, weight: 50, rest: 90),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-84",
            nameKey: "Deadlift Specialization",
            descKey: "Bring up your pull with heavy and volume deadlift days plus dedicated posterior-chain and grip work.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Heavy Deadlift", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 2, weight: 80, rest: 240),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("shrug_barbell", sets: 3, reps: 12, weight: 60, rest: 60),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Volume Deadlift", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 5, weight: 80, rest: 180),
                    CommunityStep("good_morning", sets: 3, reps: 10, weight: 35, rest: 120),
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 90),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Squat & Core", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-85",
            nameKey: "Squat Specialization",
            descKey: "Two squat sessions a week — heavy and volume — to build a bigger, stronger squat. Four days.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "POWERLIFTING",
            sessions: [
                CommunitySession(nameKey: "Heavy Squat", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("squat_front", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 8, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Volume Squat", steps: [
                    CommunityStep("squat_barbell", sets: 6, reps: 5, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 12, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Pull & Press", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 8, weight: 30, rest: 120),
                    CommunityStep("pendlay_row", sets: 3, reps: 10, weight: 50, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-86",
            nameKey: "Lean Gains Upper / Lower",
            descKey: "A moderate-volume, strength-leaning four-day plan designed to pair with a slight calorie deficit.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("barbell_row", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 2, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 6, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("pendlay_row", sets: 3, reps: 8, weight: 50, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("chin_up", sets: 3, reps: 8, weight: 0, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 2, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-87",
            nameKey: "Strongman Foundations",
            descKey: "Carries, presses and pulls for real-world strength — heavy compound lifts plus loaded carries. Three days.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "ATHLETIC",
            sessions: [
                CommunitySession(nameKey: "Pull & Carry", steps: [
                    CommunityStep("deadlift", sets: 5, reps: 3, weight: 80, rest: 210),
                    CommunityStep("deadlift_trap_bar", sets: 4, reps: 6, weight: 80, rest: 150),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep("shrug_dumbbell", sets: 3, reps: 12, weight: 26, rest: 60),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Press", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 4, weight: 30, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
                CommunitySession(nameKey: "Squat & Hinge", steps: [
                    CommunityStep("squat_front", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("rdl_barbell", sets: 4, reps: 8, weight: 55, rest: 150),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-88",
            nameKey: "Pull-up & Dip Mastery",
            descKey: "Build the two king bodyweight movements with weighted progressions and high-volume back-off work. Three days.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "CALISTHENICS",
            sessions: [
                CommunitySession(nameKey: "Pull Focus", steps: [
                    CommunityStep("pull_up_weighted", sets: 5, reps: 5, weight: 5, rest: 150),
                    CommunityStep("chin_up", sets: 4, reps: 8, weight: 0, rest: 90),
                    CommunityStep("barbell_row", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Push Focus", steps: [
                    CommunityStep("dip_chest", sets: 5, reps: 6, weight: 0, rest: 150),
                    CommunityStep("dip_parallel_bar_triceps", sets: 4, reps: 8, weight: 0, rest: 90),
                    CommunityStep("push_up", sets: 3, reps: 15, weight: 0, rest: 60),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Legs & Core", steps: [
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 4, reps: 10, weight: 16, rest: 90),
                    CommunityStep("nordic_curl", sets: 3, reps: 8, weight: 0, rest: 90),
                    CommunityStep("step_up_dumbbell", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 20, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-89",
            nameKey: "Powerbuilding Bro — 5 Day",
            descKey: "Each body-part day opens with a heavy compound for strength, then bodybuilding volume for size.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "POWERBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 4, weight: 45, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("decline_bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("dip_chest", sets: 3, reps: 12, weight: 0, rest: 75),
                    CommunityStep("push_up", sets: 2, reps: 15, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Back", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 4, weight: 80, rest: 210),
                    CommunityStep("pull_up", sets: 4, reps: 8, weight: 0, rest: 120),
                    CommunityStep("barbell_row", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                ]),
                CommunitySession(nameKey: "Shoulders", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 4, weight: 30, rest: 180),
                    CommunityStep("arnold_press", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 4, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("preacher_curl", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 4, weight: 60, rest: 180),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-90",
            nameKey: "Hypertrophy Full Body — 4 Day",
            descKey: "Four full-body days with rotating exercise selection for balanced, high-frequency muscle growth.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Full Body A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Full Body B", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Full Body C", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 8, weight: 60, rest: 150),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("crunch_cable", sets: 3, reps: 15, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Full Body D", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_cable", sets: 3, reps: 15, weight: 12, rest: 45),
                    CommunityStep("leg_curl_seated", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-91",
            nameKey: "Recovery / Deload Full Body",
            descKey: "A lighter three-day full-body week to deload — submaximal compounds and reduced volume to recover.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("squat_barbell", sets: 2, reps: 5, weight: 60, rest: 120),
                    CommunityStep("bench_press_barbell", sets: 2, reps: 5, weight: 45, rest: 120),
                    CommunityStep("cable_row_seated", sets: 2, reps: 8, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 2, reps: 12, weight: 10, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("rdl_barbell", sets: 2, reps: 6, weight: 55, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 2, reps: 8, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 2, reps: 10, weight: 45, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("leg_press_45", sets: 2, reps: 12, weight: 90, rest: 90),
                    CommunityStep("incline_bench_press_dumbbell", sets: 2, reps: 10, weight: 20, rest: 75),
                    CommunityStep("dumbbell_row_single_arm", sets: 2, reps: 10, weight: 24, rest: 75),
                    CommunityStep("calf_raise_standing", sets: 2, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-92",
            nameKey: "Beginner Glute & Upper — 4 Day",
            descKey: "A four-day plan emphasizing glutes and upper-body shape — popular for first-time female lifters.",
            frequencyDaysPerWeek: 4,
            levelKey: "Beginner",
            kicker: "GLUTES",
            sessions: [
                CommunitySession(nameKey: "Glutes", steps: [
                    CommunityStep("hip_thrust_barbell", sets: 3, reps: 10, weight: 60, rest: 120),
                    CommunityStep("squat_goblet", sets: 3, reps: 12, weight: 24, rest: 90),
                    CommunityStep("abductor_machine", sets: 3, reps: 20, weight: 35, rest: 45),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 3, reps: 15, weight: 40, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Glutes & Legs", steps: [
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 12, weight: 22, rest: 90),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("hip_thrust_barbell", sets: 3, reps: 12, weight: 60, rest: 120),
                    CommunityStep("abductor_machine", sets: 3, reps: 20, weight: 35, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper & Core", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("lateral_raise_cable", sets: 3, reps: 15, weight: 12, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 2, reps: 12, weight: 25, rest: 60),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-93",
            nameKey: "Volume Block — Hypertrophy",
            descKey: "A high-volume five-day accumulation block: lots of sets in the 8–15 range to drive growth.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "HYPERTROPHY",
            sessions: [
                CommunitySession(nameKey: "Chest & Tri", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 12, weight: 20, rest: 75),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 4, reps: 15, weight: 12, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 4, reps: 12, weight: 0, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 15, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Back & Bi", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 10, weight: 50, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 4, reps: 12, weight: 45, rest: 75),
                    CommunityStep("bicep_curl_dumbbell", sets: 4, reps: 12, weight: 12, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 12, weight: 60, rest: 120),
                    CommunityStep("leg_press_45", sets: 4, reps: 15, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Shoulders", steps: [
                    CommunityStep("overhead_press_dumbbell_seated", sets: 4, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lateral_raise_cable", sets: 5, reps: 18, weight: 12, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 5, reps: 15, weight: 8, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("shrug_dumbbell", sets: 4, reps: 15, weight: 26, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms & Weak Points", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 5, reps: 12, weight: 25, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 5, reps: 12, weight: 25, rest: 60),
                    CommunityStep("preacher_curl", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 18, weight: 10, rest: 45),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 15, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-94",
            nameKey: "Intensity Block — Strength",
            descKey: "A four-day peaking block: low reps, high intensity, long rests to express maximal strength.",
            frequencyDaysPerWeek: 4,
            levelKey: "Advanced",
            kicker: "STRENGTH",
            sessions: [
                CommunitySession(nameKey: "Squat", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 2, weight: 60, rest: 240),
                    CommunityStep("squat_front", sets: 3, reps: 5, weight: 45, rest: 150),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 10, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Bench", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 2, weight: 45, rest: 240),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 5, weight: 42, rest: 150),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 8, weight: 24, rest: 90),
                ]),
                CommunitySession(nameKey: "Deadlift", steps: [
                    CommunityStep("deadlift", sets: 4, reps: 2, weight: 80, rest: 240),
                    CommunityStep("rdl_barbell", sets: 3, reps: 5, weight: 55, rest: 150),
                    CommunityStep("back_extension_45_degree", sets: 3, reps: 10, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Press", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 3, weight: 30, rest: 180),
                    CommunityStep("pendlay_row", sets: 3, reps: 6, weight: 50, rest: 120),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-95",
            nameKey: "Functional Strength — 3 Day",
            descKey: "Big compound lifts, single-leg work and carries for balanced, transferable real-world strength.",
            frequencyDaysPerWeek: 3,
            levelKey: "Beginner",
            kicker: "ATHLETIC",
            sessions: [
                CommunitySession(nameKey: "Day 1", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 6, weight: 60, rest: 180),
                    CommunityStep("bench_press_dumbbell", sets: 3, reps: 8, weight: 22, rest: 90),
                    CommunityStep("dumbbell_row_single_arm", sets: 3, reps: 10, weight: 24, rest: 90),
                    CommunityStep(timed: "plank", sets: 3, duration: 40, rest: 45),
                ]),
                CommunitySession(nameKey: "Day 2", steps: [
                    CommunityStep("deadlift_trap_bar", sets: 4, reps: 5, weight: 80, rest: 180),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("split_squat_bulgarian_dumbbell", sets: 3, reps: 10, weight: 16, rest: 90),
                    CommunityStep("leg_raise_hanging", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Day 3", steps: [
                    CommunityStep("squat_front", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("chin_up", sets: 3, reps: 8, weight: 0, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-96",
            nameKey: "Chest & Triceps / Back & Biceps / Legs",
            descKey: "A classic 3-day bodybuilding split grouping synergist muscles for big sessions.",
            frequencyDaysPerWeek: 3,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest & Triceps", steps: [
                    CommunityStep("bench_press_barbell", sets: 4, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Back & Biceps", steps: [
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 120),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs & Shoulders", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-97",
            nameKey: "Olympic-Style Power — 3 Day",
            descKey: "Explosive triple-extension strength: heavy front squats, pulls and presses for power athletes.",
            frequencyDaysPerWeek: 3,
            levelKey: "Advanced",
            kicker: "ATHLETIC",
            sessions: [
                CommunitySession(nameKey: "Pull & Squat", steps: [
                    CommunityStep("squat_front", sets: 5, reps: 3, weight: 45, rest: 210),
                    CommunityStep("deadlift_trap_bar", sets: 5, reps: 3, weight: 80, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 6, weight: 55, rest: 150),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Press & Push", steps: [
                    CommunityStep("overhead_press_barbell", sets: 5, reps: 3, weight: 30, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 4, weight: 45, rest: 180),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 6, weight: 5, rest: 120),
                    CommunityStep("dip_parallel_bar_triceps", sets: 3, reps: 10, weight: 0, rest: 75),
                ]),
                CommunitySession(nameKey: "Squat & Pull", steps: [
                    CommunityStep("squat_barbell", sets: 5, reps: 3, weight: 60, rest: 210),
                    CommunityStep("pendlay_row", sets: 4, reps: 5, weight: 50, rest: 150),
                    CommunityStep("lunge_forward_dumbbell", sets: 3, reps: 8, weight: 14, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 12, weight: 60, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-98",
            nameKey: "Hybrid PPL Upper Lower — 5 Day",
            descKey: "A five-day blend that trains push/pull/legs then an extra upper and lower for chest and back emphasis.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "PUSH / PULL / LEGS",
            sessions: [
                CommunitySession(nameKey: "Push", steps: [
                    CommunityStep("bench_press_barbell", sets: 5, reps: 5, weight: 45, rest: 180),
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 8, weight: 20, rest: 90),
                    CommunityStep("bench_press_close_grip", sets: 3, reps: 8, weight: 42, rest: 90),
                    CommunityStep("lateral_raise_dumbbell", sets: 3, reps: 15, weight: 10, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Pull", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("barbell_row", sets: 4, reps: 6, weight: 45, rest: 150),
                    CommunityStep("pull_up_weighted", sets: 3, reps: 6, weight: 5, rest: 120),
                    CommunityStep("cable_row_seated", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("shrug_barbell", sets: 3, reps: 12, weight: 60, rest: 60),
                    CommunityStep("bicep_curl_barbell", sets: 3, reps: 10, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 12, weight: 60, rest: 45),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("cable_row_seated", sets: 4, reps: 10, weight: 45, rest: 90),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 12, weight: 14, rest: 75),
                    CommunityStep("lat_pulldown_close_grip", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 15, weight: 10, rest: 45),
                    CommunityStep("bicep_curl_dumbbell", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-99",
            nameKey: "Two-a-Week Strength — 2 Day",
            descKey: "For very busy lifters: two intense full-body strength sessions that still cover all the main lifts.",
            frequencyDaysPerWeek: 2,
            levelKey: "Intermediate",
            kicker: "FULL BODY",
            sessions: [
                CommunitySession(nameKey: "Squat Focus", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 5, weight: 60, rest: 180),
                    CommunityStep("bench_press_barbell", sets: 4, reps: 5, weight: 45, rest: 180),
                    CommunityStep("pendlay_row", sets: 3, reps: 6, weight: 50, rest: 150),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                ]),
                CommunitySession(nameKey: "Deadlift Focus", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 5, weight: 30, rest: 180),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-100",
            nameKey: "Classic Physique — 5 Day",
            descKey: "Old-school aesthetics: emphasis on shoulders, chest, back width and arms for a V-taper. Five days.",
            frequencyDaysPerWeek: 5,
            levelKey: "Advanced",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Chest & Shoulders", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("bench_press_barbell", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 4, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lateral_raise_cable", sets: 4, reps: 15, weight: 12, rest: 45),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Back", steps: [
                    CommunityStep("pull_up_weighted", sets: 4, reps: 8, weight: 5, rest: 120),
                    CommunityStep("pendlay_row", sets: 4, reps: 8, weight: 50, rest: 90),
                    CommunityStep("lat_pulldown", sets: 4, reps: 10, weight: 45, rest: 75),
                    CommunityStep("cable_row_seated", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("face_pull", sets: 3, reps: 15, weight: 20, rest: 60),
                ]),
                CommunitySession(nameKey: "Arms", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 75),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("preacher_curl", sets: 3, reps: 12, weight: 25, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("squat_barbell", sets: 4, reps: 8, weight: 60, rest: 150),
                    CommunityStep("leg_press_45", sets: 4, reps: 12, weight: 90, rest: 90),
                    CommunityStep("rdl_barbell", sets: 3, reps: 10, weight: 55, rest: 120),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_lying", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 5, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Delts & Weak Points", steps: [
                    CommunityStep("overhead_press_barbell", sets: 4, reps: 8, weight: 30, rest: 120),
                    CommunityStep("lateral_raise_dumbbell", sets: 5, reps: 18, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 4, reps: 15, weight: 8, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 4, reps: 20, weight: 60, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-101",
            nameKey: "Beginner Strength — 4 Day Upper/Lower",
            descKey: "A gentle four-day upper/lower introduction to higher-frequency training after a first linear-progression block.",
            frequencyDaysPerWeek: 4,
            levelKey: "Beginner",
            kicker: "UPPER / LOWER",
            sessions: [
                CommunitySession(nameKey: "Upper A", steps: [
                    CommunityStep("bench_press_barbell", sets: 3, reps: 6, weight: 45, rest: 150),
                    CommunityStep("barbell_row", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("overhead_press_dumbbell_seated", sets: 3, reps: 10, weight: 14, rest: 90),
                    CommunityStep("lat_pulldown", sets: 3, reps: 10, weight: 45, rest: 90),
                    CommunityStep("bicep_curl_dumbbell", sets: 2, reps: 12, weight: 12, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower A", steps: [
                    CommunityStep("squat_barbell", sets: 3, reps: 6, weight: 60, rest: 180),
                    CommunityStep("rdl_barbell", sets: 3, reps: 8, weight: 55, rest: 150),
                    CommunityStep("leg_extension_machine", sets: 3, reps: 12, weight: 45, rest: 60),
                    CommunityStep("calf_raise_standing", sets: 3, reps: 15, weight: 60, rest: 45),
                ]),
                CommunitySession(nameKey: "Upper B", steps: [
                    CommunityStep("overhead_press_barbell", sets: 3, reps: 6, weight: 30, rest: 150),
                    CommunityStep("cable_row_seated", sets: 3, reps: 8, weight: 45, rest: 120),
                    CommunityStep("incline_bench_press_dumbbell", sets: 3, reps: 10, weight: 20, rest: 90),
                    CommunityStep("chin_up", sets: 3, reps: 8, weight: 0, rest: 90),
                    CommunityStep("triceps_pushdown_rope", sets: 2, reps: 12, weight: 25, rest: 60),
                ]),
                CommunitySession(nameKey: "Lower B", steps: [
                    CommunityStep("deadlift", sets: 3, reps: 5, weight: 80, rest: 210),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_curl_lying", sets: 3, reps: 12, weight: 40, rest: 75),
                    CommunityStep(timed: "plank", sets: 3, duration: 45, rest: 45),
                ]),
            ]
        ),
        CommunityPlan(
            id: "community-gen-102",
            nameKey: "High-Volume Arms & Delts — 4 Day",
            descKey: "An upper-body-biased four-day plan with two dedicated arm-and-shoulder days for sleeve-busting growth.",
            frequencyDaysPerWeek: 4,
            levelKey: "Intermediate",
            kicker: "BODYBUILDING",
            sessions: [
                CommunitySession(nameKey: "Arms & Delts", steps: [
                    CommunityStep("bicep_curl_barbell", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("skullcrusher_ez_bar", sets: 4, reps: 10, weight: 25, rest: 60),
                    CommunityStep("hammer_curl", sets: 3, reps: 12, weight: 12, rest: 60),
                    CommunityStep("overhead_extension_dumbbell_two_hand", sets: 3, reps: 12, weight: 15, rest: 60),
                    CommunityStep("lateral_raise_dumbbell", sets: 4, reps: 18, weight: 10, rest: 45),
                    CommunityStep("rear_delt_fly_dumbbell", sets: 3, reps: 15, weight: 8, rest: 45),
                ]),
                CommunitySession(nameKey: "Legs", steps: [
                    CommunityStep("hack_squat_machine", sets: 4, reps: 10, weight: 70, rest: 120),
                    CommunityStep("rdl_dumbbell", sets: 3, reps: 10, weight: 22, rest: 90),
                    CommunityStep("leg_press_45", sets: 3, reps: 12, weight: 90, rest: 90),
                    CommunityStep("leg_extension_machine", sets: 4, reps: 15, weight: 45, rest: 60),
                    CommunityStep("leg_curl_seated", sets: 4, reps: 15, weight: 40, rest: 60),
                    CommunityStep("calf_raise_seated", sets: 4, reps: 15, weight: 40, rest: 45),
                    CommunityStep("ab_wheel_rollout_kneeling", sets: 3, reps: 12, weight: 0, rest: 60),
                ]),
                CommunitySession(nameKey: "Chest & Back", steps: [
                    CommunityStep("incline_bench_press_dumbbell", sets: 4, reps: 10, weight: 20, rest: 90),
                    CommunityStep("pendlay_row", sets: 4, reps: 10, weight: 50, rest: 90),
                    CommunityStep("cable_crossover_mid", sets: 3, reps: 15, weight: 12, rest: 60),
                    CommunityStep("lat_pulldown", sets: 3, reps: 12, weight: 45, rest: 75),
                    CommunityStep("dip_chest", sets: 3, reps: 12, weight: 0, rest: 75),
                ]),
                CommunitySession(nameKey: "Arms & Delts", steps: [
                    CommunityStep("preacher_curl", sets: 4, reps: 12, weight: 25, rest: 60),
                    CommunityStep("dip_parallel_bar_triceps", sets: 4, reps: 10, weight: 0, rest: 75),
                    CommunityStep("bicep_curl_cable", sets: 3, reps: 15, weight: 15, rest: 45),
                    CommunityStep("triceps_pushdown_rope", sets: 3, reps: 15, weight: 25, rest: 60),
                    CommunityStep("lateral_raise_cable", sets: 4, reps: 18, weight: 12, rest: 45),
                    CommunityStep("upright_row_barbell", sets: 3, reps: 12, weight: 30, rest: 60),
                ]),
            ]
        ),
    ]
}

// MARK: - Materialization — community plan → 真正的 Plan 数组 (加进 data.plans)

extension CommunityPlan {
    /// 把 community plan 的所有 session 实例化成具体 Plan 数组.
    /// 每张 Plan 一个独立 id (plan-community-<short uuid>-<idx>), 名字是
    /// "<community plan name> · <session name>".
    /// 调用者: CommunityScreen tap "Add to my plans" → data.plans.append(contentsOf:) → save()
    func materialize(now: Date = Date(), byId: [String: Exercise], idPrefix: String = "plan-community") -> [Plan] {
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
                id: "\(idPrefix)-\(shortUUID)-\(idx)",
                name: displayName,
                steps: validSteps,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        }
    }
}
