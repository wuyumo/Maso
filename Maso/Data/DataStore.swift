import Foundation
import Observation
import UIKit

// 应用级数据仓库 — MVP 阶段用 in-memory mock; 后续可接 SwiftData / CoreData
//
// 设计跟 web 端 Dexie 表对齐:
//   - exercises: 静态字典 (从 yuhonas/free-exercise-db bundled JSON)
//   - plans: 用户的训练计划
//   - sets: 历史训练记录 (SetRecord)
//   - settings: 用户偏好 (单例)
@MainActor
@Observable
final class DataStore {
    var exercises: [Exercise]
    var plans: [Plan]
    var sets: [SetRecord]
    var settings: UserSettings

    /// AI 生成的今日训练计划 — TodayScreen 优先用这个, fallback 系统推荐.
    /// `lastAIRefreshAt` 是当天日期, 同一天不重复 refresh.
    var aiTodayPlan: Plan? = nil
    var lastAIRefreshAt: Date? = nil
    /// 最近一次今日 AI 生成是否失败 (网络/服务) — TodayScreen 据此露出"够不到 AI,已用推荐·重试"提示.
    var aiTodayFailed: Bool = false

    /// 训练偏好改动后, 推荐计划是否待刷新. 改设置时只 mark dirty, 不立即 regen —
    /// 等用户在 Training Preferences 页点 Done / 关 sheet 再统一刷新 (一次, 不每次拖动都重算抖动).
    /// @ObservationIgnored — 纯内部 bookkeeping, 不该触发视图刷新.
    @ObservationIgnored var recommendedPlansDirty = false
    /// true 时全局显示 "Tailoring your AI Plans…" loading 浮层. regen 本身瞬时 (纯数组运算),
    /// 故意延时 ~0.9s 显示 loading, 让"AI 正在按新偏好重新计算"可被用户感知.
    var isTailoringPlans = false

    /// 包含两套 key:
    ///   1. 新库 ID (`bench_press_barbell` 等) — Exercise.id 真主键
    ///   2. 旧库 imageFolder ID (`Barbell_Bench_Press` 等) — 老用户的 plans / sets / favorites
    ///      存的是这种 ID. 走 alias 让 lookup 透明 (不需要一次性 migration).
    ///
    /// 2026-05 schema 升级后必须双 key, 否则现有 plan 步骤全部 lookup 失败 → inferredMuscles
    /// 空 → BodyHint 没高亮 / Plans 列表里动作图标全 fallback placeholder.
    /// P2-11: bundle 部分 (~1000 动作 + imageFolder alias) 只构建一次 —— exercises 是 app 生命周期内
    /// 不变的静态库, 没必要每次访问 exById 都重建 3 遍. lazy 建好后缓存.
    // @ObservationIgnored — lazy 在 @Observable 下不允许被 macro 追踪; 这是不可变缓存, 不需要观察.
    @ObservationIgnored private lazy var _bundleExById: [String: Exercise] = {
        var m: [String: Exercise] = [:]
        for ex in exercises { m[ex.id] = ex }
        // Legacy alias — 不覆盖已存在的 key.
        for ex in exercises { if let folder = ex.imageFolder, m[folder] == nil { m[folder] = ex } }
        return m
    }()

    var exById: [String: Exercise] {
        // 0 个自创动作 (绝大多数用户) → 直接返回缓存, O(1) 无拷贝.
        // 有自创动作 → 在缓存副本上 merge (custom 数量很小, 一次 COW 拷贝可接受).
        let custom = settings.customExercises
        if custom.isEmpty { return _bundleExById }
        var m = _bundleExById
        for ex in custom { m[ex.id] = ex }
        return m
    }

    // MARK: - Library 视图 (user-facing union)
    //
    // bundle exercises 包含 ~979 个动作, 其中 58 个 niche. 用户视角的"动作库"应该是:
    //   - bundle 非 niche (主流动作, 默认全可见)
    //   - bundle niche 中被用户"采纳"过的 (settings.adoptedNicheExerciseIds 里命中的)
    //   - 用户自创的 (settings.customExercises)
    //
    // 所有 picker / library browser 都应该 source from `userLibrary` 而不是裸 `exercises`,
    // 否则要么暴露所有 niche, 要么看不到 custom 动作.

    /// 用户的"个人库" — 主 picker / Library Browser 用这个 source.
    var userLibrary: [Exercise] {
        let adopted = Set(settings.adoptedNicheExerciseIds)
        let bundle = exercises.filter { !$0.isNiche || adopted.contains($0.id) }
        return bundle + settings.customExercises
    }

    /// 小众库里还没采纳的部分 — "Browse rare exercises" 入口用.
    /// 已采纳的不再出现 (它们已经在 userLibrary 里), 避免重复添加.
    var unadoptedNicheExercises: [Exercise] {
        let adopted = Set(settings.adoptedNicheExerciseIds)
        return exercises.filter { $0.isNiche && !adopted.contains($0.id) }
    }

    /// 采纳一个小众动作 — 加进 settings.adoptedNicheExerciseIds. 之后主 picker 能看到它.
    func adoptNicheExercise(_ id: String) {
        guard !settings.adoptedNicheExerciseIds.contains(id) else { return }
        settings.adoptedNicheExerciseIds.append(id)
        save()
    }

    /// 取消采纳 — 把动作放回 niche stash (主 picker 隐藏, 但 niche browse 还能看到).
    func unadoptNicheExercise(_ id: String) {
        settings.adoptedNicheExerciseIds.removeAll { $0 == id }
        save()
    }

    /// 加一个用户自创动作. caller 自己负责 build Exercise (含 customImageData / muscleGroups 等).
    /// id 由 caller 给 (推荐 "custom-{UUID}" 格式), 防止跟 bundle ID 冲突.
    func addCustomExercise(_ ex: Exercise) {
        settings.customExercises.append(ex)
        save()
    }

    // (旧"从截图导入 → 存为自创动作"工厂已删 — 导入改版后未匹配动作只能从库里替换,
    //  不再有绕过自创动作 Pro gate 的免费入口. 自创动作唯一入口 = 动作库 "+", 有付费墙.)

    /// 删一个自创动作.
    func deleteCustomExercise(_ id: String) {
        settings.customExercises.removeAll { $0.id == id }
        save()
    }

    /// 这个 exercise id 是否被任何 plan step 或历史 set 引用 — 删除前查, 避免产生悬空 id
    /// (悬空后 exById 查不到 → BodyHint / 图回退 placeholder, displayName 失败).
    func isExerciseReferenced(_ id: String) -> Bool {
        if plans.contains(where: { $0.steps.contains(where: { $0.exerciseId == id }) }) { return true }
        if sets.contains(where: { $0.exerciseId == id }) { return true }
        return false
    }

    init(exercises: [Exercise], plans: [Plan], sets: [SetRecord], settings: UserSettings) {
        self.exercises = exercises
        self.plans = plans
        self.sets = sets
        self.settings = settings
    }

    // MARK: - Persistence bootstrap

