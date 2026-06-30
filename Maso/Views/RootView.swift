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
                // ToolbarItemGroup — trailing 闭包可放多个按钮 (各自独立 toolbar item, 系统统一间距),
                // 跟 Plans tab 右上角两个按钮 (Exercises + Settings) 的组合方式一致.
                ToolbarItemGroup(placement: .topBarTrailing) {
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
    /// RootTab → 分析事件 tab 名 (无 PII, 纯枚举名).
    private static func tabName(_ t: RootTab) -> String {
        switch t {
        case .plans: return "plans"
        case .today: return "today"
        case .library: return "library"
        case .history: return "history"
        }
    }
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
    /// Exercises tab 右上角 "+" → 翻 true, embedded ExerciseLibraryBrowser 监听后开"加动作"选择 sheet.
    @State private var libraryAddRequested = false
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
        case "library", "exercises":
            tab = .library        // Exercises 独立 tab (#IA: 第 4 个底部 tab)
        case "routines":
            tab = .plans          // Routines tab (AI | Classics)
        case "plan_detail":
            // 计划详情 sheet — 复用 newPlanForEdit 通道 (今日推荐做内容, 截图够看).
            tab = .today
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                newPlanForEdit = data.todayRecommendedPlan ?? data.plans.first
            }
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
            // onDone = "AI 生成中"过渡跑完后回调 —— 此时才置 onboardingCompleted 切到主界面.
            // (confirm() 不再当场置位, 否则过渡 overlay 来不及显示, 见 OnboardingScreen.confirm.)
            OnboardingScreen {
                data.settings.onboardingCompleted = true
                // reached_home — 引导过渡跑完、首次进主界面 (含 AI 首份计划是否失败).
                Analytics.shared.track("reached_home", ["ai_today_failed": .bool(data.aiTodayFailed)])
                data.flushSave()
            }
                .transition(.opacity)
                // 引导期也接收 maso:// 邀请链接 — 解码后暂存 importedPlan, 引导完成进主界面时
                // else 分支的 .sheet(item:$importedPlan) 会因其非空自动弹出. 不再静默丢弃朋友的分享链接.
                .onOpenURL { url in
                    if let plan = PlanShareCodec.decodePlan(from: url) {
                        importedPlan = plan
                    } else if url.scheme == PlanShareCodec.urlScheme {
                        importFailed = true
                    }
                }
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
                // Today — 今日总览: 肌肉状态 + 今日推荐 + 自由训练 (落地页, .today tag).
                NavigationStack {
                    TodayScreen(
                        onStart: startTraining,
                        onFreeWorkout: { quickWorkoutPresented = true },
                        onNewPlan: handleNewPlan,
                        onOpenSettings: { settingsPresented = true },
                        onGoToDiscover: { tab = .plans },
                        embedded: true,
                        mode: .trainToday   // #IA-v2: Today = 肌肉状态 + 今日推荐 + Free workout. My Routines 已迁到 Plans tab.
                    )
                    .screenHeader("Today") {
                        Button(action: { settingsPresented = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .tint(MasoColor.text)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                .tabItem {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
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
                    Label("Plans", systemImage: "square.stack.3d.up.fill")
                }
                .tag(RootTab.plans)

                // Exercises — 动作库独立 tab (#IA: Hevy/Strong 同款; 跟 Routines 相邻, "计划"簇).
                // 内容类型跟 routine 集合不同 (原子动作百科), 不再挤在 Routines 的 segmented 里.
                NavigationStack {
                    ExerciseLibraryBrowser(asTab: true, embedded: true, addRequested: $libraryAddRequested)
                        .screenHeader("Exercises") {
                            Button { libraryAddRequested = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .regular))
                            }
                            .accessibilityLabel(NSLocalizedString("Add exercise", comment: ""))
                            Button(action: { settingsPresented = true }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .regular))
                            }
                            .accessibilityLabel("Settings")
                        }
                }
                .tint(MasoColor.text)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell.fill")
                }
                .tag(RootTab.library)

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
            // tab_switch — 用户切底 Tab (含程序化切换都流经这, 见 router.requestedTab / showcase).
            .onChange(of: tab) { _, newTab in
                Analytics.shared.track("tab_switch", ["tab": .string(Self.tabName(newTab))])
            }
            // "AI 正在按新偏好重算计划" loading 浮层 — 离开 Training Preferences 且改过设置时显示 ~0.9s.
            .overlay { tailoringPlansOverlay }
            .animation(.easeInOut(duration: 0.25), value: data.isTailoringPlans)
            .animation(.easeOut(duration: 0.25), value: hasActiveSession)
            // 1Hz tick — 不管 PlanPlayer sheet 开没开, 只要有 active session 就在 tick.
            // 之前 SessionTickerView 只挂在 PlanPlayerScreen 里, sheet 一收 timer 也跟着停,
            // MiniBar 上的倒计时就定住了. 挪到 RootView 顶层后, MiniBar 跟 Player 都靠它驱动.
            .background(SessionTickerView())
            // 反馈队列 daily digest — app 启动 + 每次回前台都尝试一次. 24h 内最多 send 一次,
            // 由 FeedbackStore 内部判断. 没 pending 时 trySendDigest 是 no-op.
            .task {
                // 先落 showcase 屏 (截图流水线) — 不能被下面的网络 await 阻塞.
                // (Path B 后 refreshAIWorkoutIfNeeded 会发真 LLM 网络调用, 不能再排在 showcase 前.)
                applyShowcaseModeIfNeeded()
                await feedbackStore.trySendDigest()
                // App 启动时也尝试 refresh AI 训练计划 — 同一天已经生成则 no-op
                await data.refreshAIWorkoutIfNeeded()
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
            // 训练界面 = Apple Music 式全屏 (fullScreenCover 填满整页, 无顶部缝隙/无系统 grabber).
            // 关闭走 PlanPlayerScreen 自带的顶部 Drag Handle 下拉手势 (训练中) / 完成页按钮.
            .fullScreenCover(isPresented: $playerPresented) {
                PlanPlayerScreen()
                    // 透明 cover 背景 → 下拉收起时, PlanPlayerScreen 内的淡出黑背板变透明后,
                    // 后面的标签页界面能透出来 (Apple Music 式收起). 平时背板不透明, 视觉等同全屏.
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $settingsPresented) {
                NavigationStack { SettingsScreen() }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallScreen()
                .presentationDragIndicator(.visible)
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
                .presentationDragIndicator(.visible)
            }
            // 全局重量单位同步 — 显示 helper weightLabel(_:) 读 WeightUnitProvider.current.
            // initial:true 保证首帧 (任何重量显示前) 就设好; 之后切 kg/lb 即时生效.
            .onChange(of: data.settings.weightUnit, initial: true) { _, u in
                WeightUnitProvider.current = u
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
                .presentationDragIndicator(.visible)
            }
            .alert("Invalid routine link", isPresented: $importFailed) {
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
                .presentationDragIndicator(.visible)
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

    /// "AI 正在按新偏好重算计划" loading 浮层. 用户在 Training Preferences 改了设置并离开页面后,
    /// commitRecommendedPlansIfDirty 把 isTailoringPlans 翻 true ~0.9s —— 把"刷新 AI Plans"做成
    /// 一个明确可感知的动作 (而不是改一下 stepper 就在背后悄悄重算), 让用户知道 AI 在重新计算.
    @ViewBuilder
    private var tailoringPlansOverlay: some View {
        if data.isTailoringPlans {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(MasoColor.accent)
                    Text("Tailoring your AI routines…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(MasoColor.surfaceHi)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(MasoColor.borderSoft, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 28, y: 10)
                )
            }
            .transition(.opacity)
            .zIndex(200)
        }
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
            // Apple Watch 防双计: 手表本次训练跑了 HKWorkoutSession (带实时心率, 由手表保存),
            // 手机端不再写当天这份 — 直接标记已同步. 标记消费后复位, 不影响之后的纯手机训练.
            if WatchSyncManager.shared.watchHealthSessionActive, cal.isDateInToday(key.day) {
                data.settings.healthKitSyncedSessionIds.insert(id)
                WatchSyncManager.shared.resetForNewWorkout()
                continue
            }
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
        session.start(planId: plan.id, plan: plan, segments: segments, source: Self.workoutSource(for: plan))
        playerPresented = true
    }

    /// 训练来源分类 (无 PII) — 按 plan id 前缀 + resolvedSource 推断, 供 workout_start 的 source.
    private static func workoutSource(for plan: Plan) -> String {
        if plan.id.hasPrefix("qw-") { return "free" }
        if plan.id.hasPrefix("session-replay-") { return "replay" }
        if plan.id.hasPrefix("plan-gap-") { return "gap" }
        switch plan.resolvedSource {
        case .ai: return "ai"
        case .classics: return "classic"
        case .custom: return "recommended"
        }
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

    var body: some View {
        NavigationStack {
            PlansScreen(onStart: onStart, onNewPlan: onNewPlan, onOpenSettings: onOpenSettings)
                // PlansScreen 自己设大标题 "Routines" + 右上角工具栏 ("+" 在左, 齿轮在右) — 两个按钮都在
                // PlansScreen 的一个 ToolbarItemGroup 里 (#IA-A). AI/Classics 从 "+" push 进去 (不再是 segmented).
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

