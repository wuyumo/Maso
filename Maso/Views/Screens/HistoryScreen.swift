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
                // 顶部 padding 给一点空间 (之前的 page title 移进卡片了)
                Spacer().frame(height: MasoMetrics.pagePaddingTop - 24)

                // 肌肉衰减卡 — 跟 web 端"训练状态"同款:
                //   今天训练 = 全绿; 昨天 = 0.7; 前天 = 0.4; 3 天以前 = 默认灰
                let lastMap = muscleLastTrainedMap()
                let hasAny = !lastMap.isEmpty
                VStack(spacing: 12) {
                    // Page title 移进卡片顶部 — 之前在 ScrollView 顶层占地, 现在跟 BodyHint 同卡, 更紧凑
                    Text("Muscle Status")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MasoMetrics.cardPadding)
                        .padding(.top, 4)

                    BodyHint(
                        muscles: [],
                        height: MasoMetrics.bodyHintHistory,
                        opacityFor: { m in opacityFor(muscle: m, lastMap: lastMap) },
                        coarseOnly: !data.settings.muscleDetailEnabled
                    )
                    .frame(maxWidth: .infinity)

                    // hasAny 时不再加"3 天衰减"解释文案 — legend 自己用"Fatigued / Recovering /
                    // Almost fresh / Ready to train"已经说清楚状态语义, 上面那句重复.
                    // 没数据时还是要留个空状态提示.
                    if !hasAny {
                        Text("No training this week yet")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }

                    // legend — 4 个色块: Fatigued / Recovering / Almost fresh / Ready to train
                    legendRow

                    // 按钮跟上方 element 之间稍微留点 padding (之前 14pt 让按钮显得太靠下)
                    Spacer().frame(height: 6)

                    // 两个按钮一行 — 左: 训练日历 (灰), 右: Train the gaps (白, 更显眼)
                    HStack(spacing: 10) {
                        Button(action: { showCalendar = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Workout calendar")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(MasoColor.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(MasoColor.surfaceHi)
                            .overlay(Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.8))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Train the gaps — 白色实色按钮.
                        // 点击 → 找出 ≥3 天没练的 section → 自动拼一个 plan → 直接开练.
                        // disabled 当所有 section 最近都练过.
                        Button(action: startGapWorkout) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                Text("Train the gaps")
                                    .font(.system(size: 12, weight: .heavy))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .shadow(color: .white.opacity(0.25), radius: 8, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(gapSections().isEmpty)
                        .opacity(gapSections().isEmpty ? 0.35 : 1)
                    }
                }
                .padding(.vertical, MasoMetrics.cardPadding)
                .frame(maxWidth: .infinity)
                .background(MasoColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                // 右上角 Share 按钮 overlay — 分享当天/本周肌肉状态
                .overlay(alignment: .topTrailing) {
                    ShareImageButton(previewTitle: NSLocalizedString("My Muscle Status", comment: "")) { photo, onTapAdd in
                        MuscleStatusShareCard(
                            muscleOpacity: { m in opacityFor(muscle: m, lastMap: lastMap) },
                            workoutsThisWeek: workoutsThisWeekCount,
                            totalSetsThisWeek: totalSetsThisWeek,
                            muscleSectionsHit: muscleSectionsHitThisWeek,
                            coarseOnly: !data.settings.muscleDetailEnabled,
                            userPhoto: photo,
                            onTapAddPhoto: onTapAdd
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(MasoColor.textDim)
                            .frame(width: 32, height: 32)
                            .background(MasoColor.surfaceHi)
                            .clipShape(Circle())
                    }
                    .padding(12)
                }

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

    /// 找出 "需补" 的顶层 section — 该 section 下所有解剖肌肉都 ≥3 天没被练 (或从没练过).
    /// 返回的是 [chest, back, ...] 这种顶层 section.
    private func gapSections() -> [MuscleGroup] {
        let lastMap = muscleLastTrainedMap()
        let now = Date()
        let cutoff: TimeInterval = 3 * 86400
        let topSections: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]
        var gaps: [MuscleGroup] = []
        for sec in topSections {
            // 该 section 的所有 anatomy muscles (composites 展开)
            let anatomy = expandAnatomyMuscles([sec]).filter { $0.section == sec }
            guard !anatomy.isEmpty else { continue }
            let allStale = anatomy.allSatisfy { m in
                guard let last = lastMap[m] else { return true }
                return now.timeIntervalSince(last) >= cutoff
            }
            if allStale { gaps.append(sec) }
        }
        return gaps
    }

    /// 每个 section 的"招牌动作" — 库里最经典的 compound + accessory.
    /// 用于 Train the gaps 一键生成 plan 时挑选动作.
    private static let signatureExercises: [MuscleGroup: [String]] = [
        .chest:     ["Barbell_Bench_Press_-_Medium_Grip", "Incline_Dumbbell_Press"],
        .back:      ["Pullups", "Bent_Over_Barbell_Row"],
        .shoulders: ["Standing_Military_Press", "Side_Lateral_Raise"],
        .arms:      ["Barbell_Curl", "Triceps_Pushdown"],
        .core:      ["Cable_Crunch", "Plank"],
        .legs:      ["Barbell_Squat", "Romanian_Deadlift"],
    ]

    /// 单个 SessionCard + tap handler — 给 recent / older 两个 list 共享.
    /// 长按 → contextMenu Delete → alert 二次确认. (HistoryScreen 顶部有 muscle status hero card,
    /// 没改成 List, 所以用 contextMenu 替代右滑 — 删除能力一致.)
    @ViewBuilder
    private func sessionCardRow(_ session: SessionSummary) -> some View {
        SessionCard(
            session: session,
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

    // MARK: - Share data 计算 (给 MuscleStatusShareCard 用)

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

    /// 一键: 找 gap → 拼 plan → 启动训练
    private func startGapWorkout() {
        let gaps = gapSections()
        guard !gaps.isEmpty else { return }
        var steps: [PlanStep] = []
        var idx = 0
        for sec in gaps {
            let ids = Self.signatureExercises[sec] ?? []
            for id in ids {
                guard let ex = data.exById[id] else { continue }
                let isStrength = ex.category == .strength
                steps.append(PlanStep(
                    id: "gap-\(idx)-\(id)",
                    exerciseId: id,
                    sets: 3,
                    reps: isStrength ? 10 : nil,
                    weight: isStrength ? 0 : nil,
                    duration: isStrength ? nil : 45,
                    restBetweenSets: 90,
                    rest: 0
                ))
                idx += 1
                if steps.count >= 8 { break }   // 单次训练总动作上限
            }
            if steps.count >= 8 { break }
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

    /// 每个 anatomy 直接肌肉 → 最近一次被训练的时间.
    /// 用于 BodyHint opacityFor — 跟 web 端 muscleLastTrained 同义.
    private func muscleLastTrainedMap() -> [MuscleGroup: Date] {
        var map: [MuscleGroup: Date] = [:]
        for s in data.sets {
            guard let ex = data.exById[s.exerciseId] else { continue }
            // expandAnatomyMuscles 把 chest → upperChest/midChest/lowerChest 都点亮
            let expanded = expandAnatomyMuscles(ex.muscleGroups)
            for m in expanded {
                if let prev = map[m], prev > s.performedAt { continue }
                map[m] = s.performedAt
            }
        }
        return map
    }

    /// 衰减映射 — 间距加大让三档对比明显:
    /// 0..1 d → 1.0 (满色); 1..2 d → 0.6; 2..3 d → 0.3; ≥ 3 d → nil (默认灰).
    /// 之前 1.0/0.7/0.4 三档视觉差异不够明显 (人眼对低 alpha 差异不敏感),
    /// 现在 0.4 + 0.3 + 0.3 间隔, 整体更分明.
    private func opacityFor(muscle m: MuscleGroup, lastMap: [MuscleGroup: Date]) -> Double? {
        guard let last = lastMap[m] else { return nil }
        let days = Date().timeIntervalSince(last) / 86400
        if days < 1 { return 1.0 }
        if days < 2 { return 0.6 }
        if days < 3 { return 0.3 }
        return nil
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

    /// 回放: 如果这次 session 关联了一个 plan, 返回该 plan 让 RootView 调起播放
    /// 自由组 session 返回 nil — 这一类不支持原样回放
    private func replayPlan(for session: SessionSummary) -> Plan? {
        guard let pid = session.planId else { return nil }
        return data.plans.first(where: { $0.id == pid })
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
    /// 点右下角播放按钮 → "再次训练这次的内容". nil 时不显示按钮.
    let onReplay: (() -> Void)?

    private var kicker: String {
        session.planName == nil ? NSLocalizedString("Free workout", comment: "") : prettyDay(session.day)
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
        //   行3: BodyHint + 右下角圆形播放按钮 (开始训练 — 走 onReplay 回放)
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

            ZStack(alignment: .bottomTrailing) {
                HStack {
                    Spacer()
                    BodyHint(
                        muscles: session.muscles,
                        height: 90,
                        region: .full
                    )
                    Spacer()
                }

                // History 卡的播放按钮 = "再次训练这次的内容"; 跟 Plans 同款样式
                if let onReplay {
                    Button(action: onReplay) {
                        ZStack {
                            Circle()
                                .fill(MasoColor.accent.opacity(0.18))
                                .overlay(
                                    Circle().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5)
                                )
                                .frame(width: 36, height: 36)
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(MasoColor.accent)
                                .offset(x: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat Workout")
                }
            }
            .padding(.top, 4)
        }
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

    var body: some View {
        NavigationStack {
            // List + Section 让 stepListSection 里的 ForEach 能用原生 .swipeActions (不支持 onMove —
            // 历史时间顺序是 ground truth, 不允许重排). 跟 PlanDetailSheet 同模式, 用户跨 tab 体验一致.
            List {
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
                    // 分享这次训练 — 生成 SessionShareCard 图分享出去
                    ShareImageButton(previewTitle: NSLocalizedString("My Workout", comment: "")) { photo, onTapAdd in
                        SessionShareCard(
                            session: session,
                            exerciseNames: exerciseStats.prefix(4).map { $0.exercise.displayName },
                            userPhoto: photo,
                            onTapAddPhoto: onTapAdd
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(session.planName ?? "Free workout")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                }
            }
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
