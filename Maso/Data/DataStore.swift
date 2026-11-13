import Foundation
import Observation
import UIKit
import CryptoKit

// 应用级数据仓库 — MVP 阶段用 in-memory mock; 后续可接 SwiftData / CoreData
//
// 设计跟 web 端 Dexie 表对齐:
//   - exercises: 静态字典 (从 yuhonas/free-exercise-db bundled JSON)
//   - plans: 用户的训练计划
//   - sets: 历史训练记录 (SetRecord)
//   - settings: 用户偏好 (单例)

/// 分享卡 (InsightShareCard) 的 4 个头条数字 — DataStore.summaryKeyStats() 产出.
/// 全部由 DataStore 的 summary* helper 确定性算出, 卡片从不自己算数.
struct SummaryKeyStats {
    /// 本周 vs 上周容量变化 % (上周无数据 → nil, 该 tile 不显示)
    var volumeWoWPct: Int?
    /// 本周容量 kg (Σ weight×reps, 取整)
    var weeklyVolumeKg: Int
    /// 头号动作名 (weighted set 最多的动作). 无负重记录 → nil, 该 tile 不显示.
    var topLiftName: String?
    /// 头号动作当前估算 1RM (kg, Epley).
    var topLiftE1rmKg: Int?
    /// 坚持度 (近 8 周达标周占比 %)
    var adherencePct: Int
}

@MainActor
@Observable
final class DataStore {
    var exercises: [Exercise]
    var plans: [Plan]
    var sets: [SetRecord] {
        didSet {
            let removedSessions = Set(oldValue.compactMap(\.workoutSessionID)).subtracting(sets.compactMap(\.workoutSessionID))
            WorkoutHeartLocalStore.shared.removeSessions(removedSessions)
        }
    }
    var refreshingBodyActivityHealth = false
    var settings: UserSettings

    /// AI 生成的今日训练计划 — TodayScreen 优先用这个, fallback 系统推荐.
    /// `lastAIRefreshAt` 是当天日期, 同一天不重复 refresh.
    var aiTodayPlan: Plan? = nil
    private(set) var importingExternalWorkouts = false
    var lastAIRefreshAt: Date? = nil
    /// 用户最近一次手调 aiTodayPlan 的时间 (P0#1-④) — 置位当天 refreshAIWorkoutIfNeeded 跳过自动
    /// 重生成, 不冲掉用户调过的重量 (每天静默重生成会把手调值重置回 LLM 猜值). 持久化进 snapshot,
    /// 否则重启 app 后 refresh 照样冲掉. 手动 Retry (forceRefreshAIWorkout) 不受此限.
    var aiTodayPlanEditedAt: Date? = nil
    /// 最近一次今日 AI 生成是否失败 (网络/服务) — TodayScreen 据此露出"够不到 AI,已用推荐·重试"提示.
    var aiTodayFailed: Bool = false
    /// 引导首次 AI 生成 (generateFirstPlanViaAI) 的 in-flight 标记 — 弱网下过渡页 9s 兜底先落地,
    /// 首次调用 (timeout 45s) 仍在飞时 RootView 的 refreshAIWorkoutIfNeeded (启动 task / 回前台)
    /// 会并发双跑, 后者的普通结果覆盖带 focusNote 的首次结果. 起飞置位 / 落地复位 (defer 保证),
    /// refreshAIWorkoutIfNeeded 见置位即 return. 纯内部 bookkeeping, 不驱动 UI.
    @ObservationIgnored private var firstPlanGenerationInFlight = false

    /// Coach tab 对话状态 (V1 in-memory, 不持久化 — 头注/修订环见 CoachSession.swift).
    let coachSession = CoachSession()
    /// Nil in production. A test may return false here to simulate a failed write
    /// without reading or writing the user's maso-data.json.
    var equipmentSwapSaveOverride: (() -> Bool)?
    /// Coach 生成任务 — 收归 DataStore 持有: 切 tab / 视图销毁不取消, 结果落回 coachSession
    /// (工程评审钦点, 修"60s 生成被切走即丢"). @ObservationIgnored — 任务句柄不驱动 UI,
    /// UI 看的是 coachSession.isGenerating.
    @ObservationIgnored var coachGenerateTask: Task<Void, Never>? = nil

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
    @ObservationIgnored private lazy var _bundleExById: [String: Exercise] = ExerciseLibrary.lookup(exercises)

    var exById: [String: Exercise] {
        // 0 个自创动作 (绝大多数用户) → 直接返回缓存, O(1) 无拷贝.
        // 有自创动作 → 在缓存副本上 merge (custom 数量很小, 一次 COW 拷贝可接受).
        let custom = settings.customExercises
        if custom.isEmpty { return _bundleExById }
        var m = _bundleExById
        for ex in custom { m[ex.id] = ex }
        return m
    }

    // MARK: - Library views

    /// Complete searchable library. Personal records always retain their exact variant IDs.
    var userLibrary: [Exercise] {
        exercises + settings.customExercises
    }

    var visibleExerciseLibrary: [Exercise] {
        ExerciseSelectionPolicy.shared.visibleExercises(from: userLibrary, settings: settings,
            retainingIDs: personalExerciseIDs, availableMediaIDs: ExerciseDemoService.shared.availableMediaIDs,
            legacyOnlyIDs: Set(ExerciseMediaPolicy.legacyOwners.values))
    }

    func routinePlanDefaults(_ plan: Plan) -> Plan {
        let canonical = ExerciseLibrary.canonicalPlan(plan, using: exById)
        var result = ExerciseSelectionPolicy.shared.routineDefaults(canonical, library: userLibrary, settings: settings)
        result.steps = result.steps.map { suggestingMissingParameters(for: $0) }
        return result
    }

    /// Canonical IDs of personally meaningful exercises, including existing saved plans.
    var personalExerciseIDs: Set<String> {
        var ids = settings.favoriteExerciseIds + settings.adoptedNicheExerciseIds
        ids.append(contentsOf: settings.customExercises.map(\.id))
        ids.append(contentsOf: sets.map(\.exerciseId))
        ids.append(contentsOf: plans.flatMap { $0.steps.map(\.exerciseId) })
        ids.append(contentsOf: aiTodayPlan?.steps.map(\.exerciseId) ?? [])
        let lookup = exById
        return Set(ids.map { lookup[$0]?.id ?? $0 })
    }

    /// Most recently performed concrete variants, deduplicated after legacy ID resolution.
    var recentExerciseIDs: [String] {
        let lookup = exById
        var seen = Set<String>()
        return sets.enumerated().sorted {
            $0.element.performedAt == $1.element.performedAt
                ? $0.offset < $1.offset : $0.element.performedAt > $1.element.performedAt
        }.compactMap { item in
            let record = item.element
            let id = lookup[record.exerciseId]?.id ?? record.exerciseId
            return seen.insert(id).inserted ? id : nil
        }
    }

    /// Compact default browsing, with personal and saved-plan exercises kept discoverable.
    /// Searching still uses userLibrary, so less common variants remain available.
    var curatedExerciseLibrary: [Exercise] {
        let policy = ExerciseSelectionPolicy.shared
        return policy.sorted(
            policy.browseCandidates(from: visibleExerciseLibrary, settings: settings, retainingIDs: personalExerciseIDs, availableMediaIDs: ExerciseDemoService.shared.availableMediaIDs),
            favoriteIDs: canonicalFavoriteExerciseIDs, recentIDs: recentExerciseIDs)
    }

    var canonicalFavoriteExerciseIDs: Set<String> {
        let lookup = exById
        return Set(settings.favoriteExerciseIds.map { lookup[$0]?.id ?? $0 })
    }

    /// One deterministic selection path for Quick Workout and catch-up training.
    /// Each programming group gets at most one slot, however many variants it contains.
    func suggestedTrainingExercises(
        targetMuscles: [MuscleGroup],
        perMuscleLimit: Int = 2,
        limit: Int = 8,
        equipmentFilter: String? = nil
    ) -> [Exercise] {
        return Self.suggestedTrainingExercises(
            targetMuscles: targetMuscles, library: userLibrary, settings: settings,
            preferredIDs: canonicalFavoriteExerciseIDs.union(recentExerciseIDs.prefix(40)),
            perMuscleLimit: perMuscleLimit, limit: limit, equipmentFilter: equipmentFilter)
    }

    /// Quick Workout filters name a concrete piece of equipment; profile preferences use categories.
    /// Keep the exact filter on the candidate library and only map its profile constraint here.
    static func settingsForTrainingSelection(_ settings: UserSettings, equipmentFilter: String?) -> UserSettings {
        guard let equipmentFilter else { return settings }
        var effective = settings
        if let category = EquipmentCategory.category(for: equipmentFilter) {
            effective.availableEquipment = [category.rawValue]
        } else if ["body_only", "bodyweight", "none"].contains(equipmentFilter) {
            effective.availableEquipment = ["bodyweight"]
        }
        return effective
    }

    static func suggestedTrainingExercises(
        targetMuscles: [MuscleGroup],
        library: [Exercise],
        settings: UserSettings,
        preferredIDs: Set<String> = [],
        perMuscleLimit: Int = 2,
        limit: Int = 8,
        equipmentFilter: String? = nil
    ) -> [Exercise] {
        guard perMuscleLimit > 0, limit > 0 else { return [] }
        let policy = ExerciseSelectionPolicy.shared
        let effective = settingsForTrainingSelection(settings, equipmentFilter: equipmentFilter)
        let matching = library.filter { exercise in
            guard let equipmentFilter else { return true }
            if equipmentFilter == "other" { return exercise.equipment == "other" || exercise.equipment == nil }
            return exercise.equipment == equipmentFilter
        }
        let pool = policy.generationCandidates(
            from: matching.filter { $0.category == .strength || $0.category == .hypertrophyFocus || $0.category == .calisthenics },
            settings: effective, maxPerProgrammingGroup: Int.max, preferredIDs: preferredIDs)
        var selected: [Exercise] = []
        var groups = Set<String>()
        for muscle in targetMuscles {
            let targets = expandAnatomyMuscles([muscle])
            let ranked = pool.enumerated().compactMap { index, exercise -> (Int, Exercise, Int)? in
                let score = exercise.muscleGroups.enumerated().reduce(0) { total, item in
                    total + (targets.contains(item.element) ? max(20, 100 - item.offset * 18) : 0)
                }
                return score > 0 ? (index, exercise, score) : nil
            }.sorted { lhs, rhs in
                let lt = policy.tier(for: lhs.1), rt = policy.tier(for: rhs.1)
                if lt != rt { return lt == .core }
                if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
                return lhs.0 < rhs.0
            }
            var count = 0
            for (_, exercise, _) in ranked {
                guard groups.insert(policy.programmingGroupID(for: exercise)).inserted else { continue }
                selected.append(exercise)
                count += 1
                if selected.count >= limit { return selected }
                if count >= perMuscleLimit { break }
            }
        }
        return selected
    }

    /// Specialist versions not yet adopted, using the same editorial tiers as browsing/generation.
    var unadoptedNicheExercises: [Exercise] {
        let adopted = Set(settings.adoptedNicheExerciseIds)
        let policy = ExerciseSelectionPolicy.shared
        return policy.sorted(exercises.filter { policy.tier(for: $0).isSpecialist && !adopted.contains($0.id) })
    }

    /// 采纳一个小众动作 — 加进 settings.adoptedNicheExerciseIds. 之后主 picker 能看到它.
    func adoptNicheExercise(_ id: String) {
        guard !settings.adoptedNicheExerciseIds.contains(id) else { return }
        settings.adoptedNicheExerciseIds.append(id)
        Analytics.shared.track("niche_exercise_adopt")   // 无 PII: 不带动作 ID/名
        save()
    }

    /// 取消采纳 — 把动作放回 niche stash (主 picker 隐藏, 但 niche browse 还能看到).
    func unadoptNicheExercise(_ id: String) {
        settings.adoptedNicheExerciseIds.removeAll { $0 == id }
        save()
    }

    /// 加一个用户自创动作. caller 自己负责 build Exercise (含 customImageData / muscleGroups 等).
    /// id 由 caller 给 (推荐 "custom-{UUID}" 格式), 防止跟 bundle ID 冲突.
    var canCreateCustomExercise: Bool {
        settings.isPro || settings.customExercises.count < ProAccessPolicy.current.freeCustomExercises
    }

    @discardableResult
    func addCustomExercise(_ ex: Exercise) -> Bool {
        if let existing = settings.customExercises.first(where: { $0.id == ex.id }) { return existing == ex }
        guard canCreateCustomExercise else { return false }
        settings.customExercises.append(ex)
        Analytics.shared.track("custom_exercise_add")   // 无 PII: 不带名字/图
        save()
        return true
    }

    // (旧"从截图导入 → 存为自创动作"工厂已删 — 导入改版后未匹配动作只能从库里替换,
    //  不再有绕过自创动作 Pro gate 的免费入口. 自创动作唯一入口 = 动作库 "+", 有付费墙.)

    /// 改一个已保存的自创动作 (名字 / 主肌群 / 器械 / 图片 / 计量方式).
    /// **id 必须跟原来一致** —— plan / 历史 / lastSet 全按 id 引用, 换 id 等于把它从所有
    /// 已有计划和记录里抹掉。caller (CustomExerciseFormSheet 编辑模式) 保证这点。
    /// 找不到 id 就当无事发生, 不静默 append 出一条重复的。
    func updateCustomExercise(_ ex: Exercise) {
        guard let i = settings.customExercises.firstIndex(where: { $0.id == ex.id }) else { return }
        settings.customExercises[i] = ex
        Analytics.shared.track("custom_exercise_edit")   // 无 PII
        save()
    }

    /// 删一个自创动作.
    func deleteCustomExercise(_ id: String) {
        settings.customExercises.removeAll { $0.id == id }
        save()
    }

