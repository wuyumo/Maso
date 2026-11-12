import Foundation
import CryptoKit

enum WorkoutParameter: String { case sets, reps, weight, duration }
import Observation
import SwiftUI

// 训练会话 — 全局状态, 跟 web 端 trainingSession.tsx 1:1 对齐
//
// 关键不变量:
//   - 同一时间只有一条 session
//   - playing + endsAt 一起表达 "自动倒计时"
//   - pausedRemaining 在暂停时保存剩余秒数, 恢复时变回 endsAt
//   - segmentIndex 越界时夹回
//
// "自动结束当前段" 由 SwiftUI 的 Timer 驱动 — 时间到 endsAt 就调 advance()

@MainActor
@Observable
final class TrainingSessionStore {
    @ObservationIgnored private var updatingObservedTiming = false
    @ObservationIgnored let heartRate = WorkoutHeartRateMonitor()
    @ObservationIgnored var heartRateReadEnabled = false
    @ObservationIgnored let youtubePlayback = WorkoutYouTubePlayback()
    @ObservationIgnored private let completionSound: () -> Void
    @ObservationIgnored private let clock: () -> Date
    init(completionSound: (() -> Void)? = nil, clock: @escaping () -> Date = Date.init) {
        self.completionSound = completionSound ?? { SoundPlayer.shared.playSetComplete() }
        self.clock = clock
    }

    /// "做完了一组" 的 key — 用 (stepId, setN) 而非 segmentIndex,
    /// 让 step 参数被编辑后, 已完成状态依然保留 (segment 重新生成 index 会变, stepId+setN 不变).
    /// Codable: 跟 Session 一起落盘 (active-session.json), 杀 app 后冷启动恢复.
    struct CompletedSet: Hashable, Sendable, Codable {
        let stepId: String
        let setN: Int
    }

    /// A set completed before an exercise replacement keeps its original concrete identity.
    /// Optional session storage below keeps older in-progress workouts decodable.
    struct CompletedExerciseSnapshot: Hashable, Sendable, Codable {
        let stepId: String
        let setN: Int
        let exercise: Exercise
        let totalSets: Int
        let reps: Int?
        let weight: Double?
        let duration: Int?
        let countdown: Bool
    }

    struct PlaybackUndo: Hashable, Codable {
        let anchor: SessionPersistence.Anchor
        let playing: Bool
        let remaining: TimeInterval?
        var completedSet: CompletedSet? = nil
        var recordID: String? = nil
    }

    struct Session: Hashable, Codable {
        let planId: String
        var segmentIndex: Int = 0
        var playing: Bool = true
        /// 倒计时目标时刻 (timeIntervalSinceReferenceDate); nil 表示等用户点完成或暂停
        var endsAt: Date?
        var pausedRemaining: TimeInterval?
        let startedAt: Date
        /// 训练已走完最后一段, 等用户确认结束
        var completed: Bool = false
        /// 最后一次用户交互 (advance / setIndex / togglePlay) 的时间
        /// 用于 6h-inactive auto-complete: 用户关机走了 / 忘了, 不能让训练永远挂着
        var lastActiveAt: Date = .init()
        /// 用户主动点"打勾"完成的组集合 — 只有 advance() (而非 setIndex 跳过) 才会写入.
        /// playlist + TimelineBar 用这个判断"哪些段真的做完了, 该标绿". 跳过的段保持灰.
        var completedSets: Set<CompletedSet> = []
        var completedExerciseSnapshots: [CompletedExerciseSnapshot]? = nil

        /// **实际训练顺序** — 每个动作第一次完成组时按序追加它的 stepId.
        /// completedSets 是 Set (无序), 推不出"先练了哪个", 所以单独记一条.
        /// 结束时用它把 plan.steps 重排成用户这次真实的顺序 (见 applyTrainedOrderToPlan).
        ///
        /// ⚠️ 必须是 Optional: Session 会整体落盘 (杀 app 恢复), Swift 合成的 Codable 对
        ///    **缺失的 key 会直接抛错**, 非 Optional 即使有默认值也救不了 —— 老版本存的
        ///    session 里没这个字段, 用户带着进行中的训练升级 app 就会解不出来, 训练直接丢.
        var completionOrder: [String]? = nil
        /// Optional for backward-compatible restoration of older active sessions.
        var playbackUndo: [PlaybackUndo]? = nil
        /// Exact history ownership, independent of navigation/undo and exercise replacement.
        var recordedSetIDs: Set<String>? = nil
        var openEnded: Bool? = nil
        var awaitingExercise: Bool? = nil
        var currentRestDurationOverride: Int? = nil
        var setTimings: [String: WorkoutSetTiming]? = nil
        var timingKey: String? = nil
        var segmentEnteredAt: Date? = nil
        var priorRestSeconds: Double? = nil
    }

    private(set) var session: Session? {
        // 每次 mutation 落盘 — iOS 杀后台很常见 (训练 60-90 分钟), 进度不能只活在内存里.
        // mutation 频率 = 用户操作级 (advance / 暂停 / 编辑), 文件 ~KB, 直接同步写无压力.
        didSet {
            guard !updatingObservedTiming else { return }
            updatingObservedTiming = true
            updateObservedTiming(previous: oldValue, at: clock())
            if let oldValue, oldValue.segmentIndex != session?.segmentIndex { session?.currentRestDurationOverride = nil }
            updatingObservedTiming = false
            persistActiveSession()
            if session == nil || session?.completed == true { heartRate.stop() }
            if session == nil || session?.completed == true {
                youtubePlayback.stop()
            } else if let selected = youtubePlayback.exerciseID,
                      let currentSegment, case .exercise(let exercise, _, _, _, _, _, _) = currentSegment.kind,
                      exercise.id != selected {
                youtubePlayback.stop()
            }
        }
    }
    /// 用户主动结束的标记 — 防止 player view 的 onAppear 又 auto-restart
    var endedExplicitly: Bool = false
    private var watchDiscarded = false

