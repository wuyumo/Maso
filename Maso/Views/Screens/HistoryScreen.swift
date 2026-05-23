import SwiftUI

// 训练状态页 — 显示 7 天活跃肌群 + 训练记录卡片
//
// 卡片设计: 按 "训练计划 (plan)" 维度展示, 而不是按动作组拆分.
// 一张卡片 = 一次完整的训练 session (同一 planId + 同一 calendar 日).
// 没有 planId 的记录 (自由组) 单独成卡, kicker 显示 "Quick Workout".
//
// 点卡片 → 打开 session 详情 sheet, 可查看每个动作的组数 + 再次训练.
struct HistoryScreen: View {
    @Environment(DataStore.self) private var data
    /// 点 "再次训练" 时回调到 RootView, 用统一的 startTraining 入口启动
    let onReplay: (Plan) -> Void
    /// 右上角齿轮 → 弹 Settings sheet (RootView 持有 sheet state)
    let onOpenSettings: () -> Void

    @State private var selectedSession: SessionSummary?
    @State private var showCalendar: Bool = false
    /// 7 天前的训练记录默认收折, 用户点 "Show older" 才展开.
    /// 7 天最近的训练对用户更相关 (回顾、规划), 更早的 long tail 不需要默认展开.
    @State private var showOlderSessions: Bool = false
    /// 长按 → contextMenu Delete → 二次确认 alert. 存待删 session (planId + day) 区分.
    @State private var pendingDeleteSession: SessionSummary? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Page title row — 标题 + 右上角设置入口 (跟 TodayScreen 同款).
                // 原"肌肉状态"卡 + Share 按钮已撤掉 — 肌肉状态 hero 卡挪到 Today tab,
                // Share 入口走 SessionDetailSheet (点开一条记录里有). 这个 tab 现在
                // 只剩纯粹的"训练记录列表", 标题改成 "Workout Records".
                HStack(alignment: .top, spacing: 12) {
                    Text("Workout Records")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Spacer()
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .frame(width: 34, height: 34)
                            .background(MasoColor.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .padding(.top, MasoMetrics.pagePaddingTop)

                // 训练记录 — 卡片样式 (一张卡 = 一次完整训练)
                // 7 天前的 sessions 收到"Show older"折叠按钮下面 — 减少 default 视觉负担,
                // 长期用户的几百张卡不会一开就 dump 全屏.
                let allSessions = groupedSessions()
                if allSessions.isEmpty {
                    Text("No workouts yet")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.vertical, 56)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    let cutoff = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
                    let recent = allSessions.filter { $0.day >= cutoff }
                    let older = allSessions.filter { $0.day < cutoff }

                    // section title — 放大成 18pt bold (从 10pt kicker)
                    Text("Workouts")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(recent) { session in
                            sessionCardRow(session)
                        }
                    }

                    // 7 天前 sessions 折叠区 — 有更早的才显示这个 toggle
                    if !older.isEmpty {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) { showOlderSessions.toggle() }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: showOlderSessions ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .heavy))
                                Text(showOlderSessions
                                     ? NSLocalizedString("Hide older workouts", comment: "")
                                     : String(format: NSLocalizedString("Show %d older workout(s)", comment: ""), older.count))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(MasoColor.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(MasoColor.surface.opacity(0.5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)

                        if showOlderSessions {
                            VStack(spacing: 12) {
                                ForEach(older) { session in
                                    sessionCardRow(session)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .sheet(isPresented: $showCalendar) {
            WorkoutCalendarScreen(
                sessionDates: workoutDateSet(),
                totalSetsThisWeek: totalSetsThisWeek,
                streakDaysCount: currentStreakDays
            )
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(
                session: session,
                exerciseStats: exerciseStats(for: session),
                replayPlan: replayPlan(for: session),
                onReplay: { plan in
                    selectedSession = nil
                    DispatchQueue.main.async { onReplay(plan) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        // 删除 session 的二次确认 — 长按 SessionCard → contextMenu Delete 触发.
        // 删除是 destructive (清掉这场训练的所有 SetRecord, 包括 PR), 必须 confirm.
        .alert("Delete this workout?", isPresented: Binding(
            get: { pendingDeleteSession != nil },
            set: { if !$0 { pendingDeleteSession = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let s = pendingDeleteSession {
                    data.deleteSession(planId: s.planId, day: s.day)
                }
                pendingDeleteSession = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSession = nil }
        } message: {
            Text("All sets and PRs from this workout will be removed. Your plans stay.")
        }
    }

    // MARK: - Train the gaps

    /// "可训练大肌群"集合 — 来自 MuscleSelector.groupedRows 的 major 维度.
    /// 之前 gapSections 只走 6 个顶层 section (chest/back/shoulders/arms/core/legs),
    /// 漏了 biceps / triceps / forearms / quads / hams / glutes / calves / adductors 等更细的肌群.
    /// 现在 1:1 对齐 picker 的 12 个 major chip — "用户能选" = "gap 能补".
    ///
    /// 注意: arms / legs / core 这三个 section "聚合"概念不在这, 因为我们已经按
    /// biceps/triceps/forearms (替代 arms) + quads/hams/glutes/calves/adductors (替代 legs)
    /// 拆开了, 重复算 arms/legs 会导致同一肌群被 catch-up 多次.
    private static let trainableMajorMuscles: [MuscleGroup] = [
        .chest, .back, .shoulders,
        .biceps, .triceps, .forearms,
        .core,
        .quads, .hamstrings, .glutes, .adductors, .calves,
    ]

    /// 找出"需补"的 major 肌群 — 该肌群下所有 anatomy 肌肉都 ≥3 天没被练 (或从没练过).
    /// 返回顺序按 trainableMajorMuscles 列表 (chest 优先, calves 兜底).
    private func gapMajorMuscles() -> [MuscleGroup] {
        let lastMap = muscleLastTrainedMap()
        let now = Date()
        let cutoff: TimeInterval = 3 * 86400
        var gaps: [MuscleGroup] = []
        for major in Self.trainableMajorMuscles {
            // 把这个 major 展开成它在 anatomy 上的所有 sub. 例 chest → upperChest/midChest/lowerChest.
            // 用 composites + 自己 — expandAnatomyMuscles 自动处理.
            let anatomy = expandAnatomyMuscles([major])
            guard !anatomy.isEmpty else { continue }
            let allStale = anatomy.allSatisfy { m in
                guard let last = lastMap[m] else { return true }
                return now.timeIntervalSince(last) >= cutoff
            }
            if allStale { gaps.append(major) }
        }
        return gaps
    }

    /// 兼容旧 UI 调用 (`Train the gaps` 按钮 disabled state).
    /// 实际选动作仍走 gapMajorMuscles → 更细粒度.
    private func gapSections() -> [MuscleGroup] {
        gapMajorMuscles()
    }

    /// 单个 SessionCard + tap handler — 给 recent / older 两个 list 共享.
    /// 长按 → contextMenu Delete → alert 二次确认. (HistoryScreen 顶部有 muscle status hero card,
    /// 没改成 List, 所以用 contextMenu 替代右滑 — 删除能力一致.)
    @ViewBuilder
    private func sessionCardRow(_ session: SessionSummary) -> some View {
        SessionCard(
            session: session,
            photo: data.sessionPhoto(forSessionId: session.id),
            onReplay: replayPlan(for: session).map { plan in
                { onReplay(plan) }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedSession = session }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteSession = session
            } label: {
                Label {
                    Text("Delete workout")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Share data 计算 (给 UnifiedShareCard 各 section 用)

    /// 最新一次 session 的 WorkoutSectionData — 给"肌肉状态卡"的"也加上 workout section"toggle 用.
    /// 没有 session → 返回 nil (UnifiedShareCard 会自动跳过该 section).
    private func mostRecentWorkoutSection() -> WorkoutSectionData? {
        let sessions = groupedSessions()
        guard let s = sessions.first else { return nil }
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        let names = exerciseStats(for: s).map { $0.exercise.displayName }
        return WorkoutSectionData(
            dateLabel: df.string(from: s.day),
            planName: s.planName ?? NSLocalizedString("Free workout", comment: ""),
            durationLabel: "~\(max(5, s.setCount * 2))m",
            setCount: s.setCount,
            exerciseCount: s.exerciseCount,
            prCount: s.prCount,
            muscles: s.muscles,
            exerciseNames: names
        )
    }

    /// 本周 (最近 7 天) 训练 session 数 — 不同 calendar 日算 1 次
    private var workoutsThisWeekCount: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let days = Set(data.sets.filter { $0.performedAt >= cutoff }.map { cal.startOfDay(for: $0.performedAt) })
        return days.count
    }

    /// 本周总组数
    private var totalSetsThisWeek: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        return data.sets.filter { $0.performedAt >= cutoff }.count
    }

    /// 连续训练天数 (相对今天向前数, 直到出现一个没训练的日子). 0 = 今天没训练.
    private var currentStreakDays: Int {
        let cal = Calendar.current
        let days = workoutDateSet()
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        // 包括今天 — 如果今天没训练, streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// 本周练到的大肌群 section 数 (chest/back/shoulders/arms/core/legs 6 个里命中几个)
    private var muscleSectionsHitThisWeek: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        var sections = Set<MuscleGroup>()
        for set in data.sets where set.performedAt >= cutoff {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let s = m.section { sections.insert(s) }
            }
        }
        return sections.count
    }

    /// 一键: 找 gap → 智能挑动作 → 拼 plan → 启动训练
    ///
    /// 算法 (per gap major muscle):
    /// 1. expandAnatomyMuscles 拿到该 major 的全部 sub
    /// 2. 在 ExerciseDB strength 类动作里, 用 QuickWorkoutScreen 同款 score(_:against:) 算分
    /// 3. 收藏 (favoriteExerciseIds) 命中的优先排前
    /// 4. 取 top 1-2 个作为这个 gap 的动作
    /// 5. 全部 gap 累加, 最多 12 个动作 (单次训练不要太长)
    ///
    /// 跟之前的差别: 之前用 6 个固定 signatureExercises 字典, 只覆盖 6 个 section,
    /// 漏了 biceps/triceps/forearms/quads/hams/glutes/calves/adductors 等. 现在按 picker
    /// 12 个 major 全覆盖, 而且按用户的收藏 + ExerciseDB 评分智能挑.
    private func startGapWorkout() {
        let gaps = gapMajorMuscles()
        guard !gaps.isEmpty else { return }
        let favSet = Set(data.settings.favoriteExerciseIds)
        var seenExerciseIds = Set<String>()   // 避免一个 plan 里同一动作出现两次 (e.g. squat 命中 quads + glutes)
        var steps: [PlanStep] = []
        var idx = 0
        // 单次训练动作上限 — 12 个 (gap 数量 × 1.5 平均, 12 gap × 1 = 12 ok). 太多用户做不完.
        let maxSteps = 12

        for major in gaps {
            // 1. 计算这个 major 对应的全部 anatomy 肌肉 (匹配用)
            let targetMuscles = expandAnatomyMuscles([major])
            // 2. 在所有 strength 动作里打分
            //    (gap workout 默认走 strength —— 衰减状态做拉伸/cardio 反馈不准, 用户期待是补练)
            struct Scored { let ex: Exercise; let score: Int; let isFav: Bool }
            var scored: [Scored] = []
            for ex in data.exercises where ex.category == .strength {
                if seenExerciseIds.contains(ex.id) { continue }
                let s = gapScore(ex, against: targetMuscles)
                if s > 0 {
                    scored.append(Scored(ex: ex, score: s, isFav: favSet.contains(ex.id)))
                }
            }
            // 3. 收藏前置 + score 降序
            scored.sort { lhs, rhs in
                if lhs.isFav != rhs.isFav { return lhs.isFav && !rhs.isFav }
                return lhs.score > rhs.score
            }
            // 4. 取 top 1-2 个 (compound 通常是 top 1, accessory top 2)
            let picksPerGap = 2
            for pick in scored.prefix(picksPerGap) {
                let ex = pick.ex
                seenExerciseIds.insert(ex.id)
                let isStrength = ex.category == .strength
                steps.append(PlanStep(
                    id: "gap-\(idx)-\(ex.id)",
                    exerciseId: ex.id,
                    sets: 3,
                    reps: isStrength ? 10 : nil,
                    weight: isStrength ? 0 : nil,
                    duration: isStrength ? nil : 45,
                    restBetweenSets: 90,
                    rest: 0
                ))
                idx += 1
                if steps.count >= maxSteps { break }
            }
            if steps.count >= maxSteps { break }
        }
        guard !steps.isEmpty else { return }
        let now = Date()
        let name = String(
            format: NSLocalizedString("Catch-up: %@", comment: ""),
            gaps.prefix(3).map(\.displayName).joined(separator: " + ")
        )
        // 用稳定 id, 重复点 Train the gaps 时覆盖同一张 plan, 不污染 Plans 列表
        let plan = Plan(
            id: "plan-catchup",
            name: name,
            steps: steps,
            createdAt: now,
            updatedAt: now
        )
        data.updatePlan(plan)  // upsert by id
        onReplay(plan)
    }

    /// score 跟 QuickWorkoutScreen.score(_:against:) 同款 — 复制一份避免 cross-screen private 调用.
    /// 公式: Σ max(20, 100 - idx*18). idx 越靠前 (primary) 加分越高.
    private func gapScore(_ ex: Exercise, against targets: Set<MuscleGroup>) -> Int {
        var total = 0
        for (idx, mg) in ex.muscleGroups.enumerated() {
            if targets.contains(mg) {
                total += max(20, 100 - idx * 18)
            }
        }
        return total
    }

    /// 每个 anatomy 直接肌肉 → 最近一次被训练的时间.
    /// 走 MuscleStatusCompute 共享逻辑 — 跟 SessionDetailSheet / QuickMuscleStep 同一份兜底.
    private func muscleLastTrainedMap() -> [MuscleGroup: Date] {
        MuscleStatusCompute.muscleLastTrainedMap(sets: data.sets, exById: data.exById)
    }

    /// 衰减映射 — 间距加大让三档对比明显:
    /// 0..1 d → 1.0 (满色); 1..2 d → 0.6; 2..3 d → 0.3; ≥ 3 d → nil (默认灰).
    /// 之前 1.0/0.7/0.4 三档视觉差异不够明显 (人眼对低 alpha 差异不敏感),
    /// 现在 0.4 + 0.3 + 0.3 间隔, 整体更分明.
    private func opacityFor(muscle m: MuscleGroup, lastMap: [MuscleGroup: Date]) -> Double? {
        MuscleStatusCompute.opacityFor(muscle: m, lastMap: lastMap)
    }

    /// 用户有训练的日历日集合 (供日历高亮)
    private func workoutDateSet() -> Set<Date> {
        let cal = Calendar.current
        var out: Set<Date> = []
        for s in data.sets {
            out.insert(cal.startOfDay(for: s.performedAt))
        }
        return out
    }

    /// 色块 legend — 解释颜色对应的"肌肉恢复状态", 不是"练了几天前".
    /// 训练科学背景: 肌纤维修复 ~48-72h. legend 把抽象的"时间衰减"翻译成用户能行动的语言.
    ///   - 1.0 满色 = 刚练完, 还在 fatigue 期 (今天)
    ///   - 0.6 中色 = 修复中 (~昨天)
    ///   - 0.3 浅色 = 接近 fresh (~2 天前)
    ///   - nil 灰   = 完全 fresh / 该练了
    @ViewBuilder
    private var legendRow: some View {
        HStack(spacing: 14) {
            legendDot(opacity: 1.0, label: "Fatigued")
            legendDot(opacity: 0.6, label: "Recovering")
            legendDot(opacity: 0.3, label: "Almost fresh")
            legendDot(opacity: nil, label: "Ready to train")
        }
    }

    private func legendDot(opacity: Double?, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(opacity == nil
                      ? Color(red: 0.165, green: 0.165, blue: 0.165)
                      : MasoColor.accent.opacity(opacity!))
                .frame(width: 10, height: 10)
            // label 是 "Fatigued" / "Recovering" / "Almost fresh" / "Ready to train" — 走 LSK 查表
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(MasoColor.textDim)
        }
    }

    /// 把 SetRecord 按 (planId, 日历日) 聚合成 session 卡; 按时间倒序返回
    private func groupedSessions() -> [SessionSummary] {
        let cal = Calendar.current
        struct Key: Hashable { let planId: String; let day: Date }
        var bucket: [Key: [SetRecord]] = [:]
        var order: [Key] = []
        for rec in data.sets {
            let day = cal.startOfDay(for: rec.performedAt)
            let key = Key(planId: rec.planId ?? "free", day: day)
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(rec)
        }
        let summaries: [SessionSummary] = order.map { key in
            let recs = bucket[key] ?? []
            let planName: String? = {
                if key.planId == "free" { return nil }
                return data.plans.first(where: { $0.id == key.planId })?.name
            }()
            let uniqueExercises = Set(recs.map { $0.exerciseId })
            var seenMuscles = Set<MuscleGroup>()
            var muscles: [MuscleGroup] = []
            for r in recs {
                guard let ex = data.exById[r.exerciseId] else { continue }
                for m in ex.muscleGroups where seenMuscles.insert(m).inserted {
                    muscles.append(m)
                }
            }
            let categories = Set(recs.map { $0.category })
            // 数这一场训练里 PR 的组数 — Epley 1RM 估算超过之前历史最高
            let prCount = recs.reduce(0) { $0 + (data.isPR($1) ? 1 : 0) }
            return SessionSummary(
                id: "\(key.planId)-\(Int(key.day.timeIntervalSince1970))",
                planId: key.planId == "free" ? nil : key.planId,
                day: key.day,
                planName: planName,
                exerciseCount: uniqueExercises.count,
                setCount: recs.count,
                muscles: muscles,
                categories: categories,
                lastPerformedAt: recs.map { $0.performedAt }.max() ?? key.day,
                prCount: prCount
            )
        }
        return summaries.sorted { $0.lastPerformedAt > $1.lastPerformedAt }
    }

    /// session 内每个动作的统计 (用于 detail sheet 的"动作列表"区)
    private func exerciseStats(for session: SessionSummary) -> [SessionExerciseStat] {
        let cal = Calendar.current
        let dayRecs = data.sets.filter { rec in
            let day = cal.startOfDay(for: rec.performedAt)
            let recPid = rec.planId ?? "free"
            let sessionPid = session.planId ?? "free"
            return day == session.day && recPid == sessionPid
        }
        // 按 exerciseId 分组并保持首次出现顺序 (匹配训练时的顺序)
        var order: [String] = []
        var buckets: [String: [SetRecord]] = [:]
        for r in dayRecs.sorted(by: { $0.performedAt < $1.performedAt }) {
            if buckets[r.exerciseId] == nil { order.append(r.exerciseId) }
            buckets[r.exerciseId, default: []].append(r)
        }
        return order.compactMap { exId in
            guard let recs = buckets[exId], let ex = data.exById[exId] else { return nil }
            // 取每组里最重的 weight × reps 作展示 (代表"最佳"那组)
            let bestWeight = recs.compactMap { $0.weight }.max()
            let bestReps = recs.compactMap { $0.reps }.max()
            let totalDuration = recs.compactMap { $0.duration }.reduce(0, +)
            return SessionExerciseStat(
                id: ex.id,
                exercise: ex,
                setCount: recs.count,
                bestWeight: bestWeight,
                bestReps: bestReps,
                totalDuration: totalDuration > 0 ? totalDuration : nil
            )
        }
    }

    /// 回放: 关联了 plan 的 session 直接拿原 plan; 自由训练的 session 从历史 set
    /// 合成一个临时 plan (复用 exerciseStats 拿到当天动作 + 每动作的 set 数 / reps / weight).
    /// 这样自由训练也能"再练一遍" — 跟 plan-based session 同款体验.
    private func replayPlan(for session: SessionSummary) -> Plan? {
        if let pid = session.planId {
            return data.plans.first(where: { $0.id == pid })
        }
        return synthesizeFreeReplayPlan(for: session)
    }

    /// 自由训练 → 合成临时 Plan 用于回放. 不入 DataStore (id 固定 "session-replay-{sessionId}",
    /// 反复点不会污染 Plans 列表; PlanPlayer 通过 startTrainingNow 拿到 Plan 直接展开 segments).
    private func synthesizeFreeReplayPlan(for session: SessionSummary) -> Plan? {
        let stats = exerciseStats(for: session)
        guard !stats.isEmpty else { return nil }
        let cal = Calendar.current
        let dayRecs = data.sets.filter { rec in
            cal.startOfDay(for: rec.performedAt) == session.day && rec.planId == nil
        }
        // 按 exerciseId 分桶, reps / weight / duration 取每动作的中位数 — 比 best 更代表
        // "一般情况下的负荷", 用户回放时不会被某一次特别拼的组拖垮.
        var perEx: [String: [SetRecord]] = [:]
        for r in dayRecs { perEx[r.exerciseId, default: []].append(r) }

        var steps: [PlanStep] = []
        for (idx, stat) in stats.enumerated() {
            guard let recs = perEx[stat.exercise.id], !recs.isEmpty else { continue }
            let reps: Int? = median(recs.compactMap { $0.reps })
            let weight: Double? = median(recs.compactMap { $0.weight }.map { Double($0) })
            let duration: Int? = median(recs.compactMap { $0.duration })
            steps.append(PlanStep(
                id: "step-replay-\(session.id)-\(idx)",
                exerciseId: stat.exercise.id,
                sets: recs.count,
                reps: reps,
                weight: weight,
                duration: duration,
                restBetweenSets: 90,
                rest: 0
            ))
        }
        guard !steps.isEmpty else { return nil }
        let name = NSLocalizedString("Free workout", comment: "")
        return Plan(
            id: "session-replay-\(session.id)",
            name: name,
            steps: steps,
            createdAt: session.day,
            updatedAt: Date()
        )
    }

    /// 整数 / Double 通用的中位数 helper. 空数组 → nil.
    private func median<T: Comparable & FloatingPoint>(_ arr: [T]) -> T? {
        guard !arr.isEmpty else { return nil }
        let sorted = arr.sorted()
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }
    private func median(_ arr: [Int]) -> Int? {
        guard !arr.isEmpty else { return nil }
        let sorted = arr.sorted()
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }
}

// MARK: - Session aggregation model

struct SessionSummary: Identifiable, Hashable {
    let id: String
    let planId: String?     // nil = 自由组
    let day: Date
    /// nil 表示自由组训练
    let planName: String?
    let exerciseCount: Int
    let setCount: Int
    let muscles: [MuscleGroup]
    let categories: Set<ExerciseCategory>
    let lastPerformedAt: Date
    /// 这一场训练里 PR 的组数 (Epley 1RM 估算超过历史最高). 0 = 没 PR.
    /// 渲染时 > 0 → SessionCard 右上角小🏆+ count, 不弹通知不庆祝 (理念 4 "沉默的进步反馈")
    var prCount: Int = 0
}

struct SessionExerciseStat: Identifiable, Hashable {
    let id: String
    let exercise: Exercise
    let setCount: Int
    let bestWeight: Double?
    let bestReps: Int?
    let totalDuration: Int?
}

// MARK: - SessionCard

private struct SessionCard: View {
    let session: SessionSummary
    /// 用户为该 session 加的照片 (DataStore.sessionPhoto). nil = 无照片, 不渲染缩略图.
    /// 卡片左侧渲染一个 48x48 圆角缩略图 — 跟 PlanRow / Exercise list 的 56pt thumbnail 同款大小区间,
    /// 但用户照片更 "个人化", 视觉上稍小一点低调.
    var photo: UIImage? = nil
    /// 点右下角播放按钮 → "再次训练这次的内容". nil 时不显示按钮.
    let onReplay: (() -> Void)?

    private var kicker: String {
        // 始终显示训练时间 (Today / Yesterday / X days ago / "5月8日"),
        // 即使是自由训练 — 之前 kicker 跟 title 都显示"自由训练"重复, 现在 kicker 是时间.
        prettyDay(session.day)
    }
    private var title: String {
        session.planName ?? NSLocalizedString("Free workout", comment: "")
    }
    private var subtitleLine: String {
        "\(pluralizedExercises(session.exerciseCount)) · \(pluralizedSets(session.setCount))"
    }

    var body: some View {
        // 统一布局 (跟 Plans PlanRow 同款), History 顶部多一行日期 kicker:
        //   行0: 日期 kicker (TODAY / YESTERDAY / ...)
        //   行1: title + 右箭头 (整行 tap 进 detail)
        //   行2: exercises · sets
        //   行3: [photo (有时)] [BodyHint 居中] [右下角 replay 按钮]
        //
        // 照片之前是 48×48 缩略图挂在 title 左侧, 现在挪到底部跟 BodyHint 并列 —
        // 让 muscle map + 训练照同时映入眼帘, 加强"训练日记"感.
        VStack(alignment: .leading, spacing: 6) {
            // History 独有: 训练日期
            Text(kicker.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                    // 删 minimumScaleFactor → 超长走默认 truncationMode .tail (...),
                    // 不再先缩小字号到 75% 才省略.
                // PR 标记 — 沉默的进步反馈 (理念 4): 不弹通知不庆祝, 一个小🏆 + 数字一眼可见
                if session.prCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text("\(session.prCount)")
                            .font(.system(size: 11, weight: .heavy).monospacedDigit())
                    }
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MasoColor.accent.opacity(0.14))
                    .clipShape(Capsule())
                    .accessibilityLabel("\(session.prCount) personal records")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }

            Text(subtitleLine)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)

            // 底部布局: 照片 + BodyHint 作为一组居中 (两边 Spacer 撑开), replay 按钮做
            // bottomTrailing overlay 浮在右下角, 不参与居中计算 —
            //   - 没照片时: 仅 BodyHint, 在 card 内居中
            //   - 有照片时: [Photo 80×80] [12pt] [BodyHint] 整体作为一个 unit 居中
            ZStack(alignment: .bottomTrailing) {
                HStack(alignment: .center, spacing: 12) {
                    Spacer(minLength: 0)
                    if let img = photo {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(MasoColor.borderSoft, lineWidth: 0.5)
                            )
                            .accessibilityLabel("Workout photo")
                    }
                    BodyHint(
                        muscles: session.muscles,
                        height: 80,
                        region: .full
                    )
                    Spacer(minLength: 0)
                }

                // History 卡的"再次训练"按钮 — 用 arrow.clockwise (循环箭头) 表达"重做这次"
                // 比 play.fill 更准确 (这不是"开始一个新训练", 是"再做一遍刚才的训练").
                // overlay 模式: 不参与 HStack 布局, 不影响 photo+BodyHint 的居中.
                if let onReplay {
                    Button(action: onReplay) {
                        ZStack {
                            Circle()
                                .fill(MasoColor.accent.opacity(0.18))
                                .overlay(
                                    Circle().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5)
                                )
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(MasoColor.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat Workout")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MasoMetrics.cardPadding - 4)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}

// 复用 Theme/Formatters 的 relativeDay (Today / Yesterday / N days ago / "MMM d")
private func prettyDay(_ d: Date) -> String { relativeDay(d) }

// MARK: - SessionDetailSheet

private struct SessionDetailSheet: View {
    @Environment(DataStore.self) private var data
    let session: SessionSummary
    let exerciseStats: [SessionExerciseStat]
    /// 如果是基于 plan 的训练, 这里给出原 plan, 可以一键回放
    let replayPlan: Plan?
    let onReplay: (Plan) -> Void

    @Environment(\.dismiss) private var dismiss
    /// list ↔ grid 切换 — 跟 PlanDetailSheet 共享同一 @AppStorage key, 两个 sheet 偏好同步.
    @AppStorage("planStepCardLayout") private var useCardLayout: Bool = false
    /// 点图片 → 弹动作详情 sheet
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 — 待删 exerciseId. 二次确认 alert 触发实际删除.
    @State private var pendingDeleteExerciseId: String? = nil
    /// 加/换/删训练照片 — 跟 ShareCustomizeSheet 同款 confirmationDialog + PhotoPicker flow.
    @State private var showPhotoOptions: Bool = false
    @State private var activePicker: PhotoPickerSource? = nil
    @State private var pickedPhoto: UIImage? = nil
    @State private var isCameraAvailable: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        NavigationStack {
            // List + Section 让 stepListSection 里的 ForEach 能用原生 .swipeActions (不支持 onMove —
            // 历史时间顺序是 ground truth, 不允许重排). 跟 PlanDetailSheet 同模式, 用户跨 tab 体验一致.
            List {
                // 用户照片 banner — 有照片 tap 弹换/删 dialog; 没照片显示"加照片"占位也可点.
                // 视觉跟 share card 顶部的 SharePhotoBanner 同款 (1:1 正方形).
                Section {
                    sessionPhotoBlock
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    headerCard
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 20, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                exerciseStatsSection
                if let plan = replayPlan {
                    Section {
                        Button(action: { onReplay(plan) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                                Text("Repeat Workout").font(.system(size: 14, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MasoColor.accent)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 32, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
            .background(MasoColor.background.ignoresSafeArea())
            // 点图片弹详情 sheet
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            // 加/换/删训练照片 dialog + picker — 跟 ShareCustomizeSheet 同一套 flow
            .confirmationDialog(
                NSLocalizedString("Add photo", comment: ""),
                isPresented: $showPhotoOptions,
                titleVisibility: .visible
            ) {
                if isCameraAvailable {
                    Button(NSLocalizedString("Take Photo", comment: "")) {
                        activePicker = .camera
                    }
                }
                Button(NSLocalizedString("Choose from Library", comment: "")) {
                    activePicker = .photoLibrary
                }
                if data.sessionPhoto(forSessionId: session.id) != nil {
                    Button(NSLocalizedString("Remove Photo", comment: ""), role: .destructive) {
                        data.removeSessionPhoto(forSessionId: session.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activePicker) { source in
                PhotoPicker(image: $pickedPhoto, source: source)
                    .ignoresSafeArea()
            }
            .onChange(of: pickedPhoto) { _, newPhoto in
                if let img = newPhoto {
                    data.setSessionPhoto(img, forSessionId: session.id)
                    pickedPhoto = nil   // 重置, 下次再 pick 还能触发 onChange
                }
            }
            // 右滑 / contextMenu 删除单个 exercise 的二次确认
            .alert("Delete exercise from this workout?", isPresented: Binding(
                get: { pendingDeleteExerciseId != nil },
                set: { if !$0 { pendingDeleteExerciseId = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let exId = pendingDeleteExerciseId {
                        data.deleteExerciseFromSession(
                            planId: session.planId,
                            day: session.day,
                            exerciseId: exId
                        )
                    }
                    pendingDeleteExerciseId = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteExerciseId = nil }
            } message: {
                Text("All sets of this exercise from this workout will be removed.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 分享这次训练 — 生成 UnifiedShareCard (workout section default on).
                    // 三个 section data 始终算好传入; toggle 状态由卡内 inline toggle / ShareCardMode 控制.
                    let workoutData = sessionWorkoutSection()
                    let muscleData = sessionMuscleStatusSection()
                    let calendarData = sessionCalendarSection()
                    ShareImageButton(
                        previewTitle: NSLocalizedString("My Workout", comment: ""),
                        defaultSections: ShareSections(workout: true),
                        initialPhoto: data.sessionPhoto(forSessionId: session.id),
                        shareContent: { photo, onTapAdd, mode in
                            switch mode {
                            case .editing(let binding):
                                UnifiedShareCard(
                                    userPhoto: photo,
                                    onTapAddPhoto: onTapAdd,
                                    workoutSection: workoutData,
                                    muscleStatusSection: muscleData,
                                    calendarSection: calendarData,
                                    editToggles: binding
                                )
                            case .rendering(let visible):
                                UnifiedShareCard(
                                    userPhoto: photo,
                                    onTapAddPhoto: onTapAdd,
                                    workoutSection: workoutData,
                                    muscleStatusSection: muscleData,
                                    calendarSection: calendarData,
                                    visibleSections: visible
                                )
                            }
                        },
                        onPersistPhoto: { image in
                            if let image {
                                data.setSessionPhoto(image, forSessionId: session.id)
                            } else {
                                data.removeSessionPhoto(forSessionId: session.id)
                            }
                        },
                        label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                        }
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            .tint(MasoColor.text)
        }
    }

    /// 训练照片 block — 有照片显示 240pt 正方形, 没照片显示"加照片" row (跟动作列表行同款 row 高度).
    @ViewBuilder
    private var sessionPhotoBlock: some View {
        if let photo = data.sessionPhoto(forSessionId: session.id) {
            // 已加照片: 严格 1:1 圆角正方形 — 用 Color.clear 强制 aspect ratio,
            // 图片 overlay 内 fill + clipped 裁中, 这样容器一定是正方形不会被父布局压扁.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                        .stroke(MasoColor.borderSoft, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { showPhotoOptions = true }
        } else {
            // 未加照片: 紧凑 row, 高度像动作列表 row (56pt), 全宽 + 虚线描边占位感
            Button(action: { showPhotoOptions = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(MasoColor.textDim)
                        .frame(width: 32, height: 32)
                    Text("Add a photo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MasoColor.textDim)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(MasoColor.surface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                        .strokeBorder(
                            MasoColor.borderSoft,
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            }
            .buttonStyle(.plain)
        }
    }

    /// 动作列表 Section — list / grid 两种模式. 跟 PlanDetailSheet 同结构: header 行 + 各 row,
    /// list mode 支持 swipeActions delete (历史不允许 reorder, 时间是 ground truth).
    @ViewBuilder
    private var exerciseStatsSection: some View {
        Section {
            // Header — "Exercises" kicker + 右侧 list/grid 切换 (跟 PlanDetailSheet 一致)
            HStack {
                Text("Exercises")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(MasoColor.textFaint)
                Spacer()
                LayoutToggle(useCardLayout: Binding(
                    get: { useCardLayout },
                    set: { useCardLayout = $0 }
                ))
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if exerciseStats.isEmpty {
                Text("No exercises in this workout")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
            } else if useCardLayout {
                // grid 模式 — 2 列 card. 不支持 swipe / 拖拽 (LazyVGrid 不支持). 删除走 contextMenu.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(exerciseStats) { stat in
                        ExerciseStatCard(stat: stat, onTapImage: { detailExercise = stat.exercise })
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeleteExerciseId = stat.exercise.id
                                } label: {
                                    Label {
                                        Text("Delete")
                                    } icon: {
                                        Image(systemName: "trash").foregroundStyle(.white)
                                    }
                                }
                            }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                // list 模式 — 原生 swipeActions 右滑删除. 历史时间顺序是 ground truth, 不允许 reorder.
                ForEach(exerciseStats) { stat in
                    ExerciseStatRow(stat: stat, onTapImage: { detailExercise = stat.exercise })
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                                pendingDeleteExerciseId = stat.exercise.id
                            }
                            .tint(.red)
                        }
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            BodyHint(muscles: session.muscles, height: 96, region: .full, square: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(prettyDay(session.day).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(MasoColor.accent)
                Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatPill(text: pluralizedExercises(session.exerciseCount))
                    StatPill(text: pluralizedSets(session.setCount))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MasoMetrics.cardPadding)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    // MARK: - Share section data helpers

    /// 这次 session 的 WorkoutSectionData — 主要分享内容.
    fileprivate func sessionWorkoutSection() -> WorkoutSectionData {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return WorkoutSectionData(
            dateLabel: df.string(from: session.day),
            planName: session.planName ?? NSLocalizedString("Free workout", comment: ""),
            durationLabel: "~\(max(5, session.setCount * 2))m",
            setCount: session.setCount,
            exerciseCount: session.exerciseCount,
            prCount: session.prCount,
            muscles: session.muscles,
            exerciseNames: exerciseStats.prefix(4).map { $0.exercise.displayName }
        )
    }

    /// 本周肌肉状态 (用 DataStore 全局衰减 mapping).
    fileprivate func sessionMuscleStatusSection() -> MuscleStatusSectionData {
        let lastMap = muscleLastTrainedMap()
        return MuscleStatusSectionData(
            muscleOpacity: { m in shareOpacityFor(muscle: m, lastMap: lastMap) },
            coarseOnly: !data.settings.muscleDetailEnabled,
            workoutsThisWeek: workoutsThisWeekCount(),
            totalSetsThisWeek: totalSetsThisWeek(),
            muscleSectionsHit: muscleSectionsHitThisWeek()
        )
    }

    /// 本周训练日历 frequency.
    fileprivate func sessionCalendarSection() -> CalendarSectionData {
        CalendarSectionData(
            sessionDates: workoutDateSet(),
            totalSets: totalSetsThisWeek(),
            streakDays: currentStreakDays()
        )
    }

    // 内部计算 — 走共享 MuscleStatusCompute, 跟 HistoryScreen / QuickMuscleStep 同一份兜底.
    private func muscleLastTrainedMap() -> [MuscleGroup: Date] {
        MuscleStatusCompute.muscleLastTrainedMap(sets: data.sets, exById: data.exById)
    }

    private func shareOpacityFor(muscle m: MuscleGroup, lastMap: [MuscleGroup: Date]) -> Double? {
        MuscleStatusCompute.opacityFor(muscle: m, lastMap: lastMap)
    }

    private func workoutsThisWeekCount() -> Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let days = Set(data.sets.filter { $0.performedAt >= cutoff }.map { cal.startOfDay(for: $0.performedAt) })
        return days.count
    }

    private func totalSetsThisWeek() -> Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        return data.sets.filter { $0.performedAt >= cutoff }.count
    }

    private func muscleSectionsHitThisWeek() -> Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        var sections = Set<MuscleGroup>()
        for set in data.sets where set.performedAt >= cutoff {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let s = m.section { sections.insert(s) }
            }
        }
        return sections.count
    }

    private func currentStreakDays() -> Int {
        let cal = Calendar.current
        let days = workoutDateSet()
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        while days.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    private func workoutDateSet() -> Set<Date> {
        let cal = Calendar.current
        var out: Set<Date> = []
        for s in data.sets {
            out.insert(cal.startOfDay(for: s.performedAt))
        }
        return out
    }
}

private struct StatPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(MasoColor.textDim)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
    }
}

private struct ExerciseStatRow: View {
    let stat: SessionExerciseStat
    /// 点图片 → 弹动作详情. parent 接收 callback, 在它身上挂 sheet.
    var onTapImage: (() -> Void)? = nil

    fileprivate static func detailLine(for stat: SessionExerciseStat) -> String {
        if let d = stat.totalDuration {
            return "\(pluralizedSets(stat.setCount)) · \(d)s"
        }
        if let w = stat.bestWeight, let r = stat.bestReps {
            if w > 0 { return "\(pluralizedSets(stat.setCount)) · \(formatWeight(w)) kg × \(r)" }
            return "\(pluralizedSets(stat.setCount)) × \(r)"
        }
        return pluralizedSets(stat.setCount)
    }

    private var detailLine: String { Self.detailLine(for: stat) }

    var body: some View {
        // 视觉跟"训练中" InlinePlaylist.playlistRow 完全对齐 — 全 app 动作行统一规格.
        HStack(spacing: 14) {
            Button(action: { onTapImage?() }) {
                ExerciseImage(
                    category: stat.exercise.category,
                    imageFolder: stat.exercise.imageFolder,
                    cornerRadius: 8,
                    size: 56,
                    animated: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), stat.exercise.displayName))
            VStack(alignment: .leading, spacing: 5) {
                Text(stat.exercise.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                ExerciseTagsRow(
                    muscleGroups: stat.exercise.muscleGroups,
                    equipment: stat.exercise.equipment,
                    muscleLimit: 1
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .padding(.vertical, 10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// grid 模式的卡片版本 — 跟 PlansScreen.PlanStepCard 同款 layout (大图正方形 + 名字 + 详情).
private struct ExerciseStatCard: View {
    let stat: SessionExerciseStat
    var onTapImage: (() -> Void)? = nil

    private var detailLine: String { ExerciseStatRow.detailLine(for: stat) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { onTapImage?() }) {
                GeometryReader { geo in
                    ExerciseImage(
                        category: stat.exercise.category,
                        imageFolder: stat.exercise.imageFolder,
                        cornerRadius: 8,
                        size: geo.size.width,
                        animated: false
                    )
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), stat.exercise.displayName))

            VStack(alignment: .leading, spacing: 4) {
                Text(stat.exercise.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(detailLine)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ExerciseTagsRow(
                    muscleGroups: stat.exercise.muscleGroups,
                    equipment: stat.exercise.equipment,
                    muscleLimit: 1,
                    compact: true
                )
            }
        }
        .padding(10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
