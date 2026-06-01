import HealthKit
import SwiftUI

// Tab 顺序 (左 → 中 → 右) = today / plans / history.
// 之前是 plans / today / history (today 在中间 big circle), 用户决定让 plans 上位中间 hub.
// 注意 enum case 的"声明顺序"和"UI 显示顺序"现在分开管理:
//   - case 排列保留 (避免影响其他用 RootTab 的代码)
//   - UI 实际渲染顺序在 TabBarView 里手动按 today → plans → history 排
enum RootTab: Hashable { case plans, today, library, history }

/// "Train" tab 内部的两个分页: 我的训练 (原 Today 内容) / 动作库.
enum TrainPage: Hashable { case plans, library }

extension View {
    /// 条件应用一个 transform — Train tab 内嵌 (embedded) 时各分页跳过自己的 screenHeader,
    /// 由 Train 的统一导航栏 (segmented + 右上角按钮) 接管.
    @ViewBuilder func applyIf<T: View>(_ condition: Bool, _ transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }

    /// iOS 默认导航栏 — 系统大标题 (large title, 滚动时收缩成 inline) + 右上角 toolbar 按钮.
    /// 用户要求所有 tab 的标题/右上角按钮回到 iOS 原生样式, 不再用自定义 safeAreaInset 大标题头.
    /// kicker (Today 的问候) 在原生导航栏没有对应槽位, 保留参数签名但忽略 — 调用方不用改.
    func screenHeader<T: View>(_ title: String, kicker: String? = nil, @ViewBuilder trailing: @escaping () -> T) -> some View {
        self
            .navigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    trailing()
                }
            }
    }
}

