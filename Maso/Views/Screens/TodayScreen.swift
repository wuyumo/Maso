import SwiftUI

/// Distinct from other plan pushes so each screen owns its own navigation destination.
private struct TodayWorkoutDetail: Hashable {
    let plan: Plan
}

struct TodayScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var training
    let onStart: (Plan) -> Void
    /// 拉起"自由训练" flow — Today 导航栏右上角 dumbbell 按钮触发 (RootView 的 toolbar;
    /// 非 embedded 时本 view 自己的 screenHeader 也挂同款), 走 QuickWorkout sheet 选动作开练.
    let onFreeWorkout: () -> Void
    /// 新建训练计划 — 原 Plans 页右上角 "+", 现移到 Today 的"我的训练"section. RootView 持有 sheet.
    let onNewPlan: () -> Void
    /// 标题行右上角齿轮 → 弹 Settings sheet (RootView 持有 sheet state)
    let onOpenSettings: () -> Void
    /// My Muscle Status is a regular pushed page in the app navigation stack.
    var onOpenMuscleStatus: (_ gapMuscles: [MuscleGroup], _ startGapWorkout: @escaping () -> Void) -> Void = { _, _ in }
    /// Classic Routines 是独立导航页, 从右侧 push 进入.
    /// Push the AI Coach when the user asks for a routine from the empty state or add menu.
    var onOpenCoach: () -> Void = {}
    /// Pro feature ②: My Routines 顶部优化建议卡点 "Optimize with AI" → 把诊断 focusNote 上抛给
    /// PlansScreen, 由它带 focusNote 重生成 routine (Pro gating 也在 PlansScreen 那侧). 其他用法不传.
    var onOptimize: (DataStore.RoutineSuggestion) -> Void = { _ in }
    /// 嵌在外层 AppNavigationStack (Train / Plans tab) 里时 true — 不渲染自己的大标题/齿轮.
    var embedded: Bool = false
    /// 渲染哪部分内容:
    ///   - .trainToday: 肌肉状态 + 今日训练轮播 (Today tab; 自由训练在导航栏右上角)
    ///   - .myPlans:    旧 Plans 容器复用的训练列表内容
    ///   - .full:       全部 (兼容老用法)
    enum Mode { case full, trainToday, myPlans }
    var mode: Mode = .full
    /// Routines 单页 (#single-page-IA): true = 不自带 ScrollView / 背景 / 页边距 —
    /// 外层 PlansScreen 的滚动页接管 (本 view 只出内容 VStack, sheets/alerts 照常挂在上面).
    /// Today tab (RootView) 不传, 默认 false 走自己的 ScrollView.
    var embeddedInScroll: Bool = false
    /// The home screen appends workout records directly below routines.
    var showsHistory: Bool = false
    var showMuscleIntro: Bool = false
    var homeMotionEnabled: Bool = true
    /// Routines tab (#IA-A): "+ new routine" 菜单在导航栏 (PlansScreen). 点 "Import from photo" 翻这个 →
    /// 这里开图片选择器. 其他用法 (Today tab) 不传, 默认 .constant(false) 不触发.
    var triggerImport: Binding<Bool> = .constant(false)

    /// 卡片 tap → 从右侧推入训练详情, 查看动作 + 每组 sets/reps/weight.
    @Environment(\.scenePhase) private var scenePhase
    @State private var headingDate = Date()
    @State private var homeTopInset: CGFloat = 0
    @State private var homeTitleHeight: CGFloat = 0
    @State private var homeTitleCollapsed = false
    @State private var detailPlan: TodayWorkoutDetail? = nil
    /// 删 plan 的二次确认 (从原 Plans 页迁来).
    @State private var pendingDeletePlanId: String? = nil
    /// 图片导入 routine (#image-import): 选图 → QR/OCR 解析 → ImportedPlanSheet 确认.
    @State private var importPickerShown = false
    @State private var importPickedImage: UIImage? = nil
    @State private var importParsing = false
    @State private var importedRoutine: Plan? = nil
    /// 批量分享卡 QR (≥2 个计划) → 多计划导入确认页 (#routines-batch-share).
    @State private var importedRoutines: ImportedPlansPayload? = nil
    /// OCR 第三方截图 → 置信度分级候选, 驱动 RoutineReviewSheet (QR 深链仍走 importedRoutine).
    @State private var importReview: RoutineReviewPayload? = nil
    @State private var importFailed = false
    /// Muscle Status 卡"解锁逐肌群恢复" → 付费墙 (非 Pro). 跟 HistoryScreen 的 paywall 同款.
    @State private var paywallPresented = false
    @State private var aiUpgradePrompt = UpgradePrompt()
    /// 首页 History / Insights 切换及经典训练入口。
    /// Coach 撤掉 SAVED 货架后, 这里是管理面在 Today 侧的一步可达入口.
    /// 轮播卡等高 (#today-carousel): PreferenceKey 量测每张卡自然高取 max 回写.
    /// 非 nil 后所有卡 (含尾部"自由训练"空卡) 统一到该高度; plans 变化时重置重量.
    @State private var carouselCardHeight: CGFloat? = nil
    /// showcase 截图验证专用 — env 让轮播初始停在尾部 (看尾卡). 真实用户永远 false.
    private static let showcaseCarouselEnd =
        ProcessInfo.processInfo.environment["MASO_SHOWCASE_CAROUSEL"] == "end"

    private var suggested: Plan? {
        // 逻辑在 DataStore.suggestedTodayPlan (跟 RootView 中键 quickStart 共用, 必须同一优先级):
        // 用户自己的 plans 优先 (LRU); 但全部还是引导种子模板且真 AI 已生成时优先 AI (✨AI).
        data.suggestedTodayPlan
    }

    /// Stored order is the presentation order. Only the scroll position advances.
    private var carouselPlans: [Plan] { data.plans }
    private var rotation: WorkoutRotation { data.workoutRotation }
    @State private var carouselPosition: String?

    /// 时段问候 — DESIGN.md §4.2: 0-5 凌晨 / 5-12 早上 / 12-18 下午 / 18-24 晚上.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return NSLocalizedString("Good morning", comment: "")
        case 12..<18: return NSLocalizedString("Good afternoon", comment: "")
        case 18..<24: return NSLocalizedString("Good evening", comment: "")
        default:      return NSLocalizedString("Good night", comment: "")
        }
    }

    /// Action first, followed by the recorded context. An unfinished workout takes priority.
    private var todayHeading: (title: String, subtitle: String) {
        if let session = training.session, !session.completed {
            return (NSLocalizedString("Keep going", comment: "home action"),
                    NSLocalizedString("Your workout is in progress.", comment: "home context"))
        }
        #if DEBUG
        let contextDate = ProcessInfo.processInfo.environment["MASO_MARKETING_MORNING"] == "1"
            ? (Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: headingDate) ?? headingDate)
            : headingDate
        #else
        let contextDate = headingDate
        #endif
        if let context = DailyReminderContext.heading(settings: data.settings, now: contextDate) {
            return context
        }
        guard let last = data.sets.first?.performedAt else {
            return (NSLocalizedString("Start your first workout", comment: "home action"),
                    NSLocalizedString("Your training journey starts here.", comment: "home context"))
        }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: headingDate)).day ?? 0
        switch days {
        case ...0:
            return (NSLocalizedString("Rest up", comment: "home action"),
                    NSLocalizedString("You’ve trained today.", comment: "home context"))
        case 1:
            return (NSLocalizedString("Plan your next session", comment: "home action"),
                    NSLocalizedString("You last trained yesterday.", comment: "home context"))
        default:
            let title = days < 7 ? NSLocalizedString("Make time to train", comment: "home action")
                                : NSLocalizedString("Ease back in", comment: "home action")
            let subtitle = String(format: NSLocalizedString("It’s been %lld days since your last workout.", comment: "home context"), days)
            return (title, subtitle)
        }
    }

    private var todayTipLine: String {
        showMuscleIntro ? NSLocalizedString("The muscle map shows which areas you have trained.", comment: "first home muscle map introduction") : todayHeading.subtitle
    }

    private var overlapsMuscleHero: Bool {
        showsHistory && !embeddedInScroll && mode != .myPlans
            && !data.settings.showProUpsell && !data.aiTodayFailed
    }

    /// Share the overlap calculation so moving the overview preserves the legend gap.
    private var homeContentOverlap: CGFloat {
        (overlapsMuscleHero ? (16 + 44 + 10 + 32) : 0) + MasoMetrics.homePostHeroLift
    }

    // MARK: - 我的训练 section (从 Plans 页迁来)
    private static let recommendedPrefixes = ["plan-full", "plan-bal", "plan-push", "plan-pull", "plan-legs"]
    /// 用户 plans 里已经没有任何系统推荐 plan → 显示 Restore 按钮.
    private var hasNoRecommendedPlans: Bool {
        !data.plans.contains { plan in
            Self.recommendedPrefixes.contains { plan.id.hasPrefix($0) }
        }
    }
    private func restoreRecommendedPlans() {
        data.regenerateRecommendedPlans()
        Haptics.tap()
    }

    var body: some View {
        // ScrollView + VStack — 复杂 hero 卡 (WorkoutCard 里有自定义 Layout) 在 List row 的
        // nil-width sizing pass 下会塌. ScrollView 给的是确定宽度, 渲染稳. 计划行的删/改改走长按
        // contextMenu (代替 List 的右滑); 排序暂不提供 (原 Plans 页的拖拽随 List 一起去掉了).
        // embeddedInScroll (Routines 单页嵌入) 时不自带 ScrollView/背景 — 外层滚动页接管,
        // sheets / alerts / import flow 仍挂本 view (修饰链原样生效).
        ScrollViewReader { _ in
        ScrollIf(scroll: !embeddedInScroll) {
            VStack(alignment: .leading, spacing: 16) {
                if showsHistory && !embeddedInScroll && mode != .myPlans {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(todayHeading.title)
                            .font(.largeTitle.bold())
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(todayTipLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { homeTitleHeight = $0 }
                    .zIndex(2)
                    MuscleWalkthroughHeader(
                        topExtension: homeTopInset + homeTitleHeight + 16,
                        height: 432,
                        // Match the gap to the shared card padding (20pt).
                        footerClearance: overlapsMuscleHero
                            ? homeContentOverlap - 16 - MasoMetrics.homeOverviewTopInset + MasoMetrics.cardPadding
                            : 48,
                        fatigueMap: fatigueMap,
                        gapMuscles: gapMuscles,
                        motionEnabled: homeMotionEnabled && !paywallPresented && detailPlan == nil,
                        onStartGapWorkout: startGapWorkout,
                        onUnlock: { paywallPresented = true },
                        onOpenStatus: { onOpenMuscleStatus($0, $1) }
                    )
                }
                // ===== Today tab 内容: 肌肉状态 + 今日推荐 + 自由训练 (mode != .myPlans) =====
                if mode != .myPlans {
                    // Shared marketing banner; paid and valid legacy users are excluded.
                    if data.settings.showProUpsell {
                        ProBanner { paywallPresented = true }
                    }

                    // ── 训练状态 ── (MuscleStatusOverviewCard 自带图例/提示/Train the gaps).
                    // 零训练数据时整块隐藏 (owner 拍板): 空态的灰肌肉图+引导句反而奇怪,
                    // 练过第一次 (sets 非空) 这块才出现. ROUTINES 轮播顶上来作首屏内容.
                    if !data.sets.isEmpty {
                        if !showsHistory || embeddedInScroll {
                        MuscleStatusOverviewCard(
                            fatigueMap: fatigueMap,
                            gapMuscles: gapMuscles,
                            onStartGapWorkout: startGapWorkout,
                            tipLine: todayTipLine,
                            onUnlock: { paywallPresented = true },
                            onOpenStatus: { onOpenMuscleStatus($0, $1) }
                        )
                        }
                    }

                    // AI 生成失败 → 提示条 (已回落到本地推荐, 一键重试真 AI).
                    if data.aiTodayFailed {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark").font(.system(size: 12, weight: .bold))
                            Text("AI plan unavailable — showing your recommended plan.")
                                .font(.system(size: 12, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button {
                                Haptics.tap()
                                aiUpgradePrompt.requestAI(isPro: data.settings.isPro, source: "today_ai_retry") {
                                    Task { await data.forceRefreshAIWorkout() }
                                }
                            } label: {
                                // 失败条 Retry → 次级玻璃胶囊 (映射表②); 旧系统保留原裸文字 (无底无内边距).
                                Text("Retry").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(systemGlassAvailable ? MasoColor.accent : MasoColor.textDim)
                                    .padding(.horizontal, systemGlassAvailable ? 12 : 0)
                                    .padding(.vertical, systemGlassAvailable ? 6 : 0)
                                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25))
                            }
                        }
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(MasoColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // ── 今日训练轮播 ── (#today-carousel): 全部已存 routine 横滑成卡组,
                    // 首卡 = 今日 (卡内自带 "TODAY'S WORKOUT" kicker), 右缘 peek 暗示可滑.
                    VStack(alignment: .leading, spacing: 16) {
                        if showsHistory {
                            DailyOverviewCard(onReplay: onStart)
                                .padding(.top, MasoMetrics.homeOverviewTopInset)
                        }
                        workoutCarousel
                    }
                    .padding(.top, -homeContentOverlap)
                    .zIndex(1)
                }

                if showsHistory && mode == .myPlans {
                    DailyOverviewCard(onReplay: onStart)
                }

                // ===== Plans tab 的 My Plans 分页: 我的训练 + 自由训练 + 社区 (mode != .trainToday) =====
                if mode != .trainToday {
                    // Pro feature ②: 数据驱动优化建议卡 — 练够数据 + 诊断出问题 + 有 routine 可优化时浮在最顶.
                    if !data.plans.isEmpty, let suggestion = data.routineSuggestion() {
                        RoutineOptimizeCard(suggestion: suggestion, onOptimize: onOptimize)
                    }
                    // 今日训练若是当日 AI 生成 (不在已存 plans 里) 也要在"全部"露面 —
                    // owner 反馈 bug: Today 主卡在全部列表里找不到. 带 TODAY'S WORKOUT kicker 置顶.
                    if let today = data.suggestedTodayPlan,
                       !data.plans.contains(where: { $0.id == today.id }) {
                        WorkoutCard(
                            plan: today,
                            exById: data.exById,
                            kicker: "TODAY'S WORKOUT",
                            onStart: { onStart(today) },
                            onShowDetail: { detailPlan = TodayWorkoutDetail(plan: today) },
                            prominentStart: false,
                            showStart: false,
                            compactLayout: true
                        )
                        .contextMenu {
                            Button { detailPlan = TodayWorkoutDetail(plan: today) } label: { Label("Edit", systemImage: "pencil") }
                            // deletePlan 对 aiTodayPlan 有特判 (清空 + 抑制当天重生成).
                            Button(role: .destructive) { pendingDeletePlanId = today.id } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    if data.plans.isEmpty {
                        // 无已存 routine: 一行浅提示, 不做大空态 — Routines 单页下方紧跟着
                        // FOR YOU 生成区 + Classics 入口, 引导按钮反而多余 (#single-page-IA).
                        Text("Routines you save will appear here")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textFaint)
                            .padding(.vertical, 6)
                    } else {
                        // "+ new routine" 入口已上移到 Routines tab 导航栏 (PlansScreen 的 toolbar "+") —
                        // 这里只渲染已存 routine 列表. 计划卡用 WorkoutCard (跟 Today's Workout 同详细程度).
                        ForEach(data.plans) { plan in
                            WorkoutCard(
                                plan: plan,
                                exById: data.exById,
                                kicker: "",
                                onStart: { onStart(plan) },
                                onShowDetail: { detailPlan = TodayWorkoutDetail(plan: plan) },
                                prominentStart: false,  // 计划卡的开始键弱化 (半透明绿底)
                                showStart: false,       // Routines/Saved: 不显示 play 钮, 点卡片进详情 Start
                                compactLayout: true     // 列表卡用紧凑横排 (标题/计数/[图|chips])
                            )
                            // 长按菜单代替 List 右滑 — 改/删.
                            .contextMenu {
                                Button { detailPlan = TodayWorkoutDetail(plan: plan) } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { pendingDeletePlanId = plan.id } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // AI / Classics 入口不在这里 — Routines 单页 (PlansScreen) 本身就有
                // FOR YOU 生成区 + Classics 入口卡, 这里再放 = 重复堆入口 (#single-page-IA).

                // 底部留白 — Routines 单页嵌入时由外层滚动页统一给, 这里不重复.
                if !embeddedInScroll {
                    Spacer(minLength: showsHistory ? 0 : MasoMetrics.pageBottomInset)
                }
            }
            // 页边距 — 嵌入模式下外层已给 pagePaddingHorizontal, 置 0 防双重缩进.
            .padding(.horizontal, embeddedInScroll ? 0 : MasoMetrics.pagePaddingHorizontal)
        }
        }
        .onAppear { headingDate = Date() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { headingDate = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { headingDate = Date() }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentInsets.top)
        } action: { _, inset in
            homeTopInset = inset
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > homeTitleHeight
        } action: { _, collapsed in homeTitleCollapsed = collapsed }
        .applyIf(showsHistory && !embeddedInScroll && mode != .myPlans) { view in
            view
                .navigationTitle(todayHeading.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarRole(.navigationStack)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(todayHeading.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(homeTitleCollapsed ? 1 : 0)
                            .accessibilityHidden(!homeTitleCollapsed)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: onOpenSettings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("home.settings")
                    }
                }
        }
        // 自定义页头: greeting kicker + "Today" 大标题 + 齿轮. embedded (Today / Plans tab) 时跳过 —
        // 由外层 NavigationStack 的 screenHeader / segmented 接管.
        .applyIf(!embedded) {
            $0.screenHeader("Today", kicker: greeting) {
                // 自由训练入口 = 轮播尾部空卡 (owner 拍板回退导航栏 dumbbell), 这里只留齿轮.
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                }
                .accessibilityLabel("Settings")
            }
        }
        .navigationDestination(item: $detailPlan) { route in
            PlanDetailSheet(
                initialPlan: route.plan,
                onStart: { p in
                    detailPlan = nil
                    DispatchQueue.main.async { onStart(p) }
                },
                usesParentNavigation: true
            )
        }
        // Classic Routines 通过外层 NavigationStack 从右侧 push, 不再以 sheet 呈现.
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen(source: "today_pro_feature")
            .presentationDragIndicator(.visible)
        }
        .aiUpgradeReminder(aiUpgradePrompt)
        // ── 图片导入 routine (#image-import) — 流程收进 ViewModifier, 避免 body 类型检查超时.
        .modifier(RoutineImportFlow(
            pickerShown: $importPickerShown,
            pickedImage: $importPickedImage,
            parsing: $importParsing,
            imported: $importedRoutine,
            importedMany: $importedRoutines,
            review: $importReview,
            failed: $importFailed,
            data: data
        ))
        // Routines tab 导航栏 "+" → "Import from photo" 翻 triggerImport → 这里开图片选择器 (#IA-A).
        .onChange(of: triggerImport.wrappedValue) { _, on in
            if on { importPickerShown = true; triggerImport.wrappedValue = false }
        }
        .alert("Delete plan?", isPresented: Binding(
            get: { pendingDeletePlanId != nil },
            set: { if !$0 { pendingDeletePlanId = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeletePlanId { data.deletePlan(id) }
                pendingDeletePlanId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletePlanId = nil }
        } message: {
            Text("Your training history will be kept.")
        }
    }

    // MARK: - 我的训练 section 组件

    /// "AI PLANS" 小标题 + 右侧 (restore 可选) + 新建 "+". refresh / add 同款圆圈样式 + 同尺寸,
    /// 彼此间距拉远; 整行左右留边距 (标题 + 按钮往中间靠, 不贴边).
    private var myPlansHeader: some View {
        HStack(spacing: 14) {
            // "MY ROUTINES" 文字已去 — Plans tab 导航段 (My Routines | AI | Classics) 已标这一节.
            // 只留右上角 "+" 菜单 (自建 / 从照片导入).
            Spacer()
            // "+" 菜单: 自建 / 从照片导入 (#image-import — 支持别人的分享卡 QR 或其他 app 截图 OCR).
            Menu {
                Button(action: onNewPlan) { Label("New workout", systemImage: "square.and.pencil") }
                Button { importPickerShown = true } label: { Label("Import from photo", systemImage: "photo") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(MasoColor.text.opacity(0.12)))
                    .overlay(Circle().stroke(MasoColor.text.opacity(0.4), lineWidth: 0.5))
            }
            .accessibilityLabel(NSLocalizedString("Add routine", comment: ""))
        }
        .padding(.horizontal, 12)   // 标题 + 按钮整体往中间靠, 左右留边距
    }

    /// AI Plans 头部圆圈图标按钮 — refresh / add 共用同款 (白图标 14pt + 微填充圆 30×30 + 0.5pt 细描边).
    private func headerCircleButton(_ icon: String, action: @escaping () -> Void, a11y: String) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(MasoColor.text.opacity(0.12)))
                .overlay(Circle().stroke(MasoColor.text.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(a11y, comment: ""))
    }

    // MARK: - 今日训练轮播 (#today-carousel)

    /// 横滑卡片轮播: viewAligned 分页吸附 + 右缘 peek (~60pt) 暗示可滑; 不加 page dots (极简取向).
    /// 卡片等高: 每张卡 GeometryReader 上报自然高, PreferenceKey reduce 取 max → 回写
    /// WorkoutCard.fixedHeight (卡内在底部行前垫 Spacer, 播放键仍钉右下). 标记只给前两张:
    /// 首卡 TODAY'S WORKOUT / 次卡 UP NEXT, 第三张起 kicker 留空 (顺序本身已表达).
    private var workoutCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {   // 标题行与卡片间距 ≥10pt (owner 指定)
            // 区块标题行 — 左 "ROUTINES" 标题 (13pt, owner 反馈 10pt kicker 太小) +
            // Create / free-train / photo import; Classic Routines lives with History and Insights below.
            HStack(alignment: .center) {
                Text("Workouts")
                    .trainingSectionTitle()
                Spacer()
                Menu {
                    if data.plans.isEmpty {
                        Button(action: onOpenCoach) {
                            Label("Generate routine with AI", systemImage: "message")
                        }
                    }
                    Button { Haptics.tap(); onNewPlan() } label: {
                        Label("Create a routine", systemImage: "plus")
                    }
                    .accessibilityIdentifier("home.createRoutine")
                    Button { importPickerShown = true } label: {
                        Label("Import from photo", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Add routine")
            }
            .frame(minHeight: 44)   // Match the shared action button’s full touch target.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    if data.plans.isEmpty {
                        emptyRoutinesEducationCard
                            .containerRelativeFrame(.horizontal) { length, _ in length - 56 }
                    } else {
                    ForEach(carouselPlans) { plan in
                        WorkoutCard(
                            plan: plan,
                            exById: data.exById,
                            // Completion and recommendation affect labels, never card order.
                            kicker: rotation.completedPlanIDs.contains(plan.id) ? "Completed" : (rotation.todayPlanID == plan.id ? "Today's Workout" : ""),
                            onStart: { onStart(plan) },
                            onShowDetail: { detailPlan = TodayWorkoutDetail(plan: plan) },
                            prominentStart: rotation.todayPlanID == plan.id,   // Only Today’s Workout uses the green primary action.
                            emphasized: rotation.todayPlanID == plan.id,       // accent 描边 + 辉光只给今日卡
                            fixedHeight: carouselCardHeight,
                            reservesKickerSpace: true,
                            completedOverride: rotation.completedPlanIDs.contains(plan.id)
                        )
                        // 长按菜单 — 跟 "All" sheet 里的列表卡同款 (改/删); 今日 AI 卡 (aiTodayPlan)
                        // 的删除由 DataStore.deletePlan 特判处理 (清卡 + 当天不自动重生成).
                        .contextMenu {
                            Button { detailPlan = TodayWorkoutDetail(plan: plan) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { pendingDeletePlanId = plan.id } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // 等高量测 v3 (#carousel-measure): 可见卡不再自报高度 — 改由下面的隐藏测量层
                        // 持续量"自然高", 这里只消费 fixedHeight. (v2 的 可见卡自报+棘轮+560上限+onAppear重置
                        // 会互相打架: 重置窗口内量测被上限拒收 → 卡死 nil → 卡片各自自然高 + 尾卡隐身,
                        // 就是 owner 实机看到的两个 bug.)
                        // 卡宽 = 容器宽 − 56 (容器 = 滚动区减去 contentMargins 后的正文宽):
                        // 吸附时右缘露出下一张 页边距16 + 56 − 卡间距12 = 60pt 的 peek.
                        .containerRelativeFrame(.horizontal) { length, _ in length - 56 }
                        .id(plan.id)
                    }
                    }
                    customWorkoutCard
                }
                .scrollTargetLayout()
            }
            // Let the native long-press lift extend above and below the carousel bounds.
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $carouselPosition, anchor: .leading)
            .onAppear {
                if !Self.showcaseCarouselEnd { carouselPosition = rotation.defaultPlanID }
            }
            .onChange(of: rotation.defaultPlanID) { _, id in
                if !Self.showcaseCarouselEnd { carouselPosition = id }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !Self.showcaseCarouselEnd { carouselPosition = rotation.defaultPlanID }
            }
            // showcase 专用 (SIMCTL_CHILD_MASO_SHOWCASE_CAROUSEL=end): 初始滚到轮播尾部 —
            // 夜间验证/截图能看到尾部自由训练空卡 + 等高效果. 真实用户 env 不存在, 恒 .leading.
            .defaultScrollAnchor(Self.showcaseCarouselEnd ? .trailing : .leading)
            // 横滑内容顶到屏幕两缘 (负 margin 抵掉页 padding), 首卡仍对齐正文 — 跟 Coach 货架同套路.
            .padding(.horizontal, -MasoMetrics.pagePaddingHorizontal)
            .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
            // ── 隐藏测量层: 每张卡渲染一份"永远自然高" (fixedHeight: nil) 的隐形副本, 宽度与可见卡
            // 一致 (页宽 − 边距×2 − 56), 持续上报自然高, reduce 取 max → 直接赋值 (无棘轮/无重置/无上限).
            // plans 变化 → 副本跟着变 → 新 max 自动流入; 副本永不吃 fixedHeight, 量测不会被自身污染.
            // 成本 = 多渲染 3-6 张不上屏的卡, 可接受.
            .background {
                GeometryReader { geo in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(carouselPlans) { plan in
                            WorkoutCard(plan: plan, exById: data.exById, kicker: "Today's Workout",
                                        onStart: {}, onShowDetail: {}, prominentStart: true, emphasized: true,
                                        reservesKickerSpace: true)
                                .frame(width: max(geo.size.width - 56, 100))
                                // 抗压缩: 外层 10×10 小 frame 的提案不许把副本竖向压扁 —
                                // 量到的必须是自然高.
                                .fixedSize(horizontal: false, vertical: true)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: CarouselCardHeightKey.self, value: g.size.height)
                                })
                        }
                    }
                    .frame(width: 10, height: 10, alignment: .topLeading)  // 压进小 frame, 不参与外层布局
                    .clipped()
                    .hidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onPreferenceChange(CarouselCardHeightKey.self) { h in
                // 直接赋值 (非棘轮) — 来源只有隐藏层的自然高, max reduce 后就是"最高那张"的高度.
                if h > 0, carouselCardHeight != h { carouselCardHeight = h }
            }
        }
        .padding(.top, 4)   // 外层 VStack spacing 16 + 4 = 与上方肌肉状态区间距 20pt (owner 指定 ≥20)
    }

    /// Empty-state education card routes users directly to AI Coach to build their first routine.
    private var emptyRoutinesEducationCard: some View {
        Button {
            Haptics.tap()
            onOpenCoach()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "message")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
                    .frame(width: 38, height: 38)
                    .background(MasoColor.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build your routine with AI")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(MasoColor.text)
                    Text("Tell AI Coach your goals and schedule to get a routine made for you.")
                        .font(.subheadline)
                        .foregroundStyle(MasoColor.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text("Chat with AI Coach")
                    Spacer()
                    Image(systemName: "arrow.down.right")
                        .environment(\.layoutDirection, .leftToRight)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.blue, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MasoMetrics.cardPadding)
            .frame(height: carouselCardHeight ?? 320, alignment: .center)
            .glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            .contentShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open AI Coach to create a routine")
    }

    /// Routines carousel 的尾部空卡 — 直接启动一个不带预设动作的自定义训练。
    private var customWorkoutCard: some View {
        Button {
            Haptics.tap()
            onFreeWorkout()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 48, height: 48)
                    .glassCircleButtonBackground(fallback: MasoColor.surfaceHi)
                Text("Start custom workout")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MasoColor.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: carouselCardHeight ?? 320)
            .glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
        .containerRelativeFrame(.horizontal) { length, _ in length - 56 }
        .accessibilityLabel("Start custom workout")
    }

    // MARK: - 肌肉状态 + 训练日历计算 helpers
    //
    // 从 HistoryScreen 移过来的实现 — 现在两个屏都用同一份. 长期应该把这些挪到
    // MuscleStatusCompute / DataStore extension, 暂时复制一份避免大改.

    /// Recovery 卡用 — 累计 volume 衰减模型, 跟 MuscleStatusOverviewCard 接.
    private var fatigueMap: [MuscleGroup: Double] {
        MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById)
    }

    /// "Train the gaps" 判断"3 天没碰" 用 — 跟 fatigue 不是一个概念, 单独走时间维度.
    private var lastMap: [MuscleGroup: Date] {
        MuscleStatusCompute.muscleLastTrainedMap(sets: data.sets, exById: data.exById)
    }

    private static let trainableMajorMuscles: [MuscleGroup] = [
        .chest, .back, .shoulders,
        .biceps, .triceps, .forearms,
        .core,
        .quads, .hamstrings, .glutes, .adductors, .calves,
    ]

    private var gapMuscles: [MuscleGroup] {
        // 全新用户 (零历史) 不显示 "Train the gaps" — 否则所有肌群都算 gap → 一键塞 12 个动作的马拉松,
        // 跟上方策划好的 Today's Workout 抢焦, 也吓退新用户. 等有了首次训练再让 gap 逻辑生效.
        guard !data.sets.isEmpty else { return [] }
        let map = lastMap
        let now = Date()
        let cutoff: TimeInterval = 3 * 86400
        var gaps: [MuscleGroup] = []
        for major in Self.trainableMajorMuscles {
            let anatomy = expandAnatomyMuscles([major])
            guard !anatomy.isEmpty else { continue }
            let allStale = anatomy.allSatisfy { m in
                guard let last = map[m] else { return true }
                return now.timeIntervalSince(last) >= cutoff
            }
            if allStale { gaps.append(major) }
        }
        return gaps
    }

    /// 一键: 找 gap → 智能挑动作 → 拼 plan → 启动训练 (跟 HistoryScreen.startGapWorkout 同款).
    private func startGapWorkout() {
        let gaps = gapMuscles
        guard !gaps.isEmpty else { return }
        let exercises = data.suggestedTrainingExercises(
            targetMuscles: gaps, perMuscleLimit: 2, limit: 12)
        let steps = exercises.enumerated().map { index, exercise in
            PlanStep(
                id: "gap-\(index)-\(exercise.id)", exerciseId: exercise.id,
                sets: max(1, data.settings.defaultSetsPerExercise),
                reps: exercise.mechanic == .isolation
                    ? data.settings.trainingGoal.defaultRepsForIsolation()
                    : data.settings.trainingGoal.defaultRepsForCompound(),
                weight: nil, restBetweenSets: data.settings.defaultRestSeconds, rest: 0)
        }
        guard !steps.isEmpty else { return }
        let now = Date()
        let name = String(
            format: NSLocalizedString("Catch-up: %@", comment: ""),
            gaps.prefix(3).map(\.displayName).joined(separator: " + ")
        )
        // P2-5: ephemeral — 跟自由训练同款. 不再 data.updatePlan (否则 "Catch-up: ..." 会永久
        // 留在 Plans 列表、每次点覆盖、还能进明日推荐). autoGenerated → 完成屏给"Save as plan",
        // 想留的用户自己存. id 带时间戳, 不撞 recommended 前缀.
        let plan = Plan(
            id: "plan-catchup-\(Int(now.timeIntervalSince1970))",
            name: name,
            steps: steps,
            createdAt: now,
            updatedAt: now,
            autoGenerated: true
        )
        onStart(plan)
    }


}

// MARK: - CarouselCardHeightKey — 今日轮播等高量测 (#today-carousel)
//
// 每张 WorkoutCard 上报自然渲染高, reduce 取 max → TodayScreen 回写 fixedHeight 统一所有卡.
private struct CarouselCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - ScrollIf — 条件 ScrollView (跟 RootView.NavStackIf 同套路)
//
// TodayScreen 两种宿主: 自己当页面 (Today tab) 时自带 ScrollView + 页面背景;
// 嵌进 Routines 单页 (PlansScreen 的滚动正文) 时退化成纯内容, 由外层滚动页接管.
private struct ScrollIf<Content: View>: View {
    let scroll: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        if scroll {
            // 试验性: 共享背景 = #121212 + 底部液态光斑 (embedded-in-scroll 路径不带背景, 不受影响).
            ScrollView { content() }
                .scrollClipDisabled()
                .background(AppBackground())
        } else {
            content()
        }
    }
}

// MARK: - RoutineImportFlow — 图片导入 routine 的 sheets/alert/loading (#image-import)
//
// 单独收成 ViewModifier: TodayScreen.body 修饰链已经很长, 再内联 4 个 sheet/alert/overlay
// 会让 SwiftUI 类型检查超时 ("unable to type-check in reasonable time").
struct RoutineImportFlow: ViewModifier {
    @Binding var pickerShown: Bool
    @Binding var pickedImage: UIImage?
    @Binding var parsing: Bool
    @Binding var imported: Plan?
    @Binding var importedMany: ImportedPlansPayload?
    @Binding var review: RoutineReviewPayload?
    @Binding var failed: Bool
    let data: DataStore
    /// 自增代数 — 用户连选多张图时, 只认最后一次的解析结果, 丢弃过期的.
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $pickerShown) {
                PhotoPicker(image: $pickedImage, source: .photoLibrary)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: pickedImage) { _, img in
                guard let img else { return }
                Analytics.shared.track("image_import_start")   // 选了一张图开始解析 — 无 PII
                generation += 1
                let myGen = generation
                parsing = true
                let library = data.userLibrary
                Task {
                    let result = await RoutineImageImporter.analyze(from: img, library: library)
                    await MainActor.run {
                        guard myGen == generation else { return }   // 又选了一张 → 丢弃这次过期结果
                        parsing = false
                        pickedImage = nil
                        // image_import_result — 解析结果类型 (qr / ocr / empty), 无 PII.
                        switch result {
                        case .deepLink(let plans):
                            Analytics.shared.track("image_import_result", ["result": .string("qr")])
                            // QR 分享卡: 单计划 → 完整预览; 批量卡 (≥2) → 多计划确认页.
                            if plans.count == 1 {
                                imported = plans[0]
                            } else {
                                importedMany = ImportedPlansPayload(plans: plans)
                            }
                        case .recognized(let cands):
                            Analytics.shared.track("image_import_result", ["result": .string("ocr")])
                            review = RoutineReviewPayload(candidates: cands)  // 截图 → 确认页
                        case .empty:
                            Analytics.shared.track("image_import_result", ["result": .string("empty")])
                            failed = true
                        }
                    }
                }
            }
            .sheet(item: $imported) { plan in
                ImportedPlanSheet(plan: plan, onAdd: { p in
                    imported = nil
                    // image_import_commit — 真加进库 (QR 路径). 无 PII: 只报识别数 + 结果类型.
                    Analytics.shared.track("image_import_commit", [
                        "recognized_count": .int(p.steps.count), "result": .string("qr"),
                    ])
                    DispatchQueue.main.async {
                        _ = data.saveImportedPlans([p])
                        Haptics.tap()
                    }
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $importedMany) { payload in
                ImportedPlansSheet(plans: payload.plans, onAdd: { chosen in
                    importedMany = nil
                    Analytics.shared.track("image_import_commit", [
                        "recognized_count": .int(chosen.count), "result": .string("qr_batch"),
                    ])
                    DispatchQueue.main.async {
                        _ = data.saveImportedPlans(chosen)
                        Haptics.tap()
                    }
                })
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $review) { payload in
                RoutineReviewSheet(candidates: payload.candidates, onCommit: { p in
                    review = nil
                    // image_import_commit — 真加进库 (OCR 路径). 无 PII: 只报识别数 + 结果类型.
                    Analytics.shared.track("image_import_commit", [
                        "recognized_count": .int(p.steps.count), "result": .string("ocr"),
                    ])
                    DispatchQueue.main.async {
                        _ = data.saveImportedPlans([p])
                        Haptics.tap()
                    }
                })
                .presentationDragIndicator(.visible)
            }
            .alert("Couldn't read a routine from that image", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try a clearer screenshot — exercise names need to be readable.")
            }
            .overlay {
                if parsing {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.large)
                            Text("Reading routine…")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.text)
                        }
                        .padding(22)
                        .background(MasoColor.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
    }
}


/// iOS 26 supplies the native navigation subtitle; older iOS uses the content fallback.
private struct HomeNavigationSubtitle: ViewModifier {
    let subtitle: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}
