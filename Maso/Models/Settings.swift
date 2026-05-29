import Foundation

enum WeightUnit: String, Codable, Sendable { case kg, lb }
enum DistanceUnit: String, Codable, Sendable { case km, mi }
enum Gender: String, Codable, Sendable { case male, female, other }
enum ProgramStyle: String, Codable, Sendable { case fullBody = "full-body", balanced, split }

/// 一周从哪天开始 — 影响日历 / 本周 stats / 周分组所有 calendar 计算.
/// 默认 .system, 跟随用户 iOS 系统 locale (US/JP 默认周日 = 1, 中欧大陆默认周一 = 2).
/// 用户可在 Settings 显式 override.
enum WeekStartDay: String, Codable, Sendable, CaseIterable {
    case system   // 跟随 iOS 系统 locale
    case sunday
    case monday

    /// 解析成 Calendar.firstWeekday 兼容的 Int (1 = Sunday, 2 = Monday, etc.)
    /// .system 时返回 nil — caller 用 Calendar.current 默认值.
    var resolvedFirstWeekday: Int? {
        switch self {
        case .system: return nil
        case .sunday: return 1
        case .monday: return 2
        }
    }

    /// 给 UI 显示的名字 (英文 — Localizable.strings 走 LocalizedStringKey 查表).
    var displayName: String {
        switch self {
        case .system: return "System default"
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        }
    }
}

// 订阅相关
enum SubscriptionTier: String, Codable, Sendable {
    case monthly, yearly, lifetime
}

struct ProSubscription: Codable, Sendable, Equatable {
    let tier: SubscriptionTier
    let startedAt: Date
    /// nil = lifetime (没有结束日)
    let renewsAt: Date?
}

extension SubscriptionTier: Equatable {}

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

    /// Session 用户照片 — key = SessionSummary.id (e.g. "plan-full-1-1715900000"),
    /// value = JPEG data.
    /// 用户在 ShareCustomizeSheet 加的照片存这里, History 列表 + Session 详情页都会展示.
    /// JPEG 压缩到 quality 0.7 — 在分享视觉清晰度和持久化体积之间妥协 (典型照片 ~100-300KB).
    var sessionPhotos: [String: Data] = [:]

    /// 一周从哪天开始. 默认 .system 跟随 iOS 系统 locale; 用户可在 Settings 显式 override.
    /// 影响: History tab 的日历周排版 / 本周 stats 计算 / 任何 weekOfYear 分组.
    var weekStartDay: WeekStartDay = .system

    /// 用户从 "Rare exercises" 库里"采纳"过的小众动作 ID 集合 —
    /// 一旦采纳, 该 niche 动作就出现在主 picker (跟普通动作并列), 不再被默认筛掉.
    /// 用户在 Exercise Library → "+ Add exercise" → "Browse rare exercises" 路径里 tap "Add" 才会进这个集合.
    /// Array 持久化跟 favoriteExerciseIds 同套路 (Set 跨语言 Codable 不稳).
    var adoptedNicheExerciseIds: [String] = []

    /// 用户自己创建的动作 — 在 Library 里 "+ Add exercise" → "Create your own" 路径创建的.
    /// 跟 bundle 动作并列出现在所有 picker. 数据完全自包含 (没 imageFolder, 用 customImageData 渲图).
    var customExercises: [Exercise] = []

    /// 推荐 plan 每张张多少个动作. 之前硬编码 4 (kMaxStepsPerRecommendedPlan), 现在交给用户.
    /// 1-6 区间. 6 是个上限 — 单次训练超过这个会偏长 (>60 min), 不符合"今日训练"的心智.
    var exercisesPerSession: Int = 4

    /// 每个动作默认几组. RecommendedPrograms / AI / Free workout 创建 step 都用这个.
    var defaultSetsPerExercise: Int = 3

    /// 训练目标 — 决定默认 reps + 间歇. 三档对应运动科学常见 rep range:
    ///   - strength: 1-5 reps, 长间歇 (3-5 min). 力量训练 / powerlifting style.
    ///   - hypertrophy: 6-12 reps, 60-90s. 增肌主流 (NSCA/ACSM 推荐).
    ///   - endurance: 12-20 reps, 30-60s. 肌耐力 / fat loss.
    /// 默认 hypertrophy — 覆盖最广 (健身房 80%+ 用户的目标).
    var trainingGoal: TrainingGoal = .hypertrophy
}

/// 训练目标 — 影响默认 reps + 组间歇.
/// 科学参考: NSCA "Essentials of Strength Training" + ACSM guidelines.
enum TrainingGoal: String, Codable, Sendable, CaseIterable {
    case strength      // 1-5 reps, 长歇
    case hypertrophy   // 6-12 reps, 中歇 (默认)
    case endurance     // 12-20 reps, 短歇

    /// 该目标下, 复合 (compound) 动作的默认 reps. 复合动作偏重负荷, reps 取目标低端.
    func defaultRepsForCompound() -> Int {
        switch self {
        case .strength:    return 5
        case .hypertrophy: return 8
        case .endurance:   return 15
        }
    }
    /// 该目标下, 孤立 (isolation) 动作的默认 reps. 孤立动作偏 volume, reps 取目标高端.
    func defaultRepsForIsolation() -> Int {
        switch self {
        case .strength:    return 8
        case .hypertrophy: return 12
        case .endurance:   return 18
        }
    }
    /// 该目标推荐的组间歇 (秒). 用户在 settings.defaultRestSeconds 显式 override 时优先.
    func recommendedRestSeconds() -> Int {
        switch self {
        case .strength:    return 180
        case .hypertrophy: return 90
        case .endurance:   return 45
        }
    }
    var displayName: String {
        switch self {
        case .strength:    return NSLocalizedString("Strength", comment: "")
        case .hypertrophy: return NSLocalizedString("Hypertrophy", comment: "")
        case .endurance:   return NSLocalizedString("Endurance", comment: "")
        }
    }
    var subtitle: String {
        switch self {
        case .strength:    return NSLocalizedString("1–5 reps, heavy weight, long rest", comment: "")
        case .hypertrophy: return NSLocalizedString("6–12 reps, moderate weight, ~90s rest", comment: "")
        case .endurance:   return NSLocalizedString("12–20 reps, lighter weight, short rest", comment: "")
        }
    }
}

// MARK: - 派生 Calendar (跟着 UserSettings.weekStartDay)

extension UserSettings {
    /// 按用户偏好返回一个 Calendar — 整 app 跟"周"相关的 date math 走这个,
    /// 不要直接 `Calendar.current`. 一改 settings, 整 app 周排版同步.
    /// system 模式直接返回 Calendar.current (firstWeekday 跟系统 locale).
    var calendar: Calendar {
        var cal = Calendar.current
        if let fw = weekStartDay.resolvedFirstWeekday {
            cal.firstWeekday = fw
        }
        return cal
    }
}

// MARK: - Free 用户的软上限

enum FreeLimit {
    /// 免费用户最多保存几个训练计划
    static let maxPlans: Int = 3
}
