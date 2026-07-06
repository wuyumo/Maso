import SwiftUI

struct TodayScreen: View {
    @Environment(DataStore.self) private var data
    let onStart: (Plan) -> Void
    /// 拉起"自由训练" flow — Today 卡片下方按钮触发, 走 QuickWorkout sheet 选肌肉 / 动作 / 开练
    let onFreeWorkout: () -> Void
    /// 新建训练计划 — 原 Plans 页右上角 "+", 现移到 Today 的"我的训练"section. RootView 持有 sheet.
    let onNewPlan: () -> Void
    /// 标题行右上角齿轮 → 弹 Settings sheet (RootView 持有 sheet state)
    let onOpenSettings: () -> Void
    /// Pro feature ②: My Routines 顶部优化建议卡点 "Optimize with AI" → 把诊断 focusNote 上抛给
    /// PlansScreen, 由它带 focusNote 重生成 routine (Pro gating 也在 PlansScreen 那侧). 其他用法不传.
    var onOptimize: (DataStore.RoutineSuggestion) -> Void = { _ in }
    /// 嵌在外层 NavigationStack (Train / Plans tab) 里时 true — 不渲染自己的大标题/齿轮.
    var embedded: Bool = false
    /// 渲染哪部分内容:
    ///   - .trainToday: 肌肉状态 + 今日推荐 + 自由训练 (Today tab)
    ///   - .myPlans:    我的训练列表 + 自由训练 + 社区 (Plans tab 的 My Plans 分页)
    ///   - .full:       全部 (兼容老用法)
    enum Mode { case full, trainToday, myPlans }
    var mode: Mode = .full
    /// Routines 单页 (#single-page-IA): true = 不自带 ScrollView / 背景 / 页边距 —
    /// 外层 PlansScreen 的滚动页接管 (本 view 只出内容 VStack, sheets/alerts 照常挂在上面).
    /// Today tab (RootView) 不传, 默认 false 走自己的 ScrollView.
    var embeddedInScroll: Bool = false
    /// Routines tab (#IA-A): "+ new routine" 菜单在导航栏 (PlansScreen). 点 "Import from photo" 翻这个 →
    /// 这里开图片选择器. 其他用法 (Today tab) 不传, 默认 .constant(false) 不触发.
    var triggerImport: Binding<Bool> = .constant(false)

    /// 卡片 tap → 弹 plan detail sheet 查看动作 + 每组 sets/reps/weight (WorkoutCard + PlanRow 共用)
    @State private var detailPlan: Plan? = nil
    /// 删 plan 的二次确认 (从原 Plans 页迁来).
    @State private var pendingDeletePlanId: String? = nil
    /// 社区精选 sheet (从原 Plans 页迁来).
    @State private var communityPresented: Bool = false
    /// 图片导入 routine (#image-import): 选图 → QR/OCR 解析 → ImportedPlanSheet 确认.
    @State private var importPickerShown = false
    @State private var importPickedImage: UIImage? = nil
    @State private var importParsing = false
    @State private var importedRoutine: Plan? = nil
    /// OCR 第三方截图 → 置信度分级候选, 驱动 RoutineReviewSheet (QR 深链仍走 importedRoutine).
    @State private var importReview: RoutineReviewPayload? = nil
    @State private var importFailed = false
    /// Muscle Status 卡"解锁逐肌群恢复" → 付费墙 (非 Pro). 跟 HistoryScreen 的 paywall 同款.
    @State private var paywallPresented = false

    private var suggested: Plan? {
        // 默认推用户自己的 plans (pickTodayPlan: LRU 挑最久没练那张) —
        // 这些 plan 是用户在 Plans tab 见过、可能调过的, 心智模型上是"我的训练计划",
        // 比 AI 当场生成的陌生 plan 更可信任. AI 路径只在用户 plans 为空时兜底.
        data.todayRecommendedPlan ?? data.aiTodayPlan
    }

