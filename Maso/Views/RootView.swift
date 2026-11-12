import HealthKit
import SwiftUI

// Secondary destinations; Today is the sole home screen.
// Keep legacy route names for existing summary/optimization links.
enum AppDestination: Hashable {
    case today, coach, history, insights, exerciseLibrary, classicRoutines, diet, sleep, settings
    case muscleStatus
    case muscleInfo(MuscleSelection)
    /// Home calendar day, including the widget deep link. The value is the start of that day.
    case dailyRecord(Date)
}

extension View {
    /// 条件应用一个 transform — 内嵌 (embedded) 场景各分页跳过自己的 screenHeader,
    /// 由外层容器 (RootView 的 NavigationStack / 承载它的 sheet) 接管导航栏.
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

// 顶级路由
//   - onboarding 未完成: 整屏 Onboarding
//   - 已完成: Today + Insights/Coach destinations, 加 PlanPlayer fullScreenCover
struct RootView: View {
    var launchReady: Bool = true
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(TrainingSessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var navigationPath: [AppDestination] = []
    /// 反馈队列 — 没 inject 进 environment, 因为它只在 Settings + scenePhase 监听里用,
    /// 直接拿 shared 单例最简单, 避免到处 propagate.
    @State private var feedbackStore = FeedbackStore.shared
    /// 跨 sheet 切 tab 路由
    @State private var router = AppRouter.shared
    @State private var playerPresented: Bool = false
    /// P1#12: 是否应当阻止自动锁屏 — 播放器全屏在前 + session 活跃 (未完成) + app 在前台
    /// + 用户偏好开着. 收进一个 computed 让 onChange 观察单一 Bool, 四个依赖任一变化都会
    /// 重新求值 (playerPresented @State / scenePhase env / session·settings 都是 observable).
    private var shouldKeepScreenAwake: Bool {
        playerPresented
            && scenePhase == .active
            && data.settings.keepScreenAwakeDuringWorkout
            && session.session != nil
            && session.session?.completed != true
    }

    @ViewBuilder
    private var muscleStatusDestination: some View {
        MuscleMapDetailScreen(
            fatigueMap: MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById),
            gapMuscles: muscleStatusGapMuscles,
            onStartGapWorkout: {
                navigationPath = []
                muscleStatusStartGapWorkout?()
            },
            onUnlock: { paywallPresented = true },
            onOpenMuscleInfo: { navigationPath.append(.muscleInfo($0)) }
        )
        .navigationTitle("My Muscle Status")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private func muscleInfoDestination(_ selection: MuscleSelection) -> some View {
        MuscleInfoScreen(
            muscle: selection.muscle,
            relatedMuscles: selection.relatedMuscles,
            regionNode: selection.regionNode,
            showsBack: selection.showsBack,
            onTrainMore: {
                AppRouter.shared.pendingMuscleTraining = selection.muscle
                navigationPath.append(.coach)
            }
        )
        .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .coach:
            CoachScreen(
                onStart: startTraining,
                onNewPlan: handleNewPlan,
                libraryRequested: $coachLibraryRequested,
                routinePromptRequested: $coachRoutinePromptRequested,
                quickWorkoutRequested: $coachQuickWorkoutRequested,
                bodyPhotoRequested: $coachBodyPhotoRequested
            )
            .marketingCaptureReady("coach_chat")
            .toolbar(.visible, for: .navigationBar)

        case .history, .insights:
            HistoryScreen(
                onReplay: startTraining,
                onOpenSettings: { navigationPath.append(.settings) },
                mode: destination == .history ? .records : .insights
            )
            .marketingCaptureReady("insights")
            .toolbar(.visible, for: .navigationBar)

        case .sleep:
            SleepScreen().marketingCaptureReady("sleep").toolbar(.visible, for: .navigationBar)
        case .diet:
            DietScreen().marketingCaptureReady("diet").toolbar(.visible, for: .navigationBar)
        case .exerciseLibrary:
            ExerciseLibraryBrowser(embedded: true, addRequested: $libraryAddRequested)
                .navigationTitle("Exercises")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { libraryAddRequested = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add exercise")
                    }
                }
                .toolbar(.visible, for: .navigationBar)

        case .classicRoutines:
            ClassicsScreen(onStart: { plan in
                navigationPath = []
                DispatchQueue.main.async { startTraining(plan) }
            })
            .toolbar(.visible, for: .navigationBar)

        case .settings:
            SettingsScreen(onStartWorkout: { plan in
                navigationPath = []
                DispatchQueue.main.async { startTraining(plan) }
            }, isPushed: true)
            .toolbar(.visible, for: .navigationBar)
        case .muscleStatus:
            muscleStatusDestination.marketingCaptureReady("muscle_status")
        case .muscleInfo(let selection):
            muscleInfoDestination(selection)
        case .dailyRecord(let day):
            DailyRecordSheet(day: day, onReplay: { plan in
                navigationPath.removeAll { destination in
                    if case .dailyRecord = destination { return true }
                    return false
                }
                DispatchQueue.main.async { startTraining(plan) }
            }, pushed: true)
                .accessibilityIdentifier("page.dailyRecord")
                .toolbar(.visible, for: .navigationBar)
        case .today:
            EmptyView()
        }
    }
    /// showcase "exercises"/"library" 路由 → 翻 true, CoachScreen 监听后拉起动作库 sheet
    /// (Exercises 不再是 tab — 库入口在 Coach 导航栏 dumbbell, 路由名保持不变让夜间 driver 不断).
    @State private var coachLibraryRequested = false
    @State private var homeFooterControlHeight: CGFloat = 56
    @State private var homeContentWidth: CGFloat = 0
    private enum CoachTip { case intro, bodyPhoto }
    @State private var coachIntroTipVisible = false
    @State private var firstHomeMuscleIntroVisible = false
    @State private var visibleCoachTip: CoachTip = .intro
    @State private var coachTipSessionReady = false
    @State private var coachTipInitialized = false
    @State private var coachTipShownThisSession = false
    @State private var coachBodyPhotoRequested = false
    /// Today 空 Routines 引导卡请求在 AI Coach 输入框预填建计划提示.
    @State private var coachRoutinePromptRequested = false
    @State private var coachQuickWorkoutRequested = false
    @State private var libraryAddRequested = false
    @State private var quickWorkoutPresented: Bool = false
    // DESIGN 5.3: 当用户尝试开第二个训练时, 用 plan 作为 pending 标记弹替换确认
    @State private var pendingReplacePlan: Plan?
    // + 按钮新建的 plan — 用 sheet(item:) 双向绑定; nil 表示关闭
    @State private var newPlanForEdit: Plan?
    /// 记录最近一次 + 按钮创建的 planId, 关 sheet 时用来判断要不要清理
    @State private var isCreatingPlan = false
    /// Free 用户撞到 plan 上限时弹的 paywall
    @State private var paywallPresented: Bool = false
    @State private var welcomePaywallPresented = false
    /// Imported plan from maso:// deep link — set ≠ nil 时弹 ImportedPlanSheet
    @State private var importedPlan: Plan? = nil
    /// 解析 deep link 出错 (base64 invalid / JSON invalid / 链接残破) → 弹通用错误 alert
    @State private var importFailed: Bool = false
    /// Polar 激活结果提示 (maso://activate?key= 深链回跳后弹).
    @State private var activateMessage: String? = nil
    @State private var activateShown: Bool = false
    @State private var muscleStatusGapMuscles: [MuscleGroup] = []
    @State private var muscleStatusStartGapWorkout: (() -> Void)?

