import Foundation

/// 上线开关 — 首版以"纯免费 App"提审 (账号身份/付费协议未理顺前). iapEnabled = false →
/// 隐藏所有内购入口 (付费墙 / 升级 / 恢复购买 / Settings Pro 区) + 解锁所有 Pro 功能,
/// 审核看不到"能点不能买"的购买流. 等付费协议 Active 后改回 true 再发版把内购加回来.
enum MasoFlags {
    static let iapEnabled = true
}

enum WeightUnit: String, Codable, Sendable { case kg, lb }

extension WeightUnit {
    /// 显示用单位标签.
    var label: String { self == .kg ? "kg" : "lb" }
    static let lbPerKg: Double = 2.2046226218
    /// canonical kg → 当前单位数值 (显示 / 编辑用). 全 app 重量 canonical 存 kg.
    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * Self.lbPerKg }
    /// 当前单位数值 → canonical kg (存储用).
    func toKg(_ v: Double) -> Double { self == .kg ? v : v / Self.lbPerKg }
    /// 训练负重步进增量 (kg 2.5 / lb 5).
    var weightStep: Double { self == .kg ? 2.5 : 5 }
    /// 体重步进增量 (kg 1 / lb 2).
    var bodyWeightStep: Double { self == .kg ? 1 : 2 }
    /// 训练负重上限 (canonical 500kg ≈ 1100lb).
    var weightMax: Double { self == .kg ? 500 : 1100 }
}