    /// 时段问候 — DESIGN.md §4.2: 0-5 凌晨 / 5-12 早上 / 12-18 下午 / 18-24 晚上.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return NSLocalizedString("Good morning", comment: "")
        case 12..<18: return NSLocalizedString("Good afternoon", comment: "")
        case 18..<24: return NSLocalizedString("Good evening", comment: "")
        default:      return NSLocalizedString("Good night", comment: "")
        }
    }

    /// 大标题下的一句贴心提示 — 按"距上次训练多久"给极简一句, 提醒今天该不该练.
    /// sets 是 newest-first (recordSet insert at 0), 所以 first = 最近一次.
    private var todayTipLine: String {
        let cal = Calendar.current
        guard let last = data.sets.first?.performedAt else {
            return NSLocalizedString("Let's start your first workout.", comment: "today tip — never trained")
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<0, 0: return NSLocalizedString("You've trained today — rest up.", comment: "today tip — trained today")
        case 1:       return NSLocalizedString("Last trained yesterday.", comment: "today tip — yesterday")
        case 2...6:   return String(format: NSLocalizedString("%lld days since your last session.", comment: "today tip — N days"), days)
        default:      return String(format: NSLocalizedString("%lld days off — let's get back to it.", comment: "today tip — long gap"), days)
        }
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
        ScrollIf(scroll: !embeddedInScroll) {
            VStack(alignment: .leading, spacing: 16) {
                // ===== Today tab 内容: 肌肉状态 + 今日推荐 + 自由训练 (mode != .myPlans) =====
                if mode != .myPlans {
                    // ── 训练状态 ── (MuscleStatusOverviewCard 自带 "MUSCLE STATUS" kicker;
                    //    距上次训练的贴心提示挪进卡片 kicker 行右侧).
                    MuscleStatusOverviewCard(
                        fatigueMap: fatigueMap,
                        gapMuscles: gapMuscles,
                        onStartGapWorkout: startGapWorkout,
                        tipLine: todayTipLine,
                        onUnlock: { paywallPresented = true }
                    )

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
                                Task { await data.forceRefreshAIWorkout() }
                            } label: { Text("Retry").font(.system(size: 12, weight: .bold)) }
                        }
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(MasoColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // ── 今日推荐 ── (WorkoutCard 自带 "TODAY'S WORKOUT" kicker)
                    if let plan = suggested {
                        WorkoutCard(
                            plan: plan,
                            exById: data.exById,
                            kicker: "Today's Workout",
                            onStart: { onStart(plan) },
                            onShowDetail: { detailPlan = plan },
                            emphasized: true   // accent 描边 + 辉光 — 跟下方 My Plans 弱化卡区分
                        )
                    }

                    // ── 自由训练入口 — Today 的"立即训练"动作. My Routines 列表已迁到 Plans tab,
                    //    但自由训练是"现在就练", 跟今日推荐同簇, 留在 Today.
                    entryCard(
                        icon: "dumbbell.fill",
                        title: "Free workout",
                        subtitle: "Pick your own exercises and go",
                        trailingPlay: true,
                        action: onFreeWorkout
                    )
                    .padding(.top, 4)
                }

                // ===== Plans tab 的 My Plans 分页: 我的训练 + 自由训练 + 社区 (mode != .trainToday) =====
                if mode != .trainToday {
                    // Pro feature ②: 数据驱动优化建议卡 — 练够数据 + 诊断出问题 + 有 routine 可优化时浮在最顶.
                    if !data.plans.isEmpty, let suggestion = data.routineSuggestion() {
                        RoutineOptimizeCard(suggestion: suggestion, onOptimize: onOptimize)
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
                                onShowDetail: { detailPlan = plan },
                                prominentStart: false,  // 计划卡的开始键弱化 (半透明绿底)
                                showStart: false,       // Routines/Saved: 不显示 play 钮, 点卡片进详情 Start
                                compactLayout: true     // 列表卡用紧凑横排 (标题/计数/[图|chips])
                            )
                            // 长按菜单代替 List 右滑 — 改/删.
                            .contextMenu {
                                Button { detailPlan = plan } label: { Label("Edit", systemImage: "pencil") }
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
                    Spacer(minLength: MasoMetrics.pageBottomInset)
                }
            }
            // 页边距 — 嵌入模式下外层已给 pagePaddingHorizontal, 置 0 防双重缩进.
            .padding(.horizontal, embeddedInScroll ? 0 : MasoMetrics.pagePaddingHorizontal)
        }
        // 自定义页头: greeting kicker + "Today" 大标题 + 齿轮. embedded (Today / Plans tab) 时跳过 —
        // 由外层 NavigationStack 的 screenHeader / segmented 接管.
        .applyIf(!embedded) {
            $0.screenHeader("Today", kicker: greeting) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(item: $detailPlan) { plan in
            PlanDetailSheet(
                initialPlan: plan,
                onStart: { p in
                    detailPlan = nil
                    DispatchQueue.main.async { onStart(p) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $communityPresented) {
            CommunityScreen()
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
            .presentationDragIndicator(.visible)
        }
        // ── 图片导入 routine (#image-import) — 流程收进 ViewModifier, 避免 body 类型检查超时.
        .modifier(RoutineImportFlow(
            pickerShown: $importPickerShown,
            pickedImage: $importPickedImage,
            parsing: $importParsing,
            imported: $importedRoutine,
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

    /// 并排的小入口卡 (自由训练 / 社区).
    /// Free workout / Community 共用的入口卡 — 一致排版:
    ///   第一行: 小图标 + 标题 (同一行)
    ///   第二行: 辅助文案 (说明这个入口是干嘛的)
    private func entryCard(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, trailingPlay: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // 第一行: 小图标 + 标题, 同行.
                    HStack(spacing: 7) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MasoColor.accent)
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(1)
                    }
                    // 第二行: 辅助文案.
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if trailingPlay {
                    // 自由训练 = 直接开练, 右侧用播放键 (软绿底, 无描边) 而不是导航 chevron.
                    ZStack {
                        Circle()
                            .fill(MasoColor.accent.opacity(0.18))
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.accent)
                            .offset(x: 0.5)
                    }
                    .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(MasoColor.textFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MasoMetrics.cardPadding)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
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
        let favSet = Set(data.settings.favoriteExerciseIds)
        var seenExerciseIds = Set<String>()
        var steps: [PlanStep] = []
        var idx = 0
        let maxSteps = 12

        for major in gaps {
            let targetMuscles = expandAnatomyMuscles([major])
            struct Scored { let ex: Exercise; let score: Int; let isFav: Bool }
            var scored: [Scored] = []
            // gap-fill 候选: 跳过 niche — 训练日历空缺时智能补的动作不该是 Foam Roll / Battle Rope.
            for ex in data.exercises where ex.category == .strength && !ex.isNiche {
                if seenExerciseIds.contains(ex.id) { continue }
                let s = gapScore(ex, against: targetMuscles)
                if s > 0 {
                    scored.append(Scored(ex: ex, score: s, isFav: favSet.contains(ex.id)))
                }
            }
            scored.sort { lhs, rhs in
                if lhs.isFav != rhs.isFav { return lhs.isFav && !rhs.isFav }
                return lhs.score > rhs.score
            }
            for pick in scored.prefix(2) {
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

    private func gapScore(_ ex: Exercise, against targets: Set<MuscleGroup>) -> Int {
        var total = 0
        for (idx, mg) in ex.muscleGroups.enumerated() {
            if targets.contains(mg) {
                total += max(20, 100 - idx * 18)
            }
        }
        return total
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
            ScrollView { content() }
                .background(MasoColor.background.ignoresSafeArea())
        } else {
            content()
        }
    }
}

// MARK: - RoutineImportFlow — 图片导入 routine 的 sheets/alert/loading (#image-import)
//
// 单独收成 ViewModifier: TodayScreen.body 修饰链已经很长, 再内联 4 个 sheet/alert/overlay
// 会让 SwiftUI 类型检查超时 ("unable to type-check in reasonable time").
private struct RoutineImportFlow: ViewModifier {
    @Binding var pickerShown: Bool
    @Binding var pickedImage: UIImage?
    @Binding var parsing: Bool
    @Binding var imported: Plan?
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
                        case .deepLink(let plan):
                            Analytics.shared.track("image_import_result", ["result": .string("qr")])
                            imported = plan                       // QR 分享卡 → 完整预览
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
                        data.plans.append(p)
                        data.save()
                        Haptics.tap()
                    }
                })
                .presentationDetents([.medium, .large])
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
                        data.plans.append(p)
                        data.save()
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