    @State private var widgetMealToRecord: DietMeal?

    private var showingDailyRecord: Bool {
        navigationPath.contains { destination in
            if case .dailyRecord = destination { return true }
            return false
        }
    }

    private var homeQuickActionBlocked: Bool {
        welcomePaywallPresented || paywallPresented || newPlanForEdit != nil || importedPlan != nil
            || pendingReplacePlan != nil || quickWorkoutPresented || widgetMealToRecord != nil || showingDailyRecord
    }
    private func openHomeQuickActionIfReady() {
        guard let request = router.pendingHomeQuickAction, launchReady,
              data.settings.onboardingCompleted, router.homeQuickActionsReady, scenePhase == .active else { return }
        if (request.action == .addMeal && widgetMealToRecord != nil)
            || (request.action == .freeWorkout && quickWorkoutPresented)
            || (request.action == .workout && playerPresented) {
            router.pendingHomeQuickAction = nil
            return
        }
        // Preserve an in-progress editor. Its normal dismissal resumes the latest request.
        guard !homeQuickActionBlocked else { return }
        if request.action == .freeWorkout, playerPresented {
            playerPresented = false
            return
        }
        router.pendingHomeQuickAction = nil
        switch request.action {
        case .addMeal: router.pendingWidgetDestination = .addMeal
        case .coach: router.pendingWidgetDestination = .coach
        case .freeWorkout: navigationPath = []; quickWorkoutPresented = true
        case .workout:
            navigationPath = []
            if let current = session.session, !current.completed { playerPresented = true }
            else if data.todayRecommendedPlan != nil { router.pendingWidgetDestination = .playWorkout }
            else { quickWorkoutPresented = true }
        }
        // The existing pendingWidgetDestination observer owns the shared presentation.
    }

    private func openWidgetDestinationIfReady() {
        guard data.settings.onboardingCompleted,
              router.pendingWidgetDay != nil || router.pendingWidgetDestination != nil else { return }
        if playerPresented { playerPresented = false; return }
        if widgetMealToRecord != nil {
            if router.pendingWidgetDestination == .addMeal { router.pendingWidgetDestination = nil }
            else { widgetMealToRecord = nil }
            return
        }
        // A newly requested section replaces the day page on the next pass, matching
        // the previous sheet handoff where the day closed before the other link opened.
        if showingDailyRecord && router.pendingWidgetDestination != nil {
            navigationPath.removeAll { destination in
                if case .dailyRecord = destination { return true }
                return false
            }
            return
        }
        let requestedDay = router.pendingWidgetDay
        if requestedDay != nil { router.pendingWidgetDay = nil }
        guard let destination = router.pendingWidgetDestination else {
            if let requestedDay {
                navigationPath = [.dailyRecord(data.settings.calendar.startOfDay(for: requestedDay))]
            }
            return
        }
        router.pendingWidgetDestination = nil
        switch destination {
        case .addMeal:
            navigationPath = []
            widgetMealToRecord = DietMeal(id: UUID().uuidString, title: "Meal", portions: [])
        case .home: navigationPath = []
        case .workout: navigationPath = [.insights]
        case .diet: navigationPath = data.settings.dietEnabled == false ? [.settings] : [.diet]
        case .sleep: navigationPath = data.settings.sleepEnabled == false ? [.settings] : [.sleep]
        case .recovery: navigationPath = [.muscleStatus]
        case .coach: navigationPath = [.coach]; coachRoutinePromptRequested = true
        case .playWorkout:
            navigationPath = []
            startTodayWorkout()
        case .start:
            // Retired widget play links now open Home; never launch training automatically.
            navigationPath = []
        }
        if let requestedDay {
            navigationPath.append(.dailyRecord(data.settings.calendar.startOfDay(for: requestedDay)))
        }
    }