    /// 教练记忆 (Coaching Memory) — append 一条用户用自然语言写下的偏好 / 限制.
    /// AI 对话框发送时调 (那句话同时驱动本次重生成). 以 bullet ("- xxx") 累积成一份长期备忘,
    /// 每次生成 routine 都注进 prompt. 忽略空文本，并与全部已有 Notes 去重。
    func appendCoachNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bullet = "- \(trimmed)"
        // De-duplicate across all Notes, not only consecutive lines.
        guard !CoachMemoryProposal.key(settings.coachMemory).contains(CoachMemoryProposal.key(trimmed)) else { return }
        if settings.coachMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.coachMemory = bullet
        } else {
            settings.coachMemory += "\n" + bullet
        }
        // 无 PII: 只报去重后的笔记总条数 (按行数), 不带笔记文本.
        let noteCount = settings.coachMemory
            .split(separator: "\n", omittingEmptySubsequences: true).count
        Analytics.shared.track("coach_note_append", ["note_count": .int(noteCount)])
        save()
    }

    /// 教练记忆的显示条目 — 把 coachMemory 这份 "- bullet" 文本按行解析成可展示 chip 数组:
    /// 按 \n 切行, 去首尾空白, 去掉前缀 "- ", 丢空行. (chip 展示 + 单条删除都用它.)
    var coachNotes: [String] {
        settings.coachMemory
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    /// 删除某条教练记忆 (按 coachNotes 的显示下标) — 剩下的重新加 "- " 前缀拼回 coachMemory + 存盘.
    /// 只做删除, 不触发重生成 (删除是修剪, 常批量做, 每次删都重生成既跳又费 token — 由 UI 的
    /// "Notes changed — Regenerate" pill 让用户一键统一应用).
    func removeCoachNote(at index: Int) {
        var notes = coachNotes
        guard notes.indices.contains(index) else { return }
        notes.remove(at: index)
        settings.coachMemory = notes.map { "- \($0)" }.joined(separator: "\n")
        // 无 PII: 只报删除后的剩余条数, 不带笔记文本.
        Analytics.shared.track("coach_note_delete", ["note_count": .int(notes.count)])
        save()
    }

    /// 清空全部教练记忆 (跟 coachMemorySection 的 Clear 同语义) + 存盘.
    func clearCoachNotes() {
        settings.coachMemory = ""
        save()
    }

    /// 这个 exercise id 是否被任何 plan step 或历史 set 引用 — 删除前查, 避免产生悬空 id
    /// (悬空后 exById 查不到 → BodyHint / 图回退 placeholder, displayName 失败).
    func isExerciseReferenced(_ id: String) -> Bool {
        if plans.contains(where: { $0.steps.contains(where: { $0.exerciseId == id }) }) { return true }
        if sets.contains(where: { $0.exerciseId == id }) { return true }
        return false
    }

    var aiAccess = DeviceAIQuota()

    init(exercises: [Exercise], plans: [Plan], sets: [SetRecord], settings: UserSettings) {
        let lookup = ExerciseLibrary.lookup(exercises + settings.customExercises)
        self.exercises = exercises
        self.plans = plans.map { ExerciseLibrary.canonicalPlan($0, using: lookup) }
        self.sets = sets.map { ExerciseLibrary.canonicalRecord($0, using: lookup) }
        self.settings = ExerciseLibrary.canonicalSettings(settings, using: lookup)
        if self.settings.workoutCompletions == nil {
            // Existing history has no finish events. Migrate its plan/day records
            // once; future set logging does not advance the workout rotation.
            let grouped = Dictionary(grouping: sets.filter { $0.planId != nil }) {
                "\($0.planId!)|\(settings.calendar.startOfDay(for: $0.performedAt).timeIntervalSince1970)"
            }
            self.settings.workoutCompletions = grouped.compactMap { key, records in
                guard let last = records.max(by: { $0.performedAt < $1.performedAt }), let planID = last.planId else { return nil }
                return WorkoutCompletion(sessionID: "legacy-" + key, planID: planID, finishedAt: last.performedAt)
            }
        }
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
            store.aiTodayPlan = snapshot.aiTodayPlan.map { ExerciseLibrary.canonicalPlan($0, using: store.exById) }
            store.lastAIRefreshAt = snapshot.lastAIRefreshAt
            store.aiTodayPlanEditedAt = snapshot.aiTodayPlanEditedAt
            // 匿名分析 ID — 老快照 (UserSettings.anonymousId 字段加之前存的) 解码会落空串, 这里补铸一个.
            store.mintAnonymousIdIfNeeded()
            // 一次性迁移 (→ v3, #IA): My Plans 改成"只放用户主动 save 的". 清掉历史自动塞进去的
            // 推荐计划 (plan-full/bal/push/pull/legs/comrec 前缀). 用户自建 (plan-new) / 已 save
            // (plan-saved) / 已采纳社区 (plan-community) 全保留; 历史 / 设置不动. 存盘后 version=3 不再跑.
            if snapshot.version < PersistenceController.schemaVersion {
                let autoPrefixes = ["plan-full", "plan-bal", "plan-push", "plan-pull", "plan-legs", "plan-comrec"]
                store.plans.removeAll { p in autoPrefixes.contains { p.id.hasPrefix($0) } }
                store.flushSave()
            }
            if store.plans != snapshot.plans || store.sets != snapshot.sets ||
                store.settings.favoriteExerciseIds != snapshot.settings.favoriteExerciseIds ||
                store.settings.adoptedNicheExerciseIds != snapshot.settings.adoptedNicheExerciseIds ||
                store.aiTodayPlan != snapshot.aiTodayPlan {
                store.flushSave()
            }
            store.aiAccess = DeviceAIQuota.installed(legacy: snapshot.settings.onboardingCompleted || !snapshot.plans.isEmpty || !snapshot.sets.isEmpty)
            return store
        }
        // 第一次启动 (磁盘无存档) → 全新空档: 空 plans/sets + onboardingCompleted=false.
        // 用户随即走 OnboardingScreen 填真实画像 (性别/年龄/体重/天数/聚焦肌群), 引导结尾
        // regenerateRecommendedPlans() 才生成推荐计划. 立即落盘 (flush, 不 debounce) 保证文件马上存在.
        // ⚠️ 绝不能用 makeMock() —— 它带假训练历史 + 假画像 (男/30/75) + onboardingCompleted=true,
        //    会让真实新用户跳过引导、看到自己没做过的训练. makeMock 仅供 SwiftUI Preview / 演示.
        let store = freshInstall()
        store.aiAccess = DeviceAIQuota.installed(legacy: false)
        store.mintAnonymousIdIfNeeded()
        store.flushSave()
        return store
    }

    /// 匿名分析 ID 为空时铸一个并标记需保存 (不在此立即 flush — caller 的 flushSave/save 会带上).
    /// UserSettings() 默认 anonymousId 已是 UUID, 但老快照解码出空串 / 或被清过时这里兜底.
    func mintAnonymousIdIfNeeded() {
        if settings.anonymousId.isEmpty {
            settings.anonymousId = UUID().uuidString
        }
    }

    /// Analytics 服务读的匿名 ID 访问器 (信封 anon_id).
    var anonymousId: String { settings.anonymousId }

    /// 全新安装 (无存档) 的起始数据 — 空 plans/sets, onboardingCompleted=false (UserSettings() 默认).
    /// 没有任何假历史 / 假画像 / 预生成计划; 这些等用户走完引导再由 onboarding 生成.
    static func freshInstall(deviceCountry: String? = Locale.current.region?.identifier) -> DataStore {
        var settings = UserSettings() // onboardingCompleted=false; gender/age/weight=nil
        let provisional = WeightUnitDefaulting.provisional(deviceCountry: deviceCountry)
        settings.weightUnit = provisional.unit
        settings.weightUnitOrigin = provisional.origin.rawValue
        return DataStore(
            exercises: ExerciseLibrary.all,
            plans: [],
            sets: [],
            settings: settings
        )
    }

    /// P2-1: debounce 句柄. 之前注释说"debounced"但其实每次 mutate 都同步全量写盘 —
    /// plan 名每敲一字符 = 一次 MB 级写. 现在真 debounce: 0.8s 内的连续 save 合并成一次.
    private var saveWorkItem: DispatchWorkItem?
    private static let saveDebounce: TimeInterval = 0.8

    /// 持久化当前状态 — 真 debounced (0.8s 合并). 关键时刻 (进后台 / 退出) 调 flushSave() 立即落盘.
    /// 不抛错, 失败静默 (写不进文件不影响 app 运行).
    func save() {
        settings.reconcileHealthProfileOverrides()
        SleepReminderScheduler.shared.reschedule(settings: settings)
        MealReminderScheduler.shared.reschedule(settings: settings)
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeSnapshotNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounce, execute: item)
    }

    /// 立即把当前状态落盘 (取消 pending debounce). RootView 在 scenePhase → background/inactive 调.
    func flushSave() {
        settings.reconcileHealthProfileOverrides()
        MealReminderScheduler.shared.reschedule(settings: settings)
        saveWorkItem?.cancel()
        saveWorkItem = nil
        writeSnapshotNow()
    }

    /// Equipment-swap commit. flushSave() ignores the Bool from PersistenceController.save,
    /// so a failed atomic write would still look saved. This cancels the debounced save,
    /// writes the current snapshot (plans plus history, settings, and today's plan), and
    /// returns whether that write succeeded. It does not replace flushSave().
    @discardableResult
    func saveEquipmentSwapNow() -> Bool {
        settings.reconcileHealthProfileOverrides()
        MealReminderScheduler.shared.reschedule(settings: settings)
        saveWorkItem?.cancel()
        saveWorkItem = nil
        if let equipmentSwapSaveOverride { return equipmentSwapSaveOverride() }
        return PersistenceController.shared.save(currentSnapshot())
    }

    /// 真正构 snapshot + 写盘. 在 main actor 上 (DataStore @MainActor), 读 state 安全.
    private func writeSnapshotNow() {
        BodyHealthLocalStore.saveIfNeeded(settings)
        let snapshot = PersistenceController.Snapshot(
            version: PersistenceController.schemaVersion,
            plans: plans,
            sets: sets,
            settings: settings,
            aiTodayPlan: aiTodayPlan,
            lastAIRefreshAt: lastAIRefreshAt,
            aiTodayPlanEditedAt: aiTodayPlanEditedAt,
            updatedAt: Date()
        )
        PersistenceController.shared.save(snapshot)
        WidgetSnapshotPublisher.shared.schedule(self)
    }

    /// 用 imported snapshot 替换当前所有数据. UI 调 import 时用.
    /// exercises 不动 — 那个是静态库, 不进 snapshot.
    func replaceFromSnapshot(_ snapshot: PersistenceController.Snapshot) {
        let lookup = ExerciseLibrary.lookup(exercises + snapshot.settings.customExercises)
        self.plans = snapshot.plans.map { ExerciseLibrary.canonicalPlan($0, using: lookup) }
        self.sets = snapshot.sets.map { ExerciseLibrary.canonicalRecord($0, using: lookup) }
        self.settings = ExerciseLibrary.canonicalSettings(snapshot.settings, using: lookup)
        self.aiTodayPlan = snapshot.aiTodayPlan.map { ExerciseLibrary.canonicalPlan($0, using: lookup) }
        self.lastAIRefreshAt = snapshot.lastAIRefreshAt
        self.aiTodayPlanEditedAt = snapshot.aiTodayPlanEditedAt
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
            aiTodayPlanEditedAt: aiTodayPlanEditedAt,
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
            proSubscription: nil,
            weightUnitOrigin: nil
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
    /// 给本地兜底产出打上 .builtIn 来源标 —— 卡片上会显示灰色「Built-in」徽标.
    /// 用户在 Coach 里要的是 AI, 拿到的是本地规则拼的; 不标就跟他自己手建的 routine 一模一样,
    /// 等于默默糊弄. 标了他才知道"这版是离线兜底, 联上网可以让 AI 重做".
    static func markBuiltIn(_ plans: [Plan]) -> [Plan] {
        plans.map { var p = $0; p.source = .builtIn; return p }
    }

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
        // P0#1-⑤: 模板重量按 75kg 参考体重手写 (RecommendedPrograms: 深蹲 80kg 等), 60kg 女新手
        // day-1 不该见 80kg 杠铃深蹲. 物化时按用户体重折算: factor = clamp(体重/75, 0.5...1.3),
        // 折算后取 2.5kg 步进. 只动物化层, 模板定义本身不改; 没填体重 → factor 1 不折算.
        let weightFactor: Double = {
            guard let w = settings.weight, w > 0 else { return 1 }
            return min(1.3, max(0.5, w / 75.0))
        }()
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
                // 体重折算 (P0#1-⑤). weight==0 = 自重动作 (引体等), 保持 0 不折算.
                if weightFactor != 1, let w = s.weight, w > 0 {
                    s.weight = max(2.5, (w * weightFactor / 2.5).rounded() * 2.5)
                }
                return s
            }
            p.steps = DataStore.applyEquipmentPreference(p.steps, settings: settings, exById: exById)
            // 3. 科学化兜底: 复合优先 + 同 section ≤2 + slot-1 复合 + push≥pull (先于 pad, 这样若丢了同 section
            //    第 3 个, 下面 pad 会按用户 exercises-per-plan 用别的 section 补回, 不让总数掉档).
            p.steps = DataStore.enforceScience(p.steps, exById: exById)
            // 防御性补足: 模板正常是 8 step (cap≤8 不会触发), 但万一某 step ID 失效被 compactMap
            // 丢掉导致不足 (或被 enforceScience 丢了同 section 多余项), 也按 exercises-per-plan 补回.
            p.steps = DataStore.padStepsToTarget(p.steps, target: cap, settings: settings, exById: exById)
            // #1 器械约束: 把所选器械做不了的动作换成可用替代 (availableEquipment 空时无操作).
            p.steps = DataStore.applyEquipmentPreference(p.steps, settings: settings, exById: exById)
            if p.steps.isEmpty {
                // A strict no-equipment profile can remove every pull-day step.
                // Keep a usable card by choosing a familiar, equipment-compatible
                // full-body session rather than returning an empty day or borrowing a bar.
                let targets = settings.wantStrengthen + [.chest, .legs, .back, .shoulders, .core, .arms]
                let safe = suggestedTrainingExercises(targetMuscles: targets, library: Array(exById.values),
                    settings: settings, preferredIDs: Set(settings.favoriteExerciseIds), perMuscleLimit: 1, limit: cap)
                if !safe.isEmpty {
                    p.name = NSLocalizedString("Full body", comment: "Equipment-compatible fallback workout")
                    p.steps = enforceScience(safe.enumerated().map { index, exercise in
                        PlanStep(id: "\(p.id)-fallback-\(index)", exerciseId: exercise.id,
                                 sets: floorSets, reps: exercise.mechanic == .isolation ? goal.defaultRepsForIsolation() : goal.defaultRepsForCompound(),
                                 weight: nil, duration: nil, restBetweenSets: settings.defaultRestSeconds, rest: 0)
                    }, exById: exById)
                }
            }
            p = ExerciseSelectionPolicy.shared.routineDefaults(p, library: Array(exById.values), settings: settings, preferPinned: true)
            p.steps = DataStore.applyTrainingGoal(p.steps, settings: settings, exById: exById)
            p.steps = p.steps.map { step in
                var step = step
                if step.weight == nil, step.setWeights?.contains(where: { $0 != nil }) != true,
                   let ex = exById[step.exerciseId], ExerciseWeightReference.expectsLoad(ex),
                   let reference = ExerciseWeightReference.latest(for: ex, records: sets, library: exById) {
                    step.weight = reference.kilograms
                    step.markSuggested("weight", value: reference.kilograms, source: .history,
                                       exerciseID: ex.id, recordID: reference.recordID, recordedAt: reference.recordedAt)
                }
                return step
            }
            // LRU 回填: 该 plan 在历史里最近一次训练时间 (没练过 → nil → distantPast 排最前)
            p.lastUsedAt = sets.filter { $0.planId == p.id }.map(\.performedAt).max()
            return p
        }
    }

    /// One prescription for every local plan. Reps come from the existing loading
    /// table. Fat loss keeps those compound lifts and drops extra isolation work;
    /// it does not add cardio or a spot-reduction list. Missing weight, height,
    /// injuries and experience stay missing.
    static func applyTrainingGoal(
        _ steps: [PlanStep], settings: UserSettings, exById: [String: Exercise]
    ) -> [PlanStep] {
        let kind = settings.trainingGoalKind
        let loading = kind.loading
        let rest = kind.recommendedRestSeconds()
        let floor = max(1, kind.recommendedSetsFloor())
        func prescribed(_ step: PlanStep) -> PlanStep {
            var step = step
            if step.reps != nil {
                let isolation = exById[step.exerciseId]?.mechanic == .isolation
                step.reps = isolation ? loading.defaultRepsForIsolation() : loading.defaultRepsForCompound()
                if kind == .generalFitness { step.sets = min(step.sets, floor) }
                else { step.sets = max(step.sets, floor) }
            } else if kind == .generalFitness {
                step.sets = min(step.sets, floor)
            }
            step.restBetweenSets = rest
            step.markSuggested("sets", value: Double(step.sets), source: .preference)
            if let reps = step.reps { step.markSuggested("reps", value: Double(reps), source: .preference) }
            return step
        }
        var result = steps.map(prescribed)
        guard kind == .loseFat else { return result }
        let originalCount = result.count
        let kept = result.filter { exById[$0.exerciseId]?.mechanic != .isolation }
        guard kept.contains(where: { exById[$0.exerciseId]?.mechanic == .compound }) else { return result }
        result = fillCompounds(kept, target: originalCount, settings: settings, exById: exById, sets: floor, reps: loading.defaultRepsForCompound(), rest: rest)
        return result
    }

    private static func fillCompounds(
        _ steps: [PlanStep], target: Int, settings: UserSettings, exById: [String: Exercise],
        sets: Int, reps: Int, rest: Int
    ) -> [PlanStep] {
        guard steps.count < target else { return steps }
        let policy = ExerciseSelectionPolicy.shared
        let pool = policy.generationCandidates(
            from: Array(exById.values), settings: settings, maxPerProgrammingGroup: 1,
            preferredIDs: Set(settings.favoriteExerciseIds))
        var result = steps
        var used = Set(steps.compactMap { exById[$0.exerciseId] }.map { policy.programmingGroupID(for: $0) })
        for exercise in pool where exercise.mechanic == .compound && !used.contains(policy.programmingGroupID(for: exercise)) {
            if result.count >= target { break }
            used.insert(policy.programmingGroupID(for: exercise))
            result.append(PlanStep(
                id: "goal-compound-\(exercise.id)-\(result.count)", exerciseId: exercise.id,
                sets: sets, reps: reps, weight: nil, duration: nil, restBetweenSets: rest, rest: 0))
        }
        return result
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
            p.steps = applyEquipmentPreference(p.steps, settings: settings, exById: exById)
            // 科学化兜底 (先于 pad): 复合优先 + 同 section ≤2 + slot-1 复合 + push≥pull.
            p.steps = enforceScience(p.steps, exById: exById)
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

    /// Fill generated plans with familiar accessories from their existing muscle sections.
    /// Selection is by programming group, so extra equipment variants never gain extra slots.
    static func padStepsToTarget(
        _ steps: [PlanStep],
        target: Int,
        settings: UserSettings,
        exById: [String: Exercise]
    ) -> [PlanStep] {
        guard steps.count < target else { return steps }
        let policy = ExerciseSelectionPolicy.shared
        var result = steps
        var usedGroups = Set(steps.compactMap { exById[$0.exerciseId] }.map { policy.programmingGroupID(for: $0) })
        var sections: [MuscleGroup] = []
        for step in steps {
            guard let exercise = exById[step.exerciseId] else { continue }
            for muscle in exercise.primaryMuscles {
                let section = muscle.section ?? muscle
                if section != .fullBody, !sections.contains(section) { sections.append(section) }
            }
        }
        let focus = Set(settings.wantStrengthen.map { $0.section ?? $0 })
        sections = sections.filter { focus.contains($0) } + sections.filter { !focus.contains($0) }
        guard !sections.isEmpty else { return result }
        let pool = policy.generationCandidates(
            from: Array(exById.values).filter { $0.category == .strength || $0.category == .hypertrophyFocus || $0.category == .calisthenics },
            settings: settings, maxPerProgrammingGroup: Int.max,
            preferredIDs: Set(settings.favoriteExerciseIds))
        let pools = sections.map { section in
            pool.enumerated().filter { item in
                item.element.primaryMuscles.contains { ($0.section ?? $0) == section }
            }.sorted { lhs, rhs in
                let lt = policy.tier(for: lhs.element), rt = policy.tier(for: rhs.element)
                if lt != rt { return lt == .core }
                let li = lhs.element.mechanic == .isolation, ri = rhs.element.mechanic == .isolation
                if li != ri { return li }
                return lhs.offset < rhs.offset
            }.map(\.element)
        }
        var cursor = 0, emptyStreak = 0
        while result.count < target && emptyStreak < pools.count {
            let candidates = pools[cursor % pools.count]
            cursor += 1
            guard let pick = candidates.first(where: { !usedGroups.contains(policy.programmingGroupID(for: $0)) }) else {
                emptyStreak += 1
                continue
            }
            usedGroups.insert(policy.programmingGroupID(for: pick))
            result.append(PlanStep(
                id: "step-\(pick.id)-pad\(result.count)", exerciseId: pick.id,
                sets: max(1, settings.defaultSetsPerExercise),
                reps: pick.mechanic == .isolation ? settings.trainingGoal.defaultRepsForIsolation() : settings.trainingGoal.defaultRepsForCompound(),
                weight: nil, restBetweenSets: settings.defaultRestSeconds, rest: 0))
            emptyStreak = 0
        }
        return result
    }

    /// Normalize newly generated steps against the shared familiarity and equipment rules.
    /// Existing saved plans never enter this path merely because the catalog changes.
    /// Substituting a concrete variant clears load overrides; equipment loads are not interchangeable.
    static func applyEquipmentPreference(
        _ steps: [PlanStep], settings: UserSettings, exById: [String: Exercise],
        allowSpecialistIDs: Set<String> = []
    ) -> [PlanStep] {
        let policy = ExerciseSelectionPolicy.shared
        let pool = policy.generationCandidates(from: Array(exById.values), settings: settings,
                                               maxPerProgrammingGroup: Int.max,
                                               preferredIDs: Set(settings.favoriteExerciseIds))
        let eligibleIDs = Set(pool.map(\.id))
        var usedGroups = Set<String>()
        var result: [PlanStep] = []
        for step in steps {
            guard let original = exById[step.exerciseId] else { continue }
            let group = policy.programmingGroupID(for: original)
            let retainedSpecialist = allowSpecialistIDs.contains(original.id)
                && policy.equipmentAllows(original, selected: Set(settings.availableEquipment), environment: settings.trainingEnvironment)
            if (eligibleIDs.contains(original.id) || retainedSpecialist), !usedGroups.contains(group) {
                usedGroups.insert(group)
                result.append(step)
                continue
            }
            let available = pool.filter { !usedGroups.contains(policy.programmingGroupID(for: $0)) }
            guard let replacement = policy.replacementCandidates(
                for: original, from: available, settings: settings, limit: 1).first else { continue }
            usedGroups.insert(policy.programmingGroupID(for: replacement))
            result.append(PlanStep(
                id: step.id, exerciseId: replacement.id, sets: step.sets, reps: step.reps,
                weight: nil, duration: step.duration,
                restBetweenSets: step.restBetweenSets, rest: step.rest))
        }
        return result
    }

    // MARK: - enforceScience — 出计划后的科学化硬规则兜底 (AI 输出 + 模板/社区都过这一关)
    //
    // 为什么放代码侧而不是只靠 prompt: AI path 和本地模板各自独立, prompt 的 prose 规则 LLM 可能不遵守,
    // 模板更是写死的. 这里用 100%-populated 字段 (mechanic / force / primaryMuscles.section) 做"无论如何成立"
    // 的最低保障 —— 这是"一个 routine 里两三个胸动作"投诉的权威修复.
    //
    // ⚠️ 只用 100% 字段: mechanic (compound/isolation)、force (push/pull/static)、primaryMuscles.first.section.
    //    不碰 movementPattern (只 48% 有值) —— 膝/髋主导、水平/垂直只能在 prompt prose 里表达, 不在代码 quota.
    //    force == .static (等长/支撑) 既非 push 也非 pull, 从 push/pull 比里排除.
    //
    // 步骤: (a) 复合优先稳定排序 → (b) 同 section ≤2 上限 (丢第 3+ 个) → (c) slot-1 复合保证 →
    //       (d) push≥pull 偏好 (pull 不足时不主动丢 pull).
    // 在 1-3 个动作的小 routine 上必须优雅 no-op, 且永不把 routine 砍到 0 个 step.
    static func enforceScience(_ steps: [PlanStep], exById: [String: Exercise]) -> [PlanStep] {
        guard steps.count > 1 else { return steps }   // 0/1 个 step: 无可排无可丢, 直接返回

        func sectionKey(_ s: PlanStep) -> MuscleGroup? {
            guard let ex = exById[s.exerciseId], let first = ex.primaryMuscles.first else { return nil }
            // Legs contain several independent training roles; a two-exercise cap on all
            // of them would remove hamstring/glute/calf work from an ordinary leg day.
            switch first {
            case .quads, .rectusFemoris, .vastusLateralis, .vastusMedialis: return .quads
            case .hamstrings, .bicepsFemoris, .semitendinosus: return .hamstrings
            case .glutes, .gluteusMaximus, .gluteusMedius: return .glutes
            case .calves, .gastrocnemius, .soleus, .tibialisAnterior: return .calves
            case .adductors: return .adductors
            default: return first.section ?? first
            }
        }
        func isCompound(_ s: PlanStep) -> Bool { exById[s.exerciseId]?.mechanic == .compound }
        func force(_ s: PlanStep) -> ExerciseForce? { exById[s.exerciseId]?.force }

        // (a) 复合优先, tier 内稳定 (保留模板/AI 的原意顺序) —— enumerated 带原 index 作 tie-breaker.
        var ordered = steps.enumerated().sorted { a, b in
            let ta = isCompound(a.element) ? 0 : 1
            let tb = isCompound(b.element) ? 0 : 1
            return ta != tb ? ta < tb : a.offset < b.offset
        }.map { $0.element }

        // (b) 同主肌群 section ≤2 上限 —— 走一遍, 第 3+ 个同 section 的丢掉 (section 为 nil 的不计入/不丢).
        //     已按复合优先排过, 故被保留的 2 个里复合的排在前.
        var sectionCount: [MuscleGroup: Int] = [:]
        var capped: [PlanStep] = []
        for s in ordered {
            if let sec = sectionKey(s) {
                let c = sectionCount[sec, default: 0]
                if c >= 2 { continue }   // 丢第 3+ 个同 section
                sectionCount[sec] = c + 1
            }
            capped.append(s)
        }
        // 永不砍到空: 万一全被判同 section (不该发生), 至少留排序后的第一个.
        if capped.isEmpty { capped = ordered.isEmpty ? steps : [ordered[0]] }
        ordered = capped

        // (c) slot-1 复合保证: 排序后理论上复合已在前, 但若 step 0 仍是孤立而后面有复合, 把第一个复合换到 slot 0.
        if !ordered.isEmpty, !isCompound(ordered[0]),
           let firstCompound = ordered.firstIndex(where: { isCompound($0) }) {
            let c = ordered.remove(at: firstCompound)
            ordered.insert(c, at: 0)
        }

        // (d) push≥pull 偏好: 仅统计 force 非 static 的动作. push 多于 pull 太多时, 把多出来的 push 往后挪,
        //     让 pull 相对靠前 (不丢动作, 不改 cap, 只在违例时做温和重排; slot-0 复合不动).
        let pushN = ordered.filter { force($0) == .push }.count
        let pullN = ordered.filter { force($0) == .pull }.count
        if pushN > pullN, pullN > 0 {
            // 稳定地把 push (非 slot-0) 排到 pull 之后, 其余动作 (static/无 force) 保持相对位置.
            let head = ordered.first
            let rest = Array(ordered.dropFirst())
            let pulls = rest.filter { force($0) == .pull }
            let pushes = rest.filter { force($0) == .push }
            let others = rest.filter { force($0) != .pull && force($0) != .push }
            // pull 先于 push, others 收尾 — 在不丢动作的前提下偏向 pull 靠前.
            var reordered: [PlanStep] = []
            if let head { reordered.append(head) }
            reordered.append(contentsOf: pulls)
            reordered.append(contentsOf: others)
            reordered.append(contentsOf: pushes)
            ordered = reordered
        }

        return ordered
    }

    // MARK: - 简单的 plan 操作

    func updatePlan(_ plan: Plan) {
        let enteredSteps = plan.steps
        var plan = routinePlanDefaults(plan)
        let old = plans.first(where: { $0.id == plan.id })
        for step in enteredSteps {
            let prior = old?.steps.first(where: { $0.id == step.id })
            guard !step.isSuggested("weight"),
                  prior == nil || prior?.weight != step.weight || prior?.setWeights != step.setWeights,
                  let exercise = exById[step.exerciseId] else { continue }
            rememberWeight(step.weight ?? step.setWeights?.compactMap { $0 }.first, for: exercise)
        }
        plan = routinePlanDefaults(plan)
        let isAIToday = aiTodayPlan?.id == plan.id
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        } else if !isAIToday {
            // 约束: aiTodayPlan 本就不在 plans 数组 (解耦副本) — 编辑它时绝不能 append 进 plans,
            // 否则 My Routines 冒出副本 + 删除要删两次 (deletePlan 特判命中 aiTodayPlan 只清它就 return,
            // append 进去的那份要再删一次才消失). 只有真正的新 plan (两边都没有) 才走 append.
            plans.append(plan)
        }
        // P0#1-④: 编辑的是今日 AI 计划 (PlanDetailSheet 从 Today 卡打开 / 播放器保存都带 plan-ai- id) →
        // 镜像写回 aiTodayPlan (Today 卡立即反映修改, 它跟 plans 是解耦副本) + 置"用户编辑过"时间戳,
        // 当天的 refreshAIWorkoutIfNeeded 跳过自动重生成, 不冲掉手调的重量.
        if isAIToday {
            aiTodayPlan = plan
            aiTodayPlanEditedAt = Date()
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

    /// A same-number edit confirms its origin without presenting an empty numeric
    /// change review. Never save another session value or modify any target here.
    func confirmMatchingSuggestions(from edited: PlanStep, in planID: String) {
        guard let pi = plans.firstIndex(where: { $0.id == planID }),
              let si = plans[pi].steps.firstIndex(where: { $0.id == edited.id && $0.exerciseId == edited.exerciseId }) else { return }
        var step = plans[pi].steps[si]
        let before = step
        for field in ["sets", "reps", "weight", "duration"] where step.isSuggested(field) && !edited.isSuggested(field) {
            let matches: Bool
            switch field {
            case "sets": matches = step.sets == edited.sets
            case "reps": matches = step.reps == edited.reps && step.setReps == edited.setReps
            case "weight": matches = step.weight == edited.weight && step.setWeights == edited.setWeights
            default: matches = step.duration == edited.duration && step.setDurations == edited.setDurations
            }
            if matches { step.confirmParameter(field) }
        }
        if step != before {
            plans[pi].steps[si] = step; plans[pi].updatedAt = Date(); save()
        }
    }

    /// 把 src 的训练参数 (组数/次数/重量/时长/休息 + 逐组覆盖) 写到所有 plan (+ aiTodayPlan)
    /// 里同 exerciseId 的 step. 仅在 globalExerciseParamSyncEnabled 开启时生效.
    /// 不改 id / exerciseId; 源 step 被自己覆盖是幂等 no-op.
    func syncExerciseParams(from src: PlanStep) {
        guard settings.globalExerciseParamSyncEnabled else { return }
        func apply(_ s: inout PlanStep) {
            if !src.isSuggested("sets") { s.sets = src.sets; s.confirmParameter("sets") }
            if !src.isSuggested("reps") { s.reps = src.reps; s.setReps = src.setReps; s.confirmParameter("reps") }
            if !src.isSuggested("weight"), src.weight != nil || src.setWeights?.contains(where: { $0 != nil }) == true { s.weight = src.weight; s.setWeights = src.setWeights; s.confirmParameter("weight") }
            if !src.isSuggested("duration") { s.duration = src.duration; s.setDurations = src.setDurations; s.confirmParameter("duration") }
            s.restBetweenSets = src.restBetweenSets
            s.rest = src.rest
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
            if aiChanged {
                aiTodayPlan = ai
                changed = true
                // P0#1-④: 全局同步把用户改过的参数传播进了 aiTodayPlan (训练中调重最常见的路径) —
                // 同样算"用户手调过", 当天不要被自动重生成冲掉.
                aiTodayPlanEditedAt = Date()
            }
        }
        if changed { save() }
    }

    /// Request #3 — 把"训练偏好"里改过的 per-step 默认值 (组间歇 / 动作间歇 / 默认组数) 非破坏式
    /// 地应用到所有既有 routine (+ aiTodayPlan). 不重建选择 / 不动 reps / weight / 逐组覆盖,
    /// 只更新用户确实改了的那几个字段 —— 复用全局同步那套"walk plans 改字段"的管道.
    /// 由 TrainingSettingsSheet 在用户主动确认"应用到我所有计划"时调 (opt-in, 不静默覆盖).
    ///   - setRest:      改 step.restBetweenSets (组间歇), nil = 不动
    ///   - betweenRest:  改 step.rest (动作间歇), nil = 不动
    ///   - setsFloor:    把组数抬到该地板 (max, 不压平用户调高的组数), nil = 不动
    func applyDefaultParamsToAllRoutines(setRest: Int?, betweenRest: Int?, setsFloor: Int?) {
        guard setRest != nil || betweenRest != nil || setsFloor != nil else { return }
        func apply(_ s: inout PlanStep) -> Bool {
            var touched = false
            if let r = setRest, s.restBetweenSets != r { s.restBetweenSets = r; touched = true }
            if let r = betweenRest, s.rest != r { s.rest = r; touched = true }
            // 组数是地板 (跟模板调谐 + makeSeededStep 一致语义): 只抬不压, 不覆盖用户特意调高的组数.
            if let f = setsFloor, s.sets < f { s.sets = f; touched = true }
            return touched
        }
        var changed = false
        let now = Date()
        for pi in plans.indices {
            var planChanged = false
            for si in plans[pi].steps.indices {
                if apply(&plans[pi].steps[si]) { planChanged = true }
            }
            if planChanged { plans[pi].updatedAt = now; changed = true }
        }
        if var ai = aiTodayPlan {
            var aiChanged = false
            for si in ai.steps.indices { if apply(&ai.steps[si]) { aiChanged = true } }
            if aiChanged { aiTodayPlan = ai; changed = true }
        }
        if changed { save() }
    }

    /// 两个 step 的训练参数是否完全一致 (不看 id / exerciseId) — 给同步去抖 + updatePlan diff 用.
    static func sameParams(_ a: PlanStep, _ b: PlanStep) -> Bool {
        a.sets == b.sets && a.reps == b.reps && a.weight == b.weight && a.duration == b.duration
            && a.restBetweenSets == b.restBetweenSets && a.rest == b.rest
            && a.setReps == b.setReps && a.setWeights == b.setWeights && a.setDurations == b.setDurations
            && a.parameterSuggestions == b.parameterSuggestions
    }

    /// 新建一个 PlanStep, 训练参数按"全局同步开/关"取默认 (R3):
    ///   - 同步开 + 已有别的 routine 含该动作 → 采用那份参数 (保持全局一致).
    ///   - 否则 → 从该动作"最近一次记录" (lastSet) 回填 reps/weight/duration; 组数/休息用偏好默认.
    func makeSeededStep(for ex: Exercise, stepId: String) -> PlanStep {
        if settings.globalExerciseParamSyncEnabled,
           let existing = plans.lazy.flatMap({ $0.steps }).first(where: { $0.exerciseId == ex.id }) {
            let copied = PlanStep(id: stepId, exerciseId: ex.id, sets: existing.sets, reps: existing.reps,
                                 weight: existing.weight, setReps: existing.setReps, setWeights: existing.setWeights,
                                 setDurations: existing.setDurations, duration: existing.duration,
                                 restBetweenSets: existing.restBetweenSets, rest: existing.rest,
                                 parameterSuggestions: existing.parameterSuggestions)
            return suggestingMissingParameters(for: copied)
        }
        var step = PlanStep(id: stepId, exerciseId: ex.id, sets: settings.defaultSetsPerExercise,
                            reps: nil, weight: nil, duration: nil,
                            restBetweenSets: settings.defaultRestSeconds, rest: 0)
        step.markSuggested("sets", value: Double(step.sets), source: .preference)
        return suggestingMissingParameters(for: step)
    }

    /// Fill unknown fields and refresh unconfirmed suggestions outside the live session.
    /// Zero and every explicit per-set override are user targets.
    /// Shared by Coach, routine editing, free workouts and player replacements.
    func suggestingMissingParameters(for original: PlanStep, roughRecords: [SetRecord]? = nil) -> PlanStep {
        guard let exercise = exById[original.exerciseId] else { return original }
        var step = original
        for field in ["sets", "reps", "weight", "duration"] where !step.isSuggested(field) {
            step.confirmParameter(field)
        }
        let history = sets.filter { record in
            record.exerciseId == exercise.id && record.performedAt <= Date()
                && (record.reps.map { $0 > 0 && $0 <= 999 } ?? false)
                && (record.weight.map { $0.isFinite && $0 >= 0 && $0 <= 500 } ?? true)
        }.max { $0.performedAt < $1.performedAt }
        if exercise.category == .strength {
            if step.reps == nil || (step.isSuggested("reps") && step.parameterSuggestions?["reps"]?.source != .shared), step.setReps?.contains(where: { $0 != nil }) != true {
                let value = history?.reps ?? (exercise.mechanic == .isolation
                    ? settings.trainingGoal.defaultRepsForIsolation() : settings.trainingGoal.defaultRepsForCompound())
                step.reps = value
                step.markSuggested("reps", value: Double(value), source: history == nil ? .preference : .history,
                                   exerciseID: history?.exerciseId, recordID: history?.id, recordedAt: history?.performedAt)
            }
            if step.weight == nil || (step.isSuggested("weight") && step.parameterSuggestions?["weight"]?.source != .shared),
               step.setWeights?.contains(where: { $0 != nil }) != true {
                if let reference = referenceWeight(for: exercise, targetReps: step.reps, roughRecords: roughRecords),
                   ExerciseWeightReference.expectsLoad(exercise) || reference.kilograms > 0 {
                    step.weight = reference.kilograms
                    step.markSuggested("weight", value: reference.kilograms, source: reference.source,
                                       exerciseID: reference.sourceExerciseID, recordID: reference.recordID,
                                       recordedAt: reference.recordedAt, ruleID: reference.ruleID)
                } else if step.parameterSuggestions?["weight"]?.isCrossExerciseEstimate == true {
                    // Withdraw expired/revoked/inapplicable estimates; never clear manual targets.
                    step.weight = nil; step.confirmParameter("weight")
                }
            }
        } else if step.duration == nil || (step.isSuggested("duration") && step.parameterSuggestions?["duration"]?.source != .shared), step.setDurations?.contains(where: { $0 != nil }) != true {
            let last = sets.filter { $0.exerciseId == exercise.id && $0.performedAt <= Date()
                && ($0.duration ?? 0) > 0 }.max { $0.performedAt < $1.performedAt }
            step.duration = last?.duration ?? 30
            step.markSuggested("duration", value: Double(step.duration!), source: last == nil ? .preference : .history,
                               exerciseID: last?.exerciseId, recordID: last?.id, recordedAt: last?.performedAt)
        }
        CrossExerciseLoadReference.clearIfUnsupported(&step)
        if step.parameterSuggestions?["weight"]?.source == .roughEstimate,
           step.duration != nil || step.setReps?.contains(where: { $0 != nil }) == true {
            step.weight = nil; step.confirmParameter("weight")
        }
        return step
    }

    /// P0#5 修正: ✓ 落库时 SetRecord 直接取计划值, 力竭没做满的组记的是虚高的计划数 —
    /// 休息屏"刚才: 8 × 55 kg · 调整"入口用这个窄方法把刚落库那条改回真实值 (按 id 定位, 持久化).
    /// 只动 reps/weight/duration 三个可变字段, 不动 performedAt/planId (不是"重记一组").
    func updateSetRecord(id: String, reps: Int?, weight: Double?, duration: Int?, sixRMConfirmed: Bool? = nil) {
        guard let idx = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[idx].reps = reps
        sets[idx].weight = weight
        sets[idx].duration = duration
        if let confirmed = sixRMConfirmed {
            sets[idx].sixRMReference = confirmed && sets[idx].exerciseId == CrossExerciseLoadReference.anchorID
                && reps == 6 && (weight ?? 0) > 0 && weight?.isFinite == true
                ? SixRMReference(kilograms: weight!) : nil
        } else if !sets[idx].hasConfirmedSixRM {
            sets[idx].sixRMReference = nil
        }
        save()
    }

    /// A plan may be used repeatedly on the same day. Never discard by plan/day or elapsed time.
    func discardWorkout(_ session: TrainingSessionStore.Session, recordIDs: Set<String>) {
        sets.removeAll { recordIDs.contains($0.id) }
        let completionID = "\(session.planId)|\(session.startedAt.timeIntervalSince1970)"
        settings.workoutCompletions?.removeAll { $0.sessionID == completionID }
        // Commit removal before the player clears active-session.json, including immediate app exit.
        flushSave()
    }

    /// Playback undo removes only the record created by that transition.
    func removeSetRecord(id: String) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        sets.remove(at: index)
        save()
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

    /// 删本场该动作最近 count 条 SetRecord — 训练中删掉一个已做过组的动作时用,
    /// 否则记录成孤儿, 健身历史按原始记录数多算 (见 TrainingSessionStore.deleteStep).
    /// sets 是 newest-first (insert at 0), 从头扫即"最近的先删".
    func removeRecords(exerciseId: String, planId: String?, since: Date, count: Int) {
        guard count > 0 else { return }
        var removed = 0
        var idx = 0
        while removed < count, idx < sets.count {
            let r = sets[idx]
            if r.exerciseId == exerciseId && r.planId == planId && r.performedAt >= since {
                sets.remove(at: idx)
                removed += 1
            } else {
                idx += 1
            }
        }
        if removed > 0 { save() }
    }

    /// 记录新的一组 — 同时:
    ///   1. 把 plan.lastUsedAt 推进到这次的时间 (用于 pickTodayPlan 的 LRU 排序)
    ///   2. 更新 plan.updatedAt
    func recordSet(_ record: SetRecord) {
        // workout_day_first: 当这条 set 让"有训练记录的日历日"集合首次新增这一天时, 报一次
        // (drives 留存"returned" 信号). 用插入前后的 distinct-day count 判断, 无 PII.
        let beforeDays = completedWorkoutCount
        sets.insert(record, at: 0)
        let afterDays = completedWorkoutCount
        if afterDays > beforeDays {
            Analytics.shared.track("workout_day_first", ["distinct_day_count": .int(afterDays)])
        }
        if let pid = record.planId, let idx = plans.firstIndex(where: { $0.id == pid }) {
            plans[idx].lastUsedAt = record.performedAt
            plans[idx].updatedAt = record.performedAt
        }
        if settings.calendar.isDate(record.performedAt, inSameDayAs: Date()) { captureWellnessGoal(updateDiet: true) }
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
        Analytics.shared.track("review_prompt_offered")
        save()
        return true
    }

    /// 是否该在此刻请求一次通知权限 (召回提醒默认开, 这是首个权限入口) — 练满 2 次、还没问过、
    /// 且用户没在 Settings 里明确关掉. 命中即"消费"(置 flag + 存), 全生命周期只软问一次;
    /// 跟评分请求 (≥3 次) 错开里程碑, 不撞车. 被拒 → 开关弹回关, 不再纠缠.
    func shouldOfferReminderPrompt() -> Bool {
        guard !settings.hasOfferedReminderPrompt else { return false }
        guard settings.workoutRemindersEnabled else { return false }   // 用户已在设置里主动关掉 → 不打扰
        guard completedWorkoutCount >= 2 else { return false }
        settings.hasOfferedReminderPrompt = true
        Analytics.shared.track("reminder_prompt_offered")
        save()
        return true
    }

    /// 重排召回提醒 — 训练完 / app 进后台时调. 以最近一次训练为基, 开关关时只清除.
    /// sets 是 newest-first (recordSet insert at 0), 所以 sets.first = 最近一次.
    func rescheduleWorkoutReminders() {
        let last = sets.first?.performedAt
        let body = AppNotificationText.string("You're recovered — a quick session keeps your momentum going.")
        WorkoutReminderScheduler.shared.reschedule(enabled: settings.workoutRemindersEnabled, lastWorkout: last, body: body)
    }

    /// 今日推荐 plan — 恢复档位 + LRU + wantStrengthen 覆盖度.
    /// 把首屏肌肉恢复模型真正接进推荐: 主肌群还在疲劳的 plan 沉底, 全员恢复时退化成 LRU 轮转.
    var workoutRotation: WorkoutRotation {
        WorkoutRotation(plans: plans, completions: settings.workoutCompletions ?? [],
                        calendar: settings.calendar, now: Date())
    }

    func updateWorkoutCompletion(planID: String, startedAt: Date, completed: Bool, now: Date = Date()) {
        let sessionID = "\(planID)|\(startedAt.timeIntervalSince1970)"
        var records = settings.workoutCompletions ?? []
        if completed {
            guard plans.contains(where: { $0.id == planID }), !records.contains(where: { $0.sessionID == sessionID }) else { return }
            records.append(WorkoutCompletion(sessionID: sessionID, planID: planID, finishedAt: now))
        } else {
            guard records.contains(where: { $0.sessionID == sessionID }) else { return }
            records.removeAll { $0.sessionID == sessionID }
        }
        settings.workoutCompletions = records
        save()
    }

    var todayRecommendedPlan: Plan? {
        guard let id = workoutRotation.todayPlanID else { return nil }
        return plans.first { $0.id == id }
    }

    /// The home carousel and quick-start always use the same selection.
    var suggestedTodayPlan: Plan? {
        todayRecommendedPlan ?? (plans.isEmpty ? aiTodayPlan : nil)
    }

    /// 给定 exerciseId, 找最近一次的 set 记录. 用来在 PlanPlayer / PlanDetailSheet 显示
    /// "上次: 100kg × 8" — 兑现 plan 理念 2 "历史即计划".
    /// sets 按 performedAt 倒序存 (recordSet insert at 0), 所以 first(where:) 就是最新.
    func rememberWeight(_ kilograms: Double?, for exercise: Exercise) {
        guard let kilograms, kilograms.isFinite, kilograms >= 0, kilograms <= 500,
              ExerciseWeightReference.expectsLoad(exercise) else { return }
        var inputs = settings.exerciseWeightInputs ?? [:]
        var order = settings.exerciseWeightInputOrder ?? []
        if inputs[exercise.id] == nil { order.append(exercise.id) }
        inputs[exercise.id] = kilograms
        settings.exerciseWeightInputs = inputs
        settings.exerciseWeightInputOrder = order
        var confirmed = settings.confirmedExerciseWeightInputIDs ?? []
        if !confirmed.contains(exercise.id) { confirmed.append(exercise.id) }
        settings.confirmedExerciseWeightInputIDs = confirmed
        // Remember only this explicit input. Suggestions are resolved on new targets,
        // never propagated over saved plans or used as another exercise's evidence.
        save()
    }

    func referenceWeight(for exercise: Exercise, targetReps: Int? = nil, roughRecords: [SetRecord]? = nil) -> ExerciseWeightReference.Reference? {
        let own = ExerciseWeightReference.latest(for: exercise, records: sets, library: exById)
        if let own, let date = own.recordedAt, Date().timeIntervalSince(date) <= 14 * 86400 { return own }
        // A cache matching the old completed load is history, not a new target.
        // A distinct explicit input still blocks personal inference; neither cache is mutated.
        let remembered = settings.confirmedExerciseWeightInputIDs?.contains(exercise.id) == true
            ? settings.exerciseWeightInputs?[exercise.id] : nil
        if remembered == nil || remembered == own?.kilograms,
           let personal = PersonalExerciseLoadReference.reference(for: exercise, targetReps: targetReps, records: sets, library: exById) {
            return personal
        }
        if let own { return own }
        if settings.confirmedExerciseWeightInputIDs?.contains(exercise.id) == true,
           let value = settings.exerciseWeightInputs?[exercise.id], value.isFinite, value >= 0, value <= 500 {
            return .init(kilograms: value, sourceExerciseID: exercise.id, source: .userInput)
        }
        return CrossExerciseLoadReference.reference(for: exercise, targetReps: targetReps,
                                                     records: sets, settings: settings, library: exById)
            ?? RoughExerciseLoadReference.reference(for: exercise, targetReps: targetReps, records: roughRecords ?? sets)
    }

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
        Analytics.shared.track("routine_create_blank")
        save()  // 持久化变更
        return plan
    }

    /// 免费用户最多能 save 的 plan 数. Pro 无限.
    ///
    /// 3 → 5 (2026-08-15, 竞品调研): 品类里最受爱戴的 Hevy 免费给 4 个 routine, 被上百条 5★ 点名
    /// 夸 "generous"; Strong 的 3 个上限吃到 2★ "should be borderline illegal"。我们卡在 3 =
    /// 比最受欢迎的那个还少一个, 而放宽的边际成本是零 (routine 存本地, 不耗服务端)。
    /// 真正的付费理由是 AI 教练/深度图表/自创动作, 不是"能存几张"。
    static let freeSavedPlansLimit = FreeLimit.maxPlans

    /// 还能不能再 save plan — 免费上限见 freeSavedPlansLimit, Pro 无限.
    var canSaveMorePlans: Bool {
        settings.isPro || plans.count < Self.freeSavedPlansLimit
    }

    private func importedAdditions(_ incoming: [Plan]) -> [Plan] {
        var signatures = Set(plans.map { Self.planSignature(routinePlanDefaults($0)) })
        var identifiers = Set(plans.map(\.id))
        return incoming.map { routinePlanDefaults($0) }.filter {
            guard !identifiers.contains($0.id), signatures.insert(Self.planSignature($0)).inserted else { return false }
            identifiers.insert($0.id)
            return true
        }
    }

    func canSaveImportedPlans(_ incoming: [Plan]) -> Bool {
        let additions = importedAdditions(incoming)
        return additions.isEmpty || settings.isPro || plans.count + additions.count <= Self.freeSavedPlansLimit
    }

    /// Shared by QR, OCR and URL imports: a batch is accepted atomically.
    @discardableResult
    func saveImportedPlans(_ incoming: [Plan]) -> Bool {
        guard canSaveImportedPlans(incoming) else { return false }
        let additions = importedAdditions(incoming)
        plans.append(contentsOf: additions)
        if !additions.isEmpty { save() }
        return true
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
        savePlanReturningCopy(plan) != nil
    }

    /// savePlan 本体 — 返回已存副本 (Coach 的 savedIdMap 需要拿到副本 id 记映射, 见 saveCoachPlan).
    ///   - 已存在 → 返回命中的既有副本 (幂等);
    ///   - 撞免费上限 → nil (调用方弹 paywall).
    func savePlanReturningCopy(_ plan: Plan) -> Plan? {
        let plan = routinePlanDefaults(plan)
        let sig = Self.planSignature(plan)
        if let existing = plans.first(where: { Self.planSignature(routinePlanDefaults($0)) == sig }) { return existing }
        guard canSaveMorePlans else {
            // 撞免费上限 → 不保存 (调用方弹 paywall). 报一次 at-cap 的 save 尝试. 无 PII (来源枚举).
            Analytics.shared.track("routine_save", [
                "source": .string(plan.resolvedSource.rawValue),
                "at_free_cap": .bool(true),
            ])
            return nil
        }
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
            rationale: plan.rationale,
            constraints: plan.constraints, // Keep one-off equipment intent when the saved copy starts later.
            preservesExerciseVariants: plan.preservesExerciseVariants
        )
        plans.append(copy)
        Analytics.shared.track("routine_save", [
            "source": .string(copy.resolvedSource.rawValue),
            "at_free_cap": .bool(false),
        ])
        save()
        return copy
    }

    /// 书签开关的"取消保存" (Coach 设计文档 §2) — savePlan 的逆操作: 传入的是"来源卡"的 plan
    /// (生成卡 / browse 预览), 不是已存副本本身. 定位顺序: savedIdMap 反查 (副本改名后签名会
    /// 漂移, id 不会) → 签名匹配兜底. 命中即删 + 存盘 + analytics; 没命中静默 no-op.
    func unsavePlan(matching plan: Plan) {
        var idx: Int? = nil
        if let savedId = coachSession.savedIdMap[plan.id] {
            idx = plans.firstIndex(where: { $0.id == savedId })
        }
        if idx == nil {
            let sig = Self.planSignature(routinePlanDefaults(plan))
            idx = plans.firstIndex(where: { Self.planSignature(routinePlanDefaults($0)) == sig })
        }
        guard let idx else { return }
        let removed = plans.remove(at: idx)
        // 清掉指向该副本的映射 (可能是别的生成卡 id 指过来的, 按 value 过滤).
        coachSession.savedIdMap = coachSession.savedIdMap.filter { $0.value != removed.id }
        Analytics.shared.track("routine_unsave", [
            "source": .string(removed.resolvedSource.rawValue),
        ])
        save()
    }

    /// 这个(来源)plan 是否已经在"我的计划"里. 存进去的是新 id 的独立副本, 不能用 id 比 —
    /// 按 名字 + 动作序列 的内容签名匹配. 给 Tab 2 卡片"添加"按钮显示"已添加"态用 (响应式: plans 一变即更新).
    /// ⚠️ Coach 生成卡优先用 isCoachPlanSaved (savedIdMap 反查, 副本改名后不失灵), 这个只作签名兜底.
    func isPlanSaved(_ plan: Plan) -> Bool {
        let sig = Self.planSignature(routinePlanDefaults(plan))
        return plans.contains { Self.planSignature(routinePlanDefaults($0)) == sig }
    }

    private static func planSignature(_ plan: Plan) -> String {
        (plan.preservesExerciseVariants == true ? "exact-variants\u{1}" : "") + plan.name + "\u{1}" + plan.steps.map(\.exerciseId).joined(separator: ",")
    }

    /// planId → SHA256 前 8 位十六进制 — 给分析事件用. 稳定 (同 install 同 plan 同值) 但不可逆回标题,
    /// 故无 PII. 用 CryptoKit, 不引入依赖.
    static func hashedPlanId(_ planId: String) -> String {
        let digest = SHA256.hash(data: Data(planId.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()  // 4 字节 = 8 hex 字符
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
        // 今日 AI 卡 (aiTodayPlan) 不在 plans 里 — 之前这里 guard 直接 return, 从详情/长按删它
        // 全部空转 = "Today's Workout 删不掉" bug. 删除 = 清掉它 + 置 editedAt 当"今天动过"标记
        // (refreshAIWorkoutIfNeeded 当天不再自动重生成, 否则回个前台又长回来; 主动 Retry 不受限).
        if planId == aiTodayPlan?.id {
            aiTodayPlan = nil
            aiTodayPlanEditedAt = Date()
            Analytics.shared.track("routine_delete", ["source": .string("ai_today"), "age_days": .int(0)])
            save()
            return
        }
        guard let idx = plans.firstIndex(where: { $0.id == planId }) else { return }
        let plan = plans[idx]
        let ageDays = max(0, Int(Date().timeIntervalSince(plan.createdAt) / 86400))
        Analytics.shared.track("routine_delete", [
            "source": .string(plan.resolvedSource.rawValue),
            "age_days": .int(ageDays),
        ])
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
        let cal = settings.calendar
        settings.workoutCompletions?.removeAll {
            $0.planID == planId && cal.isDate($0.finishedAt, inSameDayAs: day)
        }
        sets.removeAll { rec in
            let recDay = cal.startOfDay(for: rec.performedAt)
            let recPid: String? = rec.planId
            // 比较 planId — nil ↔ nil 或者 string ↔ string
            return cal.isDate(recDay, inSameDayAs: day) && recPid == planId
        }
        save()
    }

    // MARK: - Favorites — 收藏的动作

    /// Resolve legacy image-folder aliases without rewriting the user's stored records.
    func isFavorite(_ exerciseId: String) -> Bool {
        canonicalFavoriteExerciseIDs.contains(exById[exerciseId]?.id ?? exerciseId)
    }

    /// Toggle the concrete exercise once, removing all legacy aliases when unpinning.
    func toggleFavorite(_ exerciseId: String) {
        let lookup = exById
        let canonicalID = lookup[exerciseId]?.id ?? exerciseId
        if isFavorite(canonicalID) {
            settings.favoriteExerciseIds.removeAll { (lookup[$0]?.id ?? $0) == canonicalID }
        } else {
            settings.favoriteExerciseIds.append(canonicalID)
        }
        save()
    }

    /// 把 exercises 列表按"收藏在前, 原顺序在后"重排.
    /// 在 favoriteExerciseIds 里的排在前面 (并保持 favorites 内部相对顺序);
    /// 不在的保持原顺序排后面. 给 ExerciseLibrary / Picker / QuickWorkout 等列表用.
    func sortByFavorites(_ exercises: [Exercise]) -> [Exercise] {
        guard !settings.favoriteExerciseIds.isEmpty else { return exercises }
        let favSet = canonicalFavoriteExerciseIDs
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
        // Background recommendations never trigger a consent prompt or send
        // personal data before the user has explicitly opted in.
        guard AIDataConsent.shared.isGranted else { return }
        // gate 只看代理是否配好 (Path B: 不再要求 aiWorkoutEnabled — 代理 server-side 配好就跑, 失败回落).
        guard AIWorkoutService.isConfigured else { return }
        // 引导首次生成还在飞 (弱网下过渡页 9s 兜底先落地) → 让路, 别并发双跑冲掉带 focusNote 的首次结果.
        // lastAIRefreshAt 挡不住这个 case — 它只在成功后才置位.
        if firstPlanGenerationInFlight { return }
        if let last = lastAIRefreshAt, Calendar.current.isDateInToday(last), aiTodayPlan != nil {
            return  // 今天已经成功生成过, skip
        }
        // P0#1-④: 用户今天手调过 AI 计划 (updatePlan / 全局同步置位) → 跳过自动重生成,
        // 不冲掉手调的重量. 删除今日 AI 卡也走这个标记 (aiTodayPlan=nil + editedAt=now) —
        // 不检查 aiTodayPlan != nil, 否则删掉的卡回个前台又自动长回来.
        // 用户主动点 Retry/Refresh 走 forceRefreshAIWorkout, 不受此限.
        if let edited = aiTodayPlanEditedAt, Calendar.current.isDateInToday(edited) {
            return
        }
        let payload = buildAIPayload()
        let plan: Plan? = try? await aiAccess.perform(kind: .singleWorkout, isPro: settings.isPro,
            automatic: true, valid: { $0?.steps.isEmpty == false }, summary: { $0?.name ?? "" }) {
                await AIWorkoutService.shared.generateToday(payload: payload, library: userLibrary,
                    maxExercises: settings.exercisesPerSession)
            }
        if let plan {
            aiTodayPlan = applyScience(to: plan)   // 科学化兜底: 复合优先 + 同 section ≤2 + slot-1 + push≥pull
            aiTodayPlanEditedAt = nil              // 新生成的还没被手调过 — 清脏标
            lastAIRefreshAt = Date()
            aiTodayFailed = false
        } else {
            aiTodayFailed = true   // 网络/服务失败 → Today 露提示 + fallback 推荐
        }
    }

    /// Reuse shared history suggestions for unknown targets; preserve supplied plan values.
    private func applyScience(to plan: Plan) -> Plan {
        var p = plan
        p.steps = DataStore.enforceScience(p.steps, exById: exById)
        p.steps = p.steps.map { step in
            var s = step
            s = suggestingMissingParameters(for: s)
            return s
        }
        let intent = LocalRoutineRules.parse(settings.coachMemory)
        if !intent.focusMuscles.isEmpty {
            p = LocalRoutineRules.apply(to: [p], intent: intent, settings: settings, exById: exById).first ?? p
        }
        return p
    }

    /// 强制重新生成 (用户主动点 "Refresh"/"Retry" 时调). 跳过同日 cache 检查.
    func forceRefreshAIWorkout() async {
        guard AIWorkoutService.isConfigured else { return }
        let payload = buildAIPayload()
        let plan: Plan? = try? await aiAccess.perform(kind: .singleWorkout, isPro: settings.isPro,
            capacity: settings.isPro || plans.count < Self.freeSavedPlansLimit, valid: { $0?.steps.isEmpty == false }, summary: { $0?.name ?? "" }) {
                await AIWorkoutService.shared.generateToday(payload: payload, library: userLibrary,
                    maxExercises: settings.exercisesPerSession)
            }
        if let plan {
            aiTodayPlan = applyScience(to: plan)
            aiTodayPlanEditedAt = nil   // 用户主动重生成 = 放弃之前的手调 — 清脏标
            lastAIRefreshAt = Date()
            aiTodayFailed = false
        } else {
            aiTodayFailed = true
        }
    }

    /// 引导确认后生成首份计划 (Path B 真 AI): 先种本地起步 routine 保证库非空, 再尝试真 AI 作为
    /// 今日推荐 (✨AI). 失败 → 静默回落到本地推荐 (aiTodayPlan 不设, Today 自己 fallback).
    /// - parameter userPrompt: 引导收尾一步的自由输入 (伤病/喜好/时长要求) — 作 focusNote 进
    ///   PRIORITY 行 + 定向检索 ("练上胸"这类词把对应动作带进目录). 同一段文字由 OnboardingScreen
    ///   confirm() 写进 coachMemory (COACH NOTES 块) — 双通道: 首份计划立即吃到 + 以后每次生成长期生效.
    func generateFirstPlanViaAI(userPrompt: String? = nil) async {
        seedStarterRoutines()                       // 2 条本地起步 (内部 guard plans.isEmpty)
        guard AIWorkoutService.isConfigured else { return }
        // in-flight 标记: 起飞置位, defer 保证任何路径 (成功/失败/提前 return 之外的 throw 演化) 都复位 —
        // 期间 refreshAIWorkoutIfNeeded 直接让路, 防止弱网下双跑覆盖带 focusNote 的首次结果.
        firstPlanGenerationInFlight = true
        defer { firstPlanGenerationInFlight = false }
        var payload = buildAIPayload()
        payload.focusNote = userPrompt
        let generated: Plan? = try? await aiAccess.perform(kind: .singleWorkout, isPro: settings.isPro,
            capacity: settings.isPro || plans.count < Self.freeSavedPlansLimit,
            valid: { $0?.steps.isEmpty == false }, summary: { $0?.name ?? "" }) {
                await AIWorkoutService.shared.generateToday(payload: payload, library: userLibrary,
                    maxExercises: settings.exercisesPerSession, surface: "onboarding")
            }
        if let plan = generated {
            aiTodayPlan = applyScience(to: plan)
            aiTodayPlanEditedAt = nil
            lastAIRefreshAt = Date()
            aiTodayFailed = false
        } else {
            aiTodayFailed = true
        }
        flushSave()
    }

    /// AI Routines tab "生成": 真 AI 一条 (✨AI, 排最前) + 本地 tuned 若干作为更多选择.
    /// 返回 (plans, 是否回落到纯本地). 失败/未配置 → 纯本地 + usedFallback=true.
    /// - parameter focusNote: optimize 建议卡传进来的本次侧重 (e.g. "bias the split toward legs"),
    ///   非 nil 时注进 prompt 的 PRIORITY 行, 让这批 routine 偏向修复诊断出的问题. 默认 nil = 普通生成.
    private struct AIPlanBatch: Codable { let plans: [Plan]; let usedFallback: Bool }

    func generateAIRoutines(focusNote: String? = nil, surface: String = "ai_segment",
                            taskKind: CoachTaskKind = .weeklyPlan, operationID: String = UUID().uuidString,
                            goalID: String? = nil, parentID: String? = nil) async -> (plans: [Plan], usedFallback: Bool) {
        let count = max(1, min(7, settings.weeklyTrainingDays))
        do {
            let result = try await aiAccess.perform(kind: taskKind, isPro: settings.isPro, operationID: operationID,
                goalID: goalID, parentID: parentID,
                capacity: settings.isPro || count <= max(0, Self.freeSavedPlansLimit - plans.count),
                valid: { !$0.usedFallback && !$0.plans.isEmpty && $0.plans.allSatisfy { !$0.steps.isEmpty } },
                summary: { $0.plans.map(\.name).joined(separator: " · ") }) {
                    let result = await generateAIRoutinesUnmetered(focusNote: focusNote, surface: surface)
                    return AIPlanBatch(plans: result.plans, usedFallback: result.usedFallback)
                }
            return (result.plans, result.usedFallback)
        } catch { aiAccess.notice = error.localizedDescription; return ([], true) }
    }

    private func generateAIRoutinesUnmetered(focusNote: String? = nil, surface: String = "ai_segment") async -> (plans: [Plan], usedFallback: Bool) {
        // 本地兜底 —— 模板池 → 裁剪 → 器械替换 → 重量折算 → enforceScience.
        // ⚠️ 再叠一层 LocalRoutineRules: 把用户这次打的字 (focusNote) 解析成意图 (多练哪块 /
        //    避开哪块 / 只用什么器械 / 多长时间) 应用上去. 大陆有相当一部分用户长期够不到 AI
        //    (workers.dev 和 vercel.app 都可能被 DNS 污染), 兜底不能对用户的要求装聋.
        //    解析不到任何关键词 → Intent 为空 → apply 原样返回, 行为跟以前完全一致.
        let localIntent = LocalRoutineRules.parse([settings.coachMemory, focusNote ?? ""].joined(separator: "\n"))
        let local = DataStore.markBuiltIn(LocalRoutineRules.apply(
            to: DataStore.tunedRecommendedPlans(
                forDays: settings.weeklyTrainingDays, settings: settings,
                exById: exById, sets: sets, now: Date()),
            intent: localIntent, settings: settings, exById: exById))
        guard AIWorkoutService.isConfigured else { return (local, true) }
        // 一次 LLM 调用产出多套真 AI routine (各带 rationale, 组成周分化) — 标签页每张都是真 AI,
        // 不再 [aiPlan] + local 混本地凑数计划. 套数严格等于每周训练天数（1...7），由响应校验约束。
        let count = max(1, min(7, settings.weeklyTrainingDays))
        var payload = buildAIPayload()
        payload.focusNote = focusNote
        if let aiPlans = await AIWorkoutService.shared.generateRoutines(
            payload: payload, library: userLibrary, count: count,
            maxExercises: settings.exercisesPerSession, surface: surface), !aiPlans.isEmpty {
            // 科学化兜底: 每套真 AI routine 也过 enforceScience (复合优先 + 同 section ≤2 + slot-1 + push≥pull).
            var out = aiPlans.map { applyScience(to: $0) }
            // ⚠️ **约束硬过滤 —— 这一步以前只作用于本地兜底, 是"我说了它不听"的根源.**
            //    prompt 里写了"只用哑铃"不等于模型会照做 (竞品调研: 6 个不同 app 的用户在骂同一件事).
            //    所以拿到 LLM 结果后再过一遍同一套规则: 器械不符的替换掉、明说不练的剔掉、
            //    超时长的裁掉. 模型听话 → 这一步什么都不改; 模型不听话 → 用户依然拿到他要的东西.
            out = LocalRoutineRules.apply(to: out, intent: localIntent, settings: settings, exById: exById)
            out = attachConstraints(out, intent: localIntent)
            return (out, false)
        }
        return (attachConstraints(local, intent: localIntent), true)   // 真 AI 失败 → 回落本地模板
    }

    /// 把这一轮的约束钉在每份计划上 —— 用户在计划页上能核对 app 有没有说到做到.
    /// 空约束不写 nil 之外的东西 (老计划/无约束计划照旧不显示凭据条).
    private func attachConstraints(_ plans: [Plan], intent: LocalRoutineRules.Intent) -> [Plan] {
        let cs = LocalRoutineRules.constraints(from: intent)
        return plans.map { original in
            var p = original
            if !cs.isEmpty { p.constraints = cs }
            return routinePlanDefaults(p)
        }
    }

    // MARK: - 数据驱动优化建议 (Pro feature ②)
    //
    // 用户练了一段后, Saved routines 页顶部浮一张"优化建议"卡. routineSuggestion() 从最近 ~3 周的
    // sets 里诊断出 SINGLE 最该处理的问题 (优先级: 落后肌群 > 主项停滞 > 出勤下滑), 给一句可执行的
    // focusNote —— 用户点"用 AI 优化"时把 focusNote 注进 generateAIRoutines 重生成一批偏向修复的 routine.
    // 数据不足 (<~2 周) → nil, 不乱给建议.

    /// 单条优化建议 — title/detail 露在卡上, focusNote 注进 AI prompt 的 PRIORITY 行.
    struct RoutineSuggestion: Identifiable, Hashable {
        let id: String        // 诊断类型 key (lagging/stall/adherence) — 同问题不重复弹
        let title: String     // e.g. "Legs are undertrained"
        let detail: String    // 一句话说明诊断依据
        let focusNote: String // Ordinary workout evidence only; HealthKit data stays local.
        var reportRecordIDs: [String]? = nil
        var containsHealthEvidence = false
    }

    /// 诊断当前训练数据, 返回最该处理的一条建议; 数据不足或一切正常 → nil.
    /// 只读 sets, 不改任何状态.
    private func observedWorkoutSuggestion() -> RoutineSuggestion? {
        guard let latest = sets.filter({ $0.performedAt <= Date() && $0.performedAt >= Date().addingTimeInterval(-7 * 86400) })
            .max(by: { $0.performedAt < $1.performedAt }), let key = latest.workoutSessionID else { return nil }
        let records = sets.filter { $0.workoutSessionID == key }.sorted { $0.performedAt < $1.performedAt }
        guard records.count >= 3 else { return nil }
        var heartPolicy = WorkoutHeartAlertPolicy()
        let samples = records.flatMap { WorkoutHeartLocalStore.shared.samples(for: $0) }.sorted { $0.date < $1.date }
        let hadReminder = samples.contains { sample in
            heartPolicy.observe(bpm: sample.bpm, date: sample.date, limit: sample.reminderLimit, now: sample.date)
        }
        let pacingIssue = Dictionary(grouping: records, by: \.exerciseId).values.contains { group in
            guard group.count >= 3, let first = group.first, let last = group.last,
                  let startReps = first.reps, startReps > 0, let endReps = last.reps,
                  let startWeight = first.weight, let endWeight = last.weight,
                  abs(startWeight - endWeight) <= max(0.5, startWeight * 0.025),
                  Double(endReps) <= Double(startReps) * 0.8 else { return false }
            let rests = group.compactMap(\.restBeforeSeconds)
            return rests.count >= 2 && rests.reduce(0, +) / Double(rests.count) < Double(settings.defaultRestSeconds) * 0.75
        }
        guard hadReminder || pacingIssue else { return nil }
        let report = WorkoutTimelineReport(records: records)
        return RoutineSuggestion(id: "workout-recovery-\(key)",
            title: NSLocalizedString("Allow more recovery", comment: ""),
            detail: NSLocalizedString(hadReminder ? "Your readings stayed above your reminder limit. Review this workout before increasing intensity."
                : "Your reps fell while rests were short. Try more recovery between sets.", comment: ""),
            focusNote: "Review my rest and logged training workload for recovery before increasing intensity. " + report.coachEvidence,
            reportRecordIDs: records.map(\.id), containsHealthEvidence: hadReminder)
    }

    func routineSuggestion() -> RoutineSuggestion? {
        if let observed = observedWorkoutSuggestion() { return observed }
        let cal = Calendar.current
        let now = Date()
        let win3w = now.addingTimeInterval(-21 * 86400)
        let recent = sets.filter { $0.performedAt >= win3w }
        // 数据不足 (<2 周覆盖 或 太少组) → 不建议. 用"最早一条记录距今"估覆盖周数.
        guard let earliest = sets.map(\.performedAt).min(),
              now.timeIntervalSince(earliest) >= 14 * 86400,
              recent.count >= 6 else { return nil }

        // ── 优先级 1: 落后肌群 — 按 6 大区统计最近 3 周的"工作组"数, 某练过的区远低于最高区 (≤40%) → 建议偏向它.
        var sectionSets: [MuscleGroup: Int] = [:]
        for rec in recent {
            guard let ex = exById[rec.exerciseId],
                  let sec = ex.primaryMuscles.first?.section else { continue }
            sectionSets[sec, default: 0] += 1
        }
        let majors: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]
        if let topCount = sectionSets.values.max(), topCount >= 6 {
            // 找"练过但远低于最高"的区 (≤40% of max); 多个时取组数最少的那个 = 最落后.
            let lagging = majors
                .filter { (sectionSets[$0] ?? 0) > 0 && Double(sectionSets[$0] ?? 0) <= 0.4 * Double(topCount) }
                .min { (sectionSets[$0] ?? 0) < (sectionSets[$1] ?? 0) }
            // 也抓"完全没练过的大区" (deadliest gap), 优先级比"偏低"更高.
            let missing = majors.first { (sectionSets[$0] ?? 0) == 0 }
            if let sec = missing ?? lagging {
                let name = sec.displayName
                let lowered = name.lowercased()
                return RoutineSuggestion(
                    id: "lagging-\(sec.rawValue)",
                    title: String(format: NSLocalizedString("%@ are undertrained", comment: "optimize card title — lagging muscle"), name),
                    detail: String(format: NSLocalizedString("You've done far fewer %@ sets than your top muscle group over the last 3 weeks.", comment: "optimize card detail — lagging muscle"), lowered),
                    focusNote: "the user has been under-training their \(lowered.isEmpty ? name : lowered); bias the weekly split toward \(lowered) with extra volume and earlier slots"
                )
            }
        }

        // ── 优先级 2: 主项停滞 — 最常练的负重动作, 逐次 session 的 e1RM 在最近 ~4 次平/降 → 建议变化主项/调容量.
        if let stall = stalledLiftSuggestion(in: recent) { return stall }

        // ── 优先级 3: 出勤下滑 — 最近 3 周每周不同训练日 < 目标-1 → 建议更短可持续的分化.
        let weeks = max(1, Int(ceil(now.timeIntervalSince(max(earliest, win3w)) / (7 * 86400))))
        let distinctDays = Set(recent.map { cal.startOfDay(for: $0.performedAt) }).count
        let perWeek = Double(distinctDays) / Double(weeks)
        if perWeek < Double(settings.weeklyTrainingDays) - 1 {
            return RoutineSuggestion(
                id: "adherence",
                title: NSLocalizedString("Fewer sessions lately", comment: "optimize card title — low adherence"),
                detail: String(format: NSLocalizedString("You're averaging about %d sessions a week, below your %d-day goal.", comment: "optimize card detail — low adherence"), Int(perWeek.rounded()), settings.weeklyTrainingDays),
                focusNote: "the user has been training fewer days than planned; offer a shorter, more sustainable split that fits about \(Int(perWeek.rounded()) + 1) focused sessions a week"
            )
        }

        return nil
    }

    // MARK: - AI Insight Summary (§2 / §3 / §5)

    /// AI 教练小结所需的可否生成阈值 — 复用 routineSuggestion() 同一守卫 (≥2 周 + ≥6 组).
    /// 达不到 → 卡显示 "Insufficient data" 态, 不调 LLM.
    var summaryMinDataMet: Bool {
        guard let first = sets.map(\.performedAt).min(), Date().timeIntervalSince(first) >= 14 * 86400 else { return false }
        return sets.filter { $0.performedAt >= Date().addingTimeInterval(-21 * 86400) }.count >= 6
    }

    /// 组装发给 Worker 的确定性 payload (§2) — 全部数字来自既有 helper, 无 PII.
    /// 这里内联复刻 InsightsChartsView 的各私有 helper 计算 (它们 private 在 View 里),
    /// 只读 sets / exById / settings, 结果与卡片显示一致.
    func buildSummaryPayload() -> AISummaryPayload {
        let cal = settings.calendar
        let now = Date()
        let majors: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]

        // ── profile (从 buildAIPayload 的 profile 子集, 去身份) ──
        let kind = settings.trainingGoalKind
        let goalEnum: String = {
            switch kind.loading {
            case .strength: return "strength"
            case .hypertrophy: return "hypertrophy"
            case .endurance: return "endurance"
            }
        }()
        let equipmentEnum = settings.availableEquipment.isEmpty ? "full_gym" : "limited"
        let ageBand: String = {
            guard let a = settings.age else { return "unknown" }
            switch a {
            case ..<18: return "under-18"
            case 18...24: return "18-24"
            case 25...34: return "25-34"
            case 35...44: return "35-44"
            case 45...54: return "45-54"
            default: return "55+"
            }
        }()
        let profile = AISummaryPayload.Profile(
            goal: goalEnum,
            daysPerWeekGoal: settings.weeklyTrainingDays,
            equipment: equipmentEnum,
            ageBand: ageBand
        )

        // ── signal (weeksOfHistory / sessions14d / thin) ──
        let earliest = sets.map(\.performedAt).min()
        let weeksOfHistory = earliest.map { max(1, Int(ceil(now.timeIntervalSince($0) / (7 * 86400)))) } ?? 0
        let win14 = now.addingTimeInterval(-14 * 86400)
        let sessions14d = Set(sets.filter { $0.performedAt >= win14 }.map { cal.startOfDay(for: $0.performedAt) }).count
        let thin = sessions14d < 3

        // ── trend (weekly volume, WoW %, adherence) ──
        let volume8wk = summaryWeeklyVolumeKg()
        let wowPct = summaryWeekVolumeDeltaPct()
        let trendEnum = summaryVolumeTrend(volume8wk)
        let adherence = summaryConsistencyScore()
        let trend = AISummaryPayload.Trend(
            volumeWoWPct: wowPct,
            volume8wkKg: volume8wk,
            trend: trendEnum,
            adherencePct: adherence
        )

        // ── topLift (name + e1RM now vs ~4wk ago) ──
        let topLift = summaryTopLift()

        // ── muscles (7d sets per section + MEV/MAV band + freq) ──
        let cutoff7 = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: now) ?? now)
        var sets7d: [MuscleGroup: Int] = [:]
        for s in sets where s.performedAt >= cutoff7 {
            guard let ex = exById[s.exerciseId], let sec = ex.primaryMuscles.first?.section else { continue }
            sets7d[sec, default: 0] += 1
        }
        let freq = summaryFrequencyPerSection()
        let counts = majors.map { sets7d[$0] ?? 0 }
        let maxC = counts.max() ?? 0
        let minC = counts.min() ?? 0
        let muscles: [AISummaryPayload.Muscle] = majors.map { sec in
            let n = sets7d[sec] ?? 0
            let band = n < DataStore.summaryMEV ? "underMEV" : (n > DataStore.summaryMAV ? "overMAV" : "inBand")
            return AISummaryPayload.Muscle(section: sec.rawValue, sets7d: n, band: band, daysPerWeek: freq[sec] ?? 0)
        }
        // lagging = 练过但最少的区 (跟 weeklySetsPerSection isLagging 同判据).
        let laggingSec = majors.first { sec in
            let n = sets7d[sec] ?? 0
            return maxC > 0 && n == minC && minC < maxC
        }

        // ── recentPRs (≤3, daysAgo) ──
        let prs = summaryRecentPRs(now: now)

        // ── diagnosis (routineSuggestion 预烘) ──
        let diag = routineSuggestion().map {
            AISummaryPayload.Diagnosis(title: $0.title,
                detail: $0.containsHealthEvidence ? $0.focusNote : $0.detail, focusNote: $0.focusNote)
        }

        return AISummaryPayload(
            profile: profile,
            signal: AISummaryPayload.Signal(weeksOfHistory: weeksOfHistory, sessions14d: sessions14d, thin: thin),
            trend: trend,
            topLift: topLift,
            muscles: muscles,
            lagging: laggingSec?.rawValue,
            recentPRs: prs,
            diagnosis: diag
        )
    }

    // MEV/MAV 科学落点 — 跟 InsightsChartsView 保持一致 (RP/Israetel).
    private static let summaryMEV = 10
    private static let summaryMAV = 20

    /// 近 8 周容量序列 (周起始日 + kg) — 分享卡 (InsightShareCard) 的迷你柱状图直读.
    /// 跟 summaryWeeklyVolumeKg() 同源同口径 (它就是本序列取整): Σ weight×reps, 缺的周补 0 → 柱形连续.
    func summaryWeeklyVolumeSeries() -> [(week: Date, kg: Double)] {
        let cal = settings.calendar
        var byWeek: [Date: Double] = [:]
        for s in sets {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.performedAt)
            guard let wk = cal.date(from: comps) else { continue }
            byWeek[wk, default: 0] += w * Double(r)
        }
        let now = Date()
        let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        var out: [(week: Date, kg: Double)] = []
        for back in stride(from: 7, through: 0, by: -1) {
            guard let wk = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { continue }
            out.append((week: wk, kg: byWeek[wk] ?? 0))
        }
        return out
    }

    /// 近 8 周容量 (Σ weight×reps, kg 取整), 连续补 0 — 复刻 weeklyVolume().
    private func summaryWeeklyVolumeKg() -> [Int] {
        summaryWeeklyVolumeSeries().map { Int($0.kg.rounded()) }
    }

    /// 本周 vs 上周容量 % — 复刻 weekDeltas().volume; 无对比 → nil.
    private func summaryWeekVolumeDeltaPct() -> Int? {
        let cal = settings.calendar
        var volByWeek: [Date: Double] = [:]
        for s in sets {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.performedAt)
            guard let wk = cal.date(from: comps) else { continue }
            volByWeek[wk, default: 0] += w * Double(r)
        }
        let now = Date()
        guard let thisWk = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let lastWk = cal.date(byAdding: .weekOfYear, value: -1, to: thisWk) else { return nil }
        let cur = volByWeek[thisWk] ?? 0
        let prev = volByWeek[lastWk] ?? 0
        guard prev > 0 else { return nil }
        return Int(((cur - prev) / prev * 100).rounded())
    }

    /// 容量趋势枚举 — 最近 3 周均值 vs 前 3 周均值.
    private func summaryVolumeTrend(_ weekly: [Int]) -> String {
        guard weekly.count >= 4 else { return "flat" }
        let recent = weekly.suffix(3)
        let prior = weekly.prefix(max(1, weekly.count - 3)).suffix(3)
        let rAvg = Double(recent.reduce(0, +)) / Double(recent.count)
        let pAvg = Double(prior.reduce(0, +)) / Double(max(1, prior.count))
        guard pAvg > 0 else { return rAvg > 0 ? "ramping" : "flat" }
        let ratio = rAvg / pAvg
        if ratio >= 1.1 { return "ramping" }
        if ratio <= 0.9 { return "dropping" }
        return "flat"
    }

    /// 头号动作 (weighted set 最多) + 按天最佳估算 1RM 序列 (Epley, kg) — 分享卡的迷你折线图直读.
    /// summaryTopLift() 取本序列端点, 保证分享图跟 AI 小结 payload 同源同口径.
    func summaryTopLiftSeries() -> (name: String?, series: [(date: Date, e1rmKg: Double)]) {
        var countByEx: [String: Int] = [:]
        for s in sets where (s.weight ?? 0) > 0 && (s.reps ?? 0) > 0 {
            countByEx[s.exerciseId, default: 0] += 1
        }
        guard let topId = countByEx.max(by: { $0.value < $1.value })?.key else { return (nil, []) }
        let name = exById[topId]?.name ?? sets.first { $0.exerciseId == topId }?.exerciseName ?? topId
        let cal = Calendar.current
        var bestByDay: [Date: Double] = [:]
        for s in sets where s.exerciseId == topId {
            guard let w = s.weight, let r = s.reps, w > 0, r > 0 else { continue }
            let e1rm = w * (1 + Double(r) / 30)
            let day = cal.startOfDay(for: s.performedAt)
            bestByDay[day] = max(bestByDay[day] ?? 0, e1rm)
        }
        let series = bestByDay.sorted { $0.key < $1.key }.map { (date: $0.key, e1rmKg: $0.value) }
        return (name, series)
    }

    /// 头号动作 + e1RM 现在 vs ~4 周前 — 取 summaryTopLiftSeries() 端点.
    private func summaryTopLift() -> AISummaryPayload.TopLift? {
        let lift = summaryTopLiftSeries()
        guard let name = lift.name, let last = lift.series.last else { return nil }
        let nowE = last.e1rmKg
        // ~4 周前的最近一天最佳 e1RM (没有则退回序列首点).
        let fourWkAgo = Date().addingTimeInterval(-28 * 86400)
        let past = lift.series.last(where: { $0.date <= fourWkAgo })?.e1rmKg ?? lift.series.first?.e1rmKg ?? nowE
        let nowKg = Int(nowE.rounded())
        let pastKg = Int(past.rounded())
        let trend = nowKg > pastKg ? "up" : (nowKg < pastKg ? "down" : "flat")
        return AISummaryPayload.TopLift(name: name, e1rmNowKg: nowKg, e1rm4wkKg: pastKg, trend: trend)
    }

    /// 各大区最近 4 周平均每周命中天数 — 复刻 trainingFrequencyRows().
    private func summaryFrequencyPerSection() -> [MuscleGroup: Double] {
        let cal = settings.calendar
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -27, to: Date()) ?? Date())
        var daysBySection: [MuscleGroup: Set<Date>] = [:]
        for s in sets where s.performedAt >= cutoff {
            guard let ex = exById[s.exerciseId] else { continue }
            let day = cal.startOfDay(for: s.performedAt)
            var seen = Set<MuscleGroup>()
            for m in ex.muscleGroups {
                guard let sec = m.section, seen.insert(sec).inserted else { continue }
                daysBySection[sec, default: []].insert(day)
            }
        }
        var out: [MuscleGroup: Double] = [:]
        for sec in [MuscleGroup.chest, .back, .shoulders, .arms, .core, .legs] {
            let d = Double(daysBySection[sec]?.count ?? 0)
            out[sec] = (d / 4.0 * 10).rounded() / 10
        }
        return out
    }

    /// 一致性分 (近 8 周达标周占比) — 复刻 consistencyScore().
    private func summaryConsistencyScore() -> Int {
        let cal = settings.calendar
        let goal = max(1, settings.weeklyTrainingDays)
        var days: Set<Date> = []
        for s in sets { days.insert(cal.startOfDay(for: s.performedAt)) }
        guard let thisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return 0 }
        func trainedDays(inWeekStarting weekStart: Date) -> Int {
            let weekDays: Set<Date> = Set((0..<7).compactMap {
                cal.date(byAdding: .day, value: $0, to: weekStart).map { cal.startOfDay(for: $0) }
            })
            return days.intersection(weekDays).count
        }
        var hit = 0, considered = 0
        for back in 0..<8 {
            guard let wkStart = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { continue }
            let td = trainedDays(inWeekStarting: wkStart)
            if td > 0 || back == 0 { considered += 1 }
            if td >= goal { hit += 1 }
        }
        guard considered > 0 else { return 0 }
        return Int((Double(hit) / Double(considered) * 100).rounded())
    }

    /// 最近 ≤3 条 PR + daysAgo — 复刻 prTimeline() 取 top 3.
    private func summaryRecentPRs(now: Date) -> [AISummaryPayload.PR] {
        let cal = Calendar.current
        return sets
            .filter { isPR($0) }
            .compactMap { rec -> (Date, String)? in
                guard let w = rec.weight, w > 0, let r = rec.reps, r > 0 else { return nil }
                let name = exById[rec.exerciseId]?.displayName ?? rec.exerciseName
                return (rec.performedAt, name)
            }
            .sorted { $0.0 > $1.0 }
            .prefix(3)
            .map { (date, name) in
                let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0)
                return AISummaryPayload.PR(exercise: name, daysAgo: days)
            }
    }

    /// payload 材料字段的粗粒度 hash (§5) — 变了才有资格重生成. 刻意粗 (band/趋势枚举/e1RM 取整/
    /// adherence 分桶), 让"多一个热身组"这种抖动不触发重生成.
    func summaryDataHash() -> String {
        let p = buildSummaryPayload()
        var parts: [String] = []
        parts.append("g:\(p.profile.goal)")
        parts.append("wow:\((p.trend.volumeWoWPct ?? 0) / 5)")   // 5% 桶
        parts.append("vt:\(p.trend.trend)")
        parts.append("adh:\(p.trend.adherencePct / 10)")          // 10% 桶
        if let t = p.topLift { parts.append("tl:\(t.name):\(t.e1rmNowKg / 2):\(t.trend)") } // 2kg 桶
        for m in p.muscles { parts.append("m:\(m.section):\(m.band)") }
        parts.append("lag:\(p.lagging ?? "-")")
        parts.append("diag:\(p.diagnosis?.focusNote ?? "-")")
        return String(parts.joined(separator: "|").hashValue)
    }

    /// 生成 AI 小结 — 调 service, 写缓存; 失败 (AISummaryError) 回落用 routineSuggestion() 拼的本地小结.
    /// 达不到 min-data 阈值 → 不调 LLM, 返回 nil (卡显示 insufficient 态).
    /// - returns: 生成/回落的 AISummary; 阈值不足时 nil.
    @discardableResult
    func generateSummary() async -> AISummary? {
        guard summaryMinDataMet else { return nil }
        let payload = buildSummaryPayload()
        let hash = summaryDataHash()
        do {
            let summary = try await aiAccess.perform(kind: .trainingReview, isPro: settings.isPro,
                valid: { !$0.tldr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, summary: { $0.tldr }) {
                    try await AIWorkoutService.shared.summarizeTraining(payload: payload)
                }
            writeSummaryCache(summary, hash: hash)
            return summary
        } catch let error as DeviceAIQuotaError {
            aiAccess.notice = error.localizedDescription
            return cachedSummary // Quota denial is not a new generated or local "AI" success.
        } catch {
            // 任何 AISummaryError → 确定性本地回落 (never 空卡; apply 路径仍可用).
            let fallback = localSummaryFallback()
            writeSummaryCache(fallback, hash: hash)
            return fallback
        }
    }

    /// 确定性本地小结 — tldr = 诊断 detail, 一条 regenerate_routines 建议 (focusNote 来自诊断).
    /// 无诊断时给个中性观察. 跟 generateAIRoutines 的 tunedRecommendedPlans 回落同哲学.
    func localSummaryFallback() -> AISummary {
        if let s = routineSuggestion() {
            let safeDetail = s.containsHealthEvidence ? NSLocalizedString("Review your logged workload and rest before increasing intensity.", comment: "") : s.detail
            return AISummary(
                tldr: safeDetail,
                recommendations: [
                    AIRecommendation(
                        id: "local-\(s.id)",
                        title: s.title,
                        detail: safeDetail,
                        action: .regenerateRoutines(focusNote: s.focusNote)
                    )
                ]
            )
        }
        return AISummary(
            tldr: NSLocalizedString("Keep logging your sessions — your coach summary sharpens with more data.", comment: "AI summary neutral fallback tldr"),
            recommendations: []
        )
    }

    /// 缓存已解析的 AISummary + 材料 hash + 时间戳到 settings, 落库.
    private func writeSummaryCache(_ summary: AISummary, hash: String) {
        if let data = try? JSONEncoder().encode(summary), let json = String(data: data, encoding: .utf8) {
            settings.aiSummaryCacheJSON = json
        }
        settings.aiSummaryDataHash = hash
        settings.aiSummaryGeneratedAt = Date()
        save()
    }

    /// 读缓存里的 AISummary (nil = 没有/解码失败).
    var cachedSummary: AISummary? {
        guard let json = settings.aiSummaryCacheJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AISummary.self, from: data)
    }

    /// 分享卡 (InsightShareCard) 的 4 个头条数字 — 全部复用 summary* 私有 helper,
    /// 跟 buildSummaryPayload() 同源同口径 (卡片从不自己算数, 规则见 AISummary.swift 头注).
    func summaryKeyStats() -> SummaryKeyStats {
        let top = summaryTopLift()
        return SummaryKeyStats(
            volumeWoWPct: summaryWeekVolumeDeltaPct(),
            weeklyVolumeKg: summaryWeeklyVolumeKg().last ?? 0,
            topLiftName: top?.name,
            topLiftE1rmKg: top?.e1rmNowKg,
            adherencePct: summaryConsistencyScore()
        )
    }

    /// 是否该在开屏时后台重生成 (§5): data-hash 变了 且 (≥3 新 session 或 ≥7 天). 无缓存但阈值达到 → true.
    func shouldRegenerateSummary() -> Bool {
        guard summaryMinDataMet else { return false }
        guard let lastHash = settings.aiSummaryDataHash, let lastAt = settings.aiSummaryGeneratedAt else {
            return true   // 冷启动: 有数据没缓存 → 生成一次
        }
        guard summaryDataHash() != lastHash else { return false }   // 材料没变 → 不动
        let daysElapsed = Date().timeIntervalSince(lastAt) / 86400
        if daysElapsed >= 7 { return true }
        let newSessions = Set(sets.filter { $0.performedAt > lastAt }.map { Calendar.current.startOfDay(for: $0.performedAt) }).count
        return newSessions >= 3
    }

    /// 主项停滞诊断 — 取最近 3 周内组数最多的负重动作, 按 session (day) 聚合每天的最佳 e1RM,
    /// 若 ≥3 个 session 且最近 ~4 次 e1RM 没有进步 (最后一次 <= 这串里最高的 99%) → 判定停滞.
    private func stalledLiftSuggestion(in recent: [SetRecord]) -> RoutineSuggestion? {
        // 只看有 weight+reps 的负重动作.
        let weighted = recent.filter { ($0.weight ?? 0) > 0 && ($0.reps ?? 0) > 0 }
        guard !weighted.isEmpty else { return nil }
        var byEx: [String: [SetRecord]] = [:]
        for r in weighted { byEx[r.exerciseId, default: []].append(r) }
        guard let (exId, recs) = byEx.max(by: { $0.value.count < $1.value.count }),
              recs.count >= 6 else { return nil }

        // 按训练日聚合, 取当天最佳 e1RM (Epley).
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for r in recs {
            guard let w = r.weight, let reps = r.reps else { continue }
            let e1rm = w * (1 + Double(reps) / 30.0)
            let day = cal.startOfDay(for: r.performedAt)
            byDay[day] = max(byDay[day] ?? 0, e1rm)
        }
        let series = byDay.sorted { $0.key < $1.key }.map(\.value)
        guard series.count >= 3 else { return nil }
        let window = Array(series.suffix(4))
        guard let peak = window.max(), let last = window.last, peak > 0 else { return nil }
        // 最近一次没超过窗口峰值 (留 1% 容差) → 视为平/降.
        guard last <= peak * 0.99 else { return nil }

        let name = exById[exId]?.displayName ?? NSLocalizedString("Your main lift", comment: "optimize card — generic lift name")
        return RoutineSuggestion(
            id: "stall-\(exId)",
            title: String(format: NSLocalizedString("%@ has stalled", comment: "optimize card title — stalled lift"), name),
            detail: String(format: NSLocalizedString("Your estimated 1RM on %@ hasn't moved over your last few sessions.", comment: "optimize card detail — stalled lift"), name),
            focusNote: "the user's \(name) has plateaued; vary the main lift (different angle/variation) and adjust volume or intensity to break the stall"
        )
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

        // P0#1-②: 近 14 天每个练过的动作附"最佳组" ("Bench Press: 80kg×8") — 之前 recentHistory 只有
        // 肌群+组数, 不含任何 weight/reps, LLM 只能盲猜负重. e1RM (Epley) 最高的那组 = 最佳组;
        // 上限 20 条防 prompt 爆, 超了按 e1RM 高的优先留 (大项负重信息量最大).
        var bestByExercise: [String: SetRecord] = [:]
        func e1rm(_ rec: SetRecord) -> Double {
            guard let w = rec.weight, w > 0, let r = rec.reps, r > 0 else { return 0 }
            return w * (1 + Double(r) / 30.0)
        }
        for rec in sets where rec.performedAt >= cutoff && e1rm(rec) > 0 {
            if let cur = bestByExercise[rec.exerciseId], e1rm(cur) >= e1rm(rec) { continue }
            bestByExercise[rec.exerciseId] = rec
        }
        let bestSets: [String] = bestByExercise.values
            .sorted { e1rm($0) > e1rm($1) }
            .prefix(20)
            .map { rec in
                // 名字优先库内 canonical 英文名 — 跟 prompt 的 AVAILABLE EXERCISES 目录同一词汇表.
                let name = exById[rec.exerciseId]?.name ?? rec.exerciseName
                return "\(name): \(String(format: "%g", rec.weight ?? 0))kg×\(rec.reps ?? 0)"
            }

        // 目标驱动的 rep/sets/rest band — rep 中心值仍走既有 TrainingGoal 表 (复合 5/8/15, 孤立 8/12/18),
        // 在中心值上下做一个小区间给 LLM 留发挥空间 (compound -2..+2, isolation -2..+3, 下限夹到 1).
        let kind = settings.trainingGoalKind
        let loading = kind.loading
        let repC = loading.defaultRepsForCompound()
        let repI = loading.defaultRepsForIsolation()
        let setsBase = max(1, settings.defaultSetsPerExercise)

        return AIPayload(
            gender: settings.gender?.rawValue,
            age: settings.age,
            weightKg: settings.weightForAI,
            daysPerWeek: settings.weeklyTrainingDays,
            wantStrengthen: settings.wantStrengthen.map { $0.displayName },
            recentHistory: history,
            recentBestSets: bestSets,
            todayDateLabel: df.string(from: Date()),
            goalLabel: kind.displayName,
            goalRepCompound: max(1, repC - 2),
            goalRepCompoundHi: repC + 2,
            goalRepIso: max(1, repI - 2),
            goalRepIsoHi: repI + 3,
            goalSetsLo: max(1, setsBase - 1),
            goalSetsHi: setsBase + 1,
            goalRest: kind.recommendedRestSeconds(),
            goalKind: kind,
            equipment: EquipmentCategory.allCases
                .filter { settings.availableEquipment.contains($0.rawValue) }
                .map { $0.displayName },
            selectionEquipment: settings.availableEquipment,
            selectionFavoriteIDs: canonicalFavoriteExerciseIDs,
            selectionRecentIDs: Array(recentExerciseIDs.prefix(40)),
            // 教练记忆 — 空白时传 nil (prompt 不注入这块). prompt 侧再做长度截断.
            coachMemory: {
                let trimmed = settings.coachMemory.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }(),
            trainingWeekdays: settings.trainingWeekdays ?? [],
            trainingSessionMinutes: settings.trainingSessionMinutes,
            trainingEnvironment: settings.trainingEnvironment
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

extension DataStore {
    func deleteMeal(mealID: String, on day: Date) {
        let records = settings.mealCheckIns ?? []
        let removed = records.filter { $0.mealID == mealID && settings.calendar.isDate($0.day, inSameDayAs: day) }
        guard !removed.isEmpty else { return }
        // Delete every version so an older estimate cannot reappear.
        let remaining = records.filter { !($0.mealID == mealID && settings.calendar.isDate($0.day, inSameDayAs: day)) }
        settings.mealCheckIns = remaining
        flushSave()
        let referenced = Set(remaining.map(\.photoFilename))
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DietPhotos", isDirectory: true)
        for filename in Set(removed.map(\.photoFilename)) where !referenced.contains(filename) {
            guard !filename.isEmpty, URL(fileURLWithPath: filename).lastPathComponent == filename,
                  (filename as NSString).pathExtension.lowercased() == "jpg" else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
        }
    }
    /// Moving an edited meal to another day removes its old bucket without touching other meals.
    @discardableResult
    func saveMealRecord(_ record: MealCheckIn, replacing previous: MealCheckIn? = nil) -> [MealCheckIn] {
        let calendar = settings.calendar
        let records = settings.mealCheckIns ?? []
        var record = record
        // Old scheduled meals can reuse one ID across dates. Moving one must not overwrite another day's meal.
        if let previous, !calendar.isDate(previous.day, inSameDayAs: record.day),
           records.contains(where: { $0.mealID == record.mealID && calendar.isDate($0.day, inSameDayAs: record.day) }) {
            record.mealID = UUID().uuidString
        }
        func replaced(_ candidate: MealCheckIn) -> Bool {
            let sameDestination = candidate.mealID == record.mealID && calendar.isDate(candidate.day, inSameDayAs: record.day)
            let sameSource = previous.map { candidate.mealID == $0.mealID && calendar.isDate(candidate.day, inSameDayAs: $0.day) } ?? false
            return sameDestination || sameSource
        }
        let removed = records.filter(replaced)
        if calendar.isDateInToday(record.day) { captureWellnessGoal() }
        settings.mealCheckIns = records.filter { !replaced($0) } + [record]
        flushSave()
        return removed
    }

    func wellnessMeals(on date: Date) -> [MealCheckIn] {
        let records = (settings.mealCheckIns ?? []).filter { settings.calendar.isDate($0.day, inSameDayAs: date) }
        return Self.latestMealRecords(records)
    }
    static func latestMealRecords(_ records: [MealCheckIn]) -> [MealCheckIn] {
        return Dictionary(grouping: records, by: \.mealID).values.compactMap { $0.max(by: { $0.confirmedAt < $1.confirmedAt }) }.sorted {
            if $0.mealTime != $1.mealTime { return $0.mealTime < $1.mealTime }
            if $0.confirmedAt != $1.confirmedAt { return $0.confirmedAt < $1.confirmedAt }
            return $0.mealID < $1.mealID
        }
    }
    func dietGuidance(on date: Date = Date()) -> DietDailyGuidance? {
        let day = settings.calendar.startOfDay(for: date)
        let sleep = HealthKitService.shared.sleepMinutes[day]
            ?? settings.sleepRecords?[SleepPreferences.dayKey(day, calendar: settings.calendar)]
        return DietDailyGuidance.build(settings: settings, sets: sets, exById: exById,
                                       sleptMinutes: sleep, now: date)
    }

    func wellnessGoal(on date: Date) -> DailyWellnessGoal? {
        var goal = settings.wellnessGoals?[SleepPreferences.dayKey(date, calendar: settings.calendar)]
        if settings.calendar.isDate(date, inSameDayAs: Date()), let targets = dietGuidance(on: date)?.targets {
            if goal == nil {
                let mealIDs = DailyDietPlan.build(settings: settings, preferences: settings.dietPreferences ?? DietPreferences()).meals.map(\.id)
                goal = .init(protein: targets.protein, carbsMinimum: targets.carbohydrate,
                             fatMinimum: targets.fat, sleepMinutes: (settings.sleepPreferences ?? SleepPreferences()).targetMinutes,
                             mealIDs: mealIDs)
            }
            goal?.protein = targets.protein
            goal?.carbsMinimum = targets.carbohydrate
            goal?.fatMinimum = targets.fat
        }
        return goal
    }
    func captureWellnessGoal(plan: Plan? = nil, updateDiet: Bool = false) {
        guard let targets = dietGuidance()?.targets else { return }
        let day = settings.calendar.startOfDay(for: Date())
        let key = SleepPreferences.dayKey(day, calendar: settings.calendar)
        var goals = settings.wellnessGoals ?? [:]
        if goals[key] == nil {
            let meals = DailyDietPlan.build(settings: settings, preferences: settings.dietPreferences ?? DietPreferences()).meals.map(\.id)
            goals[key] = .init(trainingSets: plan.map { $0.steps.reduce(0) { $0 + $1.sets } }, planID: plan?.id, protein: targets.protein, carbsMinimum: targets.carbohydrate, fatMinimum: targets.fat, sleepMinutes: (settings.sleepPreferences ?? SleepPreferences()).targetMinutes, mealIDs: meals)
        } else if let plan, !plan.steps.isEmpty {
            goals[key]?.trainingSets = plan.steps.reduce(0) { $0 + $1.sets }
            goals[key]?.planID = plan.id
        }
        // Today's target tracks actual workouts even after a meal is logged.
        // Earlier dates retain their saved target snapshots.
        if updateDiet || wellnessMeals(on: day).isEmpty
            || goals[key]?.protein != targets.protein
            || goals[key]?.carbsMinimum != targets.carbohydrate
            || goals[key]?.fatMinimum != targets.fat {
            goals[key]?.protein = targets.protein; goals[key]?.carbsMinimum = targets.carbohydrate
            goals[key]?.fatMinimum = targets.fat
            goals[key]?.mealIDs = DailyDietPlan.build(settings: settings, preferences: settings.dietPreferences ?? DietPreferences()).meals.map(\.id)
        }
        settings.wellnessGoals = goals; save()
    }
    func wellnessScore(on date: Date) -> DailyWellnessScore {
        let day = settings.calendar.startOfDay(for: date)
        return .calculate(goal: wellnessGoal(on: day), sets: sets.filter { settings.calendar.isDate($0.performedAt, inSameDayAs: day) }, meals: wellnessMeals(on: day), slept: HealthKitService.shared.sleepMinutes[day] ?? settings.sleepRecords?[SleepPreferences.dayKey(day, calendar: settings.calendar)])
    }
}


extension DataStore {
    func refreshExternalWorkouts() async throws {
        guard settings.externalWorkoutImportEnabled == true, !importingExternalWorkouts else { return }
        importingExternalWorkouts = true
        defer { importingExternalWorkouts = false }
        let records = try await HealthKitService.shared.readWorkouts()
        guard settings.externalWorkoutImportEnabled == true else { return }
        replaceExternalWorkoutSnapshot(records)
    }
    /// Replace rather than append so repeated refreshes stay idempotent and Health deletions propagate.
    func replaceExternalWorkoutSnapshot(_ records: [ExternalWorkout], now: Date = Date()) {
        guard settings.externalWorkoutImportEnabled == true else { return }
        let deleted = Set(settings.deletedExternalWorkoutIDs ?? [])
        let valid = ExternalWorkout.normalized(records, now: now).filter { !deleted.contains($0.id) }
        if valid != settings.externalWorkouts {
            settings.externalWorkouts = valid
            save()
        }
    }
    /// Remove only the Masso copy; retain a tombstone so Health refresh cannot restore it.
    func deleteExternalWorkout(id: String) {
        var deleted = Set(settings.deletedExternalWorkoutIDs ?? [])
        deleted.insert(id)
        settings.deletedExternalWorkoutIDs = deleted.sorted()
        settings.externalWorkouts?.removeAll { $0.id == id }
        save()
    }
    func recordedExternalWorkouts(on day: Date? = nil, now: Date = Date()) -> [ExternalWorkout] {
        (settings.externalWorkouts ?? []).filter { record in
            !(settings.deletedExternalWorkoutIDs ?? []).contains(record.id) && record.isRecorded(by: now) && (day.map { settings.calendar.isDate(record.startedAt, inSameDayAs: $0) } ?? true)
        }.sorted { $0.startedAt > $1.startedAt }
    }
    /// Count real activity days once, across Masso and Apple Health. Recovery-only days stay blank.
    func recordedWorkoutDates(now: Date = Date(), calendar: Calendar? = nil) -> Set<Date> {
        let calendar = calendar ?? settings.calendar
        let dates = sets.filter { $0.performedAt <= now }.map(\.performedAt)
            + recordedExternalWorkouts(now: now).map(\.startedAt)
        return Set(dates.map { calendar.startOfDay(for: $0) })
    }
}