    /// App Store 截图模式 (MASO_SHOWCASE_SEED) — 演示数据不落盘, 也不恢复.
    private let sessionPersistenceDisabled =
        ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] == "1"

    /// 1Hz tick probe — 让 `remainingSeconds` 这类基于 `Date()` 的 computed property
    /// 通过 Observation 建立"我依赖 tickProbe"的图谱. SessionTickerView 每 0.5s 改一次,
    /// 所有读 remainingSeconds 的 view (MiniBar / Player) 自动重算.
    ///
    /// 没这个的话, remainingSeconds 内部用 `Date()` 是非 observed 的, view 不会自己刷新.
    /// (PlanPlayer 之前能动是因为它 onAppear 时频繁状态变化, 但 sheet 收起后 MiniBar 只在
    /// session.endsAt / segmentIndex 改变时才刷新, 中间几十秒倒计时就定住了.)
    var tickProbe: UInt32 = 0

    /// 这两个是从 DataStore 衍生出来的 — UI 层从外部传入

    var plan: Plan?
    var segments: [Segment] = []

    /// 训练中是否修改过 plan 参数 (sets/reps/weight/duration/顺序). 结束时如果 dirty 且
    /// plan 不是自由训练 (autoGenerated), 弹"保存到训练计划?"提示让用户决定是否持久化.
    /// start() 时重置 false; updateCurrentStep / reorderSteps 末尾设 true.
    private(set) var planParamsDirty: Bool = false

    var isOpenWorkout: Bool { session?.openEnded == true }
    var awaitingExercise: Bool { session?.awaitingExercise == true && session?.completed == false }

    /// 当前段 (索引夹紧后)
    var currentSegment: Segment? {
        guard !segments.isEmpty, let s = session else { return nil }
        let i = min(max(0, s.segmentIndex), segments.count - 1)
        return segments[i]
    }

    /// 当前段计算的剩余秒数 (nil = 没在倒计时)
    var remainingSeconds: Int? {
        // 建立 Observation 依赖: tickProbe 每 0.5s 被 SessionTickerView 改一次,
        // 强制所有读 remainingSeconds 的 view 跟着重算. 不能去掉这一行.
        _ = tickProbe
        guard let s = session else { return nil }
        if !s.playing, let p = s.pausedRemaining { return Int(ceil(p)) }
        guard let endsAt = s.endsAt else { return nil }
        let rem = endsAt.timeIntervalSinceNow
        return max(0, Int(ceil(rem)))
    }

    /// 训练超过 N 小时无交互 → 自动判定完成 (避免用户关机后还挂着上一天的训练)
    static let autoCompleteAfter: TimeInterval = 6 * 60 * 60  // 6h

    func start(planId: String, plan: Plan?, segments: [Segment], source: String = "unknown") {
        youtubePlayback.stop()
        endedExplicitly = false
        self.plan = plan
        self.segments = segments
        self.planParamsDirty = false  // 新一次训练 — 重置改动标志
        // workout_start — 唯一的开练入口 (所有 UI start 路径汇到这). restorePersistedSession 是冷启
        // 恢复, 不走这里, 故不会双发. planId 哈希后报 (无 PII), step_count = exercise 段数.
        let stepCount = segments.filter { if case .exercise = $0.kind { return true }; return false }.count
        Analytics.shared.track("workout_start", [
            "source": .string(source),
            "step_count": .int(stepCount),
            "planId_hash": .string(DataStore.hashedPlanId(planId)),
        ])
        let seg = segments.first
        let endsAt = initialEndsAt(for: seg)
        session = Session(
            planId: planId,
            segmentIndex: 0,
            playing: true,
            endsAt: endsAt,
            pausedRemaining: nil,
            startedAt: clock(),
            completed: false,
            lastActiveAt: clock(),
            openEnded: planId.hasPrefix("qw-open-") && plan?.autoGenerated == true
        )
        // 启动 Live Activity — 锁屏 / Dynamic Island 训练状态小窗
        LiveActivityManager.shared.start(
            planName: plan?.name ?? NSLocalizedString("Workout", comment: ""),
            initialState: liveActivityState(for: seg, endsAt: endsAt)
        )
        // Watch 镜像 — 新训练重置 HK 防双计标记, 推开局帧
        watchDiscarded = false
        WatchSyncManager.shared.resetForNewWorkout()
        syncWatch()
    }

    /// 把当前 segment + endsAt 翻译成 Live Activity 的 ContentState
    private func liveActivityState(
        for segment: Segment?,
        endsAt: Date?
    ) -> TrainingActivityAttributes.ContentState {
        guard let segment else {
            return TrainingActivityAttributes.ContentState(segmentLabel: "—", setProgress: "")
        }
        switch segment.kind {
        case .rest:
            return TrainingActivityAttributes.ContentState(
                segmentLabel: NSLocalizedString("Rest", comment: ""),
                setProgress: "",
                endsAt: endsAt,
                isRest: true,
                nextExerciseName: nextExerciseName(after: segment)
            )
        case .exercise(let ex, let setN, let total, _, _, _, let countdown):
            return TrainingActivityAttributes.ContentState(
                segmentLabel: ex.displayName,
                setProgress: "\(setN)/\(total)",
                endsAt: countdown ? endsAt : nil,
                isRest: false,
                nextExerciseName: nil
            )
        }
    }

    /// rest 段时, 找下一个 exercise 名 — 用在 Live Activity "Next: XX" 提示
    private func nextExerciseName(after current: Segment) -> String? {
        guard let s = session, let i = segments.firstIndex(where: { $0.id == current.id }) else { return nil }
        for j in (i + 1)..<segments.count {
            if case .exercise(let ex, _, _, _, _, _, _) = segments[j].kind {
                return ex.displayName
            }
        }
        _ = s
        return nil
    }

    /// 同步当前 state 到 Live Activity. 在所有 session mutating 函数末尾调.
    private func syncLiveActivity() {
        guard let s = session else { return }
        let seg = currentSegment
        LiveActivityManager.shared.update(
            liveActivityState(for: seg, endsAt: s.endsAt)
        )
        syncWatch()
    }

    /// 标记"用户仍在主动用" — bump lastActiveAt, 避免活跃 session 被 6h idle 误判完成.
    /// P2-9: 之前只有 advance/setIndex/togglePlay/编辑 算活动; 拖 playlist、进播放页这种
    /// 也算用户在场. 只在前台被调 (onAppear / 拖拽 onEnded), 不会重置"后台放置"的计时.
    func noteActivity() {
        guard var s = session, !s.completed else { return }
        s.lastActiveAt = Date()
        session = s
    }

    /// 检查 idle 时长, 超过 6h 自动 mark completed
    /// SessionTickerView 每 0.5s 调一次; app 从后台 resume 时也调
    func checkAutoComplete() {
        guard var s = session, !s.completed else { return }
        let idle = Date().timeIntervalSince(s.lastActiveAt)
        guard idle >= Self.autoCompleteAfter else { return }
        // 6h+ 没动 — 当作完成
        s.completed = true
        s.playing = false
        s.endsAt = nil
        session = s
        trackFinish(s, finishType: "auto_idle")   // 6h 闲置自动完成 — 分析里单独标, 应从"完成率"剔除
        LiveActivityManager.shared.end()
        syncWatch()
    }

    // MARK: - Session 持久化 (杀 app 恢复)

    /// session 每次变化整体落盘; session 清空 (end / 放弃) 时删文件.
    private func persistActiveSession() {
        guard !sessionPersistenceDisabled else { return }
        if let s = session {
            SessionPersistence.save(.init(
                session: s,
                plan: plan,
                planParamsDirty: planParamsDirty,
                anchor: currentAnchor(for: s)
            ))
        } else {
            SessionPersistence.clear()
        }
    }

    /// 当前位置的 (stepId, setN) 语义锚 — 恢复时 rest 默认值可能已变, segments 重新展开后
    /// 段数不同, 裸 segmentIndex 会落错; 锚定到组上跟 mutator 们的 index 映射逻辑一致.
    private func currentAnchor(for s: Session) -> SessionPersistence.Anchor? {
        guard !segments.isEmpty else { return nil }
        let i = min(max(0, s.segmentIndex), segments.count - 1)
        if case .exercise(_, let n, _, _, _, _, _) = segments[i].kind {
            return .init(stepId: segments[i].stepId, setN: n, onRestBefore: false)
        }
        // rest 段: 锚到它后面第一个 exercise 段 (= 这个 rest 是"谁的组前休息")
        for j in (i + 1)..<segments.count {
            if case .exercise(_, let n, _, _, _, _, _) = segments[j].kind {
                return .init(stepId: segments[j].stepId, setN: n, onRestBefore: true)
            }
        }
        return nil
    }

    private func expandedSessionPlan(
        _ plan: Plan,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int,
        session: Session
    ) -> [Segment] {
        let snapshots = Dictionary((session.completedExerciseSnapshots ?? []).map {
            (CompletedSet(stepId: $0.stepId, setN: $0.setN), $0)
        }, uniquingKeysWith: { first, _ in first })
        return expandPlan(plan, exById: exById, defaultRest: defaultRest,
                          defaultBetweenExerciseRest: defaultBetweenExerciseRest).map { segment in
            guard case .exercise(_, let setN, _, _, _, _, _) = segment.kind,
                  let saved = snapshots[CompletedSet(stepId: segment.stepId, setN: setN)] else { return segment }
            return Segment(id: segment.id, stepId: segment.stepId,
                           kind: .exercise(saved.exercise, setNumber: setN, totalSets: saved.totalSets,
                                           targetReps: saved.reps, targetWeight: saved.weight,
                                           duration: saved.duration, countdown: saved.countdown))
        }
    }

    /// 冷启动恢复 — app 被系统杀掉 (训练挂着) 后重启, 把进行中的 session 从磁盘接回来.
    /// 不复活的情况 (静默清掉): 已 completed (组都在历史里, 冷启动弹昨天的完成页只会迷惑)、
    /// 闲置超 autoCompleteAfter (跟 6h idle 自动完成同语义)、plan 缺失或展不开.
    /// 倒计时在 app 死掉期间走完的 → 暂停在 0, 不让 ticker 一进来就替用户自动记组/跳段.
    func restorePersistedSession(
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int
    ) {
        guard !sessionPersistenceDisabled, session == nil else { return }
        guard let payload = SessionPersistence.load() else { return }
        let saved = payload.session
        guard !saved.completed,
              Date().timeIntervalSince(saved.lastActiveAt) < Self.autoCompleteAfter,
              let savedPlan = payload.plan else {
            SessionPersistence.clear()
            return
        }
        // Exact synonym aliases change identity spelling only, never steps or loads.
        let restoredPlan = ExerciseLibrary.canonicalPlan(savedPlan, using: exById)
        var segs = expandedSessionPlan(
            restoredPlan,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: saved
        )
        guard !segs.isEmpty else {
            SessionPersistence.clear()
            return
        }
        endedExplicitly = false
        plan = restoredPlan
        segments = segs
        planParamsDirty = payload.planParamsDirty
        var s = saved
        // 位置: 优先用 (stepId, setN) 语义锚重新定位 — rest 默认值在训练中被改过时,
        // 重新展开的 segments 段数不同, 裸 segmentIndex 会落错位置. 找不到锚才退回裸下标.
        if let anchor = payload.anchor,
           let j = segs.firstIndex(where: {
               if case .exercise(_, let n, _, _, _, _, _) = $0.kind {
                   return $0.stepId == anchor.stepId && n == anchor.setN
               }
               return false
           }) {
            if anchor.onRestBefore, j - 1 >= 0, segs[j - 1].isRest {
                s.segmentIndex = j - 1
            } else {
                s.segmentIndex = j
                if anchor.onRestBefore {
                    // 保存时停在 rest 上, 但重新展开后这个 rest 没了 (rest 默认被改成 0) —
                    // 落到组上并按该段重置计时, 不沿用 rest 的 endsAt/暂停残值.
                    if s.playing {
                        s.endsAt = initialEndsAt(for: segs[j])
                        s.pausedRemaining = nil
                    } else {
                        s.endsAt = nil
                        s.pausedRemaining = initialPausedRemaining(for: segs[j])
                    }
                }
            }
        } else {
            s.segmentIndex = min(max(0, s.segmentIndex), segs.count - 1)
        }
        if let endsAt = s.endsAt, endsAt.timeIntervalSinceNow <= 0 {
            s.endsAt = nil
            s.pausedRemaining = 0
            s.playing = false
        }
        if let duration = s.currentRestDurationOverride, segs.indices.contains(s.segmentIndex), segs[s.segmentIndex].isRest {
            let old = segs[s.segmentIndex]
            segs[s.segmentIndex] = Segment(id: old.id, stepId: old.stepId, kind: .rest(duration: duration))
            segments = segs
        }
        if let key = s.timingKey {
            var timing = s.setTimings?[key] ?? WorkoutSetTiming()
            timing.openSince = nil; timing.completeCoverage = false
            s.setTimings?[key] = timing
        }
        s.segmentEnteredAt = nil
        session = s
        // Live Activity 重建 — start 内部先清旧 activity, 不会重复.
        // 手表帧由 caller 随后的 pushWatchState() 推, 这里不用重复 sync.
        LiveActivityManager.shared.start(
            planName: restoredPlan.name,
            initialState: liveActivityState(for: currentSegment, endsAt: s.endsAt)
        )
    }

    func setIndex(_ i: Int) {
        guard var s = session else { return }
        let safe = min(max(0, i), max(0, segments.count - 1))
        if safe != s.segmentIndex, let undo = playbackSnapshot(s) {
            s.playbackUndo = (s.playbackUndo ?? []) + [undo]
        }
        s.segmentIndex = safe
        let seg = segments[safe]
        // P2-8: 保留暂停态 — 之前无条件 playing=true, 暂停的用户点 playlist 跳一下就被静默恢复.
        // 暂停中跳转: 计时段把满时长存 pausedRemaining (恢复时从该段起算), 不自动跑.
        if s.playing {
            s.endsAt = initialEndsAt(for: seg)
            s.pausedRemaining = nil
        } else {
            s.endsAt = nil
            s.pausedRemaining = initialPausedRemaining(for: seg)
        }
        s.lastActiveAt = Date()  // 用户交互 — reset idle
        session = s
        syncLiveActivity()
    }

    /// 点 playlist 动作行 → 跳到该动作"下一组未完成"的 exercise 段 (跳过其前的 rest 段).
    /// 全做完 → 落第一组. 因为只 land 在 exercise 段, setIndex 不会启动休息倒计时 →
    /// 切去别的动作再切回来不会重新休息, 直接落到未做的下一组. (修: 切换训练重置休息.)
    func jumpToStep(stepId: String) {
        let done = session?.completedSets ?? []
        let exSegs: [(idx: Int, setN: Int)] = segments.enumerated().compactMap { i, seg in
            if case .exercise(_, let setN, _, _, _, _, _) = seg.kind, seg.stepId == stepId {
                return (i, setN)
            }
            return nil
        }
        guard !exSegs.isEmpty else { return }
        let target = exSegs.first { !done.contains(CompletedSet(stepId: stepId, setN: $0.setN)) } ?? exSegs[0]
        setIndex(target.idx)
    }

    var workoutSessionID: String? {
        session.map { "\($0.planId)|\($0.startedAt.timeIntervalSince1970)" }
    }

    private func timingKey(for segment: Segment) -> String {
        if case .exercise(let exercise, let number, _, _, _, _, _) = segment.kind {
            return "\(segment.stepId)|\(exercise.id)|\(number)"
        }
        return "rest|\(segment.id)"
    }

    private func updateObservedTiming(previous: Session?, at now: Date) {
        guard var value = session, let segment = currentSegment else { return }
        let key = timingKey(for: segment)
        let changed = value.timingKey != key
        var clocks = value.setTimings ?? [:]
        if let oldKey = previous?.timingKey,
           changed || !value.playing || value.completed {
            var old = clocks[oldKey] ?? WorkoutSetTiming()
            old.close(at: now); clocks[oldKey] = old
        }
        if changed {
            if let previous, previous.timingKey?.hasPrefix("rest|") == true,
               let entered = previous.segmentEnteredAt, segment.isExercise {
                value.priorRestSeconds = max(0, now.timeIntervalSince(entered))
            } else { value.priorRestSeconds = nil }
            value.segmentEnteredAt = now
            value.timingKey = key
        }
        if value.playing && !value.completed {
            var current = clocks[key] ?? WorkoutSetTiming()
            current.open(at: now); clocks[key] = current
        }
        value.setTimings = clocks
        session = value
    }

    func pauseForSafety() {
        if session?.playing == true { togglePlay() }
    }

    func nextUnfinishedSegment() -> Segment? {
        guard let session else { return nil }
        let unfinished: (Segment) -> Bool = { segment in
            guard case .exercise(_, let number, _, _, _, _, _) = segment.kind else { return false }
            return !session.completedSets.contains(.init(stepId: segment.stepId, setN: number))
        }
        return segments.dropFirst(session.segmentIndex).first(where: unfinished) ?? segments.first(where: unfinished)
    }

    @discardableResult
    func jumpToFirstUnfinishedStep(stepId: String) -> Bool {
        guard let session, !session.completed,
              let index = segments.firstIndex(where: { segment in
                  guard segment.stepId == stepId, case .exercise(_, let number, _, _, _, _, _) = segment.kind else { return false }
                  return !session.completedSets.contains(.init(stepId: stepId, setN: number))
              }) else { return false }
        setIndex(index)
        return true
    }

    func updateCurrentRest(seconds: Int, now: Date = Date()) {
        guard var session, let segment = currentSegment, case .rest(let duration) = segment.kind else { return }
        let remaining = session.endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? session.pausedRemaining ?? Double(duration)
        let newDuration = min(3600, max(0, seconds))
        let newRemaining = max(0, Double(newDuration) - max(0, Double(duration) - remaining))
        segments[session.segmentIndex] = Segment(id: segment.id, stepId: segment.stepId, kind: .rest(duration: newDuration))
        session.currentRestDurationOverride = newDuration
        if session.playing { session.endsAt = now.addingTimeInterval(newRemaining); session.pausedRemaining = nil }
        else { session.endsAt = nil; session.pausedRemaining = newRemaining }
        session.lastActiveAt = now
        self.session = session
        syncLiveActivity(); syncWatch()
    }

    /// Preferences govern every future workout. Preserve the active segment and
    /// recorded history, even if the rest finished while its editor was open.
    func applyRestPreferences(setRest: Int, switchingRest: Int, exById: [String: Exercise], now: Date = Date()) {
        guard let session, !session.completed, let plan, let current = currentSegment else { return }
        let next = segments.dropFirst(session.segmentIndex + 1).first(where: { $0.isExercise })
        if current.isRest {
            updateCurrentRest(seconds: next?.stepId != current.stepId ? switchingRest : setRest, now: now)
        }
        let anchor = current.isRest ? next : current
        guard let anchor, case .exercise(_, let setNumber, _, _, _, _, _) = anchor.kind else { return }
        let expanded = expandedSessionPlan(plan, exById: exById, defaultRest: setRest,
                                          defaultBetweenExerciseRest: switchingRest, session: session)
        guard let index = expanded.firstIndex(where: {
            guard $0.stepId == anchor.stepId, case .exercise(_, let n, _, _, _, _, _) = $0.kind else { return false }
            return n == setNumber
        }) else { return }
        let suffixStart = current.isRest ? index : index + 1
        segments = Array(segments.prefix(session.segmentIndex + 1)) + expanded.dropFirst(suffixStart).map {
            Segment(id: UUID().uuidString, stepId: $0.stepId, kind: $0.kind)
        }
        persistActiveSession()
        syncLiveActivity(); syncWatch()
    }

    func togglePlay() {
        guard !awaitingExercise else { return }
        guard var s = session else { return }
        if s.playing {
            if let endsAt = s.endsAt {
                s.pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
                s.endsAt = nil
            }
            s.playing = false
        } else {
            if let p = s.pausedRemaining {
                s.endsAt = Date().addingTimeInterval(p)
                s.pausedRemaining = nil
            }
            s.playing = true
        }
        s.lastActiveAt = Date()  // 用户交互 — reset idle
        session = s
        syncLiveActivity()
    }

    func advance(record: ((SetRecord) -> Void)? = nil) {
        guard var s = session, !s.completed, !awaitingExercise else { return }
        var undo = playbackSnapshot(s)
        let curWasRest = currentSegment?.isRest ?? false
        // Only a newly recorded set earns completion feedback; revisiting a logged set does not.
        var recordedNewSet = false
        // 保存力量段的训练记录 + 标记 (stepId, setN) 已完成
        // —— advance() 是"用户点打勾 / 倒计时自然走完", 是真完成. setIndex 不走这里.
        // 守卫: 已完成的 (stepId, setN) 再打勾不重复记录 (用户 setIndex 跳回已完成组再点✓ 的场景).
        // 否则 data.sets 多一条幽灵记录 → 历史容量双计 + 分享卡组数对不上 + QR 多一组.
        if let cur = currentSegment, case .exercise(let ex, let setN, _, let reps, let weight, let dur, let countdown) = cur.kind,
           !s.completedSets.contains(CompletedSet(stepId: cur.stepId, setN: setN)) {
            // workout_complete_set — 真完成一组 (打勾 / 倒计时走完). 无 PII: 不带动作名/重量.
            //   kind: strength/cardio 派生自 category; trigger: countdown 段 = countdown, 否则 manual.
            let setKind = (ex.category == .cardio) ? "cardio" : "strength"
            Analytics.shared.track("workout_complete_set", [
                "set_index": .int(setN),
                "kind": .string(setKind),
                "trigger": .string(countdown ? "countdown" : "manual"),
            ])
            let observedAt = clock()
            let observedTiming = s.setTimings?[timingKey(for: cur)]
            let rec = SetRecord(
                id: UUID().uuidString,
                exerciseId: ex.id,
                exerciseName: ex.name,
                category: ex.category,
                weight: weight,
                reps: reps,
                duration: dur,
                performedAt: observedAt,
                planId: s.planId,
                // 快照 — plan 被删后历史卡名不退化. 但合成的临时 plan (自由训练 qw- /
                // 重练 session-replay-) 名字带时间戳且语言定格在落库时刻, 不入快照 —
                // 历史卡对这类继续走 render-time 本地化的 "Free workout" fallback.
                planName: {
                    guard let p = plan,
                          !p.id.hasPrefix("qw-"),
                          !p.id.hasPrefix("session-replay-") else { return nil }
                    return p.name
                }(),
                workoutSessionID: workoutSessionID,
                stepID: cur.stepId,
                setNumber: setN,
                activeIntervals: observedTiming?.completeCoverage == true ? observedTiming?.measuredIntervals(at: observedAt) : nil,
                restBeforeSeconds: s.priorRestSeconds
            )
            undo?.recordID = rec.id
            undo?.completedSet = CompletedSet(stepId: cur.stepId, setN: setN)
            record?(rec)
            s.recordedSetIDs = (s.recordedSetIDs ?? []).union([rec.id])
            // 写入"已做完"集合 — playlist / TimelineBar 据此标绿
            recordedNewSet = true
            s.completedSets.insert(CompletedSet(stepId: cur.stepId, setN: setN))
            // 记实际训练顺序 — 只在这个动作**第一次**完成组时追加 (后续组不重复记).
            var order = s.completionOrder ?? []
            if !order.contains(cur.stepId) {
                order.append(cur.stepId)
                s.completionOrder = order
            }
        }
        if let undo { s.playbackUndo = (s.playbackUndo ?? []) + [undo] }
        // QA-B: 播放列表排序是自由的 — 未完成动作可能被拖到播放头之前 (严格 +1 会在
        // 结束时静默吞掉它), 已完成动作也可能被拖到播放头之后 (严格 +1 会重播 + 重复记录).
        // → 前向找下一个"未完成 exercise"段 (落在它紧邻的 rest 上, 组前休息不变);
        //   前方没有 → 回卷到全场最早的未完成段; 哪儿都没有 → 真完成.
        guard let next = nextLandingIndex(from: s.segmentIndex + 1, completedSets: s.completedSets) else {
            if s.openEnded == true {
                s.awaitingExercise = true
                s.playing = false
                s.endsAt = nil
                s.pausedRemaining = nil
                s.lastActiveAt = Date()
                session = s
                syncLiveActivity()
                syncWatch()
                if recordedNewSet { Haptics.setComplete(); completionSound() }
                return
            }
            s.completed = true
            s.playing = false
            s.endsAt = nil
            applyTrainedOrderToPlan(s)   // 按这次真实训练顺序重排 (必须在 session=s 之前)
            session = s
            trackFinish(s, finishType: "natural")   // 自然走完最后一段
            LiveActivityManager.shared.end()
            syncWatch()
            return
        }
        s.segmentIndex = next
        let seg = segments[next]
        s.endsAt = initialEndsAt(for: seg)
        s.pausedRemaining = nil
        s.playing = true
        s.lastActiveAt = Date()  // advance 也算用户活动
        session = s
        syncLiveActivity()
        // DESIGN 7: 关键节点触觉 + 音效反馈 (都跟用户的音乐共存, 不打断).
        if curWasRest {
            Haptics.restEnded()
            // 休息结束 (无论自动倒计时归零 or 用户手动 skip) — 都放一次上行音
            SoundPlayer.shared.playRestEnded()
        } else if recordedNewSet {
            Haptics.setComplete()
            completionSound()
        }
        // Entering rest stays silent; only its ending has a separate click.
        if seg.isRest {
            SoundPlayer.shared.playEnterRest()
        }
    }

    /// advance 的落点解析: 从 start 起前向找第一个未完成 exercise 段; 若它紧邻的前一段
    /// 是 rest 且 rest 也在 start 之后, 落在 rest 上 (保留"组 → 休息 → 组"节奏).
    /// 前方没有 → 回卷从头找 (排序把未完成动作拖到播放头之前的场景); 全完成 → nil.
    /// 正常未排序流程下, 它跟 segmentIndex + 1 给出完全相同的结果.
    private func nextLandingIndex(from start: Int, completedSets: Set<CompletedSet>) -> Int? {
        func isUndoneExercise(_ seg: Segment) -> Bool {
            if case .exercise(_, let n, _, _, _, _, _) = seg.kind {
                return !completedSets.contains(CompletedSet(stepId: seg.stepId, setN: n))
            }
            return false
        }
        if start < segments.count,
           let j = (start..<segments.count).first(where: { isUndoneExercise(segments[$0]) }) {
            if j - 1 >= start, segments[j - 1].isRest { return j - 1 }
            return j
        }
        // 回卷 — 播放头之前还有没做的组 (被拖到前面的), 跳回去补完
        if let j = segments.indices.first(where: { isUndoneExercise(segments[$0]) }) {
            if j - 1 >= 0, segments[j - 1].isRest { return j - 1 }
            return j
        }
        return nil
    }

    /// Discard only this session's records before clearing its restoration snapshot.
    /// The undo IDs also support sessions saved before explicit ownership was added.
    func discard(recordRemoval: (Session, Set<String>) -> Void) {
        watchDiscarded = true
        if let session {
            let ids = (session.recordedSetIDs ?? []).union(
                (session.playbackUndo ?? []).compactMap(\.recordID))
            recordRemoval(session, ids)
        }
        if let key = workoutSessionID { WorkoutHeartLocalStore.shared.removeSessions([key]) }
        endedExplicitly = true
        end()
    }

    func end() {
        session = nil
        plan = nil
        segments = []
        LiveActivityManager.shared.end()
        syncWatch()   // → idle
    }

    /// 把 plan.steps 重排成**这次实际的训练顺序** (owner: 错序练完后, 新 routine 按这次的顺序展示,
    /// 用户点保存就按这个顺序存).
    ///
    /// 规则: 真练过的动作按 completionOrder 排在前 (谁先做完排谁), 一组没做的保持它们之间的
    /// 原有相对顺序、落到后面 —— 这就是"这次的顺序": 没练的自然沉底.
    /// 顺序没变 → 什么都不做 (不置 dirty, 不让用户看一张"全无修改"的确认页).
    ///
    /// ⚠️ 只改 self.plan (session-local 副本), **不动 data.plans** —— 是否落盘由用户在
    ///    SaveChangesConfirmView 上决定. 下游 RoutineDiff 会用 LIS 把真正被移动的那几个标 Moved.
    /// ⚠️ planParamsDirty 必须先于 session 赋值 —— session 的 didSet 落盘会快照这个 flag.
    private func applyTrainedOrderToPlan(_ s: Session) {
        guard var p = plan, p.steps.count > 1 else { return }
        let order = s.completionOrder ?? []
        guard !order.isEmpty else { return }          // 一组没完成 (纯跳过) → 谈不上"训练顺序"
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) },
                              uniquingKeysWith: { first, _ in first })
        // enumerated 的 offset 作 tie-break: 未练过的动作彼此保持原相对顺序 (稳定排序).
        let reordered = p.steps.enumerated().sorted { a, b in
            let ra = rank[a.element.id], rb = rank[b.element.id]
            switch (ra, rb) {
            case let (x?, y?):   return x != y ? x < y : a.offset < b.offset
            case (_?, nil):      return true      // 练过的排前面
            case (nil, _?):      return false
            case (nil, nil):     return a.offset < b.offset
            }
        }.map(\.element)

        guard reordered.map(\.id) != p.steps.map(\.id) else { return }   // 顺序没变
        p.steps = reordered
        planParamsDirty = true   // 先于 session 写 (didSet 落盘会快照它)
        plan = p
        // 不重建 segments: 这个方法只在**完成时**调用, segments 已不再驱动播放
        // (currentSegment / nextLandingIndex 都不会再被用到), 重建反而要多传 exById 等一堆参数.
    }

    /// 提前结束 — 跳到 completed 态保留已完成组. 跟 end() 区别: end 清空 session (=放弃),
    /// finishEarly 把它标记完成 (=用户主动提前圆满收工, CompletedView 会显示).
    func finishEarly() {
        guard var s = session else { return }
        s.completed = true
        s.playing = false
        s.endsAt = nil
        s.lastActiveAt = Date()
        applyTrainedOrderToPlan(s)   // 按这次真实训练顺序重排 (必须在 session=s 之前)
        session = s
        trackFinish(s, finishType: "early")   // 用户主动 End 提前收工
        LiveActivityManager.shared.end()
        syncWatch()
    }

    /// workout_finish 上报 — 三处 (natural / early / auto_idle) 共用. 无 PII: 只报计数 + 时长 + 类型.
    /// total_sets = 计划里 exercise 段总数; done_sets = 真完成组数 (completedSets); duration 秒.
    private func trackFinish(_ s: Session, finishType: String) {
        let totalSets = segments.filter { if case .exercise = $0.kind { return true }; return false }.count
        let doneSets = s.completedSets.count
        let durationSec = max(0, Int(Date().timeIntervalSince(s.startedAt)))
        Analytics.shared.track("workout_finish", [
            "finish_type": .string(finishType),
            "total_sets": .int(totalSets),
            "done_sets": .int(doneSets),
            "duration_sec": .int(durationSec),
        ])
    }

    private func playbackSnapshot(_ s: Session) -> PlaybackUndo? {
        guard let anchor = currentAnchor(for: s) else { return nil }
        let remaining = s.endsAt.map { max(0, $0.timeIntervalSinceNow) } ?? s.pausedRemaining
        return PlaybackUndo(anchor: anchor, playing: s.playing, remaining: remaining)
    }

    private func undoIndex(_ undo: PlaybackUndo) -> Int? {
        guard let index = segments.firstIndex(where: {
            if case .exercise(_, let n, _, _, _, _, _) = $0.kind {
                return $0.stepId == undo.anchor.stepId && n == undo.anchor.setN
            }
            return false
        }) else { return nil }
        if undo.anchor.onRestBefore {
            guard index > 0, segments[index - 1].isRest else { return nil }
            return index - 1
        }
        return index
    }

    var canUndoPlayback: Bool {
        guard let undo = session?.playbackUndo?.last else { return false }
        return undoIndex(undo) != nil
    }

    /// Undo one playback transition, including its exact recorded set, never another session's record.
    @discardableResult
    func undoPlayback(removeRecord: (String) -> Void) -> Bool {
        guard var s = session, let undo = s.playbackUndo?.last, let index = undoIndex(undo) else { return false }
        s.playbackUndo?.removeLast()
        if let done = undo.completedSet {
            s.setTimings = s.setTimings?.filter { !($0.key.hasPrefix(done.stepId + "|") && $0.key.hasSuffix("|\(done.setN)")) }
            s.timingKey = nil

            s.completedSets.remove(done)
            s.completedExerciseSnapshots?.removeAll { $0.stepId == done.stepId && $0.setN == done.setN }
            if !s.completedSets.contains(where: { $0.stepId == done.stepId }) {
                s.completionOrder?.removeAll { $0 == done.stepId }
            }
        }
        if let recordID = undo.recordID { removeRecord(recordID) }
        s.segmentIndex = index
        s.completed = false
        s.awaitingExercise = false
        s.playing = undo.playing
        var remaining = undo.remaining
        // An expired countdown must not immediately re-complete itself after undo.
        if let value = remaining, value <= 0 {
            remaining = initialPausedRemaining(for: segments[index])
            s.playing = false
        }
        s.endsAt = s.playing ? remaining.map { Date().addingTimeInterval($0) } : nil
        s.pausedRemaining = s.playing ? nil : remaining
        s.lastActiveAt = Date()
        session = s
        syncLiveActivity()
        syncWatch()
        return true
    }

    /// "上一动作" — backward.end.fill 的 playlist 语义 (回退一个**训练动作**, 不是上一组).
    ///   - 休息段: 回到休息前刚做完的那组的播放态 (休息不算一步, 回去可直接重练).
    ///   - 训练段: 跳到上一个 **不同动作** — 落点复用 jumpToStep (= 点 playlist 行同逻辑:
    ///     该动作下一组未完成的 set, 全做完落第一组).
    /// 之前的实现只回退"上一段"(常是同动作的上一组), 大图/标题不变 → 用户感知"没回退动作".
    func skipBackToPrevExercise() {
        guard let s = session, !segments.isEmpty else { return }
        let cur = min(max(0, s.segmentIndex), segments.count - 1)
        if segments[cur].isRest {
            // 休息中 → 回到刚做完的那组 (最近一个 exercise 段)
            var i = cur - 1
            while i >= 0 {
                if !segments[i].isRest { setIndex(i); return }
                i -= 1
            }
            return
        }
        // 训练组 → 向前找第一个"不同 stepId"的 exercise 段 = 上一个动作
        let curStep = segments[cur].stepId
        var i = cur - 1
        while i >= 0 {
            if !segments[i].isRest, segments[i].stepId != curStep {
                jumpToStep(stepId: segments[i].stepId)
                return
            }
            i -= 1
        }
        // 已是第一个动作 — 留在原地
    }

    var canSkipBack: Bool {
        guard let s = session, !segments.isEmpty else { return false }
        let cur = min(max(0, s.segmentIndex), segments.count - 1)
        if segments[cur].isRest {
            var i = cur - 1
            while i >= 0 {
                if !segments[i].isRest { return true }
                i -= 1
            }
            return false
        }
        let curStep = segments[cur].stepId
        var i = cur - 1
        while i >= 0 {
            if !segments[i].isRest, segments[i].stepId != curStep { return true }
            i -= 1
        }
        return false
    }

    /// R2: 当前播放头所在动作是否有"已完成组"可撤销 (回退键据此切换成"撤销"语义).
    var currentStepHasCompletedSet: Bool {
        guard let s = session, let cur = currentSegment else { return false }
        if case .exercise = cur.kind {
            return s.completedSets.contains { $0.stepId == cur.stepId }
        }
        return false
    }

    /// R2: 撤销"最近打勾的那组" — 清 completedSet + 删对应 SetRecord, 播放头落到该组以便重练.
    /// removeRecord(exerciseId, planId, since): 调用方据此删 DataStore 里本场该动作最近一条记录.
    /// 每调用一次撤一组.
    /// P0#5: ✓ 之后播放头通常已落在 rest 段 (或最后一组时 completed 态), 撤销 toast 在那时触发 —
    /// 所以目标不能只认"当前 exercise 段": 从当前位置(含)向前回溯, 找最近一个"有已完成组"的
    /// exercise 段, 正常流程下就是刚打勾的那组所属动作.
    @discardableResult
    func undoLastCompletedSet(
        removeRecord: ((_ exerciseId: String, _ planId: String?, _ since: Date) -> Void)? = nil
    ) -> Bool {
        guard var s = session, !segments.isEmpty else { return false }
        var probe = min(max(0, s.segmentIndex), segments.count - 1)
        var found: (stepId: String, ex: Exercise)? = nil
        while probe >= 0 {
            if case .exercise(let ex, _, _, _, _, _, _) = segments[probe].kind,
               s.completedSets.contains(where: { $0.stepId == segments[probe].stepId }) {
                found = (segments[probe].stepId, ex)
                break
            }
            probe -= 1
        }
        guard let (stepId, ex) = found else { return false }
        let mine = s.completedSets.filter { $0.stepId == stepId }
        guard let top = mine.max(by: { $0.setN < $1.setN }) else { return false }
        let recordedExerciseID = s.completedExerciseSnapshots?.first {
            $0.stepId == stepId && $0.setN == top.setN
        }?.exercise.id ?? ex.id
        s.completedSets.remove(top)
        s.completed = false   // 撤销后训练不再算"已完成"
        // 播放头落到被撤的那组, 方便直接重练
        if let idx = segments.firstIndex(where: { seg in
            if case .exercise(_, let n, _, _, _, _, _) = seg.kind { return seg.stepId == stepId && n == top.setN }
            return false
        }) {
            s.segmentIndex = idx
            let seg = segments[idx]
            if s.playing {
                s.endsAt = initialEndsAt(for: seg); s.pausedRemaining = nil
            } else {
                s.endsAt = nil; s.pausedRemaining = initialPausedRemaining(for: seg)
            }
        }
        s.lastActiveAt = Date()
        session = s
        // 删本场该动作最近一条历史记录 (normal 顺序完成下即被撤那组)
        removeRecord?(recordedExerciseID, s.planId, s.startedAt)
        Haptics.tap()
        syncLiveActivity()
        return true
    }

    private func initialEndsAt(for seg: Segment?) -> Date? {
        guard let seg else { return nil }
        switch seg.kind {
        case .rest(let dur):
            return Date().addingTimeInterval(TimeInterval(dur))
        case .exercise(_, _, _, _, _, let dur, let countdown):
            if countdown, let dur, dur > 0 {
                return Date().addingTimeInterval(TimeInterval(dur))
            }
            return nil // 力量动作: 等用户点完成
        }
    }

    /// 该段满时长 (秒) — 暂停态跳转时用, 存进 pausedRemaining 让恢复时从满时长起算.
    /// nil = 该段不计时 (力量动作).
    private func initialPausedRemaining(for seg: Segment?) -> TimeInterval? {
        guard let seg else { return nil }
        switch seg.kind {
        case .rest(let dur):
            return TimeInterval(dur)
        case .exercise(_, _, _, _, _, let dur, let countdown):
            if countdown, let dur, dur > 0 { return TimeInterval(dur) }
            return nil
        }
    }

    // MARK: - 训练中编辑当前 step 参数 (组数 / 次数 / 重量 / 时长)

    /// Re-resolve unconfirmed targets after completion, edits and undo. Never rebuild time.
    func refreshLoadSuggestions(using data: DataStore) {
        guard let state = session, !state.completed, var updated = plan else { return }
        var evidence = data.sets
        for index in evidence.indices {
            let record = evidence[index]
            guard record.workoutSessionID == workoutSessionID,
                  let step = updated.steps.first(where: { $0.id == record.stepID }),
                  !step.isSuggested("weight"),
                  state.completedSets.contains(.init(stepId: step.id, setN: record.setNumber ?? 0)) else { continue }
            // An explicit live edit adjusts projections only, never the performed record.
            let nextSet = (1...max(1, step.sets)).first {
                !state.completedSets.contains(.init(stepId: step.id, setN: $0))
            }
            evidence[index].weight = nextSet.map { step.weightForSet($0) } ?? step.weight
        }
        var changed = false
        for index in updated.steps.indices {
            let step = updated.steps[index]
            // Completing a target confirms that step; explicit/per-set/shared values stay locked.
            guard !state.completedSets.contains(where: { $0.stepId == step.id }),
                  step.weight == nil || step.isSuggested("weight"),
                  step.parameterSuggestions?["weight"]?.source != .shared,
                  step.setWeights?.contains(where: { $0 != nil }) != true else { continue }
            let resolved = data.suggestingMissingParameters(for: step, roughRecords: evidence)
            var next = step
            next.weight = resolved.weight
            if let provenance = resolved.parameterSuggestions?["weight"] {
                next.parameterSuggestions = next.parameterSuggestions ?? [:]
                next.parameterSuggestions?["weight"] = provenance
            } else { next.confirmParameter("weight") }
            guard next != step else { continue }
            updated.steps[index] = next
            changed = true
            segments = segments.map { segment in
                guard segment.stepId == step.id,
                      case .exercise(let ex, let number, let total, let reps, _, let duration, let countdown) = segment.kind else { return segment }
                return Segment(id: segment.id, stepId: segment.stepId,
                    kind: .exercise(ex, setNumber: number, totalSets: total, targetReps: reps,
                                    targetWeight: next.weight, duration: duration, countdown: countdown))
            }
        }
        guard changed else { return }
        plan = updated
        persistActiveSession()
        syncLiveActivity()
    }

    func confirmParameters(stepId: String, fields: Set<String>) {
        guard var p = plan, let index = p.steps.firstIndex(where: { $0.id == stepId }), !fields.isEmpty else { return }
        for field in fields { p.steps[index].confirmParameter(field) }
        plan = p; planParamsDirty = true
        persistActiveSession()
    }

    /// Apply an explicitly confirmed load change without rebuilding the playback timeline.
    /// Completed set targets/records stay intact; only remaining sets receive the new load.
    /// When this step is already complete, change its saved-plan targets for the next workout.
    @discardableResult
    func updateStepWeight(stepId: String, weightKg: Double, markAsUserEdit: Bool = true) -> Bool {
        guard weightKg.isFinite, weightKg > 0, weightKg <= WeightUnit.kg.weightMax,
              var s = session, !s.completed, var p = plan,
              let index = p.steps.firstIndex(where: { $0.id == stepId }),
              p.steps[index].sets > 0 else { return false }

        let previous = p.steps[index]
        let completed = Set(s.completedSets.filter { $0.stepId == stepId }.map(\.setN))
        let setNumbers = 1...previous.sets
        let hasRemaining = setNumbers.contains { !completed.contains($0) }
        var updated = previous
        if markAsUserEdit { updated.confirmParameter("weight") }

        if completed.isEmpty || !hasRemaining {
            updated.weight = weightKg
            if previous.setWeights?.isEmpty == false {
                updated.setWeights = setNumbers.map { _ in weightKg }
            }
        } else {
            // Materialize completed targets before changing the common fallback. A completed
            // nil target must remain nil, so retain its old fallback in that rare mixed case.
            let hasUnweightedCompletedSet = setNumbers.contains {
                completed.contains($0) && previous.weightForSet($0) == nil
            }
            updated.weight = hasUnweightedCompletedSet ? previous.weight : weightKg
            updated.setWeights = setNumbers.map {
                completed.contains($0) ? previous.weightForSet($0) : weightKg
            }
        }

        guard updated != previous else { return true }
        p.steps[index] = updated
        plan = p
        // No expandPlan: rest segments, segment IDs, playback index and countdown deadlines
        // remain exactly as they were when the confirmation appeared.
        segments = segments.map { segment in
            guard segment.stepId == stepId,
                  case .exercise(let exercise, let setN, let total, let reps, _, let duration, let countdown) = segment.kind,
                  !completed.contains(setN) else { return segment }
            return Segment(id: segment.id, stepId: segment.stepId,
                           kind: .exercise(exercise, setNumber: setN, totalSets: total,
                                           targetReps: reps, targetWeight: weightKg,
                                           duration: duration, countdown: countdown))
        }
        s.lastActiveAt = Date()
        planParamsDirty = planParamsDirty || markAsUserEdit
        session = s
        syncLiveActivity()
        return true
    }

    /// 训练中编辑当前动作的参数. 全字段 mandatory — UI 端始终带当前值, 用户保存时写回所有 4 个字段.
    /// 不改 = UI 端把现值传回来. 清空 = UI 端把 nil 传回来 (比如清空 reps).
    ///
    /// 工作流:
    ///   1. 改 self.plan.steps[i] 的字段 (session-local, 不写回 DataStore)
    ///   2. 重新 expandPlan 生成新 segments — sets 改了会增删 segments
    ///   3. 把 segmentIndex 映射到新 segments 中相同 (stepId, setN) 的位置
    ///   4. completedSets 用 (stepId, setN) key, 重新生成后自动保留
    ///   5. 重置 endsAt — 改了 duration/reps 后, 旧倒计时目标不一定对, 简单重新计
    ///
    /// 边界:
    ///   - 新 sets < 当前 setN → 当前 set 已超出 → 跳到下一 step 第一个 exercise (没下一 step 则训练完成)
    ///   - 当前在 rest → 跳到该 step 中"尚未完成"的下一个 exercise; 都完成了跳下一 step
    /// 训练中编辑任意 step 参数 (不只是当前) — InlinePlaylist 右滑 Edit 用.
    /// 跟 updateCurrentStep 同 session-local 逻辑, 只是 base step 由参数指定不是 currentSegment.
    /// 当前在做的 segment 跟着原 stepId+setN 在新 segments 里 re-find 位置.
    func updateStep(
        _ stepId: String,
        sets newSets: Int,
        reps newReps: Int?,
        weight newWeight: Double?,
        duration newDuration: Int?,
        setReps newSetReps: [Int?]? = nil,
        setWeights newSetWeights: [Double?]? = nil,
        setDurations newSetDurations: [Int?]? = nil,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int,
        preserveTiming: Bool = false
    ) {
        guard var s = session, var p = plan else { return }
        guard let stepIdx = p.steps.firstIndex(where: { $0.id == stepId }) else { return }

        // 捕获当前位置 — 用户编辑别的 step 时, 当前 segment 位置可能因 sets 变化重排
        let curStepId = currentSegment?.stepId
        var curSetN: Int? = nil
        if case .exercise(_, let sn, _, _, _, _, _) = currentSegment?.kind {
            curSetN = sn
        }
        let wasRest = currentSegment?.isRest ?? false
        let restOrdinal = segments.prefix(s.segmentIndex).filter { $0.stepId == curStepId && $0.isRest }.count

        // 改 plan
        var step = p.steps[stepIdx]
        if step.sets != max(1, newSets) { step.confirmParameter("sets") }
        if step.reps != newReps || step.setReps != newSetReps { step.confirmParameter("reps") }
        if step.weight != newWeight || step.setWeights != newSetWeights { step.confirmParameter("weight") }
        if step.duration != newDuration { step.confirmParameter("duration") }
        step.sets = max(1, newSets)
        step.reps = newReps
        step.weight = newWeight
        step.setReps = newSetReps
        step.setWeights = newSetWeights
        step.setDurations = newSetDurations ?? step.setDurations
        step.duration = newDuration
        CrossExerciseLoadReference.clearIfUnsupported(&step)
        p.steps[stepIdx] = step
        self.plan = p

        // 重新 expand
        let newSegments = expandedSessionPlan(
            p,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: s
        )
        self.segments = newSegments

        // 映射当前 segmentIndex — 找不到原位置 (e.g. sets 被改小于当前组号) 时不能兜底 0
        // (播放头会跳回整场 segment 0), 跟 updateCurrentStep 同款: fallback 到下一 step 的 exercise.
        var newIdx: Int? = nil
        if let cstpid = curStepId, let csn = curSetN {
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == cstpid,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   n == csn { return true }
                return false
            }) ?? nextStepExerciseIndex(in: newSegments, plan: p, afterStepId: cstpid)
        } else if let cstpid = curStepId, wasRest {
            let rests = newSegments.indices.filter { newSegments[$0].stepId == cstpid && newSegments[$0].isRest }
            newIdx = (preserveTiming && !rests.isEmpty ? rests[min(restOrdinal, rests.count - 1)] : rests.first)
                ?? nextStepExerciseIndex(in: newSegments, plan: p, afterStepId: cstpid)
        }

        s.segmentIndex = min(max(0, newIdx ?? 0), max(0, newSegments.count - 1))
        // P0-4: 如果编辑的就是当前 step (改了 duration / countdown 类别), 重算计时器 —
        // 否则当前有氧段会沿用旧 endsAt, 显示的 duration 跟实际倒计时不符.
        if stepId == curStepId && !preserveTiming {
            let seg = newSegments[s.segmentIndex]
            s.endsAt = initialEndsAt(for: seg)
            s.pausedRemaining = nil
        }
        s.lastActiveAt = Date()
        planParamsDirty = true   // 必须先于 session 写 — session didSet 落盘会快照这个 flag
        session = s
        syncLiveActivity()
    }

    /// Small in-session adjustments retain completed prescriptions and the running clock.
    func adjustParameter(_ parameter: WorkoutParameter, by direction: Int, stepId: String,
                         unit: WeightUnit, exById: [String: Exercise], defaultRest: Int,
                         defaultBetweenExerciseRest: Int) {
        guard let before = session, let original = plan?.steps.first(where: { $0.id == stepId }) else { return }
        var target = original
        let delta = direction < 0 ? -1 : 1
        let done = Set(before.completedSets.filter { $0.stepId == stepId }.map(\.setN))
        var currentN: Int? = nil
        if currentSegment?.stepId == stepId, case .exercise(_, let n, _, _, _, _, _) = currentSegment?.kind { currentN = n }
        let firstPending = (1...max(1, original.sets)).first { !done.contains($0) } ?? original.sets
        let editedN = currentN ?? firstPending
        let segmentDuration = segments.compactMap { segment -> Int? in
            if segment.stepId == stepId, case .exercise(_, let n, _, _, _, let duration, _) = segment.kind, n == editedN { return duration }
            return nil
        }.first ?? 30
        switch parameter {
        case .sets:
            let pendingDuringRest = currentSegment?.stepId == stepId && currentSegment?.isRest == true && firstPending > (done.max() ?? 0) ? firstPending : 1
            let minimum = max(pendingDuringRest, max(done.max() ?? 0, currentN ?? 1))
            target.sets = max(minimum, min(99, original.sets + delta))
        case .reps:
            target.reps = min(999, max(1, (original.reps ?? original.repsForSet(editedN) ?? 1) + delta))
            target.setReps = (1...max(1, original.sets)).map { n in
                let old = original.repsForSet(n)
                return done.contains(n) ? old : min(999, max(1, (old ?? 1) + delta))
            }
        case .weight:
            let amount = unit.toKg(unit.weightStep) * Double(delta)
            let cap = unit.toKg(unit.weightMax)
            target.weight = min(cap, max(0, (original.weight ?? original.weightForSet(editedN) ?? 0) + amount))
            target.setWeights = (1...max(1, original.sets)).map { n in
                let old = original.weightForSet(n)
                return done.contains(n) ? old : min(cap, max(0, (old ?? 0) + amount))
            }
        case .duration:
            target.duration = max(5, (original.duration ?? original.durationForSet(editedN) ?? segmentDuration) + delta * 15)
            target.setDurations = (1...max(1, original.sets)).map { n in
                let old = original.durationForSet(n)
                return done.contains(n) ? old : max(5, (old ?? segmentDuration) + delta * 15)
            }
        }
        guard target != original else { return }
        confirmParameters(stepId: stepId, fields: [parameter.rawValue])
        updateStep(stepId, sets: target.sets, reps: target.reps, weight: target.weight, duration: target.duration,
                   setReps: target.setReps, setWeights: target.setWeights, setDurations: target.setDurations,
                   exById: exById, defaultRest: defaultRest, defaultBetweenExerciseRest: defaultBetweenExerciseRest,
                   preserveTiming: true)
        if parameter == .duration, currentN != nil, var updated = session {
            let seconds = Double((target.durationForSet(editedN) ?? 0) - (original.durationForSet(editedN) ?? segmentDuration))
            if let remaining = updated.pausedRemaining { updated.pausedRemaining = max(0, remaining + seconds) }
            else if let end = updated.endsAt { updated.endsAt = max(Date(), end.addingTimeInterval(seconds)) }
            session = updated
            syncLiveActivity()
        }
    }

    /// Replace future sets with a concrete variant and clear the previous exercise's load.
    /// Completed sets retain their original exercise/targets and actual records; only this
    /// session changes until the user explicitly saves its revised routine.
    ///
    /// 当前 segment 跟着 stepId+setN 在重 expand 后的 segments 里 re-find 位置, 用户不会跳段.
    func replaceStepExercise(
        _ stepId: String,
        newExerciseId: String,
        initialWeightKg: Double? = nil,
        suggestedStep: PlanStep? = nil,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int
    ) {
        guard var s = session, var p = plan else { return }
        guard let stepIdx = p.steps.firstIndex(where: { $0.id == stepId }),
              let replacement = exById[newExerciseId],
              exById[p.steps[stepIdx].exerciseId]?.id != replacement.id else { return }
        var snapshots = s.completedExerciseSnapshots ?? []
        var snapshotted = Set(snapshots.map { CompletedSet(stepId: $0.stepId, setN: $0.setN) })
        for segment in segments where segment.stepId == stepId {
            guard case .exercise(let exercise, let setN, let total, let reps, let weight, let duration, let countdown) = segment.kind,
                  s.completedSets.contains(CompletedSet(stepId: stepId, setN: setN)),
                  snapshotted.insert(CompletedSet(stepId: stepId, setN: setN)).inserted else { continue }
            snapshots.append(.init(stepId: stepId, setN: setN, exercise: exercise, totalSets: total,
                                   reps: reps, weight: weight, duration: duration, countdown: countdown))
        }
        s.completedExerciseSnapshots = snapshots.isEmpty ? nil : snapshots

        // 捕当前位置 — 跟 updateStep 同套路
        let curStepId = currentSegment?.stepId
        var curSetN: Int? = nil
        if case .exercise(_, let sn, _, _, _, _, _) = currentSegment?.kind {
            curSetN = sn
        }
        let wasRest = currentSegment?.isRest ?? false
        let restOffset = wasRest ? segments.prefix(s.segmentIndex + 1).filter {
            $0.stepId == curStepId && $0.isRest
        }.count - 1 : nil

        // 替 exerciseId — PlanStep.exerciseId 是 let, 用整 step 重建保留其它字段.
        let old = p.steps[stepIdx]
        p.steps[stepIdx] = PlanStep(
            id: old.id,
            exerciseId: replacement.id,
            sets: old.sets,
            reps: old.reps,
            weight: suggestedStep?.weight ?? initialWeightKg,
            setReps: old.setReps,
            setWeights: nil,
            setDurations: old.setDurations,
            duration: old.duration,
            restBetweenSets: old.restBetweenSets,
            rest: old.rest,
            parameterSuggestions: old.parameterSuggestions?.filter { $0.key != "weight" }
        )
        if let suggestion = suggestedStep?.parameterSuggestions?["weight"] {
            if p.steps[stepIdx].parameterSuggestions == nil { p.steps[stepIdx].parameterSuggestions = [:] }
            p.steps[stepIdx].parameterSuggestions?["weight"] = suggestion
        }
        let newSegments = expandedSessionPlan(
            p,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: s
        )
        guard !newSegments.isEmpty else { return }
        self.plan = p
        self.segments = newSegments

        // 映射当前 segmentIndex 回去
        var newIdx: Int? = nil
        if let cstpid = curStepId, let csn = curSetN {
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == cstpid,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   n == csn { return true }
                return false
            })
        } else if let cstpid = curStepId, wasRest {
            let rests = newSegments.indices.filter { newSegments[$0].stepId == cstpid && newSegments[$0].isRest }
            if let restOffset, rests.indices.contains(restOffset) { newIdx = rests[restOffset] }
        }
        s.segmentIndex = min(max(0, newIdx ?? 0), max(0, newSegments.count - 1))
        // P0-4: 替换的是当前 step 时, 新动作的 countdown 类别可能跟旧的不同 (力量↔有氧),
        // 必须重算计时器 — 否则力量→有氧卡 0:00 无法前进, 有氧→力量会被旧 endsAt 自动记一组.
        if stepId == curStepId, !wasRest {
            let seg = newSegments[s.segmentIndex]
            if s.playing {
                s.endsAt = initialEndsAt(for: seg)
                s.pausedRemaining = nil
            } else {
                s.endsAt = nil
                s.pausedRemaining = initialPausedRemaining(for: seg)
            }
        }
        s.lastActiveAt = Date()
        planParamsDirty = true   // 必须先于 session 写 — session didSet 落盘会快照这个 flag
        session = s
        syncLiveActivity()
    }

    func updateCurrentStep(
        sets newSets: Int,
        reps newReps: Int?,
        weight newWeight: Double?,
        duration newDuration: Int?,
        setReps newSetReps: [Int?]? = nil,
        setWeights newSetWeights: [Double?]? = nil,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int
    ) {
        guard var s = session, var p = plan, let cur = currentSegment else { return }
        let stepId = cur.stepId
        guard let stepIdx = p.steps.firstIndex(where: { $0.id == stepId }) else { return }

        // 捕获当前位置信息 — 重新展开后用来定位新 index
        var curSetN: Int? = nil
        if case .exercise(_, let sn, _, _, _, _, _) = cur.kind {
            curSetN = sn
        }
        let wasRest = cur.isRest

        // 改 plan 数据 (session-local copy)
        var step = p.steps[stepIdx]
        if step.sets != max(1, newSets) { step.confirmParameter("sets") }
        if step.reps != newReps || step.setReps != newSetReps { step.confirmParameter("reps") }
        if step.weight != newWeight || step.setWeights != newSetWeights { step.confirmParameter("weight") }
        if step.duration != newDuration { step.confirmParameter("duration") }
        step.sets = max(1, newSets)
        step.reps = newReps
        step.weight = newWeight
        step.setReps = newSetReps
        step.setWeights = newSetWeights
        step.duration = newDuration
        CrossExerciseLoadReference.clearIfUnsupported(&step)
        p.steps[stepIdx] = step
        self.plan = p

        // 重新展开
        let newSegments = expandedSessionPlan(
            p,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: s
        )
        self.segments = newSegments

        // 映射 segmentIndex
        var newIdx: Int? = nil
        if let sn = curSetN {
            // 当前在 exercise — 优先找 (stepId, sn). 找不到 (sets 减到 < sn) → 下一 step.
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == stepId,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   n == sn { return true }
                return false
            }) ?? nextStepExerciseIndex(in: newSegments, plan: p, afterStepId: stepId)
        } else if wasRest {
            // 当前在 rest — 找该 step 内"尚未完成"的下一 exercise
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == stepId,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   !s.completedSets.contains(CompletedSet(stepId: stepId, setN: n)) {
                    return true
                }
                return false
            }) ?? nextStepExerciseIndex(in: newSegments, plan: p, afterStepId: stepId)
        }

        guard let resolved = newIdx else {
            // 无处可去 — 训练完成 (用户把 sets 改到很小, 之前的 set 都做完了)
            s.completed = true
            s.playing = false
            s.endsAt = nil
            session = s
            LiveActivityManager.shared.end()
            syncWatch()
            return
        }

        s.segmentIndex = min(max(0, resolved), max(0, newSegments.count - 1))
        let seg = newSegments[s.segmentIndex]
        s.endsAt = initialEndsAt(for: seg)
        s.pausedRemaining = nil
        s.playing = true
        s.lastActiveAt = Date()
        planParamsDirty = true  // 改了参数 — 结束时提示保存 (先于 session 写: didSet 落盘快照它)
        session = s
        syncLiveActivity()
    }

    /// 训练中拖拽排序 plan.steps. 跟 updateCurrentStep 一样, 全程 session-local — 改 self.plan
    /// + 重新 expandPlan + 定位新 segmentIndex, 不写回 DataStore.plans.
    ///
    /// 行为:
    ///   - completedSets 用 (stepId, setN) key, 不受顺序影响, 自动保留
    ///   - 当前 step 跟着位置走 (用户在做 chest press, 拖到 plan 第一 → chest press 仍是当前)
    ///   - segmentIndex 映射到 (curStepId, curSetN) 在新 segments 里的新位置
    ///   - endsAt / pausedRemaining 都保留 — 拖排序不打断计时
    ///
    /// 用户长期想保存这个顺序 → 走 Plan 编辑器 (跟 updateCurrentStep 一致, 训练中改的都不持久).
    func reorderSteps(
        from source: IndexSet,
        to destination: Int,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int
    ) {
        guard var s = session, var p = plan, let cur = currentSegment else { return }
        let curStepId = cur.stepId
        var curSetN: Int? = nil
        if case .exercise(_, let sn, _, _, _, _, _) = cur.kind {
            curSetN = sn
        }
        let wasRest = cur.isRest

        // 移动 — SwiftUI ForEach.onMove 的语义跟 Array.move(fromOffsets:toOffset:) 一致
        p.steps.move(fromOffsets: source, toOffset: destination)
        self.plan = p

        // 重新展开 segments. completedSets 是按 (stepId, setN) 索引, 不依赖顺序.
        let newSegments = expandedSessionPlan(
            p,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: s
        )
        self.segments = newSegments

        // 把 segmentIndex 重新映射到当前 (stepId, setN) 在新 segments 中的位置.
        var newIdx: Int? = nil
        if let sn = curSetN {
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == curStepId,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   n == sn { return true }
                return false
            })
        } else if wasRest {
            // 当前在 rest 段 — 找当前 step 的 rest segment (同 stepId + isRest).
            newIdx = newSegments.firstIndex(where: { $0.stepId == curStepId && $0.isRest })
        }

        guard let resolved = newIdx else {
            // 不应发生 (move 不会让 curStepId 消失) — 兜底回 0.
            s.segmentIndex = 0
            session = s
            syncLiveActivity()
            return
        }

        s.segmentIndex = min(max(0, resolved), max(0, newSegments.count - 1))
        s.lastActiveAt = Date()
        planParamsDirty = true  // 改了顺序 — 结束时提示保存 (先于 session 写: didSet 落盘快照它)
        session = s
        syncLiveActivity()
    }

    /// 训练中删除一个 step (session-local, 不写回 DataStore.plans).
    /// 跟 reorderSteps / updateCurrentStep 同模式: 改 self.plan + 重新 expandPlan + 定位新 segmentIndex.
    ///
    /// 边界处理:
    ///   - 删的是当前 step → 跳到下一个未完成 exercise (没有则训练完成)
    ///   - 删的是其它 step → 当前 (stepId, setN) 在新 segments 里找到新位置
    ///   - 该 step 的 completedSets 一并清掉 (避免孤儿数据)
    ///   - plan 删空 → 训练完成
    /// 训练中追加一个新动作 — 自由训练 / 中途想加一个的入口. 跟 ExercisePickerSheet 同 onPick
    /// 语义: 选完一个 exercise, 用合理 defaults 构造 PlanStep, 加到 plan.steps 末尾, 重 expand.
    /// 当前 segment 跟着 stepId+setN 在新 segments 里 re-find, 用户不会跳段.
    ///
    /// reps / sets 默认值走用户 Training Preferences (settings.trainingGoal + defaultSetsPerExercise),
    /// 而非硬编码 3 sets × 10 reps. 让"中途加一个动作"也尊重用户设的训练目标.
    func appendStep(
        exercise: Exercise,
        settings: UserSettings,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int,
        initialWeightKg: Double? = nil,
        suggestedStep: PlanStep? = nil
    ) {
        guard var s = session, var p = plan else { return }

        // 捕当前位置 — 跟 updateStep / replaceStepExercise 同模式.
        let curStepId = currentSegment?.stepId
        var curSetN: Int? = nil
        if case .exercise(_, let sn, _, _, _, _, _) = currentSegment?.kind {
            curSetN = sn
        }
        let wasRest = currentSegment?.isRest ?? false

        // Defaults 从 Training Preferences 推导:
        //   - sets = settings.defaultSetsPerExercise
        //   - reps (力量动作) = goal × mechanic (compound vs isolation)
        //   - rest = settings.defaultRestSeconds (用户调过) 否则 goal 推荐值
        let isCompound = exercise.mechanic == .compound
        let reps: Int? = exercise.category == .strength
            ? (isCompound
               ? settings.trainingGoal.defaultRepsForCompound()
               : settings.trainingGoal.defaultRepsForIsolation())
            : nil
        var newStep = PlanStep(
            id: "step-\(exercise.id)-\(Int(Date().timeIntervalSince1970))",
            exerciseId: exercise.id,
            sets: settings.defaultSetsPerExercise,
            reps: reps,
            weight: exercise.category == .strength ? initialWeightKg : nil,
            duration: exercise.category != .strength ? 30 : nil,
            restBetweenSets: settings.defaultRestSeconds,
            rest: 0
        )
        if let suggestedStep {
            newStep.sets = suggestedStep.sets; newStep.reps = suggestedStep.reps
            newStep.weight = suggestedStep.weight; newStep.duration = suggestedStep.duration
            newStep.setReps = suggestedStep.setReps; newStep.setWeights = suggestedStep.setWeights
            newStep.setDurations = suggestedStep.setDurations
            newStep.parameterSuggestions = suggestedStep.parameterSuggestions
        } else {
            newStep.markSuggested("sets", value: Double(newStep.sets), source: .preference)
            if let reps = newStep.reps { newStep.markSuggested("reps", value: Double(reps), source: .preference) }
        }
        p.steps.append(newStep)
        self.plan = p

        let newSegments = expandedSessionPlan(
            p,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: s
        )
        self.segments = newSegments

        // 映射当前 segmentIndex 回去
        var newIdx: Int? = nil
        if let cstpid = curStepId, let csn = curSetN {
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == cstpid,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   n == csn { return true }
                return false
            })
        } else if let cstpid = curStepId, wasRest {
            newIdx = newSegments.firstIndex(where: { $0.stepId == cstpid && $0.isRest })
        }
        if s.awaitingExercise == true {
            newIdx = newSegments.firstIndex { $0.stepId == newStep.id && $0.isExercise }
            s.awaitingExercise = false
            s.playing = true
            s.endsAt = newIdx.flatMap { initialEndsAt(for: newSegments[$0]) }
            s.pausedRemaining = nil
        }
        s.segmentIndex = min(max(0, newIdx ?? 0), max(0, newSegments.count - 1))
        s.lastActiveAt = Date()
        planParamsDirty = true   // 必须先于 session 写 — session didSet 落盘会快照这个 flag
        session = s
        syncLiveActivity()
    }

    /// removeRecords(exerciseId, planId, since, count): 删本场该动作最近 count 条 SetRecord.
    /// 训练中删掉一个已做过组的动作时调用 — 否则那几条记录成孤儿, 历史卡按原始记录数多算
    /// (播放列表已删到 N 组, 历史却仍显示 N+被删动作组数). 传了才删, 跟 undoLastCompletedSet 同套.
    func deleteStep(
        _ stepId: String,
        exById: [String: Exercise],
        defaultRest: Int,
        defaultBetweenExerciseRest: Int,
        removeRecords: ((_ exerciseId: String, _ planId: String?, _ since: Date, _ count: Int) -> Void)? = nil
    ) {
        guard var s = session, var p = plan else { return }
        // 删之前捕获当前位置, 用于映射
        let curStepId = currentSegment?.stepId
        let oldSegIdx = s.segmentIndex  // P2-7: 删当前 step 时从这个位置向后找, 不从 0 倒回
        var curSetN: Int? = nil
        if case .exercise(_, let sn, _, _, _, _, _) = currentSegment?.kind {
            curSetN = sn
        }

        // 删记录前先算: 被删 step 的动作 + 本场它已打勾的组数 → 连带清掉那几条 SetRecord.
        // 顺序要紧: 在 removeAll / filter 之前读, 之后 p.steps 与 completedSets 已不含该 step.
        let deletedExId = p.steps.first(where: { $0.id == stepId })?.exerciseId
        var loggedCounts: [String: Int] = [:]
        for completed in s.completedSets where completed.stepId == stepId {
            let exerciseID = s.completedExerciseSnapshots?.first {
                $0.stepId == stepId && $0.setN == completed.setN
            }?.exercise.id ?? deletedExId
            if let exerciseID { loggedCounts[exerciseID, default: 0] += 1 }
        }
        for (exerciseID, count) in loggedCounts {
            removeRecords?(exerciseID, s.planId, s.startedAt, count)
        }

        // 移除 step + 清掉该 step 的 completedSets (孤儿数据)
        p.steps.removeAll { $0.id == stepId }
        s.completedSets = s.completedSets.filter { $0.stepId != stepId }
        s.completedExerciseSnapshots?.removeAll { $0.stepId == stepId }

        self.plan = p

        // plan 删空 → 训练完成
        if p.steps.isEmpty {
            s.completed = true
            s.playing = false
            s.endsAt = nil
            planParamsDirty = true   // 先于 session 写 — didSet 落盘快照它
            session = s
            segments = []
            LiveActivityManager.shared.end()
            syncWatch()
            return
        }

        // 重新 expand segments + 定位 segmentIndex
        let newSegments = expandedSessionPlan(
            p,
            exById: exById,
            defaultRest: defaultRest,
            defaultBetweenExerciseRest: defaultBetweenExerciseRest,
            session: s
        )
        self.segments = newSegments

        var newIdx: Int? = nil
        if curStepId == stepId {
            // P2-7: 删的是当前 step — 从删除位置 *向后* 找第一个未完成 exercise (不从 0 倒回,
            // 否则会把用户甩回更早跳过的 step). 向后没有了再 fallback 全局找 / 0.
            let anchor = min(max(0, oldSegIdx), max(0, newSegments.count - 1))
            func firstUncompleted(from start: Int) -> Int? {
                guard start < newSegments.count else { return nil }
                for k in start..<newSegments.count {
                    guard case .exercise(_, let sn, _, _, _, _, _) = newSegments[k].kind else { continue }
                    if !s.completedSets.contains(CompletedSet(stepId: newSegments[k].stepId, setN: sn)) {
                        return k
                    }
                }
                return nil
            }
            newIdx = firstUncompleted(from: anchor) ?? firstUncompleted(from: 0) ?? 0
        } else if let stp = curStepId, let sn = curSetN {
            // 删的是其它 step — 当前位置可能 index 变了, 重新找
            newIdx = newSegments.firstIndex(where: {
                if $0.stepId == stp,
                   case .exercise(_, let n, _, _, _, _, _) = $0.kind,
                   n == sn { return true }
                return false
            })
        }

        s.segmentIndex = min(max(0, newIdx ?? 0), max(0, newSegments.count - 1))
        s.lastActiveAt = Date()
        // 进入新 segment, 重置计时
        let seg = newSegments[s.segmentIndex]
        s.endsAt = initialEndsAt(for: seg)
        s.pausedRemaining = nil
        planParamsDirty = true  // 改了 plan — 结束时提示保存 (先于 session 写: didSet 落盘快照它)
        session = s
        syncLiveActivity()
    }

    // MARK: - Watch 镜像 (#apple-watch)

    /// 把当前 session 翻译成手表的一帧状态. session nil → idle; completed → done.
    func makeWatchState() -> WatchSyncState {
        guard let s = session else { var idle = WatchSyncState.idle; idle.discarded = watchDiscarded; return idle }
        var st = WatchSyncState()
        st.planName = plan?.name ?? ""
        st.workoutSessionID = workoutSessionID
        st.heartRateSharingEnabled = heartRateReadEnabled
        st.weightUnit = WeightUnitProvider.current.rawValue
        st.canUndo = canUndoPlayback
        st.rows = (plan?.steps ?? []).map { step in
            WatchExerciseRow(id: step.id, name: segments.compactMap { segment -> String? in
                guard segment.stepId == step.id, case .exercise(let ex, _, _, _, _, _, _) = segment.kind else { return nil }
                return ex.displayName
            }.first ?? step.exerciseId, detail: "", completed: s.completedSets.filter { $0.stepId == step.id }.count, total: step.sets)
        }
        st.totalSets = segments.filter(\.isExercise).count
        st.doneSets = s.completedSets.count
        if s.completed {
            st.mode = .done
            if let bytes = st.encoded() { st.context = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
            return st
        }
        guard let seg = currentSegment else { return .idle }
        st.paused = !s.playing
        st.endsAt = s.playing ? s.endsAt : nil
        st.pausedRemaining = s.pausedRemaining.map { Int(ceil($0)) }
        switch seg.kind {
        case .rest:
            st.mode = .rest
            st.nextExercise = nextExerciseName(after: seg)
            if case .rest(let duration) = seg.kind { st.restDuration = duration }
            if let upcoming = nextUnfinishedSegment(), case .exercise(let ex, let n, let total, let reps, let weight, _, _) = upcoming.kind {
                st.exerciseName = ex.displayName; st.stepID = upcoming.stepId
                st.setN = n; st.setTotal = total; st.reps = reps; st.weight = weight
                st.expectsWeight = weight != nil || ExerciseWeightReference.expectsLoad(ex)
            }
        case .exercise(let ex, let setN, let total, let reps, let weight, let dur, let countdown):
            st.mode = .exercise
            st.stepID = seg.stepId; st.reps = reps; st.weight = weight
            st.expectsWeight = weight != nil || ExerciseWeightReference.expectsLoad(ex)
            st.exerciseName = ex.displayName
            st.setN = setN
            st.setTotal = total
            st.manualConfirm = !countdown
            var parts: [String] = []
            if let reps {
                parts.append(String(format: NSLocalizedString("%d reps", comment: "watch detail"), reps))
            }
            if let weight, weight > 0 {
                let num = weight.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", weight) : String(format: "%.1f", weight)
                parts.append("\(num) kg")
            }
            if countdown, let dur, dur > 0 {
                parts.append(String(format: "%d:%02d", dur / 60, dur % 60))
            }
            st.detail = parts.joined(separator: " · ")
        }
        // Fingerprint excludes wall-clock sentAt; edits and playback transitions invalidate old commands.
        if let bytes = st.encoded() { st.context = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        return st
    }

    /// Commands are bound to the exact mirrored prescription and playback state.
    @discardableResult
    func applyWatchCommand(_ command: WatchCommand, data: DataStore) -> Bool {
        let state = makeWatchState()
        guard command.sessionID == workoutSessionID, command.context == state.context,
              (session?.completed == false || command.kind == .undo) else { return false }
        defer { refreshLoadSuggestions(using: data) }
        switch command.kind {
        case .advance: advance { data.recordSet($0) }
        case .togglePlay: togglePlay()
        case .undo: return undoPlayback { data.removeSetRecord(id: $0) }
        case .jump:
            guard let id = command.stepID else { return false }
            return jumpToFirstUnfinishedStep(stepId: id)
        case .rest:
            guard state.mode == .rest, let seconds = command.value, seconds.isFinite,
                  seconds >= 0, seconds <= 3600 else { return false }
            updateCurrentRest(seconds: Int(seconds)) // Explicitly this rest only, never silently change preferences.
        case .reps, .weight:
            guard state.mode == .exercise, let stepID = state.stepID,
                  let n = session, let segment = currentSegment,
                  case .exercise(_, let number, _, _, _, _, _) = segment.kind,
                  !n.completedSets.contains(.init(stepId: stepID, setN: number)),
                  var step = plan?.steps.first(where: { $0.id == stepID }),
                  let value = command.value, value.isFinite else { return false }
            if command.kind == .reps {
                guard state.manualConfirm, value >= 1, value <= 999, value.rounded() == value else { return false }
                var values = (1...max(1, step.sets)).map { step.repsForSet($0) }
                values[number - 1] = Int(value); step.setReps = values
            } else {
                guard state.expectsWeight == true, value >= 0, value <= 500 else { return false }
                if case .exercise(let ex, _, _, _, _, _, _) = segment.kind { data.rememberWeight(value, for: ex) }
                var values = (1...max(1, step.sets)).map { step.weightForSet($0) }
                values[number - 1] = value; step.setWeights = values
            }
            updateStep(stepID, sets: step.sets, reps: step.reps, weight: step.weight, duration: step.duration,
                       setReps: step.setReps, setWeights: step.setWeights, setDurations: step.setDurations,
                       exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                       defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds, preserveTiming: true)
        case .finish: finishEarly()
        case .discard:
            discard { data.discardWorkout($0, recordIDs: $1) }
        }
        return true
    }

    private func syncWatch() {
        WatchSyncManager.shared.sync(makeWatchState())
    }

    /// App 启动时推一帧当前状态 — 不然手机被杀后重启, 手表会永远停在上一次训练的旧帧
    /// (没有 mutation 就没有 sync). MasoApp .task 调.
    func pushWatchState() { syncWatch() }

    /// 找指定 stepId 之后的下一 step 的第一个 exercise segment index. 没有 → nil.
    private func nextStepExerciseIndex(in segs: [Segment], plan: Plan, afterStepId stepId: String) -> Int? {
        guard let curStepIdx = plan.steps.firstIndex(where: { $0.id == stepId }),
              curStepIdx + 1 < plan.steps.count else { return nil }
        let nextStepId = plan.steps[curStepIdx + 1].id
        return segs.firstIndex(where: { $0.stepId == nextStepId && $0.isExercise })
    }
}

// MARK: - 1Hz 计时器, 驱动 endsAt → 自动 advance + 倒计时刷新

struct SessionTickerView: View {
    @Environment(TrainingSessionStore.self) private var store
    @Environment(DataStore.self) private var data
    @State private var tick = 0

    var body: some View {
        Color.clear
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                // 1) 6h idle auto-complete
                store.checkAutoComplete()
                // 2) endsAt 到点自动 advance
                guard let s = store.session, s.playing, let endsAt = s.endsAt else { return }
                if endsAt <= Date() {
                    store.advance { rec in data.recordSet(rec) }
                } else {
                    // 改 store 上的 observed property — 所有读 remainingSeconds 的 view 都会重算.
                    // (之前用 SessionTickerView 内部 @State tick 只让 ticker 自己刷新, 没用.)
                    store.tickProbe &+= 1
                    tick &+= 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // app 从后台回前台立即检查一次 (用户可能关屏 8h 后再开)
                store.checkAutoComplete()
            }
            .allowsHitTesting(false)
    }
}