    /// 启动入口 — 优先从 `PersistenceController` 加载, 没有再走 mock 兜底.
    /// MasoApp 用这个替代 makeMock(), 保证 app 重启后用户数据还在.
    ///
    /// exercises 永远从 `ExerciseLibrary` (bundled JSON) 加载 — 它是静态参考数据,
    /// 不进持久化文件 (873 个动作 / ~5MB JSON, 没必要重复存 + 升级 app 时新增动作自动更新).
    static func bootstrap() -> DataStore {
        let library = ExerciseLibrary.all
        if let snapshot = PersistenceController.shared.load() {
            // 有磁盘文件 → 用持久化数据
            let store = DataStore(
                exercises: library,
                plans: snapshot.plans,
                sets: snapshot.sets,
                settings: snapshot.settings
            )
            store.aiTodayPlan = snapshot.aiTodayPlan
            store.lastAIRefreshAt = snapshot.lastAIRefreshAt
            // 一次性迁移 (→ v3, #IA): My Plans 改成"只放用户主动 save 的". 清掉历史自动塞进去的
            // 推荐计划 (plan-full/bal/push/pull/legs/comrec 前缀). 用户自建 (plan-new) / 已 save
            // (plan-saved) / 已采纳社区 (plan-community) 全保留; 历史 / 设置不动. 存盘后 version=3 不再跑.
            if snapshot.version < PersistenceController.schemaVersion {
                let autoPrefixes = ["plan-full", "plan-bal", "plan-push", "plan-pull", "plan-legs", "plan-comrec"]
                store.plans.removeAll { p in autoPrefixes.contains { p.id.hasPrefix($0) } }
                store.flushSave()
            }
            return store
        }
        // 第一次启动 (磁盘无存档) → 全新空档: 空 plans/sets + onboardingCompleted=false.
        // 用户随即走 OnboardingScreen 填真实画像 (性别/年龄/体重/天数/聚焦肌群), 引导结尾
        // regenerateRecommendedPlans() 才生成推荐计划. 立即落盘 (flush, 不 debounce) 保证文件马上存在.
        // ⚠️ 绝不能用 makeMock() —— 它带假训练历史 + 假画像 (男/30/75) + onboardingCompleted=true,
        //    会让真实新用户跳过引导、看到自己没做过的训练. makeMock 仅供 SwiftUI Preview / 演示.
        let store = freshInstall()
        store.flushSave()
        return store
    }

    /// 全新安装 (无存档) 的起始数据 — 空 plans/sets, onboardingCompleted=false (UserSettings() 默认).
    /// 没有任何假历史 / 假画像 / 预生成计划; 这些等用户走完引导再由 onboarding 生成.
    static func freshInstall() -> DataStore {
        DataStore(
            exercises: ExerciseLibrary.all,
            plans: [],
            sets: [],
            settings: UserSettings()   // onboardingCompleted=false; gender/age/weight=nil; wantStrengthen=[]
        )
    }

    /// P2-1: debounce 句柄. 之前注释说"debounced"但其实每次 mutate 都同步全量写盘 —
    /// plan 名每敲一字符 = 一次 MB 级写. 现在真 debounce: 0.8s 内的连续 save 合并成一次.
    private var saveWorkItem: DispatchWorkItem?
    private static let saveDebounce: TimeInterval = 0.8

