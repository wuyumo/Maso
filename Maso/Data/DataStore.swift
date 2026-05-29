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
            return store
        }
        // 第一次启动 → 走 mock, 立即落盘 (flush, 不 debounce) 保证文件马上存在
        let mock = makeMock()
        mock.flushSave()
        return mock
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
        let cap = max(1, min(6, settings.exercisesPerSession))
        let floorSets = max(1, settings.defaultSetsPerExercise)
        return raw.map { plan -> Plan in
            var p = plan
            p.steps = Array(p.steps.prefix(cap)).map { step -> PlanStep in
                var s = step
                s.sets = max(s.sets, floorSets)  // 地板, 不压平
                return s
            }
            // LRU 回填: 该 plan 在历史里最近一次训练时间 (没练过 → nil → distantPast 排最前)
            p.lastUsedAt = sets.filter { $0.planId == p.id }.map(\.performedAt).max()
            return p
        }
    }

    // MARK: - 简单的 plan 操作

    func updatePlan(_ plan: Plan) {
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        } else {
            plans.append(plan)
        }
        save()  // 持久化变更
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
        guard settings.aiWorkoutEnabled else { return }
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
        }
    }

    /// 强制重新生成 (用户主动点 "Refresh" 时调). 跳过同日 cache 检查.
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
        }
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
            let planName = key.planId == "free"
                ? "Quick Workout"
                : (plans.first(where: { $0.id == key.planId })?.name ?? "Plan")
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
    func regenerateRecommendedPlans() {
        let recommendedPrefixes = ["plan-full", "plan-bal", "plan-push", "plan-pull", "plan-legs"]
        plans.removeAll { plan in
            recommendedPrefixes.contains(where: { plan.id.hasPrefix($0) })
        }
        let tuned = DataStore.tunedRecommendedPlans(
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
        ("Barbell_Incline_Bench_Press_-_Medium_Grip", 3, 45, 8),
        ("Barbell_Squat",                              3, 80, 8),
        ("Pullups",                                    3, 0,  8),
        ("Side_Lateral_Raise",                         3, 8,  12),
        ("Dumbbell_Bicep_Curl",                        3, 12, 10),
    ])

    // 3 天前 — 全身 B
    addSession(planId: "plan-fullB", daysAgo: 3, stepIds: [
        ("Dumbbell_Bench_Press",   3, 24, 10),
        ("Romanian_Deadlift",      3, 70, 8),
        ("Bent_Over_Barbell_Row",  3, 50, 10),
        ("Seated_Dumbbell_Press",  3, 18, 8),
        ("Triceps_Pushdown",       3, 25, 12),
    ])

    // 5 天前 — 自由组 (planId = nil)
    addSession(planId: nil, daysAgo: 5, stepIds: [
        ("Dumbbell_Bicep_Curl",    4, 14, 8),
        ("Triceps_Pushdown",       4, 28, 10),
    ])

    // 7 天前 — 全身 C
    addSession(planId: "plan-fullC", daysAgo: 7, stepIds: [
        ("Decline_Barbell_Bench_Press",  3, 55, 8),
        ("Barbell_Hip_Thrust",           3, 80, 10),
        ("Seated_Cable_Rows",            3, 50, 10),
        ("Face_Pull",                    3, 15, 12),
        ("Cross_Body_Hammer_Curl",       3, 10, 10),
    ])

    // 按 performedAt 倒序返回 (最近的在最前面)
    return out.sorted { $0.performedAt > $1.performedAt }
}