// 顶级路由 — 跟 web 端 App.tsx 1:1
//   - onboarding 未完成: 整屏 Onboarding
//   - 已完成: TabBar + 3 个屏 (Plans / Today / History), 加 PlanPlayer sheet
struct RootView: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: RootTab = .today
    /// "Train" tab 当前分页 (My Plans / Exercise Library). 提到 RootView 以便 showcase / 路由能切.
    @State private var trainPage: TrainPage = .plans
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
    /// Imported plan from maso:// deep link — set ≠ nil 时弹 ImportedPlanSheet
    @State private var importedPlan: Plan? = nil
    /// 解析 deep link 出错 (base64 invalid / JSON invalid / 链接残破) → 弹通用错误 alert
    @State private var importFailed: Bool = false

    /// Marketing screenshot mode — set MASO_SHOWCASE env var on simulator launch to land on a specific screen.
    /// Values: today (default) / history / settings / player / free_workout / rest
    /// Used by App Store screenshot pipeline. No-op in production (env var only set when launching
    /// from CI / asset gen script). Safe to keep — no behavior change for real users.
    private func applyShowcaseModeIfNeeded() {
        let mode = ProcessInfo.processInfo.environment["MASO_SHOWCASE"] ?? ""
        guard !mode.isEmpty else { return }
        switch mode {
        case "library":
            tab = .plans          // Plans tab
            trainPage = .library  // 切到 Exercises 分页
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
            // iOS 默认 TabView — 3 个 tab 用系统标准 bar
            // MiniBar 通过 .safeAreaInset(edge:.bottom) 应用到每个 tab 的内容上
            // (而不是整个 TabView), 这样系统 TabBar 始终留在底部, MiniBar 紧贴 TabBar 上方,
            // 两者并排显示. 之前在 TabView 上加 safeAreaInset 会出现 MiniBar 跟 TabBar
            // 视觉粘在一起像一个大方块的情况.
            TabView(selection: $tab) {
                // 三个 tab 都包 NavigationStack — 走 iOS 默认 navigationTitle + toolbar 样式.
                // .tint(MasoColor.text) 覆盖系统默认 (Asset AccentColor 是绿) — toolbar 右上角按钮
                // 走白色, 跟 dark theme 配色一致 (不再绿).
                // Train — 今日总览: 肌肉状态 + 今日推荐 (落地页, .today tag).
                NavigationStack {
                    TodayScreen(
                        onStart: startTraining,
                        onFreeWorkout: { quickWorkoutPresented = true },
                        onNewPlan: handleNewPlan,
                        onOpenSettings: { settingsPresented = true },
                        embedded: true,
                        mode: .trainToday
                    )
                    .screenHeader("Train") {
                        Button(action: { settingsPresented = true }) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .tint(MasoColor.text)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                .tabItem {
                    Label("Train", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(RootTab.today)

                // Plans — segmented [My Plans | Exercises]: 我的训练 + 自由训练 + 社区, 以及动作库.
                PlansTabScreen(
                    page: $trainPage,
                    onStart: startTraining,
                    onFreeWorkout: { quickWorkoutPresented = true },
                    onNewPlan: handleNewPlan,
                    onOpenSettings: { settingsPresented = true }
                )
                .tint(MasoColor.text)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                .tabItem {
                    Label("Plans", systemImage: "list.bullet.clipboard.fill")
                }
                .tag(RootTab.plans)

                NavigationStack {
                    HistoryScreen(
                        onReplay: startTraining,
                        onOpenSettings: { settingsPresented = true }
                    )
                }
                .tint(MasoColor.text)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                .tabItem {
                    // "History" 比 "Workout Records" 短一半 — Tab 3 不再溢出. 中文走 zh-Hans
                    // Localizable.strings 里 "History" = "训练记录", 不影响中文显示.
                    Label("History", systemImage: "clock.fill")
                }
                .tag(RootTab.history)
            }
            .tint(MasoColor.accent)
            .animation(.easeOut(duration: 0.25), value: hasActiveSession)
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
                } else if newPhase == .background || newPhase == .inactive {
                    // 进后台 → 如果当前在休息段, 调度倒计时结束通知 (锁屏 / 切其它 app 时收到)
                    scheduleRestNotificationIfNeeded()
                    // P2-1: save() 现在是 debounced — 进后台/inactive 立即 flush, 防 pending 写丢失.
                    data.flushSave()
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
                    // .library / .plans 现在都是 Plans tab 的分页 — 映射到 .plans + 对应 trainPage.
                    switch newTab {
                    case .library: tab = .plans; trainPage = .library
                    case .plans:   tab = .plans; trainPage = .plans
                    default:       tab = newTab
                    }
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
            // 自由训练 — 跳过选肌肉那步, 直接进多选动作 picker (部位/动作/器械三列筛选).
            // 选好若干动作 → Start → 合成 plan 开练.
            .sheet(isPresented: $quickWorkoutPresented) {
                ExercisePickerSheet(
                    onPick: { _ in },               // multiSelect 模式不走单选回调
                    multiSelect: true,
                    onPickMultiple: { startFreeWorkout($0) },
                    startTitle: NSLocalizedString("Start workout", comment: "")
                )
            }
            // maso://import?plan=<base64> — 拦截 deep link, 解码 → 弹 ImportedPlanSheet.
            // 失败 (链接残破 / base64 invalid / JSON 解码错) 弹通用 alert, 不静默吞掉.
            .onOpenURL { url in
                if let plan = PlanShareCodec.decodePlan(from: url) {
                    importedPlan = plan
                } else if url.scheme == PlanShareCodec.urlScheme {
                    // 是我们的 scheme 但内容坏掉 — 才报错;
                    // 别的 scheme (不太可能, 因为系统按 scheme 路由) 默认忽略.
                    importFailed = true
                }
            }
            // Imported plan 预览 sheet — 用户在外面点 maso:// 链接 → 在这里弹
            .sheet(item: $importedPlan) { plan in
                ImportedPlanSheet(
                    plan: plan,
                    onAdd: { p in
                        // 先 dismiss sheet 再写 data — 跟 community add 同步骤,
                        // 防 sheet 关闭过渡中引用的旧 plan 副本闪一下.
                        importedPlan = nil
                        DispatchQueue.main.async {
                            data.plans.append(p)
                            data.save()
                            Haptics.tap()
                            // 落到 Plans/My Plans, 让用户在"我的训练"列表里看到新加的 plan
                            tab = .plans
                            trainPage = .plans
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .alert("Invalid plan link", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This Maso link is damaged or unsupported. Ask your friend to share again.")
            }
            // + 按钮创建的新 plan — 关 sheet 时如果空了自动清理
            .sheet(item: $newPlanForEdit, onDismiss: {
                if let planId = lastCreatedPlanId { data.removePlanIfEmpty(planId) }
                lastCreatedPlanId = nil
                // 新建的 plan 出现在 Plans/My Plans 列表 — 切过去让用户看到.
                tab = .plans
                trainPage = .plans
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

    /// Tab 切换决定右上角浮动按钮:
    ///   - 所有 tab 都不再用 RootView 右上角浮动按钮 — Today 的 settings 入口
    ///     挪到 TodayScreen 标题行里, 跟 GOOD AFTERNOON 同一 section 视觉对齐.
    @ViewBuilder
    private var topRightAction: some View {
        EmptyView()
    }

    /// + 按钮 — 建一个空白 plan, 弹出编辑 sheet.
    ///
    /// Free 用户撞到 plan 上限 (FreeLimit.maxPlans) 弹 paywall; Pro 用户无限新建.
    private func handleNewPlan() {
        if !data.settings.isPro && data.plans.count >= FreeLimit.maxPlans {
            paywallPresented = true
            return
        }
        let plan = data.createBlankPlan()
        lastCreatedPlanId = plan.id
        newPlanForEdit = plan
    }

    /// 是否有进行中的训练 (用于 MiniBar 显隐 + safeArea 调整)
    private var hasActiveSession: Bool {
        guard let s = session.session else { return false }
        return !s.completed && session.currentSegment != nil
    }

    /// MiniBar 内容 — 给每个 tab 的 .safeAreaInset 复用. 用 @ViewBuilder 让它能在
    /// hasActiveSession=false 时返回 EmptyView (MiniBarHost 会判断是否实际渲染).
    @ViewBuilder
    private var miniBarContent: some View {
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
        // 大圆按钮 (左侧) = Today tab.
        // 1) 不在 Today tab → 切到 Today (跟其他 side tab tap 行为一致).
        if tab != .today {
            tab = .today
            return
        }
        // 2) 已在 Today + 训练中 → 拉起正在进行的 PlanPlayer
        if hasActiveSession {
            playerPresented = true
            return
        }
        // 3) 已在 Today + 没训练 → quickStart 开了就直接开练今日推荐 (muscle memory: 选中 tab 再点 = 开始)
        let quickStart = data.settings.quickStartOnActiveTab
        guard quickStart else { return }
        // P1-1: 跟 TodayScreen.suggested 用同一优先级 (recommended ?? ai) —
        // 否则点中间 tab 启动的训练 ≠ 卡片上显示的那张, 状态错位.
        let plan = data.todayRecommendedPlan ?? data.aiTodayPlan
        guard let plan, !plan.steps.isEmpty else { return }
        startTraining(plan)
    }

    /// 统一启动训练入口 — DESIGN 5.3:
    /// 如果已有别的进行中 session, 先弹确认; 用户确认后才替换
    /// 自由训练 — 把多选 picker 选出的动作合成一个 autoGenerated plan 开练.
    /// (镜像旧 QuickWorkoutScreen.synthesizePlan: 默认 category 排序 + 上次负荷回填.)
    private func startFreeWorkout(_ exercises: [Exercise]) {
        guard !exercises.isEmpty else { return }
        let now = Date()
        let sorted = exercises.sorted { l, r in
            if l.category != r.category {
                return l.category == .strength || (l.category == .cardio && r.category == .flexibility)
            }
            return false
        }
        let steps: [PlanStep] = sorted.enumerated().map { (i, ex) in
            let lastSet = data.sets.first(where: { $0.exerciseId == ex.id })
            let isStrength = ex.category == .strength
            return PlanStep(
                id: "qw-step-\(Int(now.timeIntervalSince1970))-\(i)",
                exerciseId: ex.id,
                sets: 3,
                reps: isStrength ? (lastSet?.reps ?? 10) : nil,
                weight: isStrength ? (lastSet?.weight ?? 0) : nil,
                duration: isStrength ? nil : 30,
                restBetweenSets: data.settings.defaultRestSeconds,
                rest: 0
            )
        }
        let dateStr = now.formatted(.dateTime.month().day().hour().minute())
        let plan = Plan(
            id: "qw-\(Int(now.timeIntervalSince1970))",
            name: "\(NSLocalizedString("Free workout", comment: "")) · \(dateStr)",
            steps: steps,
            createdAt: now,
            updatedAt: now,
            autoGenerated: true
        )
        startTraining(plan)
    }

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

    /// 是否应该展示首次"中间 tab"提示.
    /// 现在中间 tab 是 plans (不再是 today), 原文案"Tap to start today's workout"语义不再对,
    /// 暂时关掉. Today tab 上 WorkoutCard 自带 play button 已经是显眼的开始训练入口.
    private var shouldShowCenterTabHint: Bool {
        false
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

    /// 进后台时如果在休息段 *或正在跑的有氧倒计时段*, 调度倒计时通知.
    /// 前台时由 app 自己提示, 不发通知.
    /// P1-9: 之前只给 rest 发通知, 有氧 countdown 动作在后台到点无任何提示.
    private func scheduleRestNotificationIfNeeded() {
        guard let seg = session.currentSegment,
              let endsAt = session.session?.endsAt,
              session.session?.playing == true else { return }
        // 有氧倒计时段 — 发"Time's up"通知, 不走 rest 的 next-set 文案.
        if seg.isExercise {
            if case .exercise(_, _, _, _, _, _, let countdown) = seg.kind, countdown {
                RestNotificationScheduler.shared.schedule(
                    endsAt: endsAt,
                    isCrossExercise: false,
                    nextExerciseName: nil,
                    exerciseCountdown: true
                )
            }
            return
        }
        guard seg.isRest else { return }
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

// 条件 NavigationStack — embedded 时直接给 content (由外层 Train NavStack 接管), 否则自带一层.
struct NavStackIf<Content: View>: View {
    let embedded: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        if embedded { content() } else { NavigationStack { content() } }
    }
}

// MARK: - PlansTabScreen — "Plans" tab: 单一导航栏, segmented 当标题切 My Plans / Exercises
//
// 一个 NavigationStack 接管整页. 顶部导航栏中央放 segmented (= 标题), 右上角按钮按分页切
// (My Plans → 齿轮; Exercises → +). 两个分页 (TodayScreen .myPlans / ExerciseLibraryBrowser) 都
// embedded: 不自带 NavStack / 大标题. 切页保留各自滚动 / sheet 状态.
private struct PlansTabScreen: View {
    @Binding var page: TrainPage
    let onStart: (Plan) -> Void
    let onFreeWorkout: () -> Void
    let onNewPlan: () -> Void
    let onOpenSettings: () -> Void
    /// embedded Library 的 "+" 触发器 — Train 右上角 + 翻 true, Library 监听后开"加动作" sheet.
    @State private var libraryAddRequested = false

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .plans:
                    TodayScreen(
                        onStart: onStart,
                        onFreeWorkout: onFreeWorkout,
                        onNewPlan: onNewPlan,
                        onOpenSettings: onOpenSettings,
                        embedded: true,
                        mode: .myPlans
                    )
                case .library:
                    ExerciseLibraryBrowser(asTab: true, embedded: true, addRequested: $libraryAddRequested)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $page.animation(.easeOut(duration: 0.18))) {
                        Text("My Plans").tag(TrainPage.plans)
                        Text("Exercises").tag(TrainPage.library)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    switch page {
                    case .plans:
                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    case .library:
                        Button(action: { libraryAddRequested = true }) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(NSLocalizedString("Add exercise", comment: ""))
                    }
                }
            }
            .tint(MasoColor.text)
        }
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