    /// 持久化当前状态 — 真 debounced (0.8s 合并). 关键时刻 (进后台 / 退出) 调 flushSave() 立即落盘.
    /// 不抛错, 失败静默 (写不进文件不影响 app 运行).
    func save() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeSnapshotNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounce, execute: item)
    }

    /// 立即把当前状态落盘 (取消 pending debounce). RootView 在 scenePhase → background/inactive 调.
    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writeSnapshotNow()
    }

    /// 真正构 snapshot + 写盘. 在 main actor 上 (DataStore @MainActor), 读 state 安全.
    private func writeSnapshotNow() {
        let snapshot = PersistenceController.Snapshot(
            version: PersistenceController.schemaVersion,
            plans: plans,
            sets: sets,
            settings: settings,
            aiTodayPlan: aiTodayPlan,
            lastAIRefreshAt: lastAIRefreshAt,
            updatedAt: Date()
        )
        PersistenceController.shared.save(snapshot)
    }

    /// 用 imported snapshot 替换当前所有数据. UI 调 import 时用.
    /// exercises 不动 — 那个是静态库, 不进 snapshot.
    func replaceFromSnapshot(_ snapshot: PersistenceController.Snapshot) {
        self.plans = snapshot.plans
        self.sets = snapshot.sets
        self.settings = snapshot.settings
        self.aiTodayPlan = snapshot.aiTodayPlan
        self.lastAIRefreshAt = snapshot.lastAIRefreshAt
        flushSave()  // import 是显式动作, 立即落盘不 debounce
    }

    /// 当前状态 → snapshot. Export 时用这个产文件.
    func currentSnapshot() -> PersistenceController.Snapshot {
        PersistenceController.Snapshot(
            version: PersistenceController.schemaVersion,
            plans: plans,
            sets: sets,
            settings: settings,
            aiTodayPlan: aiTodayPlan,
            lastAIRefreshAt: lastAIRefreshAt,
            updatedAt: Date()
        )
    }

    /// ⚠️ 仅供 SwiftUI Preview / 演示截图 —— 带假训练历史 + 假画像 + onboardingCompleted=true.
    /// 真实启动走 `freshInstall()` (空档 + 引导). 不要在 bootstrap / 生产路径里用这个.
    static func makeMock() -> DataStore {
        // 全量 yuhonas 库 (873 个动作) — 真实图片 + 完整 metadata
        let library = ExerciseLibrary.all
        let byId = ExerciseLibrary.byId
        let now = Date()
        // Free tier by default — 新用户撞 plan 上限会被 paywall 拦住, 走 IAP 升级 Pro.
        // (开发时如果需要临时解锁所有 Pro 功能, 把 proSubscription 改成一个非 nil 的
        // ProSubscription 实例; 上线前必须改回 nil.)
        let settings = UserSettings(
            onboardingCompleted: true,
            weeklyTrainingDays: 3,
            // 默认必须用 MuscleSelector 暴露的 major 值, 不能用 sub (e.g. .lats).
            // 之前 .lats 是 sub muscle, MuscleSelector 不渲染它, 导致用户取消所有 major chip
            // 后 wantStrengthen 还残留 .lats, UI 显示 count = 1 但无处可点. 改成 .back (major).
            wantStrengthen: [.chest, .back, .quads],
            gender: .male,
            age: 30,
            weight: 75,
            proSubscription: nil
        )
        // sample sets 先生成 (planId 是硬编码字符串, 不依赖最终 plan 数组),
        // 再用共享 helper 生成 settings-aware + LRU-backfilled 的推荐 plan.
        let prelimPlans = RecommendedPrograms.plans(forDays: settings.weeklyTrainingDays,
                                                    now: now, byId: byId)
        let sets = sampleSets(now: now, plans: prelimPlans, byId: byId)
        let plans = tunedRecommendedPlans(
            forDays: settings.weeklyTrainingDays,
            settings: settings,
            exById: byId,
            sets: sets,
            now: now
        )
        return DataStore(
            exercises: library,
            plans: plans,
            sets: sets,
            settings: settings
        )
    }

    // MARK: - 推荐 plan 生成 (单一真相 — makeMock / onboarding / regenerate 全走这)
    //
    // 之前 makeMock 和 regenerateRecommendedPlans 各有一份生成逻辑, 行为不一致:
    //   - makeMock cap 死在 4 (kDefaultMaxStepsPerRecommendedPlan), 忽略 exercisesPerSession
    //   - regenerate 用 exercisesPerSession 但漏了 lastUsedAt 回填 + 漏了 save()
    // 合一后三处行为完全一致.
    //
    // 关键设计:
    //   - cap = exercisesPerSession (用户设的每次动作数)
    //   - sets = max(模板组数, defaultSetsPerExercise) —— "默认组数"是地板, 不是覆盖.
    //     这样默认 3 不会把模板里手调的 4 组复合动作压平 (P1-3); 用户调高到 5 则全体 ≥5.
    //   - reps 保留模板值 (模板按动作手调, 比 goal 默认更贴具体动作)
    //   - lastUsedAt 从 sets 历史回填, 保证 pickTodayPlan 的 LRU A→B→C 轮换可用 (P0-2)
    static func tunedRecommendedPlans(
        forDays days: Int,
        settings: UserSettings,
        exById: [String: Exercise],
        sets: [SetRecord],
        now: Date
    ) -> [Plan] {
        let raw = RecommendedPrograms.plans(forDays: days, now: now, byId: exById)
        let cap = max(1, min(8, settings.exercisesPerSession))  // 模板现在 8 个动作, 上限 8
        let floorSets = max(1, settings.defaultSetsPerExercise)
        let goal = settings.trainingGoal
        // wantStrengthen 折叠到大肌群 section — 给"cap 时优先保留聚焦肌群动作"打分用.
        let focusSections: Set<MuscleGroup> = Set(settings.wantStrengthen.map { $0.section ?? $0 })
        func hitsFocus(_ step: PlanStep) -> Bool {
            guard !focusSections.isEmpty, let ex = exById[step.exerciseId] else { return false }
            return ex.primaryMuscles.contains { focusSections.contains($0.section ?? $0) }
        }
        return raw.map { plan -> Plan in
            var p = plan
            // 1. cap 到 exercisesPerSession — 选了聚焦肌群时优先保留命中的动作 (保留原始顺序).
            let kept: [PlanStep]
            if focusSections.isEmpty || p.steps.count <= cap {
                kept = Array(p.steps.prefix(cap))
            } else {
                let order = p.steps.indices.sorted { i, j in
                    let hi = hitsFocus(p.steps[i]), hj = hitsFocus(p.steps[j])
                    return hi != hj ? (hi && !hj) : i < j   // 命中聚焦肌群的排前, 同档按原顺序
                }
                let keepSet = Set(order.prefix(cap))
                kept = p.steps.indices.filter { keepSet.contains($0) }.map { p.steps[$0] }
            }
            // 2. 应用偏好: 组数地板 + reps 跟训练目标 (复合取低端 / 孤立取高端).
            p.steps = kept.map { step -> PlanStep in
                var s = step
                s.sets = max(s.sets, floorSets)  // 地板, 不压平
                if s.reps != nil {  // 只动力量类 (有 reps) 的; cardio/flex 计时段不碰
                    let isIso = exById[s.exerciseId]?.mechanic == .isolation
                    s.reps = isIso ? goal.defaultRepsForIsolation() : goal.defaultRepsForCompound()
                }
                return s
            }
            // 防御性补足: 模板正常是 8 step (cap≤8 不会触发), 但万一某 step ID 失效被 compactMap
            // 丢掉导致不足, 也按 exercises-per-plan 补回, 保证用户设定数严格成立.
            p.steps = DataStore.padStepsToTarget(p.steps, target: cap, settings: settings, exById: exById)
            // #1 器械约束: 把所选器械做不了的动作换成可用替代 (availableEquipment 空时无操作).
            p.steps = DataStore.applyEquipmentPreference(p.steps, settings: settings, exById: exById)
            // LRU 回填: 该 plan 在历史里最近一次训练时间 (没练过 → nil → distantPast 排最前)
            p.lastUsedAt = sets.filter { $0.planId == p.id }.map(\.performedAt).max()
            return p
        }
    }

    /// "偏好社区计划" 开关打开时的推荐计划来源 — 不再从模板自动生成, 而是从 Community 里挑一套
    /// 最符合用户 days/week + 训练目标的成熟计划, materialize 进来 (按 exercises-per-plan 轻微调,
    /// 但保留社区计划自己设计的 sets/reps/rest — 那是计划的精髓). 兜底回退到模板.
    static func communityRecommendedPlans(
        forDays days: Int,
        settings: UserSettings,
        exById: [String: Exercise],
        sets: [SetRecord],
        now: Date
    ) -> [Plan] {
        let all = CommunityPlans.all
        // 训练目标 → 偏好的 kicker 关键词.
        let goalHints: [String]
        switch settings.trainingGoal {
        case .strength:    goalHints = ["STRENGTH", "POWERLIFTING", "POWERBUILDING"]
        case .hypertrophy: goalHints = ["HYPERTROPHY", "BODYBUILDING", "PUSH / PULL / LEGS", "UPPER / LOWER", "POWERBUILDING"]
        case .endurance:   goalHints = ["FULL BODY", "CALISTHENICS", "ATHLETIC"]
        }
        func score(_ p: CommunityPlan) -> Int {
            var s = (p.frequencyDaysPerWeek == days) ? 4 : -abs(p.frequencyDaysPerWeek - days)
            if goalHints.contains(where: { p.kicker.uppercased().contains($0) }) { s += 2 }
            return s
        }
        guard let chosen = all.max(by: { score($0) < score($1) }) else {
            return tunedRecommendedPlans(forDays: days, settings: settings, exById: exById, sets: sets, now: now)
        }
        let cap = max(1, min(8, settings.exercisesPerSession))
        let focusSections: Set<MuscleGroup> = Set(settings.wantStrengthen.map { $0.section ?? $0 })
        func hitsFocus(_ step: PlanStep) -> Bool {
            guard !focusSections.isEmpty, let ex = exById[step.exerciseId] else { return false }
            return ex.primaryMuscles.contains { focusSections.contains($0.section ?? $0) }
        }
        let plans = chosen.materialize(now: now, byId: exById, idPrefix: "plan-comrec").map { plan -> Plan in
            var p = plan
            if p.steps.count > cap {  // 只在超过用户每张动作数时裁 (优先保留聚焦肌群命中动作)
                if focusSections.isEmpty {
                    p.steps = Array(p.steps.prefix(cap))
                } else {
                    let order = p.steps.indices.sorted { i, j in
                        let hi = hitsFocus(p.steps[i]), hj = hitsFocus(p.steps[j])
                        return hi != hj ? (hi && !hj) : i < j
                    }
                    let keep = Set(order.prefix(cap))
                    p.steps = p.steps.indices.filter { keep.contains($0) }.map { p.steps[$0] }
                }
            }
            // 反向: 动作数 < 用户设定时补足配件 —— 社区计划自身偏短 (一个 session 只有 5 个动作) 也
            // 严格兑现 exercises-per-plan, 不让用户设了 7 却只看到 5.
            p.steps = padStepsToTarget(p.steps, target: cap, settings: settings, exById: exById)
            // #1 器械约束.
            p.steps = applyEquipmentPreference(p.steps, settings: settings, exById: exById)
            p.lastUsedAt = sets.filter { $0.planId == p.id }.map(\.performedAt).max()
            return p
        }
        // 极端兜底: 万一所选社区计划的 step 全部 invalid (不该发生, 已校验) → 回退模板.
        return plans.isEmpty
            ? tunedRecommendedPlans(forDays: days, settings: settings, exById: exById, sets: sets, now: now)
            : plans
    }

    /// 把一组 step 补足到 `target` 个动作 —— 计划自身的动作数 < 用户设定的 "exercises per plan"
    /// 时调用, 严格兑现用户偏好 (用户设 7 就给 7, 而不是被社区计划自身的 5 个卡住).
    ///
    /// 补动作原则: 只从"这次 session 已经在练的大肌群"里挑配件 (聚焦肌群优先) —— Push 日补的是
    /// 胸/肩/三头配件, 不会乱加腿, 保持计划的肌群主题一致. 候选优先孤立动作 (配件感更对),
    /// 不够再放宽到复合; 排除 niche / 计划里已有的; 稳定排序保证结果可复现. 找不到更多就停 (不死循环).
    static func padStepsToTarget(
        _ steps: [PlanStep],
        target: Int,
        settings: UserSettings,
        exById: [String: Exercise]
    ) -> [PlanStep] {
        guard steps.count < target else { return steps }
        var result = steps
        var used = Set(steps.map { $0.exerciseId })

        // 本次已练的大肌群 section (按出现顺序), 聚焦肌群整体提前.
        var sections: [MuscleGroup] = []
        for s in steps {
            guard let ex = exById[s.exerciseId] else { continue }
            for m in ex.primaryMuscles {
                let sec = m.section ?? m
                if sec != .fullBody, !sections.contains(sec) { sections.append(sec) }
            }
        }
        let focus = Set(settings.wantStrengthen.compactMap { $0.section ?? $0 })
        sections = sections.filter { focus.contains($0) } + sections.filter { !focus.contains($0) }
        guard !sections.isEmpty else { return result }

        let setsFloor = max(1, settings.defaultSetsPerExercise)
        let reps = settings.trainingGoal.defaultRepsForIsolation()

        func pool(_ section: MuscleGroup, isolationOnly: Bool) -> [String] {
            exById.values
                .filter { ex in
                    ex.category == .strength && !ex.isNiche &&
                    (!isolationOnly || ex.mechanic == .isolation) &&
                    ex.primaryMuscles.contains { ($0.section ?? $0) == section }
                }
                .map(\.id)
                .sorted()
        }

        // 两轮: 先填孤立配件, 还不够再放宽到复合.
        for isolationOnly in [true, false] {
            let pools = sections.map { pool($0, isolationOnly: isolationOnly) }
            var cursor = 0, emptyStreak = 0
            while result.count < target && emptyStreak < pools.count {
                let p = pools[cursor % pools.count]
                cursor += 1
                if let pick = p.first(where: { !used.contains($0) }) {
                    used.insert(pick)
                    result.append(PlanStep(
                        id: "step-\(pick)-pad\(result.count)",
                        exerciseId: pick,
                        sets: setsFloor,
                        reps: reps,
                        weight: nil,
                        restBetweenSets: settings.defaultRestSeconds,
                        rest: 0
                    ))
                    emptyStreak = 0
                } else {
                    emptyStreak += 1
                }
            }
            if result.count >= target { break }
        }
        return result
    }

    /// #1 器械约束 — 把"所选器械做不了"的动作换成同主肌群 section + 可用器械的替代动作.
    /// settings.availableEquipment 空 → 原样返回 (不限制). 找不到替代 → 保留原动作 (不留空).
    static func applyEquipmentPreference(_ steps: [PlanStep], settings: UserSettings, exById: [String: Exercise]) -> [PlanStep] {
        let selected = Set(settings.availableEquipment)
        guard !selected.isEmpty else { return steps }
        var used = Set(steps.map { $0.exerciseId })
        return steps.map { step -> PlanStep in
            guard let ex = exById[step.exerciseId],
                  !EquipmentCategory.allows(ex, selected: selected) else { return step }
            let targetSection = ex.primaryMuscles.first.map { $0.section ?? $0 }
            let alt = exById.values
                .filter { c in
                    c.id != ex.id && !used.contains(c.id) && c.category == ex.category && !c.isNiche &&
                    EquipmentCategory.allows(c, selected: selected) &&
                    (targetSection == nil || c.primaryMuscles.contains { ($0.section ?? $0) == targetSection })
                }
                .sorted { a, b in
                    let am = (a.mechanic == ex.mechanic) ? 0 : 1
                    let bm = (b.mechanic == ex.mechanic) ? 0 : 1
                    return am != bm ? am < bm : a.name < b.name
                }
                .first
            guard let alt else { return step }
            used.insert(alt.id)
            // exerciseId 是 let → 重建. 换了动作, weight/逐组覆盖清掉 (不同动作重量不通用).
            return PlanStep(
                id: step.id, exerciseId: alt.id, sets: step.sets, reps: step.reps,
                weight: nil, duration: step.duration,
                restBetweenSets: step.restBetweenSets, rest: step.rest
            )
        }
    }

    // MARK: - 简单的 plan 操作

    func updatePlan(_ plan: Plan) {
        let old = plans.first(where: { $0.id == plan.id })
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        } else {
            plans.append(plan)
        }
        // R3 全局同步: 把本次"改了参数的既有 step"传播到所有 routine 的同 exerciseId step.
        // 仅在既有 step (id 不变) + 同动作 (exerciseId 不变) + 参数确有变化时触发;
        // 新增 step / 换动作不在此传播 (新增走 makeSeededStep 的"采用全局"逻辑, 换动作只是 swap).
        if settings.globalExerciseParamSyncEnabled, let old {
            for step in plan.steps {
                guard let oldStep = old.steps.first(where: { $0.id == step.id }),
                      oldStep.exerciseId == step.exerciseId,
                      !Self.sameParams(oldStep, step) else { continue }
                syncExerciseParams(from: step)
            }
        }
        save()  // 持久化变更
    }

    // MARK: - R3 全局动作参数同步

    /// 把 src 的训练参数 (组数/次数/重量/时长/休息 + 逐组覆盖) 写到所有 plan (+ aiTodayPlan)
    /// 里同 exerciseId 的 step. 仅在 globalExerciseParamSyncEnabled 开启时生效.
    /// 不改 id / exerciseId; 源 step 被自己覆盖是幂等 no-op.
    func syncExerciseParams(from src: PlanStep) {
        guard settings.globalExerciseParamSyncEnabled else { return }
        func apply(_ s: inout PlanStep) {
            s.sets = src.sets
            s.reps = src.reps
            s.weight = src.weight
            s.duration = src.duration
            s.restBetweenSets = src.restBetweenSets
            s.rest = src.rest
            s.setReps = src.setReps
            s.setWeights = src.setWeights
            s.setDurations = src.setDurations
        }
        var changed = false
        let now = Date()
        for pi in plans.indices {
            var planChanged = false
            for si in plans[pi].steps.indices where plans[pi].steps[si].exerciseId == src.exerciseId {
                if !Self.sameParams(plans[pi].steps[si], src) {
                    apply(&plans[pi].steps[si]); planChanged = true
                }
            }
            if planChanged { plans[pi].updatedAt = now; changed = true }
        }
        if var ai = aiTodayPlan {
            var aiChanged = false
            for si in ai.steps.indices where ai.steps[si].exerciseId == src.exerciseId {
                if !Self.sameParams(ai.steps[si], src) { apply(&ai.steps[si]); aiChanged = true }
            }
            if aiChanged { aiTodayPlan = ai; changed = true }
        }
        if changed { save() }
    }

    /// 两个 step 的训练参数是否完全一致 (不看 id / exerciseId) — 给同步去抖 + updatePlan diff 用.
    static func sameParams(_ a: PlanStep, _ b: PlanStep) -> Bool {
        a.sets == b.sets && a.reps == b.reps && a.weight == b.weight && a.duration == b.duration
            && a.restBetweenSets == b.restBetweenSets && a.rest == b.rest
            && a.setReps == b.setReps && a.setWeights == b.setWeights && a.setDurations == b.setDurations
    }

    /// 新建一个 PlanStep, 训练参数按"全局同步开/关"取默认 (R3):
    ///   - 同步开 + 已有别的 routine 含该动作 → 采用那份参数 (保持全局一致).
    ///   - 否则 → 从该动作"最近一次记录" (lastSet) 回填 reps/weight/duration; 组数/休息用偏好默认.
    func makeSeededStep(for ex: Exercise, stepId: String) -> PlanStep {
        let isStrength = ex.category == .strength
        if settings.globalExerciseParamSyncEnabled,
           let existing = plans.lazy.flatMap({ $0.steps }).first(where: { $0.exerciseId == ex.id }) {
            return PlanStep(
                id: stepId, exerciseId: ex.id,
                sets: existing.sets, reps: existing.reps, weight: existing.weight,
                setReps: existing.setReps, setWeights: existing.setWeights, setDurations: existing.setDurations,
                duration: existing.duration,
                restBetweenSets: existing.restBetweenSets, rest: existing.rest
            )
        }
        let last = lastSet(forExerciseId: ex.id)
        return PlanStep(
            id: stepId, exerciseId: ex.id,
            sets: settings.defaultSetsPerExercise,
            reps: isStrength ? (last?.reps ?? 10) : nil,
            weight: isStrength ? (last?.weight ?? 0) : nil,
            duration: isStrength ? nil : (last?.duration ?? 30),
            restBetweenSets: settings.defaultRestSeconds,
            rest: 0
        )
    }

    /// R2 撤销: 删掉本场 session 里某动作"最近一条"记录 (sets 倒序存, firstIndex 即最新).
    func removeLastSet(exerciseId: String, planId: String?, since: Date) {
        if let idx = sets.firstIndex(where: {
            $0.exerciseId == exerciseId && $0.planId == planId && $0.performedAt >= since
        }) {
            sets.remove(at: idx)
            save()
        }
    }

    /// 记录新的一组 — 同时:
    ///   1. 把 plan.lastUsedAt 推进到这次的时间 (用于 pickTodayPlan 的 LRU 排序)
    ///   2. 更新 plan.updatedAt
    func recordSet(_ record: SetRecord) {
        sets.insert(record, at: 0)
        if let pid = record.planId, let idx = plans.firstIndex(where: { $0.id == pid }) {
            plans[idx].lastUsedAt = record.performedAt
            plans[idx].updatedAt = record.performedAt
        }
        save()  // 持久化变更
    }

    /// 已完成训练次数 — 按"有训练记录的日历日"去重计数 (一天练多次算一次).
    var completedWorkoutCount: Int {
        let cal = Calendar.current
        return Set(sets.map { cal.startOfDay(for: $0.performedAt) }).count
    }

    /// 是否该在此刻请求 App Store 评分 — 练满 3 次且从没请求过. 命中即"消费"(置 flag + 存),
    /// 保证整个生命周期只主动请求一次 (iOS 自身另有每年至多 3 次的限频). 调用方拿 true 才调 requestReview.
    func shouldOfferReview() -> Bool {
        guard !settings.hasRequestedReview else { return false }
        guard completedWorkoutCount >= 3 else { return false }
        settings.hasRequestedReview = true
        save()
        return true
    }

    /// 重排召回提醒 — 训练完 / app 进后台时调. 以最近一次训练为基, 开关关时只清除.
    /// sets 是 newest-first (recordSet insert at 0), 所以 sets.first = 最近一次.
    func rescheduleWorkoutReminders() {
        let last = sets.first?.performedAt
        let body = NSLocalizedString("You're recovered — a quick session keeps your momentum going.",
                                     comment: "comeback reminder body")
        let enabled = settings.workoutRemindersEnabled
        Task { @MainActor in
            WorkoutReminderScheduler.shared.reschedule(enabled: enabled, lastWorkout: last, body: body)
        }
    }

    /// 今日推荐 plan — wantStrengthen 覆盖度 + LRU (跟 web 端 pickTodayPlan 一致)
    var todayRecommendedPlan: Plan? {
        pickTodayPlan(plans: plans, settings: settings, exById: exById)
    }

    /// 给定 exerciseId, 找最近一次的 set 记录. 用来在 PlanPlayer / PlanDetailSheet 显示
    /// "上次: 100kg × 8" — 兑现 plan 理念 2 "历史即计划".
    /// sets 按 performedAt 倒序存 (recordSet insert at 0), 所以 first(where:) 就是最新.
    func lastSet(forExerciseId id: String) -> SetRecord? {
        sets.first(where: { $0.exerciseId == id })
    }

    /// 找历史最高 (weight × reps 的 1RM 估算最大) — 用来 PR 检测.
    /// 只算 strength 类的记录 (有 weight + reps).
    /// 1RM 估算用 Epley 公式: 1RM = weight * (1 + reps / 30)
    /// 不在乎绝对精度, 只用来比较"这次 vs 历史最高"分胜负.
    func estimatedMaxLoad(forExerciseId id: String, excluding recordId: String? = nil) -> Double {
        sets.filter { $0.exerciseId == id && $0.id != recordId }
            .compactMap { rec -> Double? in
                guard let w = rec.weight, w > 0, let r = rec.reps, r > 0 else { return nil }
                return w * (1 + Double(r) / 30.0)
            }
            .max() ?? 0
    }

    /// 检测一条记录是不是 PR — 比历史最高 1RM 估算高就算
    /// 第一次做这个动作 → 不算 PR (没有比较基准, 算是"首试")
    func isPR(_ record: SetRecord) -> Bool {
        guard let w = record.weight, w > 0, let r = record.reps, r > 0 else { return false }
        let thisLoad = w * (1 + Double(r) / 30.0)
        let historicalMax = estimatedMaxLoad(forExerciseId: record.exerciseId, excluding: record.id)
        guard historicalMax > 0 else { return false }  // 没历史 = 首试, 不是 PR
        return thisLoad > historicalMax
    }

    /// 创建一张空白的新计划 (供 + 按钮新建用)
    /// - 自动取一个不冲突的 "New Workout" / "New Workout 2" / "New Workout 3" 名字
    /// - 返回新建的 plan, 调用方可以立刻打开 PlanDetailSheet 编辑
    func createBlankPlan() -> Plan {
        let now = Date()
        // base name 走 i18n — 中文用户应该看到 "新训练" 不是 "New Workout"
        let baseName = NSLocalizedString("New Workout", comment: "default name for blank plan")
        let existing = Set(plans.map { $0.name })
        var name = baseName
        var i = 2
        while existing.contains(name) {
            name = "\(baseName) \(i)"
            i += 1
        }
        let plan = Plan(
            id: "plan-new-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.prefix(6))",
            name: name,
            steps: [],
            createdAt: now,
            updatedAt: now
        )
        plans.append(plan)
        save()  // 持久化变更
        return plan
    }

    /// 免费用户最多能 save 的 plan 数. Pro 无限.
    static let freeSavedPlansLimit = 3

    /// 还能不能再 save plan — 免费上限 3, Pro 无限.
    var canSaveMorePlans: Bool {
        settings.isPro || plans.count < Self.freeSavedPlansLimit
    }

    /// Onboarding 完成后种少量 AI routine 进 "My Routines" — 让用户首次进 Today 不是空状态.
    /// 已有 routine 就跳过 (避免重复种). 按 onboarding 收集的偏好用本地 tunedRecommendedPlans 即时生成,
    /// 取前 2 条 (留 1 个免费保存位); 标 autoGenerated 区分"系统种子" vs 用户主动 save 的.
    func seedStarterRoutines() {
        guard plans.isEmpty else { return }
        let tuned = DataStore.tunedRecommendedPlans(
            forDays: settings.weeklyTrainingDays,
            settings: settings, exById: exById, sets: sets, now: Date()
        )
        let now = Date()
        for (i, p) in tuned.prefix(2).enumerated() {
            let t = now.addingTimeInterval(Double(i))
            plans.append(Plan(
                id: "plan-saved-\(Int(t.timeIntervalSince1970))-\(UUID().uuidString.prefix(6))",
                name: p.name, steps: p.steps, createdAt: t, updatedAt: t,
                autoGenerated: true, lastUsedAt: nil
            ))
        }
        save()
    }

    /// 把一个 plan (AI 生成 / 社区) save 到"我的计划" (Saved).
    ///   - 已存在 (同 名字+动作序列) → 幂等成功, 不重复加.
    ///   - 到达免费上限 → 不加, 返回 false (调用方弹 paywall).
    /// save 的是独立副本 (新 id + 时间戳), 之后用户编辑不影响来源.
    @discardableResult
    func savePlan(_ plan: Plan) -> Bool {
        if isPlanSaved(plan) { return true }
        guard canSaveMorePlans else { return false }
        let now = Date()
        let copy = Plan(
            id: "plan-saved-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.prefix(6))",
            name: plan.name,
            steps: plan.steps,
            createdAt: now,
            updatedAt: now,
            autoGenerated: false,
            lastUsedAt: nil,
            source: plan.resolvedSource,   // 保留来源 (AI/Classics) → 重 id 后标签不丢
            rationale: plan.rationale      // 保留 AI 理由 → 存下来后卡上仍显示
        )
        plans.append(copy)
        save()
        return true
    }

    /// 这个(来源)plan 是否已经在"我的计划"里. 存进去的是新 id 的独立副本, 不能用 id 比 —
    /// 按 名字 + 动作序列 的内容签名匹配. 给 Tab 2 卡片"添加"按钮显示"已添加"态用 (响应式: plans 一变即更新).
    func isPlanSaved(_ plan: Plan) -> Bool {
        let sig = Self.planSignature(plan)
        return plans.contains { Self.planSignature($0) == sig }
    }

    private static func planSignature(_ plan: Plan) -> String {
        plan.name + "\u{1}" + plan.steps.map(\.exerciseId).joined(separator: ",")
    }

    /// 关 sheet 时调用 — 如果用户开了"新建"但一个动作都没加, 自动清理掉, 不留空 plan
    func removePlanIfEmpty(_ planId: String) {
        if let idx = plans.firstIndex(where: { $0.id == planId }), plans[idx].steps.isEmpty {
            plans.remove(at: idx)
            save()
        }
    }

    /// 显式删除一个 plan — 用户在 Plans 列表长按 → Delete 触发.
    /// 不动 sets (历史记录引用 planId 留着无害, 即使 plan 已删, 历史还在),
    /// 不动 aiTodayPlan (它是 AI 生成的独立副本, 跟 plans 数组解耦).
    /// 当前正在训练的 session 不会因 plan 删除而失效 — store.plan 是 session-local 副本.
    func deletePlan(_ planId: String) {
        guard let idx = plans.firstIndex(where: { $0.id == planId }) else { return }
        plans.remove(at: idx)
        save()
    }

    /// 拖拽排序 — SwiftUI List.onMove 直接传给这, IndexSet 是源, Int 是目标.
    /// 持久化新顺序到 disk, 让用户长期偏好(常用的 plan 放最上)保留.
    func reorderPlans(from source: IndexSet, to destination: Int) {
        plans.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// 删除一个训练 session 的所有 SetRecord (同 day + 同 planId).
    /// History 列表的"删除这次训练" — session 是 SetRecord 聚合而成, 删 session = 删它的 sets.
    /// planId 用 `?? "free"` 跟 groupedSessions 保持一致 — nil 表自由训练(没绑 plan).
    func deleteSession(planId: String?, day: Date) {
        let cal = Calendar.current
        sets.removeAll { rec in
            let recDay = cal.startOfDay(for: rec.performedAt)
            let recPid: String? = rec.planId
            // 比较 planId — nil ↔ nil 或者 string ↔ string
            return recDay == day && recPid == planId
        }
        save()
    }

    // MARK: - Favorites — 收藏的动作

    /// 检查动作是否已收藏. O(1) wrapper around Settings.favoriteExerciseIds 查询.
    /// 用 Set 转换避免 array contains O(n) — favorites 可能几十个, list 一刷新查多次.
    func isFavorite(_ exerciseId: String) -> Bool {
        settings.favoriteExerciseIds.contains(exerciseId)
    }

    /// 切换动作的收藏态. 已收藏 → 取消; 未收藏 → 加入.
    func toggleFavorite(_ exerciseId: String) {
        if let idx = settings.favoriteExerciseIds.firstIndex(of: exerciseId) {
            settings.favoriteExerciseIds.remove(at: idx)
        } else {
            settings.favoriteExerciseIds.append(exerciseId)
        }
        save()
    }

    /// 把 exercises 列表按"收藏在前, 原顺序在后"重排.
    /// 在 favoriteExerciseIds 里的排在前面 (并保持 favorites 内部相对顺序);
    /// 不在的保持原顺序排后面. 给 ExerciseLibrary / Picker / QuickWorkout 等列表用.
    func sortByFavorites(_ exercises: [Exercise]) -> [Exercise] {
        guard !settings.favoriteExerciseIds.isEmpty else { return exercises }
        let favSet = Set(settings.favoriteExerciseIds)
        let favs = exercises.filter { favSet.contains($0.id) }
        let rest = exercises.filter { !favSet.contains($0.id) }
        return favs + rest
    }

    // MARK: - Session photos — 用户在分享卡加的照片, 持久化绑到 sessionId

    /// 保存用户为某个 session 添加的照片. 重复 set 会覆盖.
    /// id = SessionSummary.id (e.g. "plan-full-1-1715900000"), 由 groupedSessions 生成.
    /// 训练完成入口可以用相同的 id 模板: "\(planId ?? "free")-\(Int(day.startOfDay.timeIntervalSince1970))"
    func setSessionPhoto(_ image: UIImage, forSessionId id: String) {
        // quality 0.7 — 视觉无明显损失, 体积约为 0.9 的 60%.
        if let data = image.jpegData(compressionQuality: 0.7) {
            settings.sessionPhotos[id] = data
            save()
        }
    }

    /// 读取已存的照片 (nil = 该 session 没存过).
    func sessionPhoto(forSessionId id: String) -> UIImage? {
        guard let data = settings.sessionPhotos[id] else { return nil }
        return UIImage(data: data)
    }

    /// 移除一张照片. 用户在 ShareCustomizeSheet 点 Remove Photo 时触发.
    func removeSessionPhoto(forSessionId id: String) {
        if settings.sessionPhotos.removeValue(forKey: id) != nil {
            save()
        }
    }

    /// 删除一个 session 内某个 exercise 的所有 SetRecord — 用于 SessionDetailSheet 右滑删除单个动作.
    /// (session 是 SetRecord 聚合, 删一个 exercise = 删它在该 session 范围内的所有 sets.)
    func deleteExerciseFromSession(planId: String?, day: Date, exerciseId: String) {
        let cal = Calendar.current
        sets.removeAll { rec in
            let recDay = cal.startOfDay(for: rec.performedAt)
            return recDay == day && rec.planId == planId && rec.exerciseId == exerciseId
        }
        save()
    }

    // MARK: - AI workout

    /// 检查并 (在需要时) 刷新今日 AI 训练计划.
    /// API key 由 AIWorkoutService 内部从 Info.plist 读取, 上层不需要传.
    /// - 跳过条件: 同一日历日已经成功 refresh 过 / settings 关
    /// - 网络失败 → state 写入失败但不抛, TodayScreen 继续 fallback 到系统推荐
    func refreshAIWorkoutIfNeeded() async {
        // gate 只看代理是否配好 (Path B: 不再要求 aiWorkoutEnabled — 代理 server-side 配好就跑, 失败回落).
        guard AIWorkoutService.isConfigured else { return }
        if let last = lastAIRefreshAt, Calendar.current.isDateInToday(last), aiTodayPlan != nil {
            return  // 今天已经成功生成过, skip
        }
        let payload = buildAIPayload()
        let plan = await AIWorkoutService.shared.generateToday(
            payload: payload,
            library: exercises,
            maxExercises: settings.exercisesPerSession
        )
        if let plan {
            aiTodayPlan = plan
            lastAIRefreshAt = Date()
            aiTodayFailed = false
        } else {
            aiTodayFailed = true   // 网络/服务失败 → Today 露提示 + fallback 推荐
        }
    }

    /// 强制重新生成 (用户主动点 "Refresh"/"Retry" 时调). 跳过同日 cache 检查.
    func forceRefreshAIWorkout() async {
        guard AIWorkoutService.isConfigured else { return }
        let payload = buildAIPayload()
        let plan = await AIWorkoutService.shared.generateToday(
            payload: payload,
            library: exercises,
            maxExercises: settings.exercisesPerSession
        )
        if let plan {
            aiTodayPlan = plan
            lastAIRefreshAt = Date()
            aiTodayFailed = false
        } else {
            aiTodayFailed = true
        }
    }

    /// 引导确认后生成首份计划 (Path B 真 AI): 先种本地起步 routine 保证库非空, 再尝试真 AI 作为
    /// 今日推荐 (✨AI). 失败 → 静默回落到本地推荐 (aiTodayPlan 不设, Today 自己 fallback).
    func generateFirstPlanViaAI() async {
        seedStarterRoutines()                       // 2 条本地起步 (内部 guard plans.isEmpty)
        guard AIWorkoutService.isConfigured else { return }
        let payload = buildAIPayload()
        if let plan = await AIWorkoutService.shared.generateToday(
            payload: payload, library: exercises, maxExercises: settings.exercisesPerSession) {
            aiTodayPlan = plan
            lastAIRefreshAt = Date()
            aiTodayFailed = false
        } else {
            aiTodayFailed = true
        }
        flushSave()
    }

    /// AI Routines tab "生成": 真 AI 一条 (✨AI, 排最前) + 本地 tuned 若干作为更多选择.
    /// 返回 (plans, 是否回落到纯本地). 失败/未配置 → 纯本地 + usedFallback=true.
    func generateAIRoutines() async -> (plans: [Plan], usedFallback: Bool) {
        let local = DataStore.tunedRecommendedPlans(
            forDays: settings.weeklyTrainingDays, settings: settings,
            exById: exById, sets: sets, now: Date())
        guard AIWorkoutService.isConfigured else { return (local, true) }
        // 一次 LLM 调用产出多套真 AI routine (各带 rationale, 组成周分化) — 标签页每张都是真 AI,
        // 不再 [aiPlan] + local 混本地凑数计划. 套数 = 每周天数, 夹到 2...4 (token 预算 + 不过载).
        let count = max(2, min(4, settings.weeklyTrainingDays))
        let payload = buildAIPayload()
        if let aiPlans = await AIWorkoutService.shared.generateRoutines(
            payload: payload, library: exercises, count: count,
            maxExercises: settings.exercisesPerSession), !aiPlans.isEmpty {
            return (aiPlans, false)
        }
        return (local, true)   // 真 AI 失败 → 回落本地模板 (此时确实没有 rationale, 顶部有提示条)
    }

    /// 构 AI 输入 payload — 把 user profile + 最近 14 天历史打包.
    /// 之前只给 refreshAIWorkoutIfNeeded 私用, 现在 QuickWorkout 的"帮我自动选"也要, 改 public.
    func buildAIPayload() -> AIPayload {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        // 把最近 14 天 sets 按 (planId, day) 聚合成简短 history line
        let cal = Calendar.current
        let cutoff = Date().addingTimeInterval(-14 * 86400)
        struct Key: Hashable { let planId: String; let day: Date }
        var bucket: [Key: [SetRecord]] = [:]
        var order: [Key] = []
        for rec in sets where rec.performedAt >= cutoff {
            let day = cal.startOfDay(for: rec.performedAt)
            let key = Key(planId: rec.planId ?? "free", day: day)
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(rec)
        }
        let history: [AIPayload.HistoryEntry] = order.map { key in
            let recs = bucket[key] ?? []
            // 术语统一 "Free workout" — 跟 History 卡 / Share 卡一致 (之前这里是 "Quick Workout").
            // plan 被删 → 用记录里的落库名快照, AI 上下文不丢具体计划名.
            let planName = key.planId == "free"
                ? "Free workout"
                : (plans.first(where: { $0.id == key.planId })?.name
                   ?? recs.compactMap(\.planName).first
                   ?? "Plan")
            var seen = Set<MuscleGroup>()
            var muscles: [MuscleGroup] = []
            for r in recs {
                guard let ex = exById[r.exerciseId] else { continue }
                for m in ex.muscleGroups where seen.insert(m).inserted {
                    if let major = m.section { muscles.append(major) }
                }
            }
            let majors = Array(Set(muscles)).prefix(3).map { $0.displayName }
            return AIPayload.HistoryEntry(
                dateLabel: df.string(from: key.day),
                planName: planName,
                muscleSummary: majors.joined(separator: " + "),
                setCount: recs.count
            )
        }
        .sorted { $0.dateLabel > $1.dateLabel }  // 最近的在前

        return AIPayload(
            gender: settings.gender?.rawValue,
            age: settings.age,
            weightKg: settings.weight,
            daysPerWeek: settings.weeklyTrainingDays,
            wantStrengthen: settings.wantStrengthen.map { $0.displayName },
            recentHistory: history,
            todayDateLabel: df.string(from: Date())
        )
    }

    /// 按当前 settings.weeklyTrainingDays 重新生成推荐计划.
    /// - 1-3 天 → Full Body × 3 (覆盖胸/背/腿 + 小肌群)
    /// - 4-5 天 → Bro Split (每天 1-2 个大肌群 + 协同小肌群)
    /// - 6+ 天 → Push/Pull/Legs × 2 (三分化)
    ///
    /// 只覆盖系统生成的 plan (id 前缀 `plan-full/plan-bal/plan-push/plan-pull/plan-legs`),
    /// 用户自定义 plan (`plan-new-...`) 完整保留.
    /// 标记"训练偏好已改, 推荐计划待刷新" —— 改设置时调它, 不立即 regen.
    /// 真正的刷新推迟到用户离开 Training Preferences (Done / 关 sheet), 由 commit 统一执行.
    func markRecommendedPlansDirty() {
        recommendedPlansDirty = true
    }

    /// 用户离开 Training Preferences 时调 —— 如有改动, 带 loading 重算推荐计划.
    /// regen 本身瞬时 (纯数组运算), 故意延时 ~0.9s 显示 "Tailoring your AI Plans…" 浮层,
    /// 让"AI 正在按新偏好重新计算"可被用户感知; 计算完成的瞬间换上新计划, 浮层同时消失.
    @MainActor func commitRecommendedPlansIfDirty() {
        // #IA: My Plans = 用户主动 save 的, 改训练偏好不再往 data.plans 塞推荐计划.
        // Discover 的 AI 计划每次进入按当前偏好现算 (见 PlansScreen.regenerateAI), 故这里只清标记.
        recommendedPlansDirty = false
    }

    func regenerateRecommendedPlans() {
        // plan-comrec = "偏好社区计划"开关打开时 materialize 进来的社区推荐计划 (同样按推荐集管理,
        // regen / 关开关时一并清掉). 用户从 Community 主动 "Add" 的是 plan-community-, 不在此列, 不会被清.
        let recommendedPrefixes = ["plan-full", "plan-bal", "plan-push", "plan-pull", "plan-legs", "plan-comrec"]
        plans.removeAll { plan in
            recommendedPrefixes.contains(where: { plan.id.hasPrefix($0) })
        }
        let tuned = settings.preferCommunityPlans
            ? DataStore.communityRecommendedPlans(
                forDays: settings.weeklyTrainingDays,
                settings: settings,
                exById: exById,
                sets: sets,
                now: Date()
            )
            : DataStore.tunedRecommendedPlans(
                forDays: settings.weeklyTrainingDays,
                settings: settings,
                exById: exById,
                sets: sets,
                now: Date()
            )
        plans.append(contentsOf: tuned)
        save()  // P0-1: 之前漏了 save → 改设置重启就回退. 现在持久化.
    }
}

