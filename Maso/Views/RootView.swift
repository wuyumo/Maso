import HealthKit
import SwiftUI

enum RootTab: Hashable { case plans, today, history }

// 顶级路由 — 跟 web 端 App.tsx 1:1
//   - onboarding 未完成: 整屏 Onboarding
//   - 已完成: TabBar + 3 个屏 (Plans / Today / History), 加 PlanPlayer sheet
struct RootView: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: RootTab = .today
    /// 反馈队列 — 没 inject 进 environment, 因为它只在 Settings + scenePhase 监听里用,
    /// 直接拿 shared 单例最简单, 避免到处 propagate.
    @State private var feedbackStore = FeedbackStore.shared
    /// 首次提示气泡的 pulse 动画状态
    @State private var hintPulse: Bool = false
    /// "Tap to start" 提示是否已看过 — 走 UserDefaults 真持久化, app 卸载重装才会重置.
    /// (DataStore 是 in-memory mock, 用 data.settings.hasSeenCenterTabHint 每次启动重置成 false → hint 重复出现)
    @AppStorage("maso.hasSeenCenterTabHint") private var hasSeenCenterTabHint: Bool = false
    /// 跨 sheet 切 tab 路由
    @State private var router = AppRouter.shared
    @State private var playerPresented: Bool = false
    @State private var settingsPresented: Bool = false
    @State private var quickWorkoutPresented: Bool = false
    // DESIGN 5.3: 当用户尝试开第二个训练时, 用 plan 作为 pending 标记弹替换确认
    @State private var pendingReplacePlan: Plan?
    // + 按钮新建的 plan — 用 sheet(item:) 双向绑定; nil 表示关闭
    @State private var newPlanForEdit: Plan?
    /// 记录最近一次 + 按钮创建的 planId, 关 sheet 时用来判断要不要清理
    @State private var lastCreatedPlanId: String?
    /// Free 用户撞到 plan 上限时弹的 paywall
    @State private var paywallPresented: Bool = false

    /// Marketing screenshot mode — set MASO_SHOWCASE env var on simulator launch to land on a specific screen.
    /// Values: today (default) / history / settings / player / free_workout / rest
    /// Used by App Store screenshot pipeline. No-op in production (env var only set when launching
    /// from CI / asset gen script). Safe to keep — no behavior change for real users.
    private func applyShowcaseModeIfNeeded() {
        let mode = ProcessInfo.processInfo.environment["MASO_SHOWCASE"] ?? ""
        guard !mode.isEmpty else { return }
        switch mode {
        case "history":
            tab = .history
        case "settings":
            tab = .history
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settingsPresented = true }
        case "free_workout":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { quickWorkoutPresented = true }
        case "player":
            if let plan = data.todayRecommendedPlan {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { startTrainingNow(plan) }
            }
        case "rest":
            if let plan = data.todayRecommendedPlan {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    startTrainingNow(plan)
                    // 在 player 启动后再 advance 一次, 跳到 rest 段
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        session.advance { rec in data.recordSet(rec) }
                    }
                }
            }
        default:
            break
        }
    }

    var body: some View {
        if !data.settings.onboardingCompleted {
            OnboardingScreen { /* onDone */ }
                .transition(.opacity)
        } else {
            ZStack(alignment: .bottom) {
                MasoColor.background.ignoresSafeArea()

                // 主屏内容
                Group {
                    switch tab {
                    case .plans:    PlansScreen(onStart: startTraining, onNewPlan: handleNewPlan)
                    case .today:    TodayScreen(
                                        onStart: startTraining,
                                        onFreeWorkout: { quickWorkoutPresented = true }
                                    )
                    case .history:  HistoryScreen(onReplay: startTraining)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    // MiniBar (60pt) 出现时, 给上面的主屏多让 60pt 空间, 避免内容被 MiniBar 盖住
                    Color.clear.frame(
                        height: MasoMetrics.bottomNavHeight + (hasActiveSession ? 60 : 0)
                    )
                }

                // 右上角浮动按钮 — 按当前 tab 切换:
                //   Today / Plans → + (新建一份训练计划)
                //   History → ⚙ (设置)
                VStack {
                    HStack {
                        Spacer()
                        topRightAction
                            .padding(12)
                    }
                    Spacer()
                }
                .padding(.top, 8).padding(.trailing, 4)

                // 首次提示气泡 — 指向中间 Tab 的开始训练按钮.
                // 只在 (1) 用户没看过过 (2) 没有 active session (3) 当前在 Today tab 时显示.
                // 任意位置 tap / 中间 tab tap → flag = true, 消失.
                if shouldShowCenterTabHint {
                    centerTabHint
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .zIndex(50)
                }

                // 底部: MiniBar (训练中) + TabBar
                VStack(spacing: 0) {
                    if hasActiveSession, let seg = session.currentSegment {
                        TrainingMiniBar(
                            segment: seg,
                            playing: session.session?.playing ?? true,
                            remaining: session.remainingSeconds,
                            nextExercise: nextExerciseAfter(seg),
                            isCrossExercise: isCrossExerciseRest(seg),
                            onTap: { playerPresented = true },
                            onAdvance: { session.advance { rec in data.recordSet(rec) } },
                            onTogglePlay: { session.togglePlay() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    TabBarView(
                        selection: $tab,
                        onCenterPrimary: handleCenterPrimary,
                        // 中间 tab 长按菜单的 "New workout" — 走跟 Plans + 按钮同款的"新建空白 plan → 编辑详情"流程.
                        // 之前是拉 QuickWorkoutScreen, 现在 unify (那个 muscle picker 入口留在 Today card 下方).
                        onNewWorkout: handleNewPlan
                    )
                }
                .animation(.easeOut(duration: 0.25), value: hasActiveSession)
            }
            // 1Hz tick — 不管 PlanPlayer sheet 开没开, 只要有 active session 就在 tick.
            // 之前 SessionTickerView 只挂在 PlanPlayerScreen 里, sheet 一收 timer 也跟着停,
            // MiniBar 上的倒计时就定住了. 挪到 RootView 顶层后, MiniBar 跟 Player 都靠它驱动.
            .background(SessionTickerView())
            // 反馈队列 daily digest — app 启动 + 每次回前台都尝试一次. 24h 内最多 send 一次,
            // 由 FeedbackStore 内部判断. 没 pending 时 trySendDigest 是 no-op.
            .task {
                await feedbackStore.trySendDigest()
                // App 启动时也尝试 refresh AI 训练计划 — 同一天已经生成则 no-op
                await data.refreshAIWorkoutIfNeeded()
                // App Store 截图模式 — 读 MASO_SHOWCASE env var, 自动落到指定屏幕
                applyShowcaseModeIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await feedbackStore.trySendDigest() }
                    // 回前台也顺手同步一次 HealthKit (中间用户可能在 Health.app 改了权限)
                    if data.settings.healthKitSyncEnabled {
                        Task { await catchUpHealthKitSync() }
                    }
                    // 回前台 — 如果跨天了, refreshAIWorkoutIfNeeded 会触发新一次 AI 生成
                    Task { await data.refreshAIWorkoutIfNeeded() }
                    // 回前台 → 取消 rest 通知 (app 自己有 visible 倒计时, 不再需要 push)
                    RestNotificationScheduler.shared.cancel()
                } else if newPhase == .background {
                    // 进后台 → 如果当前在休息段, 调度倒计时结束通知 (锁屏 / 切其它 app 时收到)
                    scheduleRestNotificationIfNeeded()
                }
            }
            // 训练完成 (session.completed flip true) → 实时写 HealthKit
            .onChange(of: session.session?.completed ?? false) { _, completed in
                if completed && data.settings.healthKitSyncEnabled {
                    Task { await catchUpHealthKitSync() }
                }
            }
            // 跨 sheet tab 切换请求 — Settings 里点 "Plans" 让我们切到 Plans tab
            .onChange(of: router.requestedTab) { _, newTab in
                if let newTab {
                    tab = newTab
                    settingsPresented = false
                    router.requestedTab = nil
                }
            }
            .sheet(isPresented: $playerPresented) {
                PlanPlayerScreen()
                    .interactiveDismissDisabled(false)
                    .presentationDetents([.large])
                    // 系统原生 drag indicator — 在 sheet 容器顶部边缘渲染中性灰小条,
                    // 不受 sheet 内容 z-layer / 颜色干扰. 之前自定义 DragHandle 在 rest 段
                    // 因为 0.55 黑 mask + 30% 白 fill 视觉太弱看不见, 改用系统的就稳了.
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $settingsPresented) {
                NavigationStack { SettingsScreen() }
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallScreen()
            }
            .sheet(isPresented: $quickWorkoutPresented) {
                QuickWorkoutScreen(onStart: startTraining)
            }
            // + 按钮创建的新 plan — 关 sheet 时如果空了自动清理
            .sheet(item: $newPlanForEdit, onDismiss: {
                if let planId = lastCreatedPlanId { data.removePlanIfEmpty(planId) }
                lastCreatedPlanId = nil
                // 切到 Plans tab 让用户看到新建的 plan (如果保留了的话)
                if tab == .today { tab = .plans }
            }) { plan in
                PlanDetailSheet(
                    initialPlan: plan,
                    onStart: { p in
                        newPlanForEdit = nil
                        DispatchQueue.main.async { startTraining(p) }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            // DESIGN 5.3: 替换正在进行的训练 — 二次确认
            .alert(
                "Another workout is in progress",
                isPresented: Binding(
                    get: { pendingReplacePlan != nil },
                    set: { if !$0 { pendingReplacePlan = nil } }
                ),
                presenting: pendingReplacePlan
            ) { plan in
                Button("Replace", role: .destructive) {
                    session.endedExplicitly = true
                    session.end()
                    pendingReplacePlan = nil
                    DispatchQueue.main.async {
                        startTrainingNow(plan)
                    }
                }
                Button("Keep current", role: .cancel) {
                    pendingReplacePlan = nil
                }
            } message: { _ in
                Text("Starting this will replace the workout you're in. Continue?")
            }
        }
    }

    /// Tab 切换决定右上角浮动按钮: Today → +, Plans → 无 (按钮挪到 PlansScreen 的标题行了),
    /// History → ⚙
    @ViewBuilder
    private var topRightAction: some View {
        switch tab {
        case .today:
            Button(action: handleNewPlan) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 34, height: 34)
                    .background(MasoColor.surface.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New workout")
        case .plans:
            EmptyView()  // + 按钮已经在 PlansScreen 标题行里
        case .history:
            Button { settingsPresented = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(width: 34, height: 34)
                    .background(MasoColor.surface.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    /// + 按钮 — 建一个空白 plan, 弹出编辑 sheet.
    ///
    /// ⚠️ TODO[deploy-restore-paywall]: 测试阶段暂时关掉了"撞 plan 上限弹 paywall" 的检查,
    /// 用户不论 free / pro 都能直接新建. **deploy 前必须恢复下面注释的 4 行**, 否则 free
    /// 用户能无限新建 plan, 失去付费动力. (项目根 PRE_DEPLOY.md 也记了这一项.)
    private func handleNewPlan() {
        // if !data.settings.isPro && data.plans.count >= FreeLimit.maxPlans {
        //     paywallPresented = true
        //     return
        // }
        let plan = data.createBlankPlan()
        lastCreatedPlanId = plan.id
        newPlanForEdit = plan
    }

    /// 是否有进行中的训练 (用于 MiniBar 显隐 + safeArea 调整)
    private var hasActiveSession: Bool {
        guard let s = session.session else { return false }
        return !s.completed && session.currentSegment != nil
    }

    private func nextExerciseAfter(_ cur: Segment) -> Exercise? {
        guard let s = session.session else { return nil }
        for i in (s.segmentIndex + 1)..<session.segments.count {
            if case .exercise(let ex, _, _, _, _, _, _) = session.segments[i].kind {
                return ex
            }
        }
        return nil
    }

    /// 判断当前 rest segment 是不是 "切换动作" 类型的 rest
    /// (前后两个 exercise segment 的 stepId 不同)
    private func isCrossExerciseRest(_ cur: Segment) -> Bool {
        guard cur.isRest, let s = session.session else { return false }
        let i = s.segmentIndex
        var prevStepId: String?
        var j = i - 1
        while j >= 0 {
            if session.segments[j].isExercise { prevStepId = session.segments[j].stepId; break }
            j -= 1
        }
        var nextStepId: String?
        var k = i + 1
        while k < session.segments.count {
            if session.segments[k].isExercise { nextStepId = session.segments[k].stepId; break }
            k += 1
        }
        guard let p = prevStepId, let n = nextStepId else { return false }
        return p != n
    }

    private func handleCenterPrimary() {
        // 1) 不在 Today tab → 优先切到 Today (即使训练中也是先切 tab, 不直接拉 player).
        //    这样"训练中点中间 tab" 第一下是回 Today, 第二下才唤起 player.
        if tab != .today {
            tab = .today
            return
        }
        // 2) 已在 Today + 训练中 → 拉起正在进行的 PlanPlayer
        if hasActiveSession {
            playerPresented = true
            return
        }
        // 3) 已在 Today + 没训练 → 看 quickStart 开关; 如果开了, 直接开练今日推荐
        let quickStart = data.settings.quickStartOnActiveTab
        guard quickStart else { return }
        // 跟 TodayScreen.suggested 一致 — aiTodayPlan 优先, fallback 系统推荐.
        // 之前只用 todayRecommendedPlan 导致跟 Today 卡片显示的 plan 不一致, 而且没 guard
        // plan.steps 为空 → expandPlan 返回 [] → currentSegment nil → 空白训练屏 bug.
        let plan = data.aiTodayPlan ?? data.todayRecommendedPlan
        guard let plan, !plan.steps.isEmpty else { return }
        startTraining(plan)
    }

    /// 统一启动训练入口 — DESIGN 5.3:
    /// 如果已有别的进行中 session, 先弹确认; 用户确认后才替换
    private func startTraining(_ plan: Plan) {
        let cur = session.session
        let hasOtherActive = cur != nil
            && cur?.planId != plan.id
            && !(cur?.completed ?? false)
        if hasOtherActive {
            pendingReplacePlan = plan
            return
        }
        startTrainingNow(plan)
    }

    /// 把所有未同步的 session 写 HealthKit. SettingsScreen 也有同款实现, 这里独立一份让
    /// session 完成的实时 hook 不需要打开 Settings sheet 就能跑.
    private func catchUpHealthKitSync() async {
        let svc = HealthKitService.shared
        svc.refreshAuthStatus()
        guard svc.authStatus == .authorized else { return }

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
        for key in order {
            let id = "\(key.planId)-\(Int(key.day.timeIntervalSince1970))"
            if data.settings.healthKitSyncedSessionIds.contains(id) { continue }
            guard let recs = bucket[key], !recs.isEmpty else { continue }
            let start = recs.map { $0.performedAt }.min() ?? key.day
            let end = recs.map { $0.performedAt }.max() ?? key.day
            let safeEnd = end.timeIntervalSince(start) < 60 ? start.addingTimeInterval(60) : end
            let activity = HKWorkoutActivityType.bestMatch(forCategories: recs.map { $0.category })
            // 简化的 kcal 估算 — 跟 Settings 里那份一致
            let weight = data.settings.weight ?? 70
            var counts: [ExerciseCategory: Int] = [:]
            for r in recs { counts[r.category, default: 0] += 1 }
            let top = counts.max(by: { $0.value < $1.value })?.key ?? .strength
            let met: Double = (top == .strength) ? 5.0 : (top == .cardio ? 7.5 : 2.5)
            let kcal = met * (safeEnd.timeIntervalSince(start) / 3600) * weight
            let ok = await svc.writeWorkout(
                activity: activity, start: start, end: safeEnd,
                kcal: kcal, sourceTag: id
            )
            if ok {
                data.settings.healthKitSyncedSessionIds.insert(id)
            }
        }
    }

    // MARK: - 首次提示

    /// 是否应该展示首次"中间 tab"提示
    private var shouldShowCenterTabHint: Bool {
        !hasSeenCenterTabHint
            && !hasActiveSession
            && tab == .today
            && data.settings.onboardingCompleted
    }

    /// 把 hint 标成已读 — 第一次 tap 任意位置后调.
    /// 走 UserDefaults, app 卸载重装才会重置.
    private func dismissCenterTabHint() {
        withAnimation(.easeOut(duration: 0.25)) {
            hasSeenCenterTabHint = true
        }
    }

    @ViewBuilder
    private var centerTabHint: some View {
        VStack(spacing: 0) {
            Spacer()
            // 气泡 — accent 绿实色底 + 黑字, 跟 brand CTA 一致. 视觉权重高, 一眼吸引注意.
            // (之前改成深灰底太低调, 用户更喜欢绿色版本.)
            Text("Tap to start today's workout")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(MasoColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: MasoColor.accent.opacity(0.55), radius: 18, y: 4)
                .overlay(alignment: .bottom) {
                    Triangle()
                        .fill(MasoColor.accent)
                        .frame(width: 14, height: 8)
                        .offset(y: 7)
                }
                .scaleEffect(hintPulse ? 1.04 : 1.0)
                .padding(.bottom, MasoMetrics.bottomNavHeight + 18)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        hintPulse = true
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { dismissCenterTabHint() }
    }

    /// 进后台时如果在休息段, 调度倒计时通知. 前台时由 app 自己提示, 不发通知.
    private func scheduleRestNotificationIfNeeded() {
        guard let seg = session.currentSegment,
              seg.isRest,
              let endsAt = session.session?.endsAt,
              session.session?.playing == true else { return }
        // 当前 rest 段之后下一个 exercise 名 (给通知 body)
        var nextName: String? = nil
        if let sess = session.session {
            for i in (sess.segmentIndex + 1)..<session.segments.count {
                if case .exercise(let ex, _, _, _, _, _, _) = session.segments[i].kind {
                    nextName = ex.displayName  // 本地化通知文案
                    break
                }
            }
        }
        // 判断是不是跨动作 rest — 跟 PlanPlayer 同款逻辑
        let isCross: Bool = {
            guard let sess = session.session else { return false }
            let i = sess.segmentIndex
            var prevStepId: String?
            var j = i - 1
            while j >= 0 {
                if session.segments[j].isExercise { prevStepId = session.segments[j].stepId; break }
                j -= 1
            }
            var nextStepId: String?
            var k = i + 1
            while k < session.segments.count {
                if session.segments[k].isExercise { nextStepId = session.segments[k].stepId; break }
                k += 1
            }
            guard let p = prevStepId, let n = nextStepId else { return false }
            return p != n
        }()
        RestNotificationScheduler.shared.schedule(
            endsAt: endsAt,
            isCrossExercise: isCross,
            nextExerciseName: nextName
        )
    }

    /// 直接启动 (无确认) — 仅在确认替换后或没有冲突时调用
    private func startTrainingNow(_ plan: Plan) {
        let segments = expandPlan(
            plan,
            exById: data.exById,
            defaultRest: data.settings.defaultRestSeconds,
            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
        )
        session.start(planId: plan.id, plan: plan, segments: segments)
        playerPresented = true
    }
}

/// 等腰三角形 — 用于 centerTabHint 气泡底部指向下方的小箭头.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