/// 全局当前重量单位 — 显示 helper (weightLabel) 读它, 免在几十个子视图里穿线传 unit.
/// RootView 在 settings.weightUnit 变化时 (含首帧) 更新; 仅 UI 线程读写.
enum WeightUnitProvider {
    /// 只在主线程读写 (RootView 更新 / 显示 helper 读), 用 nonisolated(unsafe) 让自由函数 helper 也能读.
    nonisolated(unsafe) static var current: WeightUnit = .kg
}
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

    /// iapEnabled = false (免费版上线) → 视为 Pro, 解锁所有 gate (无内购时不留功能墙).
    /// proSubscription 仍保持 nil — 不写假数据, 改回 iapEnabled = true 即恢复正常 free/pro 判定.
    var isPro: Bool { !MasoFlags.iapEnabled || proSubscription != nil }

    /// Apple Fitness (HealthKit) 同步开关.
    /// 用户在 Settings 主动打开 → 触发 HealthKit 授权对话框 → 已存训练补写 + 之后每次完成都写.
    /// 默认 false — 不能未经允许就写入用户健康数据.
    var healthKitSyncEnabled: Bool = false

    /// 已经成功写到 HealthKit 的 session id 集合 (sessionId = "planId|day" 格式或自由组).
    /// 避免同一次训练重复 push.
    var healthKitSyncedSessionIds: Set<String> = []

    /// 用户是否已经看过"点中间 Tab 开始训练"的首次提示 — 看过后不再展示.
    var hasSeenCenterTabHint: Bool = false

    /// 是否已经请求过 App Store 评分 — 只在用户练到一定次数后请求一次 (iOS 自身也会限频, 每年至多 3 次).
    var hasRequestedReview: Bool = false

    /// 召回提醒开关 — 默认关 (opt-in, 符合"不打扰"品牌). 打开后在恢复窗口轻推"该练了".
    var workoutRemindersEnabled: Bool = false

    /// 是否已经在训练完成的正向时刻软问过一次"要不要开召回提醒" — 全生命周期只问一次, 不纠缠.
    var hasOfferedReminderPrompt: Bool = false

    /// 是否启用 AI 训练计划生成. 默认开 (Path B: 代理 server-side 已配, 真 AI 默认跑, 失败自动回落本地).
    /// 现已不再作为 gate (各调用点只看 AIWorkoutService.isConfigured); 保留作未来用户开关位.
    var aiWorkoutEnabled: Bool = true

    /// 偏好社区计划. 默认关. 打开后: 推荐计划 (AI Plans) 不再从模板自动生成, 而是从 Community
    /// 里挑一套符合用户 days/week + 训练目标的成熟计划 materialize 进来 (按 exercises-per-plan 微调).
    /// 即"少自动生成, 多采用社区已验证的计划". 见 DataStore.regenerateRecommendedPlans.
    var preferCommunityPlans: Bool = false

    /// #1 健身房可用器械 — 存 EquipmentCategory.rawValue. 空 = 不限制 (默认, 全器械可用).
    /// 非空 = 只用所选器械 (+ 自重永远可用) 出计划; AI / 本地推荐都按这个约束选动作.
    /// 用户场景: 进健身房前勾上"我这家健身房有的设备", 之后推荐 / AI 只出这些器械能做的动作.
    var availableEquipment: [String] = []

    /// 肌肉分区颗粒度. true (默认): 暴露 sub-muscle (上胸/下胸/股二头/股内肌...).
    /// false: UI 只暴露 major (chest / back / quads / hamstrings...). 身体图也合并描边显示成大块.
    /// 影响:
    ///   - QuickMuscleStep 是否显示 sub chip
    ///   - BodyHint 渲染时是否画 sub 间分隔线
    ///   - 身体图 tap → 始终落到 major (无论开关, sub 折叠到 major 都是 Step 1 的语义)
    /// 新手 / 不在意分区的用户关掉可以减少认知负担; 专业用户开着拿精确度.
    var muscleDetailEnabled: Bool = true

    /// 全局动作参数同步 (R3). 默认 ON.
    /// true: 在任意 routine / 训练中改了某动作的参数 (组数/次数/重量/休息/逐组覆盖),
    ///       会传播到所有含该动作的 routine — "一处改, 全局更新".
    /// false: 各 routine 的同一动作参数互相独立; 新 routine 里加该动作时默认从
    ///        该动作最近一次记录 (lastSet) 回填数值.
    var globalExerciseParamSyncEnabled: Bool = true

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

    /// 训练目标 (内部 loading 档) — 决定默认 reps + 间歇. 三档对应运动科学常见 rep range:
    ///   - strength: 1-5 reps, 长间歇 (3-5 min). 力量训练 / powerlifting style.
    ///   - hypertrophy: 6-12 reps, 60-90s. 增肌主流 (NSCA/ACSM 推荐).
    ///   - endurance: 12-20 reps, 30-60s. 肌耐力 / fat loss.
    /// 默认 hypertrophy — 覆盖最广 (健身房 80%+ 用户的目标).
    /// ⚠️ 现在它是 trainingGoalKind 的派生值 (见下) — UI 不再直接写它, 改写 trainingGoalKind,
    /// 由 didSet 级联设这个 + defaultRestSeconds. 所有既有"读 settings.trainingGoal"保持不变.
    var trainingGoal: TrainingGoal = .hypertrophy

    /// 用户面训练目标 (5 档, 比 trainingGoal 更贴用户心智) — 增肌 / 增力 / 减脂 / 健康 / 耐力.
    /// 改它时级联: trainingGoal = kind.loading (映射到 3 档 loading), defaultRestSeconds = 该目标推荐组间歇.
    /// (跟旧 TrainingGoal 菜单"选目标也设组间歇"的行为一致, 只是上移到 5 档这一层.)
    var trainingGoalKind: TrainingGoalKind = .buildMuscle {
        didSet {
            trainingGoal = trainingGoalKind.loading
            defaultRestSeconds = trainingGoalKind.recommendedRestSeconds()
        }
    }
}

