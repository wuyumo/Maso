import Foundation

enum WeightUnit: String, Codable, Sendable { case kg, lb }
enum DistanceUnit: String, Codable, Sendable { case km, mi }
enum Gender: String, Codable, Sendable { case male, female, other }
enum ProgramStyle: String, Codable, Sendable { case fullBody = "full-body", balanced, split }

// 订阅相关
enum SubscriptionTier: String, Codable, Sendable {
    case monthly, yearly, lifetime
}

struct ProSubscription: Codable, Sendable {
    let tier: SubscriptionTier
    let startedAt: Date
    /// nil = lifetime (没有结束日)
    let renewsAt: Date?
}

// 用户设置 — 跟 web 端的 Settings 1:1 对齐
struct UserSettings: Codable, Sendable {
    var weightUnit: WeightUnit = .kg
    var distanceUnit: DistanceUnit = .km
    var defaultRestSeconds: Int = 90
    /// 动作之间的休息 (秒) — Plan 内 step 之间默认插入的过渡 rest
    /// 跟 defaultRestSeconds (同动作组间) 分开, 因为换动作往往需要更长时间走位 / 调器械
    var defaultBetweenExerciseRestSeconds: Int = 120
    var hapticOnSetComplete: Bool = true
    var language: String = "zh-Hans"
    var sleepGoalHours: Int = 8

    var onboardingCompleted: Bool = false
    var weeklyTrainingDays: Int = 3
    var recommendedPlanIds: [String] = []
    var programStyle: ProgramStyle = .fullBody

    /// 用户希望加强的肌群 (优先 2x / week)
    var wantStrengthen: [MuscleGroup] = []
    /// 用户希望维持的肌群 (优先 1x / week)
    var wantMaintain: [MuscleGroup] = []

    var gender: Gender?
    var age: Int?
    var weight: Double?

    /// 在「今日」页时, 再次点击高亮的中间 Tab 是否直接启动推荐训练
    /// true (默认): 二次点击 = 启动今日推荐训练 (快捷)
    /// false:       二次点击 = 无操作
    var quickStartOnActiveTab: Bool = true

    /// Pro 订阅状态 — nil = free 用户
    /// (MVP 阶段是本地 mock, 生产环境接 StoreKit 2)
    var proSubscription: ProSubscription? = nil

    var isPro: Bool { proSubscription != nil }

    /// Apple Fitness (HealthKit) 同步开关.
    /// 用户在 Settings 主动打开 → 触发 HealthKit 授权对话框 → 已存训练补写 + 之后每次完成都写.
    /// 默认 false — 不能未经允许就写入用户健康数据.
    var healthKitSyncEnabled: Bool = false

    /// 已经成功写到 HealthKit 的 session id 集合 (sessionId = "planId|day" 格式或自由组).
    /// 避免同一次训练重复 push.
    var healthKitSyncedSessionIds: Set<String> = []

    /// 用户是否已经看过"点中间 Tab 开始训练"的首次提示 — 看过后不再展示.
    var hasSeenCenterTabHint: Bool = false

    /// 是否启用 AI 训练计划生成. 默认关 (用户需要先填 API key 才能启用).
    var aiWorkoutEnabled: Bool = false

    /// 肌肉分区颗粒度. true (默认): 暴露 sub-muscle (上胸/下胸/股二头/股内肌...).
    /// false: UI 只暴露 major (chest / back / quads / hamstrings...). 身体图也合并描边显示成大块.
    /// 影响:
    ///   - QuickMuscleStep 是否显示 sub chip
    ///   - BodyHint 渲染时是否画 sub 间分隔线
    ///   - 身体图 tap → 始终落到 major (无论开关, sub 折叠到 major 都是 Step 1 的语义)
    /// 新手 / 不在意分区的用户关掉可以减少认知负担; 专业用户开着拿精确度.
    var muscleDetailEnabled: Bool = true

    /// 收藏的动作 ID 集合 — 所有"选择动作"列表会把收藏动作排在最前.
    /// (e.g. Library / ExercisePickerSheet / QuickWorkout Step 2 都用.)
    /// Set<String> Codable 自动 work, 用 Array 持久化 (Set 跨语言 Codable 不稳).
    var favoriteExerciseIds: [String] = []
}

// MARK: - Free 用户的软上限

enum FreeLimit {
    /// 免费用户最多保存几个训练计划
    static let maxPlans: Int = 3
}