    /// maso://activate?key=<license> 深链 — Polar 结账成功回跳自动激活.
    /// 返回 true = 已消费掉 (是 activate 链接), 调用方就别再当 plan import 处理.
    private func handleActivateURL(_ url: URL) -> Bool {
        guard url.scheme == PlanShareCodec.urlScheme, url.host == "activate" else { return false }
        let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "key" })?.value ?? ""
        guard !key.isEmpty else { return true }
        Task {
            do {
                let ok = try await data.activatePolar(key: key)
                activateMessage = ok
                    ? NSLocalizedString("You're Pro now — thanks for supporting Masso.", comment: "Pro activation success")
                    : NSLocalizedString("That code isn't active yet. Check the email from your purchase, or try again in a moment.", comment: "Pro activation not active")
                if ok { Haptics.trainingComplete() }
            } catch {
                activateMessage = NSLocalizedString("Couldn't verify your code — check your connection and try again.", comment: "Pro activation network error")
            }
            // 深链结账回跳时 paywall sheet 通常还开着 (用户点 Continue 去 Safari 付款,
            // sheet 没关). iOS 不会在已有 sheet 之上弹 alert → 成功提示会被吞. 先关 sheet,
            // 等 dismiss 动画落定 (~0.4s) 再弹, 否则刚付完钱的人看不到任何确认.
            if paywallPresented { paywallPresented = false }
            try? await Task.sleep(nanoseconds: 400_000_000)
            activateShown = true
        }
        return true
    }

    #if DEBUG
    /// Six real library exercises. Used only by MASO_SHOWCASE=plan_detail_layout.
    private static func layoutCheckPlan() -> Plan {
        let ids = [
            "bench_press_barbell", "squat_barbell", "pull_up",
            "leg_curl_lying", "overhead_press_barbell", "barbell_row",
        ]
        let now = Date()
        return Plan(
            id: "layout-check-plan",
            name: "Layout Check",
            steps: ids.enumerated().map { index, exerciseId in
                PlanStep(id: "layout-check-\(index)", exerciseId: exerciseId, sets: 3, reps: 8, weight: 40)
            },
            createdAt: now,
            updatedAt: now
        )
    }
    #endif

    /// Marketing screenshot mode — set MASO_SHOWCASE env var on simulator launch to land on a specific screen.
    /// Values: today (default) / history / settings / player / free_workout / rest
    /// Used by App Store screenshot pipeline. No-op in production (env var only set when launching
    /// from CI / asset gen script). Safe to keep — no behavior change for real users.
    private func applyShowcaseModeIfNeeded() {
        #if DEBUG
        MarketingCaptureSeed.apply(to: data)
        #endif
        let mode = ProcessInfo.processInfo.environment["MASO_SHOWCASE"] ?? ""
        guard !mode.isEmpty else { return }
        switch mode {
        case "library", "exercises":
            // 路由名保持不变 (夜间 verify-app driver 的 ROUTES 依赖) — Exercises 已并入 Coach:
            // 落 Coach tab + 拉起动作库 sheet. 延迟到 CoachScreen 挂载后再翻, onChange 才收得到;
            // sheet 全屏盖住 Coach → 截图跟 "routines"/today 保持 distinct.
            navigationPath = [.coach]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { coachLibraryRequested = true }
        #if DEBUG
        case "home_muscle_intro":
            navigationPath = []
            data.settings.firstHomeMuscleIntroPending = true
            data.settings.coachIntroTipPending = false
            data.settings.coachBodyPhotoTipSeen = true
        case "coach_tip":
            navigationPath = []
            data.settings.coachIntroTipPending = true
        case "coach_photo_tip":
            navigationPath = []
            data.settings.coachIntroTipPending = false
            data.settings.coachBodyPhotoTipSeen = false
        #endif
        case "routines":
            navigationPath = [.coach]          // 原 Routines tab 能力已整体迁入 Coach
        case "coach_templates", "coach_prefs", "coach_chat", "coach_advice":
            // 顶栏走查用: 只负责落 Coach tab, sheet/种子对话由 CoachScreen 自己读 env 拉起
            // (templatesPresented/prefsPresented 是 CoachScreen 私有 state, 不走 binding 减少管线).
            navigationPath = [.coach]
        case "plan_detail":
            // 计划详情 sheet — 复用 newPlanForEdit 通道 (今日推荐做内容, 截图够看).
            navigationPath = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                newPlanForEdit = data.todayRecommendedPlan ?? data.plans.first
            }
        #if DEBUG
        case "plan_detail_layout":
            // UI test only. The plan stays in the sheet and is not written into the library.
            navigationPath = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                newPlanForEdit = Self.layoutCheckPlan()
            }
        #endif
        case "history":
            navigationPath = []
        case "diet":
            navigationPath = [.diet]
        case "sleep":
            navigationPath = [.sleep]
        case "muscle_status":
            #if DEBUG
            if ProcessInfo.processInfo.environment["MASO_MARKETING_GAPS"] == "1" {
                muscleStatusGapMuscles = [.back, .quads]
            }
            #endif
            navigationPath = [.muscleStatus]
        case "insights", "coach_insights":
            navigationPath = [.insights]
        case "settings":
            navigationPath = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { navigationPath.append(.settings) }
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

    @ViewBuilder
    private var demoPrefetchIDs: [String] {
        let plans = (data.suggestedTodayPlan.map { [$0] } ?? []) + data.plans + (data.aiTodayPlan.map { [$0] } ?? [])
        return plans.flatMap { $0.steps }.compactMap { data.exById[$0.exerciseId]?.id }
    }

    var body: some View {
        Group {
            if data.settings.onboardingCompleted { appNavigationContent }
            else { onboardingContent }
        }
        .background {
            WorkoutYouTubeRetentionHost(playback: session.youtubePlayback)
                .frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
        }
        .task(id: "\(session.workoutSessionID ?? "none")|\(session.session?.completed == true)|\(data.settings.workoutHeartRateEnabled == true)|\(WorkoutHeartRecommendation.effective(settings: data.settings, samples: WorkoutHeartLocalStore.shared.samples, excluding: session.workoutSessionID))") {
            session.heartRateReadEnabled = data.settings.workoutHeartRateEnabled == true
            session.heartRate.bind(sessionID: session.session?.completed == false ? session.workoutSessionID : nil,
                                   start: session.session?.startedAt, enabled: session.heartRateReadEnabled,
                                   limit: WorkoutHeartRecommendation.effective(settings: data.settings, samples: WorkoutHeartLocalStore.shared.samples, excluding: session.workoutSessionID))
            session.pushWatchState()
            await session.heartRate.startWatchWorkoutIfNeeded()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { homeContentWidth = $0 }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MASO_SHOWCASE"] == "plan_detail_layout" {
                data.settings.onboardingCompleted = true
            }
            #endif
            if !coachTipInitialized {
                coachTipInitialized = true
                coachTipSessionReady = data.settings.onboardingCompleted
            }
        }
        .task(id: nextCoachTip) {
            guard let tip = nextCoachTip else { return }
            // Let onboarding / modal dismissal and footer layout finish; cancel on navigation.
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, nextCoachTip == tip else { return }
            visibleCoachTip = tip
            coachIntroTipVisible = true
        }
        .task(id: "\(coachTipHomeAvailable)|\(data.settings.firstHomeMuscleIntroPending == true)") {
            guard data.settings.onboardingCompleted, coachTipHomeAvailable, data.settings.firstHomeMuscleIntroPending == true else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, coachTipHomeAvailable, data.settings.firstHomeMuscleIntroPending == true else { return }
            firstHomeMuscleIntroVisible = true
            data.settings.firstHomeMuscleIntroPending = false
            data.save()
        }
        .onChange(of: coachTipHomeAvailable) { _, available in
            if !available {
                coachIntroTipVisible = false
                firstHomeMuscleIntroVisible = false
            }
        }
        .onChange(of: navigationPath) { _, path in
            if path.contains(.coach), coachTipSessionReady, data.settings.coachIntroTipPending == true {
                dismissCoachIntroTip()
            }
        }
        .onChange(of: router.pendingHomeQuickAction, initial: true) { _, _ in openHomeQuickActionIfReady() }
        .onChange(of: router.homeQuickActionsReady) { _, _ in openHomeQuickActionIfReady() }
        .onChange(of: homeQuickActionBlocked) { _, blocked in
            if !blocked {
                Task { try? await Task.sleep(for: .milliseconds(350)); openHomeQuickActionIfReady() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && data.settings.onboardingCompleted {
                coachTipSessionReady = true
                coachTipShownThisSession = false
            }
            if phase == .active { openHomeQuickActionIfReady() }
        }
        .onChange(of: router.pendingWidgetDestination, initial: true) { _, _ in openWidgetDestinationIfReady() }
        .onChange(of: router.pendingWidgetDay, initial: true) { _, _ in openWidgetDestinationIfReady() }
        .onChange(of: data.settings.onboardingCompleted) { _, _ in openWidgetDestinationIfReady(); openHomeQuickActionIfReady() }
        .onChange(of: launchReady, initial: true) { _, _ in presentWelcomePaywallIfNeeded(); openHomeQuickActionIfReady() }
        .onChange(of: subscriptions.hasCheckedEntitlements) { _, _ in presentWelcomePaywallIfNeeded() }
        .fullScreenCover(isPresented: $welcomePaywallPresented, onDismiss: {
            data.settings.hasSeenWelcomePaywall = true
            data.save()
        }) {
            PaywallScreen(source: "first_launch", context: .welcome)
        }
    }

    private func presentWelcomePaywallIfNeeded() {
        guard launchReady, subscriptions.hasCheckedEntitlements,
              ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1" else { return }
        if WelcomePaywallPolicy.shouldPresent(hasSeen: data.settings.hasSeenWelcomePaywall,
                                              onboardingCompleted: data.settings.onboardingCompleted,
                                              isPro: data.settings.isPro) {
            welcomePaywallPresented = true
        }
    }

    private func receiveSharedPlan(_ url: URL) {
        if let plan = PlanShareCodec.decodePlan(from: url) { importedPlan = plan }
    }

    private var onboardingContent: some View {
        OnboardingScreen { plan in
            data.settings.onboardingCompleted = true
            data.settings.firstHomeMuscleIntroPending = true
            data.settings.coachIntroTipPending = true
            Analytics.shared.track("reached_home")
            data.flushSave()
            if let plan, router.pendingHomeQuickAction == nil { DispatchQueue.main.async { startTraining(plan) } }
        }
        .transition(.opacity)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { receiveSharedPlan(url) }
        }
        .onOpenURL { url in
            if url.scheme == "maso", url.host == "widget" { return }
            if handleActivateURL(url) { return }
            if let plan = PlanShareCodec.decodePlan(from: url) {
                importedPlan = plan
            } else if url.scheme == PlanShareCodec.urlScheme {
                importFailed = true
            }
        }
    }

    private var appNavigationContent: some View {
            AppNavigationStack(path: $navigationPath) {
                TodayScreen(
                    onStart: startTraining,
                    onFreeWorkout: { quickWorkoutPresented = true },
                    onNewPlan: handleNewPlan,
                    onOpenSettings: { navigationPath.append(.settings) },
                    onOpenMuscleStatus: { gaps, startGapWorkout in
                        muscleStatusGapMuscles = gaps
                        muscleStatusStartGapWorkout = startGapWorkout
                        navigationPath.append(.muscleStatus)
                    },
                    onOpenCoach: {
                        coachRoutinePromptRequested = true
                        navigationPath.append(.coach)
                    },
                    embedded: true,
                    mode: .trainToday,
                    showsHistory: true,
                    showMuscleIntro: firstHomeMuscleIntroVisible,
                    homeMotionEnabled: navigationPath.isEmpty && !playerPresented
                )
                .marketingCaptureReady("today")
                .safeAreaInset(edge: .bottom, spacing: 0) { homeBottomControls }
                .navigationDestination(for: AppDestination.self) { destination in destinationView(for: destination) }
            }
            .tint(MasoColor.text)
            .background(AppBackground())
            // "AI 正在按新偏好重算计划" loading 浮层 — 离开 Training Preferences 且改过设置时显示 ~0.9s.
            .overlay { tailoringPlansOverlay }
            .animation(.easeInOut(duration: 0.25), value: data.isTailoringPlans)
            .animation(.easeOut(duration: 0.25), value: hasActiveSession)
            // 1Hz tick — 不管 PlanPlayer sheet 开没开, 只要有 active session 就在 tick.
            // 之前 SessionTickerView 只挂在 PlanPlayerScreen 里, sheet 一收 timer 也跟着停,
            // MiniBar 上的倒计时就定住了. 挪到 RootView 顶层后, MiniBar 跟 Player 都靠它驱动.
            .background(SessionTickerView())
            // 反馈队列 daily digest — app 启动 + 每次回前台都尝试一次. 24h 内最多 send 一次,
            // 有离线报告时重试上传；汇总和每周邮件由服务端负责.
            .task {
                SleepReminderScheduler.shared.reschedule(settings: data.settings)
                // 先落 showcase 屏 (截图流水线) — 不能被下面的网络 await 阻塞.
                // (Path B 后 refreshAIWorkoutIfNeeded 会发真 LLM 网络调用, 不能再排在 showcase 前.)
                applyShowcaseModeIfNeeded()
                if ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1", NSClassFromString("XCTestCase") == nil,
                   ProcessInfo.processInfo.environment["MASO_EXERCISE_UI_TEST_SCENE"] == nil, let local = BodyHealthLocalStore.read() {
                    data.settings.restoreLocalBodyHealth(local)
                }
                await data.refreshBodyActivityHealth()
                try? await data.refreshExternalWorkouts()
                await feedbackStore.tryUploadPending()
                // App 启动时也尝试 refresh AI 训练计划 — 同一天已经生成则 no-op
                await data.refreshAIWorkoutIfNeeded()
            }
            .task(id: demoPrefetchIDs) {
                await ExerciseDemoService.shared.prefetch(demoPrefetchIDs)
            }
            .onChange(of: scenePhase) { _, newPhase in handleScenePhaseChange(newPhase) }
            .onChange(of: data.sets) { _, _ in session.refreshLoadSuggestions(using: data) }
            .onChange(of: session.plan, initial: true) { _, _ in session.refreshLoadSuggestions(using: data) }
            .onChange(of: session.awaitingExercise) { _, waiting in
                if waiting { playerPresented = true }
            }
            // 训练完成 (session.completed flip true) → 实时写 HealthKit
            .onChange(of: session.session?.completed ?? false, initial: true) { _, completed in
                if let current = session.session {
                    data.updateWorkoutCompletion(planID: current.planId, startedAt: current.startedAt,
                                                 completed: completed && !current.completedSets.isEmpty)
                }
                if completed && data.settings.healthKitSyncEnabled {
                    Task { await catchUpHealthKitSync() }
                }
                // 在 MiniBar 上完成最后一组: completed=true → hasActiveSession=false → bar 消失,
                // 完成页/保存确认/分享全被跳过. 这里补拉起播放器让完成流照常走.
                // guard !playerPresented — 播放器已打开时完成流由它自己接管, 不重复触发 cover.
                if completed && !playerPresented {
                    playerPresented = true
                }
            }
            // Summary/optimization links open Coach after their presenting sheet dismisses.
            .onChange(of: router.requestedDestination) { _, destination in
                if let destination {
                    switch destination {
                    case .today:
                        navigationPath.removeAll()
                    default:
                        navigationPath = [destination]
                    }
                    router.requestedDestination = nil
                }
            }
            // P1#12: 训练时保持屏幕常亮 — 力量组不倒计时, 系统 30s 自动锁屏会让每组结束时屏幕已黑.
            // 条件全部收在 shouldKeepScreenAwake (播放器在前 + session 活跃 + app 在前台 + 开关开);
            // 任一条件破 (收回 mini-bar / 完成 / 退后台 / 关开关) 立即复位, 不留常亮泄漏耗电.
            // initial:true — 冷启恢复 session 直接进播放器的场景, 首帧就要置位.
            .onChange(of: shouldKeepScreenAwake, initial: true) { _, keepAwake in
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
            // 训练界面 = Apple Music 式全屏 (fullScreenCover 填满整页, 无顶部缝隙/无系统 grabber).
            // 关闭走 PlanPlayerScreen 自带的顶部 Drag Handle 下拉手势 (训练中) / 完成页按钮.
            .fullScreenCover(isPresented: $playerPresented, onDismiss: { session.youtubePlayback.minimize(); openWidgetDestinationIfReady(); openHomeQuickActionIfReady() }) {
                PlanPlayerScreen().marketingCaptureReady("player")
                    // 透明 cover 背景 → 下拉收起时, PlanPlayerScreen 内的淡出黑背板变透明后,
                    // 后面的标签页界面能透出来 (Apple Music 式收起). 平时背板不透明, 视觉等同全屏.
                    .presentationBackground(.clear)
            }
            .sheet(item: $widgetMealToRecord, onDismiss: { openWidgetDestinationIfReady(); openHomeQuickActionIfReady() }) { meal in
                MealEditorSheet(meal: meal, image: nil)
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallScreen()
                .presentationDragIndicator(.visible)
            }
            // 自由训练 — 跳过选肌肉那步, 直接进多选动作 picker (部位/动作/器械三列筛选).
            // 选好若干动作 → Start → 合成 plan 开练.
            .sheet(isPresented: $quickWorkoutPresented) {
                ExercisePickerSheet(
                    onPick: { exercise in
                        quickWorkoutPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            startFreeWorkout([exercise])
                        }
                    },
                    directPick: true,
                    pickerTitle: "Choose your first exercise",
                    onPickConfigured: { exercise, step in
                        quickWorkoutPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            startFreeWorkout([exercise], configuredStep: step)
                        }
                    }
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
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { receiveSharedPlan(url) }
            }
            .onOpenURL { url in
                if url.scheme == "maso", url.host == "widget" { return }
                if handleActivateURL(url) { return }
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
                            guard data.saveImportedPlans([p]) else { paywallPresented = true; return }
                            Haptics.tap()
                            // Imported routines are immediately available on Today.
                            navigationPath = []
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(isPresented: $importFailed) { invalidRoutineLinkAlert }
            // Polar 激活结果 (maso://activate 深链回跳后).
            .alert(isPresented: $activateShown) { activationAlert }
            // Creation uses a local draft; only Save adds it to the library.
            .sheet(item: $newPlanForEdit, onDismiss: {
                isCreatingPlan = false
                // Return to the routines on Today.
                navigationPath = []
            }) { plan in
                PlanDetailSheet(
                    initialPlan: plan,
                    isCreating: isCreatingPlan,
                    onStart: { p in
                        newPlanForEdit = nil
                        DispatchQueue.main.async { startTraining(p) }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // DESIGN 5.3: 替换正在进行的训练 — 二次确认
            .alert(isPresented: replacementAlertBinding) { replacementAlert }
    }

    private var invalidRoutineLinkAlert: Alert {
        Alert(title: Text("Invalid routine link"),
              message: Text("This Masso link is damaged or unsupported. Ask your friend to share again."),
              dismissButton: .default(Text("OK")))
    }

    private var activationAlert: Alert {
        Alert(title: Text("Masso Pro"),
              message: Text(verbatim: activateMessage ?? ""),
              dismissButton: .default(Text("OK")) { activateMessage = nil })
    }

    private var replacementAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingReplacePlan != nil },
            set: { isPresented in if !isPresented { pendingReplacePlan = nil } }
        )
    }

    private var replacementAlert: Alert {
        let plan = pendingReplacePlan
        return Alert(
            title: Text("Another workout is in progress"),
            message: Text("Starting this will replace the workout you're in. Continue?"),
            primaryButton: .destructive(Text("Replace"), action: {
                guard let plan else { return }
                session.endedExplicitly = true
                session.end()
                pendingReplacePlan = nil
                DispatchQueue.main.async { startTrainingNow(plan) }
            }),
            secondaryButton: .cancel(Text("Keep current"), action: { pendingReplacePlan = nil })
        )
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

    /// Only show against the visible home launcher, after the startup flow and any modal.
    private var coachTipHomeAvailable: Bool {
        launchReady && scenePhase == .active && homeContentWidth > 0
            && navigationPath.isEmpty && !welcomePaywallPresented && !paywallPresented
            && !playerPresented && !quickWorkoutPresented && newPlanForEdit == nil
            && importedPlan == nil && widgetMealToRecord == nil && !showingDailyRecord
            && pendingReplacePlan == nil && !importFailed && !activateShown
            && !data.isTailoringPlans && router.pendingWidgetDestination == nil
            && router.pendingWidgetDay == nil && router.pendingHomeQuickAction == nil
    }

    private var nextCoachTip: CoachTip? {
        guard !coachTipShownThisSession else { return nil }
        if CoachIntroTipPolicy.shouldOffer(pending: data.settings.coachIntroTipPending,
                                           onboardingCompleted: data.settings.onboardingCompleted,
                                           homeAvailable: coachTipHomeAvailable, reopened: coachTipSessionReady) {
            return .intro
        }
        guard data.settings.coachIntroTipPending != true, coachTipSessionReady, coachTipHomeAvailable,
              data.settings.coachBodyPhotoTipSeen != true, data.settings.onboardingCompleted else { return nil }
        if CoachIntroTipPolicy.shouldOfferPhoto(seen: data.settings.coachBodyPhotoTipSeen,
            onboardingCompleted: data.settings.onboardingCompleted, homeAvailable: coachTipHomeAvailable,
            reopened: coachTipSessionReady, shownThisSession: coachTipShownThisSession,
            workoutCount: data.recordedWorkoutSessions().count) { return .bodyPhoto }
        return nil
    }

    private func dismissCoachIntroTip() {
        let wasVisible = coachIntroTipVisible
        coachIntroTipVisible = false
        if data.settings.coachIntroTipPending == true && (wasVisible || coachTipSessionReady) {
            data.settings.coachIntroTipPending = false
            data.save()
        }
    }

    private var coachLauncherTooltip: some View {
        VStack(alignment: .trailing, spacing: -1) {
            HStack(alignment: visibleCoachTip == .intro ? .center : .top, spacing: 10) {
                if visibleCoachTip == .intro {
                    Color.clear.frame(width: 28, height: 1).accessibilityHidden(true)
                }
                VStack(alignment: visibleCoachTip == .intro ? .center : .leading, spacing: 8) {
                    Text(LocalizedStringKey(visibleCoachTip == .intro
                         ? "Want to adjust your training plan? Ask AI Coach."
                         : "Share a body photo for training suggestions."))
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(visibleCoachTip == .intro ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: visibleCoachTip == .intro ? .center : .leading)
                        .foregroundStyle(MasoColor.text)
                        .accessibilityIdentifier("home.coachTip.text")
                    if visibleCoachTip == .bodyPhoto {
                        Button("Choose photo") {
                            dismissCoachIntroTip()
                            coachBodyPhotoRequested = true
                            navigationPath.append(.coach)
                        }
                        .nativeGlassButtonStyle().controlSize(.small).tint(MasoColor.accent)
                        .accessibilityIdentifier("home.coachTip.photo")
                    }
                }
                Button(action: dismissCoachIntroTip) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(MasoColor.textDim)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("home.coachTip.close")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .environment(\.layoutDirection, layoutDirection)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MasoColor.borderSoft, lineWidth: 0.7))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MasoColor.surfaceHi)
                .padding(.trailing, 26)
                .accessibilityHidden(true)
        }
        .frame(width: min(300, max(0, homeContentWidth - 64)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.coachTip")
        .onAppear {
            // Consume only once the actual tooltip is on screen, never under onboarding/player.
            coachTipShownThisSession = true
            if visibleCoachTip == .intro { data.settings.coachIntroTipPending = false }
            else { data.settings.coachBodyPhotoTipSeen = true }
            data.save()
        }
    }

    private var coachLauncherButton: some View {
        HomeLauncherButton(symbol: "message", prominent: false) {
            dismissCoachIntroTip()
            Haptics.tap()
            navigationPath.append(.coach)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if height > 0 { homeFooterControlHeight = height }
        }
        .accessibilityLabel("AI Coach")
        .accessibilityIdentifier("home.coach")
        .accessibilityHint("Adjust your routines with your coach")
        .overlay(alignment: .bottomTrailing) {
            if coachIntroTipVisible && coachTipHomeAvailable {
                coachLauncherTooltip
                    .padding(.bottom, homeFooterControlHeight + (visibleCoachTip == .intro ? 4 : 10))
            }
        }
    }

    /// Both the Home launcher and the explicit Widget play link use this action.
    private func startTodayWorkout() {
        guard let plan = data.todayRecommendedPlan else { return }
        Haptics.tap()
        startTraining(plan)
    }

    private var todayWorkoutLauncher: some View {
        HomeLauncherButton(symbol: "play.fill", prominent: true) {
            Analytics.shared.track("home_workout_entry", ["entry": .string("today")])
            startTodayWorkout()
        }
        .accessibilityLabel("Today's Workout")
        .accessibilityIdentifier("home.startTodayWorkout")
        .contextMenu {
            Button("Today's Workout") {
                Analytics.shared.track("home_workout_entry", ["entry": .string("today")])
                startTodayWorkout()
            }.disabled(data.todayRecommendedPlan == nil)
            Button("Start custom workout") {
                Analytics.shared.track("home_workout_entry", ["entry": .string("custom")])
                quickWorkoutPresented = true
            }
            Button("AI Quick Workout") {
                Analytics.shared.track("home_workout_entry", ["entry": .string("ai")])
                dismissCoachIntroTip()
                coachQuickWorkoutRequested = true
                navigationPath.append(.coach)
            }
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
        let now = Date()
        let plan = Plan(id: "plan-\(UUID().uuidString)", name: "", steps: [], createdAt: now, updatedAt: now)
        isCreatingPlan = true
        newPlanForEdit = plan
    }

    /// 是否有进行中的训练 (用于 MiniBar 显隐 + safeArea 调整)
    private var hasActiveSession: Bool {
        guard let s = session.session else { return false }
        return !s.completed && session.currentSegment != nil
    }

    /// Mounted exclusively on Today, never on navigation destinations.
    private var homeBottomControls: some View {
        HStack(spacing: 12) {
            if hasActiveSession {
                miniBarContent
                    .environment(\.layoutDirection, layoutDirection)
                    .frame(maxWidth: .infinity)
            } else {
                todayWorkoutLauncher.fixedSize()
                Spacer(minLength: 0)
            }
            coachLauncherButton.fixedSize()
        }
        // Physical placements; text inside the minibar retains the app's direction.
        .environment(\.layoutDirection, .leftToRight)
        .padding(.leading, hasActiveSession ? MasoMetrics.pagePaddingHorizontal : 32)
        .padding(.trailing, 32)
        .padding(.top, 8)
    }

    /// Training continues on other pages; only Today renders its compact controls.
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
                onTogglePlay: { session.togglePlay() },
                controlHeight: homeFooterControlHeight
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

    /// 统一启动训练入口 — DESIGN 5.3:
    /// 如果已有别的进行中 session, 先弹确认; 用户确认后才替换
    /// 自由训练 — 把多选 picker 选出的动作合成一个 autoGenerated plan 开练.
    /// (镜像旧 QuickWorkoutScreen.synthesizePlan: 默认 category 排序 + 上次负荷回填.)
    private func startFreeWorkout(_ exercises: [Exercise], configuredStep: PlanStep? = nil) {
        guard !exercises.isEmpty else { return }
        let now = Date()
        let sorted = exercises.sorted { l, r in
            if l.category != r.category {
                return l.category == .strength || (l.category == .cardio && r.category == .flexibility)
            }
            return false
        }
        let steps: [PlanStep] = sorted.enumerated().map { (i, ex) in
            return data.makeSeededStep(for: ex, stepId: "qw-step-\(Int(now.timeIntervalSince1970))-\(i)")
        }
        let dateStr = now.formatted(.dateTime.month().day().hour().minute())
        let plan = Plan(
            id: "qw-open-\(UUID().uuidString)",
            name: "\(NSLocalizedString("Free workout", comment: "")) · \(dateStr)",
            steps: configuredStep.map { [$0] } ?? steps,
            createdAt: now,
            updatedAt: now,
            autoGenerated: true
        )
        startTraining(plan)
    }

    private func startTraining(_ plan: Plan) {
        let cur = session.session
        // 同 plan 且未完成 → 只恢复播放器, 不能走 startTrainingNow (TrainingSession.start()
        // 会重建 session, 静默清掉本场已完成的组). "再点开始" 的语义 = 回到进行中的训练.
        if let cur, cur.planId == plan.id, !cur.completed {
            playerPresented = true
            return
        }
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

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            Task { await data.refreshBodyActivityHealth() }
            Task { try? await data.refreshExternalWorkouts() }
            Task { await feedbackStore.tryUploadPending() }
            if data.settings.healthKitSyncEnabled {
                Task { await catchUpHealthKitSync() }
            }
            Task { await data.refreshAIWorkoutIfNeeded() }
            RestNotificationScheduler.shared.cancel()
        } else if newPhase == .background || newPhase == .inactive {
            scheduleRestNotificationIfNeeded()
            data.flushSave()
        }
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
        let plan = data.routinePlanDefaults(plan)
        let segments = expandPlan(
            plan,
            exById: data.exById,
            defaultRest: data.settings.defaultRestSeconds,
            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
        )
        if !plan.steps.isEmpty { data.captureWellnessGoal(plan: plan) }
        session.start(planId: plan.id, plan: plan, segments: segments, source: Self.workoutSource(for: plan))
        playerPresented = true
    }

    /// 训练来源分类 (无 PII) — 按 plan id 前缀 + resolvedSource 推断, 供 workout_start 的 source.
    private static func workoutSource(for plan: Plan) -> String {
        if plan.id.hasPrefix("qw-") { return "free" }
        if plan.id.hasPrefix("session-replay-") { return "replay" }
        // TodayScreen.startGapWorkout 生成的 id 前缀是 "plan-catchup-" (非 "plan-gap-"),
        // 判错前缀会让 catch-up 训练的 analytics source 永远报不出 gap.
        if plan.id.hasPrefix("plan-catchup-") { return "gap" }
        switch plan.resolvedSource {
        case .ai: return "ai"
        case .classics: return "classic"
        case .builtIn: return "builtin"   // 本地规则兜底 (AI 够不到时) — analytics 要分得开
        case .custom: return "recommended"
        }
    }
}

// 条件 NavigationStack — embedded 时直接给 content (由外层 Train NavStack 接管), 否则自带一层.
struct NavStackIf<Content: View>: View {
    let embedded: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        if embedded { content() } else { AppNavigationStack { content() } }
    }
}




/// Identical native sizing for both home launchers; only the glass style and tint differ.
private struct HomeLauncherButton: View {
    let symbol: String
    let prominent: Bool
    let action: () -> Void
    @ViewBuilder var body: some View {
        let button = Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .medium))
                .frame(width: 32, height: 32)
        }.controlSize(.large).buttonBorderShape(.circle)
        if prominent { button.nativeGlassProminentButtonStyle().tint(MasoColor.accent) }
        else { button.nativeGlassButtonStyle().tint(MasoColor.text) }
    }
}
