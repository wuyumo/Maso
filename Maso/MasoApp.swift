import SwiftUI

// Maso — 简单的健身记录 (iOS native port)
//
// 视觉语言:
//   - 深色优先, Spotify 风格
//   - 单一强调色 #1ED760 (绿)
//   - 大字号, 高对比, 单手可达
//   - 训练时优先, 营销第二
//
// 架构:
//   - SwiftUI + Observation (iOS 17+)
//   - SplashScreen → RootView, 中间用 .transition(.opacity) 平滑过渡
//   - 单根 RootView 持有 TabBarView, 切换 3 个主屏 (Plans / Today / History)
//   - TrainingSessionStore 是全局 ObservableObject, 训练状态独立于路由
//   - 数据层暂时用 in-memory mock (DataStore), 后续可接 SwiftData
@main
struct MasoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = TrainingSessionStore()
    // bootstrap() 优先从 PersistenceController (Documents/maso-data.json) 加载持久化数据.
    // 没有 → 走 mock 兜底 (seed 推荐 plan + sample sets). 同时把 mock 写一次文件, 下次有持久化.
    // 改自 .makeMock(): 之前每次启动都重置数据, 现在用户的 plans / sets / settings 都保留.
    // MASO_SHOWCASE_SEED=1 (仅截图流水线注入的 env) → 用 makeMock 演示数据 (跳过引导, 带计划+历史).
    // 生产无此 env, 永远走 bootstrap. 不持久化 mock (不调 save), 不污染真实数据文件.
    @State private var dataStore = ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] == "1"
        ? DataStore.makeMock()
        : DataStore.bootstrap()
    /// StoreKit 2 订阅管理器 — load products / listen transactions / 回写 DataStore entitlement.
    /// 在 .task 里 configure(), 注入 callback 让它把 entitlement 变化同步到 dataStore.settings.
    @State private var subscriptions = SubscriptionManager()
    @State private var splashDone = false
    /// 启动时 init 一次, 让它从 UserDefaults 读上次选的语言, 立刻 apply 到 Bundle.
    /// observe 这个 manager 保证语言切换时 SwiftUI 整树 re-render.
    @State private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                if splashDone {
                    RootView()
                        .environment(session)
                        .environment(dataStore)
                        .environment(subscriptions)
                        .transition(.opacity)
                } else {
                    SplashScreen { withAnimation(.easeOut(duration: 0.3)) { splashDone = true } }
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            // 全局 tint 改成白色 — 让 alert Cancel / contextMenu icon / NavigationLink chevron 等
            // system 默认走 control 颜色都白. accent 绿留给 explicit 强调位 (Pro banner / 选中 chip /
            // primary 按钮), 避免到处都是绿. iOS dark theme 下白色作 default control 颜色更自然.
            .tint(MasoColor.text)
            // 跟 effectiveLanguage 绑定的 id —— 语言变了 → ZStack 整体重建 → 所有 Text 重读
            .id(languageManager.effectiveLanguage.rawValue)
            // App 进后台 → 强制持久化一次, 防止用户改了 settings 没 save 就被系统挂起.
            // (Settings 里 toggle 不直接调 dataStore.save(), 走默认 SwiftUI @Bindable mutate.)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    dataStore.save()
                    // 进后台时以"最近一次训练"为基重排召回提醒 (开关关时只清除).
                    dataStore.rescheduleWorkoutReminders()
                    // 分析: app_background + flush 缓冲. 这是 scenePhase 的**唯一**根级站点 —
                    // RootView 也有个 scenePhase handler 但只做 feedback/HK/AI, 不报生命周期事件 (防双发).
                    Analytics.shared.handleBackground()
                }
                // 回前台 → 刷一次 entitlements (用户可能在 Settings.app 改了订阅状态)
                if newPhase == .active {
                    Task { await subscriptions.refreshEntitlements() }
                    Analytics.shared.handleForeground()
                }
            }
            // configure SubscriptionManager — 注入 callback 让 StoreKit entitlement 变化时
            // 自动写到 dataStore.settings.proSubscription. .task 保证只跑一次.
            .task {
                // 产品分析 boot — Phase 0: NoOpSink (事件只缓冲本地, 不离开设备).
                // 注入门控/信封上下文 (读 settings 的 anon_id + opt-out); 先确保 anon_id 已铸.
                dataStore.mintAnonymousIdIfNeeded()
                Analytics.shared.configure(
                    sink: NoOpSink(),
                    context: { [weak dataStore] in
                        Analytics.Context(
                            anonymousId: dataStore?.settings.anonymousId ?? "",
                            optOut: dataStore?.settings.analyticsOptOut ?? false
                        )
                    }
                )
                // app_launch — is_fresh_install / onboarding_completed / days_since_install (无 PII).
                let isFresh = dataStore.sets.isEmpty && dataStore.plans.isEmpty
                    && !dataStore.settings.onboardingCompleted
                let daysSinceInstall: Int = {
                    guard let earliest = dataStore.sets.map(\.performedAt).min() else { return 0 }
                    return max(0, Int(Date().timeIntervalSince(earliest) / 86400))
                }()
                Analytics.shared.track("app_launch", [
                    "is_fresh_install": .bool(isFresh),
                    "onboarding_completed": .bool(dataStore.settings.onboardingCompleted),
                    "days_since_install": .int(daysSinceInstall),
                ])

                subscriptions.configure { newSub in
                    // 只在变化时写 + save, 避免每次 currentEntitlements 触发都 mark dirty.
                    if dataStore.settings.proSubscription != newSub {
                        dataStore.settings.proSubscription = newSub
                        dataStore.save()
                    }
                }
                // 冷启动恢复进行中的训练 — iOS 杀后台 (训练 60-90 分钟很常见) 后, 把
                // active-session.json 里的 session 接回来; 已完成 / 闲置 6h+ 的静默丢弃.
                // 必须在 pushWatchState() 之前 — 恢复出的训练帧要推给手表, 而不是 idle 帧.
                session.restorePersistedSession(
                    exById: dataStore.exById,
                    defaultRest: dataStore.settings.defaultRestSeconds,
                    defaultBetweenExerciseRest: dataStore.settings.defaultBetweenExerciseRestSeconds
                )
                // Apple Watch 镜像 — 激活 WCSession + 接线手表动作:
                // ✓/Skip → advance (跟手机主按钮同语义, 含 SetRecord 落库); 暂停 → togglePlay.
                WatchSyncManager.shared.activate()
                WatchSyncManager.shared.onAdvance = {
                    session.advance { rec in dataStore.recordSet(rec) }
                }
                WatchSyncManager.shared.onTogglePlay = {
                    session.togglePlay()
                }
                // 启动即推一帧 (idle / 恢复的 session) — 防手表停留在上次训练的旧状态.
                session.pushWatchState()
            }
        }
    }
}
