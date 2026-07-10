import HealthKit
import SwiftUI

// Tab 顺序 = today / coach / history (4→3, docs/coach-tab-design.md §0):
//   Today = 今天练什么 + 开练; Coach = 对话式生成与管理 routines (原 Plans tab 整体退役 + Exercises
//   tab 并入 Coach 导航栏 dumbbell); history tag 名保留 (analytics / showcase 路由按它写死), label 显示 "Progress".
enum RootTab: Hashable { case today, coach, history }

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
//   - 已完成: 系统 TabView + 3 个屏 (Today / Coach / Progress), 加 PlanPlayer fullScreenCover
struct RootView: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: RootTab = .today
    /// RootTab → 分析事件 tab 名 (无 PII, 纯枚举名). tab_switch 的 coach 映射在这 (设计文档 §4).
    private static func tabName(_ t: RootTab) -> String {
        switch t {
        case .today: return "today"
        case .coach: return "coach"
        case .history: return "history"
        }
    }
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
    @State private var settingsPresented: Bool = false
    /// showcase "exercises"/"library" 路由 → 翻 true, CoachScreen 监听后拉起动作库 sheet
    /// (Exercises 不再是 tab — 库入口在 Coach 导航栏 dumbbell, 路由名保持不变让夜间 driver 不断).
    @State private var coachLibraryRequested = false
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
            // 路由名保持不变 (夜间 verify-app driver 的 ROUTES 依赖) — Exercises 已并入 Coach:
            // 落 Coach tab + 拉起动作库 sheet. 延迟到 CoachScreen 挂载后再翻, onChange 才收得到;
            // sheet 全屏盖住 Coach → 截图跟 "routines"/today 保持 distinct.
            tab = .coach
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { coachLibraryRequested = true }
        case "routines":
            tab = .coach          // 原 Routines tab 能力已整体迁入 Coach
        case "coach_templates", "coach_prefs", "coach_chat":
            // 顶栏走查用: 只负责落 Coach tab, sheet/种子对话由 CoachScreen 自己读 env 拉起
            // (templatesPresented/prefsPresented 是 CoachScreen 私有 state, 不走 binding 减少管线).
            tab = .coach
        case "classics":
            // Today 的 Classics (CommunityScreen) — sheet 由 TodayScreen 读 env 拉起.
            tab = .today
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
            // ⚠️ inset 必须挂在 NavigationStack **里面** (screen 视图上): 挂外面时 NavigationStack
            // 不把缩小的 safe area 传给内部固定钉底的内容 — 三个旧 tab 全是 ScrollView 看不出来,
            // Coach 的 composer 是第一个钉底实体控件, 训练中 MiniBar 直接盖住它 (owner 实机报障)。
            TabView(selection: $tab) {
                // 三个 tab 都包 NavigationStack — 走 iOS 默认 navigationTitle + toolbar 样式.
                // .tint(MasoColor.text) 覆盖系统默认 (Asset AccentColor 是绿) — toolbar 右上角按钮
                // 走白色, 跟 dark theme 配色一致 (不再绿).
                // Today — 今日总览: 肌肉状态 + 今日训练轮播 (落地页, .today tag; 自由训练在导航栏右上角).
                NavigationStack {
                    TodayScreen(
                        onStart: startTraining,
                        onFreeWorkout: { quickWorkoutPresented = true },
                        onNewPlan: handleNewPlan,
                        onOpenSettings: { settingsPresented = true },
                        embedded: true,
                        mode: .trainToday   // Today = 肌肉状态 + 今日训练轮播 (#today-carousel); 自由训练 = 轮播尾部空卡.
                    )
                    .screenHeader("Today") {
                        // 自由训练入口 = 轮播尾部空卡 (owner 拍板回退导航栏 dumbbell), 这里只留齿轮.
                        Button(action: { settingsPresented = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .accessibilityLabel("Settings")
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                }
                .tint(MasoColor.text)
                .tabItem {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(RootTab.today)

                // Coach — 对话式生成与管理 routines (docs/coach-tab-design.md §1 三段式).
                // 原 Plans tab 能力全部迁入 (SAVED 货架 + All sheet); Exercises 从导航栏 dumbbell 一步拉起.
                // 注入跟原 Plans tab 同构: onStart → player fullScreenCover 管线 / onNewPlan → handleNewPlan
                // (paywall gating + 共享 sheet 容器) / onOpenSettings → settings sheet.
                NavigationStack {
                    CoachScreen(
                        onStart: startTraining,
                        onNewPlan: handleNewPlan,
                        onOpenSettings: { settingsPresented = true },
                        libraryRequested: $coachLibraryRequested
                    )
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                }
                .tint(MasoColor.text)
                .tabItem {
                    // 单气泡 message = "跟教练聊" 最素的表达 (双气泡版 owner 嫌丑;
                    // ✨ 留给 AI badge / 生成按钮, tab 表达的是"对话"这个动作本身).
                    Label("Coach", systemImage: "message")
                }
                .tag(RootTab.coach)

                NavigationStack {
                    HistoryScreen(
                        onReplay: startTraining,
                        onOpenSettings: { settingsPresented = true }
                    )
                    .safeAreaInset(edge: .bottom, spacing: 0) { miniBarContent }
                }
                .tint(MasoColor.text)
                .tabItem {
                    // Tab 标签重命名 → "Progress" (进度): 这个 tab 现在既装分析(Insights)又装
                    // 记录(History), "History" 只描述了一半. 复用已有的 "Progress"="进度" key.
                    // icon = chart.bar (空心柱, 留白多 → 视觉体量最轻, 跟 dumbbell 的通透感一致;
                    // chart.bar.fill 四根实心高柱填满整格显重, chart.line.uptrend.xyaxis 又太细碎).
                    // 只改 LABEL — RootTab.history / case "history" 路由 / 类型名保持不动 (analytics tag 也走 RootTab, 无需改).
                    Label("Progress", systemImage: "chart.bar")
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
                // 在 MiniBar 上完成最后一组: completed=true → hasActiveSession=false → bar 消失,
                // 完成页/保存确认/分享全被跳过. 这里补拉起播放器让完成流照常走.
                // guard !playerPresented — 播放器已打开时完成流由它自己接管, 不重复触发 cover.
                if completed && !playerPresented {
                    playerPresented = true
                }
            }
            // 跨 sheet tab 切换请求 — e.g. Progress AI 小结 Apply → 切到 Coach (深链消息由 CoachScreen 消费).
            // 3-tab 后不再需要旧的 .library → .plans+trainPage 映射, 直取即可.
            .onChange(of: router.requestedTab) { _, newTab in
                if let newTab {
                    tab = newTab
                    settingsPresented = false
                    router.requestedTab = nil
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
                            // 落到 Coach — SAVED 货架常驻钉顶, 新加的 plan 一眼可见.
                            tab = .coach
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
                // 新建的 plan 出现在 Coach 的 SAVED 货架 — 切过去让用户看到.
                tab = .coach
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
        // TodayScreen.startGapWorkout 生成的 id 前缀是 "plan-catchup-" (非 "plan-gap-"),
        // 判错前缀会让 catch-up 训练的 analytics source 永远报不出 gap.
        if plan.id.hasPrefix("plan-catchup-") { return "gap" }
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