// MARK: - sample sets — 用于 History 页展示卡片样例
// 思路: 模拟最近 5 天的若干次训练 session, 每次 session 一个 plan + 多个动作 × 多组
// session 卡片按 (planId, day) 聚合; 这里给出 3 次完成的 plan + 1 次自由组

private func sampleSets(now: Date, plans: [Plan], byId: [String: Exercise]) -> [SetRecord] {
    var out: [SetRecord] = []

    func addSession(planId: String?, daysAgo: Int, stepIds: [(id: String, sets: Int, weight: Double?, reps: Int?)]) {
        let base = now.addingTimeInterval(-Double(daysAgo) * 86400 - 3600 * 2)
        var t = base
        for (stepId, setCount, w, r) in stepIds {
            guard let ex = byId[stepId] else { continue }
            for _ in 0..<setCount {
                out.append(SetRecord(
                    id: UUID().uuidString,
                    exerciseId: ex.id,
                    exerciseName: ex.name,
                    category: ex.category,
                    weight: w,
                    reps: r,
                    duration: nil,
                    performedAt: t,
                    planId: planId
                ))
                t = t.addingTimeInterval(90)  // 每组间 ~1.5 分钟
            }
        }
    }

    // 1 天前 — 全身 A (上次刚做的)
    addSession(planId: "plan-fullA", daysAgo: 1, stepIds: [
        ("incline_bench_press_barbell", 3, 45, 8),
        ("squat_barbell",                              3, 80, 8),
        ("pull_up",                                    3, 0,  8),
        ("lateral_raise_dumbbell",                         3, 8,  12),
        ("bicep_curl_dumbbell",                        3, 12, 10),
    ])

    // 3 天前 — 全身 B
    addSession(planId: "plan-fullB", daysAgo: 3, stepIds: [
        ("bench_press_dumbbell",   3, 24, 10),
        ("rdl_barbell",      3, 70, 8),
        ("barbell_row",  3, 50, 10),
        ("overhead_press_dumbbell_seated",  3, 18, 8),
        ("triceps_pushdown_rope",       3, 25, 12),
    ])

    // 5 天前 — 自由组 (planId = nil)
    addSession(planId: nil, daysAgo: 5, stepIds: [
        ("bicep_curl_dumbbell",    4, 14, 8),
        ("triceps_pushdown_rope",       4, 28, 10),
    ])

    // 7 天前 — 全身 C
    addSession(planId: "plan-fullC", daysAgo: 7, stepIds: [
        ("decline_bench_press_barbell",  3, 55, 8),
        ("hip_thrust_barbell",           3, 80, 10),
        ("cable_row_seated",            3, 50, 10),
        ("face_pull",                    3, 15, 12),
        ("cross_body_hammer_curl",       3, 10, 10),
    ])

    // 按 performedAt 倒序返回 (最近的在最前面)
    return out.sorted { $0.performedAt > $1.performedAt }
}