/// 用户面训练目标 (5 档) — 比内部 TrainingGoal (strength/hypertrophy/endurance) 更贴用户心智.
/// 是 TrainingGoal 之上的"薄壳": 每档派生 (loading 档 + 推荐组间歇 + 组数地板), rep 表仍走 TrainingGoal.
/// 科学参考: NSCA / ACSM + 增肌容量 (10-20 hard sets/muscle/wk) 文献.
enum TrainingGoalKind: String, Codable, Sendable, CaseIterable {
    case buildMuscle      // 增肌 → hypertrophy loading
    case getStronger      // 增力 → strength loading
    case loseFat          // 减脂 → hypertrophy loading + 更紧组间歇
    case generalFitness   // 健康 → hypertrophy reps, 组数地板更低
    case endurance        // 耐力 → endurance loading

    var displayName: String {
        switch self {
        case .buildMuscle:    return NSLocalizedString("Build muscle", comment: "training goal")
        case .getStronger:    return NSLocalizedString("Get stronger", comment: "training goal")
        case .loseFat:        return NSLocalizedString("Lose fat / get lean", comment: "training goal")
        case .generalFitness: return NSLocalizedString("Stay fit & healthy", comment: "training goal")
        case .endurance:      return NSLocalizedString("Build endurance", comment: "training goal")
        }
    }

    var subtitle: String {
        switch self {
        case .buildMuscle:    return NSLocalizedString("Add size — moderate reps, higher volume.", comment: "training goal subtitle")
        case .getStronger:    return NSLocalizedString("Lift heavier — low reps, heavy compounds, long rest.", comment: "training goal subtitle")
        case .loseFat:        return NSLocalizedString("Keep muscle while leaning out — compound-heavy, tighter rest.", comment: "training goal subtitle")
        case .generalFitness: return NSLocalizedString("Balanced full-body work, short and sustainable.", comment: "training goal subtitle")
        case .endurance:      return NSLocalizedString("High reps, short rest, circuit-style stamina.", comment: "training goal subtitle")
        }
    }

    /// SF Symbol — 用在引导步选项 + Settings 菜单 (icon 跟语义对齐).
    var icon: String {
        switch self {
        case .buildMuscle:    return "figure.strengthtraining.traditional"
        case .getStronger:    return "dumbbell.fill"
        case .loseFat:        return "flame.fill"
        case .generalFitness: return "heart.fill"
        case .endurance:      return "figure.run"
        }
    }

    /// 映射到内部 loading 档 (rep 表来源). 增肌 / 减脂 / 健康都走 hypertrophy reps.
    var loading: TrainingGoal {
        switch self {
        case .buildMuscle, .loseFat, .generalFitness: return .hypertrophy
        case .getStronger: return .strength
        case .endurance:   return .endurance
        }
    }

    /// 该目标推荐组间歇 (秒). 改目标时级联设 defaultRestSeconds.
    ///   增肌 90 / 增力 180 / 减脂 60 (更密提热量消耗) / 健康 75 / 耐力 45.
    func recommendedRestSeconds() -> Int {
        switch self {
        case .buildMuscle:    return 90
        case .getStronger:    return 180
        case .loseFat:        return 60
        case .generalFitness: return 75
        case .endurance:      return 45
        }
    }

    /// 该目标的每动作组数地板 (Casual lifter): 增力 3 (低 reps 多组) / 健康 2 (短 session) / 其余 3.
    func recommendedSetsFloor() -> Int {
        switch self {
        case .getStronger:    return 3
        case .generalFitness: return 2
        default:              return 3
        }
    }
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

// MARK: - EquipmentCategory (#1)
//
// 数据里有 80+ 个细粒度 equipment 值 (dumbbell / bench_flat / leg_press_machine …),
// 用户面不可能逐个勾. 归并成 ~9 个大类供"健身房可用器械"多选.
// gate 只看动作的"主器械" (equipmentAll.first / equipment) —— bench / plate / rack 等
// 附件不卡 (有哑铃的健身房默认有凳), 避免过度限制把能做的动作也筛掉.
enum EquipmentCategory: String, CaseIterable, Identifiable, Sendable {
    case dumbbell, barbell, cable, machine, smith, kettlebell, bands, pullupBar, cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dumbbell:   return NSLocalizedString("Dumbbells", comment: "equipment")
        case .barbell:    return NSLocalizedString("Barbell & plates", comment: "equipment")
        case .cable:      return NSLocalizedString("Cable machine", comment: "equipment")
        case .machine:    return NSLocalizedString("Resistance machines", comment: "equipment")
        case .smith:      return NSLocalizedString("Smith machine", comment: "equipment")
        case .kettlebell: return NSLocalizedString("Kettlebells", comment: "equipment")
        case .bands:      return NSLocalizedString("Resistance bands", comment: "equipment")
        case .pullupBar:  return NSLocalizedString("Pull-up / dip bar", comment: "equipment")
        case .cardio:     return NSLocalizedString("Cardio machines", comment: "equipment")
        }
    }

    var icon: String {
        switch self {
        case .dumbbell:   return "dumbbell.fill"
        case .barbell:    return "figure.strengthtraining.traditional"
        case .cable:      return "cablecar"
        case .machine:    return "gearshape.2.fill"
        case .smith:      return "square.split.1x2.fill"
        case .kettlebell: return "figure.core.training"
        case .bands:      return "alternatingcurrent"
        case .pullupBar:  return "figure.gymnastics"
        case .cardio:     return "figure.run"
        }
    }

    /// 这个大类涵盖的细粒度 equipment 值.
    var rawEquipmentValues: Set<String> {
        switch self {
        case .dumbbell:   return ["dumbbell", "dumbbells"]
        case .barbell:    return ["barbell","barbells","ez_bar","ez_curl_bar","trap_bar","axle_bar","safety_squat_bar","weight_plate","squat_rack","rack","power_rack","platform","chains"]
        case .cable:      return ["cable","cables"]
        case .machine:    return ["machine","leverage_machine","leg_press_machine","leg_curl_machine","leg_extension_machine","hack_squat_machine","abductor_machine","adductor_machine","calf_raise_machine","back_extension_machine","glute_kickback_machine","hip_thrust_machine","donkey_calf_machine","belt_squat_machine","sissy_squat_machine","tibialis_machine","reverse_hyper_machine","ghd_machine","preacher_bench","hyperextension_bench"]
        case .smith:      return ["smith_machine","smith"]
        case .kettlebell: return ["kettlebell","kettlebells"]
        case .bands:      return ["resistance_band","band","bands"]
        case .pullupBar:  return ["pull_up_bar","dip_bar","dip_bars","dip_belt","rings","gymnastic_rings","parallel_bars","captains_chair","push_up_handles"]
        case .cardio:     return ["treadmill","stationary_bike","spin_bike","assault_bike","rowing_machine","ski_erg","elliptical","arc_trainer","stairmaster","jump_rope"]
        }
    }

    /// 某细粒度 equipment 值属于哪个大类 (附件/未知 → nil).
    static func category(for raw: String) -> EquipmentCategory? {
        let r = raw.lowercased()
        return allCases.first { $0.rawEquipmentValues.contains(r) }
    }

    /// 在"可用大类"集合下, 动作能不能做.
    ///   - selected 空 → 不限制, 全可用.
    ///   - 自重 / 无器械 → 永远可用.
    ///   - 主器械大类在 selected 里 → 可用; 主器械归不到任何大类 (附件) → 不卡, 视作可用.
    static func allows(_ exercise: Exercise, selected: Set<String>) -> Bool {
        guard !selected.isEmpty else { return true }
        let primary = (exercise.equipmentAll?.first ?? exercise.equipment ?? "").lowercased()
        if primary.isEmpty || primary == "body_only" || primary == "bodyweight" || primary == "none" { return true }
        guard let cat = category(for: primary) else { return true }
        return selected.contains(cat.rawValue)
    }
}
