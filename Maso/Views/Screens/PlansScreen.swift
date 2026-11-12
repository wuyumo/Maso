import SwiftUI

// MARK: - 共享计划组件 (原 PlansScreen 正文已退役 — Coach tab 接管, docs/coach-tab-design.md 拆迁清单)
//
// PlansScreen struct (单页 IA 正文) 与 Plans tab 挂载已在批次 3 拆除; 本文件现在只装被
// Coach / Today / RootView 复用的组件: ClassicsSheet / PlanRationaleCard / TrainingPreferencesSheet /
// PlanRow / PlanDetailSheet (+EditStepView) / ExercisePickerSheet / ActivityViewController.


// MARK: - ClassicsScreen — Collection → Routine → Detail
//
// Routines 单页的 Classics 入口卡 → 这个 sheet. 自包含: Level/Days 筛选条固定钉在顶部 (sheet 语境
// 走简单固定, 不用 safeAreaBar), 计划卡 / 详情预览 / 满额 paywall 都挂在 sheet 内部 (sheet 之上
// 再叠 sheet 是允许的; 若挂回底下的 PlansScreen 会撞"一次只能 present 一个 sheet").
// Today 页底部的 Classic Routines 入口通过 AppDestination push 到此页。
private struct ClassicsWorkoutDetail: Hashable {
    let plan: Plan
}

struct ClassicsScreen: View {
    @Environment(DataStore.self) private var data
    /// 详情关闭后上抛 Start，由宿主依次关闭 Explore / My Routines 再启动训练。
    let onStart: (Plan) -> Void

    /// Classics 筛选 (#filters): 等级 + 每周天数. nil = 全部.
    @State private var communityLevel: String? = nil
    @State private var communityDays: Int? = nil
    @State private var detailPlan: ClassicsWorkoutDetail? = nil
    @State private var pendingStart: Plan?
    /// detailPlan 是哪套 Classics 项目的预览 — 详情页 Save 要按"整套"存 (所有训练日), 不能只存
    /// 预览的那一张, 所以得记住来源 CommunityPlan. 跟 detailPlan 同时设置.
    @State private var detailCP: CommunityPlan? = nil
    /// Save 满额 (免费上限) → paywall — 跟 PlansScreen.addToSaved 同规则, 付费/上限逻辑不变.
    @State private var paywallPresented = false
    /// 保存成功 toast ("已添加 N 个训练日") — 多日项目存的是 N 张 Plan, 必须明确告知, 否则用户
    /// 以为只存了一张. ~2.2s 自动消失 (跟 HistoryScreen.applyToast 同款).
    @State private var workoutSaveFlow = WorkoutSaveFlow()
    @State private var saveAfterDetail: CommunityPlan?
    @State private var materializedPlansByCollection: [String: [Plan]] = [:]
    @State private var loadingCollectionIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // 筛选条固定钉在导航栏下方, 不随列表滚动.
            classicsFilterBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    let plans = filteredCommunityPlans
                    if plans.isEmpty {
                        Text("No Classics match these filters.")
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else {
                        ForEach(plans) { cp in
                            collectionSection(cp, plans: materializedPlansByCollection[cp.id])
                                .onAppear { loadCollection(cp) }
                        }
                    }
                    Color.clear.frame(height: MasoMetrics.pageBottomInset)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 4)
            }
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle("Classic Routines")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MasoColor.text)
        .navigationDestination(item: $detailPlan) { route in
            PlanDetailSheet(
                initialPlan: route.plan,
                onStart: { p in
                    pendingStart = p
                    detailPlan = nil
                },
                // Save 存整套 (所有训练日), 不是预览的这一张 — 见 addClassics (P0#3).
                onAddToSaved: { _ in
                    if let cp = detailCP {
                        saveAfterDetail = cp
                        detailPlan = nil
                    }
                },
                classicsDayCount: detailCP.map(\.sessions.count),
                savedOverride: detailCP.flatMap { materializedPlansByCollection[$0.id] }.map { data.areCoachPlansSaved($0) },
                usesParentNavigation: true
            )
        }
        .onChange(of: detailPlan) { _, plan in
            guard plan == nil else { return }
            if let started = pendingStart {
                pendingStart = nil
                onStart(started)
            } else if let collection = saveAfterDetail {
                saveAfterDetail = nil
                DispatchQueue.main.async { addClassics(collection) }
            }
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
                .presentationDragIndicator(.visible)
        }
        .workoutSaveConfirmation(flow: workoutSaveFlow) { paywallPresented = true }
    }

    // MARK: - Classics filters (#filters)

    private var communityLevelOptions: [String] { Array(Set(CommunityPlans.all.map(\.levelKey))).sorted() }
    private var communityDayOptions: [Int] { Array(Set(CommunityPlans.all.map(\.frequencyDaysPerWeek))).sorted() }
    private var filteredCommunityPlans: [CommunityPlan] {
        CommunityPlans.all.filter {
            (communityLevel == nil || $0.levelKey == communityLevel) &&
            (communityDays == nil || $0.frequencyDaysPerWeek == communityDays)
        }
    }

    /// Native menu pickers match the shared Exercises filter row.
    private var classicsFilterBar: some View {
        HStack {
            Picker("Level", selection: $communityLevel) {
                Text("All levels").tag(nil as String?)
                ForEach(communityLevelOptions, id: \.self) { level in
                    Text(LocalizedStringKey(level)).tag(Optional(level))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Days/week", selection: $communityDays) {
                Text("Any frequency").tag(nil as Int?)
                ForEach(communityDayOptions, id: \.self) { days in
                    Text("\(days) days/wk").tag(Optional(days))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.vertical, MasoMetrics.rowPaddingV)
    }

    /// 每个 Collection 作为一个 section, 其 Routine 卡直接列在分组信息下方。
    private func collectionSection(_ cp: CommunityPlan, plans: [Plan]?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(cp.kicker)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                    Text("·")
                    Text(NSLocalizedString(cp.levelKey, comment: "community plan level"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(MasoColor.accent)

                Text(NSLocalizedString(cp.nameKey, comment: "community plan name"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(NSLocalizedString(cp.descKey, comment: "community plan description"))
                    .font(.system(size: 13))
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(String(format: NSLocalizedString("%lld routines", comment: ""), cp.sessions.count)) · \(String(format: NSLocalizedString("%lld days/wk", comment: ""), cp.frequencyDaysPerWeek))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(MasoColor.textFaint)
            }
            .padding(.bottom, 2)

            if let plans {
                ForEach(Array(plans.enumerated()), id: \.offset) { index, plan in
                    WorkoutCard(
                        plan: plan,
                        exById: data.exById,
                        kicker: cp.kicker + " · " + String(format: NSLocalizedString("Day %lld", comment: "routine day number"), index + 1),
                        onStart: {},
                        onShowDetail: { detailCP = cp; detailPlan = ClassicsWorkoutDetail(plan: plan) },
                        prominentStart: false,
                        showStart: false,
                        compactLayout: true,
                        denseLayout: true,
                        showsExercisePills: true
                    )
                }
            } else if loadingCollectionIDs.contains(cp.id) {
                ProgressView()
                    .controlSize(.small)
                    .tint(MasoColor.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }

            let saved = plans.map { data.areCoachPlansSaved($0) } ?? false
            AddToPlansButton(isSaved: saved,
                             routineCount: plans?.count ?? cp.sessions.count,
                             action: { addClassics(cp, anchorID: cp.id) })
                .workoutSaveConfirmation(flow: workoutSaveFlow, anchorID: cp.id) { paywallPresented = true }
                .accessibilityIdentifier("classics.save-batch.\(cp.id)")
                .disabled(saved || plans == nil || plans?.isEmpty == true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusLarge, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    /// Materialize only collections near the viewport and cache the generated Plans.
    /// The old eager VStack built every card (and fresh UUIDs) before the page appeared.
    private func loadCollection(_ cp: CommunityPlan) {
        guard materializedPlansByCollection[cp.id] == nil,
              !loadingCollectionIDs.contains(cp.id) else { return }
        loadingCollectionIDs.insert(cp.id)
        let exerciseIndex = data.exById
        Task {
            let plans = await Task.detached(priority: .userInitiated) {
                Self.makeCollectionPlans(cp, byId: exerciseIndex)
            }.value
            materializedPlansByCollection[cp.id] = plans
            loadingCollectionIDs.remove(cp.id)
        }
    }

    nonisolated private static func makeCollectionPlans(_ cp: CommunityPlan, byId: [String: Exercise]) -> [Plan] {
        cp.materialize(byId: byId).enumerated().map { index, plan in
            var namedPlan = plan
            if cp.sessions.indices.contains(index) {
                namedPlan.name = NSLocalizedString(cp.sessions[index].nameKey, comment: "community routine name")
            }
            return namedPlan
        }
    }

    /// 卡片 kicker — 多日项目追加 "· N 个训练日": 卡片上的动作/组数只是第一天的量, 不标注天数
    /// 会跟 "PPL 6-day" 这类标题自相矛盾 (P0#3 附带问题). 单日项目保持原 kicker.
    private func classicsKicker(_ cp: CommunityPlan) -> String {
        guard cp.sessions.count > 1 else { return cp.kicker }
        return cp.kicker + " · " + String(format: NSLocalizedString("%lld training days", comment: "classics card day count"), cp.sessions.count)
    }

    /// 详情页 Save / 卡片星标 → 把整套项目的**所有训练日**逐张存进 My Routines (P0#3).
    /// materialize 返回每 session 一张 Plan (命名 "项目名 · Session名"); 之前只存第一张却顶着
    /// 整套名字 — 存 "PPL 6-day" 实际只拿到 Push 日. 语义对齐旧 CommunityScreen.handleAdd.
    private func addClassics(_ cp: CommunityPlan, anchorID: String? = nil) {
        guard let plans = materializedPlansByCollection[cp.id], !plans.isEmpty else { return }
        workoutSaveFlow.request(plans, anchorID: anchorID, data: data) { paywallPresented = true }
    }
}


// MARK: - Training Preferences 编辑层 (sheet)
//
// 点 Training Preferences 卡 → 拉起这层 (large detent). 内容 = Settings 同款 TrainingSettingsSection
// (live 写 data.settings). 右上 Save 是唯一保存入口; 偏好有变化时先询问是否同步更新 routines.
// Cancel → 回滚到进入时快照.
// internal (非 private) — 历史上给 Coaching sheet 复用过, 现仅本文件用, 保持 internal 无害.
struct TrainingPreferencesSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 关层 + 重生成的回调 (= aiPage 的 startGenerateRoutines / Coach 的 send).
    var onConfirm: () -> Void
    @State private var draft = TrainingPreferenceDraft(settings: UserSettings())
    @State private var original: TrainingPreferenceDraft?
    @State private var showRoutineUpdateConfirmation = false
    private var hasChanges: Bool { original.map { draft != $0 } ?? false }
    private var routinePreferencesChanged: Bool { original.map { draft.affectsRoutine(comparedTo: $0) } ?? false }

    var body: some View {
        AppNavigationStack {
            Form {
                TrainingSettingsSection(settings: $draft)
            }
            .navigationTitle("Training Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 顶栏规范: 编辑型 sheet = 左上 Cancel + 右上粗体主操作.
                // 右上 Save = 只保存不生成; "生成"是升格路径, 放底部大 CTA 不进顶栏.
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) { saveTapped() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { if original == nil { draft = TrainingPreferenceDraft(settings: data.settings); original = draft } }
        .confirmPreferenceDismissal(hasChanges: hasChanges)
        .alert("Update routines?", isPresented: $showRoutineUpdateConfirmation) {
            Button("Update routines") { saveAndGenerate() }
            Button("Save only") { saveOnly() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save these training preferences and regenerate your routines to match?")
        }
    }

    private func cancel() {
        dismiss()
    }

    private func saveTapped() {
        Haptics.tap()
        if routinePreferencesChanged {
            showRoutineUpdateConfirmation = true
        } else {
            saveOnly()
        }
    }

    /// 保存偏好但保留当前 routines; 下次生成时新偏好自然生效.
    private func saveOnly() {
        draft.apply(to: &data.settings)
        data.save()
        original = nil
        dismiss()
    }

    /// 用户确认后保存偏好并立即触发 routine 更新.
    private func saveAndGenerate() {
        draft.apply(to: &data.settings)
        data.save()
        original = nil
        dismiss()
        onConfirm()   // → startGenerateRoutines / Coach send: loading → 新 routine
    }
}

// MARK: - PlanDetailSheet — 可编辑版 (RootView 也用它做新建)

/// Wide-and-short plan detail. Portrait stays the stacked form.
/// Duo's inner landscape is about 951×669 pt and can stay vertically regular,
/// so `verticalSizeClass == .compact` is not the signal.
enum PlanDetailLayout {
    static let minimumAspect: CGFloat = 1.25
    static let maximumHeight: CGFloat = 740

    /// `size` must be the window bounds. A regular-width sheet is a centered
    /// card; measuring that card stays under the aspect threshold.
    static func usesSideBySide(width: CGFloat, height: CGFloat) -> Bool {
        guard width > 1, height > 1 else { return false }
        return width >= height * minimumAspect && height <= maximumHeight
    }

    /// Large portrait (Duo inner 669×951), not a phone. The sheet is tall enough
    /// that a floating CTA covers a lower row unless the form can scroll past it.
    static func needsPortraitScrollClearance(width: CGFloat, height: CGFloat) -> Bool {
        width >= 600 && height > width
    }

    static func windowSize() -> CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        guard let window else { return .zero }
        return liveSize(of: window)
    }

    /// Bounds of the window that hosts this view. Device-orientation notifications
    /// are not a rotation signal on Duo: DeviceHub rotates the inner display
    /// without posting one, so a size captured at appear stays 951×669.
    static func liveSize(of window: UIWindow) -> CGSize {
        let bounds = window.bounds.size
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 1, bounds.height > 1 else { return .zero }
        guard let scene = window.windowScene else { return bounds }
        let screen = scene.screen.bounds.size
        guard screen.width.isFinite, screen.height.isFinite, screen.width > 1, screen.height > 1 else { return bounds }
        // Same display, possibly mid-rotation: bounds can keep the old aspect
        // after the screen (and interface orientation) have already swapped.
        let sameDisplay = abs(max(bounds.width, bounds.height) - max(screen.width, screen.height)) < 2
            && abs(min(bounds.width, bounds.height) - min(screen.width, screen.height)) < 2
        guard sameDisplay else { return bounds }
        let short = min(screen.width, screen.height)
        let long = max(screen.width, screen.height)
        switch scene.interfaceOrientation {
        case .portrait, .portraitUpsideDown:
            // Screen already portrait, or bounds still holding the previous landscape aspect.
            if screen.height + 1 >= screen.width || bounds.width > bounds.height {
                return CGSize(width: short, height: long)
            }
            return bounds
        case .landscapeLeft, .landscapeRight:
            // Screen already landscape. Portrait bounds are left alone when the
            // screen has already swapped and only the orientation flag is stale.
            if screen.width + 1 >= screen.height {
                return CGSize(width: long, height: short)
            }
            return bounds
        default:
            return bounds
        }
    }

    /// Never feeds NaN or a negative remainder into `.frame`.
    static func layoutLength(_ proposed: CGFloat, minimum: CGFloat, maximum: CGFloat, limit: CGFloat) -> CGFloat {
        guard minimum.isFinite, maximum.isFinite, minimum > 0, maximum >= minimum else { return 1 }
        guard proposed.isFinite, limit.isFinite, limit > 0 else { return minimum }
        let chosen = min(maximum, max(minimum, min(proposed, limit)))
        return chosen.isFinite && chosen > 0 ? chosen : minimum
    }
}

/// Reads the hosting window on layout, bounds KVO, and rotation completion.
/// A 1×1 probe does not get `layoutSubviews` when the window swaps aspect, so
/// this view is the sheet background and samples again after the transition.
private struct WindowGeometryReader: UIViewControllerRepresentable {
    var onChange: (CGSize) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onChange = onChange
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onChange = onChange
        controller.publish()
    }

    final class Controller: UIViewController {
        var onChange: ((CGSize) -> Void)?
        private var last: CGSize = .zero
        private var boundsObservation: NSKeyValueObservation?
        private var retryWork: DispatchWorkItem?

        deinit { boundsObservation?.invalidate() }

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            self.view = view
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if boundsObservation == nil, view.window != nil {
                observeWindow()
            }
            publish()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: { _ in
                self.publishSoon()
            }, completion: { _ in
                self.publishSoon()
            })
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            observeWindow()
            publishSoon()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            observeWindow()
            publishSoon()
        }

        private func observeWindow() {
            boundsObservation?.invalidate()
            boundsObservation = view.window?.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                self?.publishSoon()
            }
        }

        private func publishSoon() {
            publish()
            retryWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.publish() }
            retryWork = work
            DispatchQueue.main.async { [weak self] in self?.publish() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        func publish() {
            guard let window = view.window else { return }
            let size = PlanDetailLayout.liveSize(of: window)
            guard size.width > 1, size.height > 1, size != last else { return }
            last = size
            let callback = onChange
            DispatchQueue.main.async {
                callback?(size)
            }
        }
    }
}

private struct WideSheetPresentation: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            // Page sizing uses the window width. The default form sheet is the
            // centered card that leaves the page underneath visible.
            content
                .presentationSizing(.page)
                .presentationDetents([.large])
        } else {
            content
        }
    }
}

struct PlanDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let initialPlan: Plan
    let isCreating: Bool
    let onStart: (Plan) -> Void
    /// Discover 用 — 非 nil 时右上角显示系统默认 "+" 加进 Saved (并隐藏 …/Delete 菜单, 因为这张还没拥有).
    let onAddToSaved: ((Plan) -> Void)?
    /// Classics 预览专用 — 整套项目的训练日数. > 1 时在 Save CTA 下标注 "含 N 个训练日":
    /// 预览显示的只是第一天, 不标注会让用户以为整套就这几个动作 (P0#3). 其他调用方不传 (nil 不显示).
    let classicsDayCount: Int?
    /// 书签态覆盖 (Coach 生成卡详情用 — savedIdMap 反查, 副本改名后不失灵).
    /// nil → 现状 data.isPlanSaved(draft) (签名匹配), 其它调用方不受影响.
    let savedOverride: Bool?
    /// False keeps the sheet's own navigation stack. Card-to-detail pushes use the parent stack.
    var usesParentNavigation = false

    @State private var draft: Plan
    @State private var resolvedDefaults = false
    @State private var showAddPicker: Bool = false
    /// 删除整个 plan 的确认 alert. 走 sheet 的"…"菜单触发.
    @State private var confirmDelete: Bool = false
    /// 点 step 行 / 卡片图片缩略图弹的动作详情. tap 文字区域走 NavigationLink 进编辑页.
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 step / contextMenu Delete 的待删 stepId — alert 二次确认才真删.
    @State private var pendingDeleteStepId: String? = nil
    /// 右滑 Edit / NavigationLink tap 共用同一 navigation path — append stepId 触发 push 进编辑页.
    @State private var stepEditPath = NavigationPath()
    @State private var editingStepID: String?
    /// 动作列表的视图模式 — 单列 row (default) 还是 2 列 grid card.
    /// 持久化到 UserDefaults — 跨 sheet 开关 / app 重启都保留, 用户偏好一旦设定不会"忘".
    @AppStorage("planStepCardLayout") private var useCardLayout: Bool = false
    /// Share plan — 点 toolbar 分享按钮 → 拉起 UIActivityViewController 分享 maso:// 链接.
    /// 分享图 — RoutineShareCard 渲染产物 (含 maso:// 深链 QR). 设了就弹 share sheet.
    @State private var showsShare = false
    /// Share encode 失败时弹的简单 alert (理论上不会触发).
    /// 右滑"替换动作"流程: stepId set 非 nil 时弹 ExercisePickerSheet 让用户挑新动作,
    /// 选完后只换 exerciseId, 保留 sets/reps/weight 等参数 (用户调过的负荷不要被替换抹掉).
    /// 跟 showAddPicker (append) 走两套 sheet, 语义清楚.
    @State private var stepToReplaceId: String? = nil
    /// Window bounds, not the sheet's proposed size.
    @State private var windowSize: CGSize = .zero

    init(initialPlan: Plan, isCreating: Bool = false, onStart: @escaping (Plan) -> Void, onAddToSaved: ((Plan) -> Void)? = nil,
         classicsDayCount: Int? = nil, savedOverride: Bool? = nil, usesParentNavigation: Bool = false) {
        self.initialPlan = initialPlan
        self.isCreating = isCreating
        self.onStart = onStart
        self.onAddToSaved = onAddToSaved
        self.classicsDayCount = classicsDayCount
        self.savedOverride = savedOverride
        self.usesParentNavigation = usesParentNavigation
        self._draft = State(initialValue: initialPlan)
        self._windowSize = State(initialValue: PlanDetailLayout.windowSize())
    }

    private var muscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for s in draft.steps {
            guard let ex = data.exById[s.exerciseId] else { continue }
            for m in ex.muscleGroups where seen.insert(m).inserted {
                out.append(m)
            }
        }
        return out
    }

    private var totalSets: Int { draft.steps.reduce(0) { $0 + $1.sets } }

    private var wideWindow: Bool {
        PlanDetailLayout.usesSideBySide(width: windowSize.width, height: windowSize.height)
    }

    var body: some View {
        Group {
            if usesParentNavigation {
                detailForm
            } else {
                // Creation and other explicit modals keep a stack so their Cancel button has a bar.
                AppNavigationStack(path: $stepEditPath) { detailForm }
            }
        }
        .modifier(WideSheetPresentation(enabled: wideWindow))
        .background {
            WindowGeometryReader { size in
                if size != windowSize {
                    windowSize = size
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            windowSize = PlanDetailLayout.windowSize()
        }
    }

    private var detailForm: some View {
            Group {
                if wideWindow {
                    wideDetailForm(size: windowSize)
                } else {
                    portraitDetailForm
                }
            }
            .background(alignment: .topLeading) {
                // Probes are not ancestors of the list or Start. An identifier on the
                // container was copied onto the button, the text field, and this probe.
                detailAccessibilityProbes
            }
            // 不显示 nav title — 用户要求 Edit Workout 系列页面都不要标题
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isCreating ? Text("Create a routine") : Text(""))
            .toolbar {
                if isCreating {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.tint(MasoColor.text)
                    }
                }
                // 拥有的计划 (Today/Saved): 右上角显眼的"分享"按钮 (一键分享 routine 图 + QR),
                // 左上角直接摆删除按钮 (owner 拍板: 原 "…" overflow 里只有一个 Delete, 多一跳没意义;
                // 破坏性动作有 confirmDelete 二次确认兜底).
                if onAddToSaved == nil && !isCreating {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            handleSharePlan()
                        } label: {
                            ShareIcon()
                        }
                        .accessibilityLabel(NSLocalizedString("Share plan", comment: ""))
                        if usesParentNavigation {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(NSLocalizedString("Delete Plan", comment: ""))
                        }
                    }
                    if !usesParentNavigation {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(NSLocalizedString("Delete Plan", comment: ""))
                        }
                    }
                }
                // Tab 2 browse 预览: 主操作 = body 的 "★ Add to my plans" 大 CTA, 顶栏不再放 "+" (去重).
                // 顶栏 Start 胶囊也删了 — body 大 CTA 够显眼; iOS sheet 自带下拉关闭, 不需要 Done.
            }
            .sheet(isPresented: $showsShare) {
                FullPageShareSheet(title: NSLocalizedString("Share routines", comment: ""), surface: "routine", imageOnly: true) {
                    RoutineShareCard(plan: draft, exById: data.exById,
                        qrPayload: PlanShareCodec.appStoreDataLink(for: [draft]) ?? MasoLinks.appStore)
                }
            }
            .alert("Delete plan?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    // 先关 sheet 再删 — 否则 sheet 关闭时引用的 initialPlan 已经被 data store 删了,
                    // 中间过渡会闪一下黑色 placeholder. 顺序: dismiss → 下一个 runloop tick 删.
                    dismiss()
                    let planId = draft.id
                    DispatchQueue.main.async {
                        data.deletePlan(planId)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your training history will be kept.")
            }
            // 右滑 / contextMenu 删除 step 的二次确认 alert
            .alert("Delete exercise?", isPresented: Binding(
                get: { pendingDeleteStepId != nil },
                set: { if !$0 { pendingDeleteStepId = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteStepId,
                       let idx = draft.steps.firstIndex(where: { $0.id == id }) {
                        draft.steps.remove(at: idx)
                        commit()
                    }
                    pendingDeleteStepId = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteStepId = nil }
            } message: {
                Text("This only removes the exercise from this plan, not from your library.")
            }
            // 子页面 nav 目的地: 编辑某个 step
            .sheet(isPresented: Binding(get: { editingStepID != nil }, set: { if !$0 { editingStepID = nil } })) {
                AppNavigationStack {
                if let stepId = editingStepID, let idx = draft.steps.firstIndex(where: { $0.id == stepId }),
                   let ex = data.exById[draft.steps[idx].exerciseId] {
                    EditStepView(
                        exercise: ex,
                        step: $draft.steps[idx],
                        onDelete: {
                            draft.steps.remove(at: idx)
                            commit()
                        },
                        // Replace 入口挪进编辑页顶部 (跟播放列表 Edit sheet 一致): 点后弹回列表并弹替换 picker.
                        onReplace: {
                            editingStepID = nil   // Close parameter sheet before replacement
                            stepToReplaceId = stepId           // 再弹 ExercisePickerSheet
                        }
                    )
                    .onChange(of: draft.steps[safe: idx]) { _, _ in commit() }
                }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddPicker) {
                // 添加动作 = 多选勾选 (跟 Free Workout 一致), 一次可选多个 → 底部 "Add (N)" 一并加入.
                ExercisePickerSheet(
                    onPick: { _ in },   // multiSelect 模式不走单选回调
                    multiSelect: true,
                    onPickMultiple: { exercises in
                        for (i, ex) in exercises.enumerated() {
                            // R3: 参数按"全局同步开/关"取默认 — 开则采用已有 routine 里该动作的参数,
                            // 否则从该动作最近一次记录回填 (取代过去硬编码的 3 组 / 10 次 / 90s).
                            draft.steps.append(data.makeSeededStep(
                                for: ex,
                                stepId: "step-\(ex.id)-\(Int(Date().timeIntervalSince1970))-\(i)"
                            ))
                        }
                        commit()
                        showAddPicker = false
                    },
                    startTitle: NSLocalizedString("Add", comment: "add selected exercises CTA")
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // 替换动作 sheet — 跟 add 走同款 ExercisePickerSheet, 但 onPick 只替换 exerciseId,
            // 保留 sets/reps/weight 等强度参数. 用 isPresented bool binding 而不是 item, 因为
            // body 已经很大, item: Binding 让编译器 type-check 超时.
            .sheet(isPresented: replaceSheetPresented) {
                ExercisePickerSheet(
                    onPick: handleReplacePick,
                    // 替换: 预选原动作部位 (动作 + 器械留空).
                    initialMuscle: {
                        guard let id = stepToReplaceId,
                              let exId = draft.steps.first(where: { $0.id == id })?.exerciseId,
                              let ex = data.exById[exId] else { return nil }
                        return ex.primaryMuscles.first?.section
                    }(),
                    replacingExerciseId: stepToReplaceId.flatMap { id in
                        draft.steps.first(where: { $0.id == id })?.exerciseId
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // 点 PlanStepRow / Card 图片 → 弹动作详情 (跟其它 5 个列表共用 ExerciseDetailSheet).
            // 整行 tap 仍走 NavigationLink 进 EditStepView (改 sets/reps/weight). 图片是 Button,
            // hit-test 优先级高于 NavigationLink, 不会同时触发.
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                guard !resolvedDefaults else { return }
                draft = data.routinePlanDefaults(draft)
                resolvedDefaults = true
            }
            .tint(MasoColor.text)
    }

    // 把 draft 写回 data store
    private func commit() {
        draft = data.routinePlanDefaults(draft)
        draft.updatedAt = Date()
        if !isCreating { data.updatePlan(draft) }
    }

    /// 替换动作 sheet 的 isPresented binding — 拆出来减轻 body type-check 负担.
    private var replaceSheetPresented: Binding<Bool> {
        Binding(
            get: { stepToReplaceId != nil },
            set: { if !$0 { stepToReplaceId = nil } }
        )
    }

    /// 替换动作完成回调 — ExercisePickerSheet 选了新 ex 后调进来.
    /// PlanStep.exerciseId 是 let, 不能直接改, 用整 step 替换 (保留 sets/reps/weight/duration
    /// 等强度参数, 避免用户调过的负荷被抹).
    private func handleReplacePick(_ newExercise: Exercise) {
        defer { stepToReplaceId = nil }
        guard let id = stepToReplaceId,
              let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let old = draft.steps[idx]
        draft.steps[idx] = PlanStep(
            id: old.id,
            exerciseId: newExercise.id,
            sets: old.sets,
            reps: old.reps,
            weight: newExercise.id == old.exerciseId ? old.weight : nil,
            setReps: old.setReps,
            setWeights: newExercise.id == old.exerciseId ? old.setWeights : nil,
            setDurations: old.setDurations,
            duration: old.duration,
            restBetweenSets: old.restBetweenSets,
            rest: old.rest,
            parameterSuggestions: newExercise.id == old.exerciseId ? old.parameterSuggestions : nil
        )
        draft.steps[idx] = data.suggestingMissingParameters(for: draft.steps[idx])
        commit()
    }

    /// Share — 渲染 RoutineShareCard 分享图 (计划内容 + 品牌 footer + 二合一 QR).
    /// QR = App Store 链接 + 数据锚点: 相机扫照常进商店 (宣传), Masso "从照片导入" 读锚点
    /// 无损还原 (名称+逐组 1:1); 数据过大回落纯商店链 (导入走 OCR). 渲染失败 → alert 兜底.
    private func handleSharePlan() {
        Haptics.tap()
        showsShare = true
    }

    // 顶部信息卡 — 简化版.
    // 之前: BodyHint 左 + WORKOUT kicker + TextField + 2 StatPills 信息密. 用户反馈"信息过多 + TextField 不明显".
    // 现在: TextField 独立一行带明显 input 样式 + BodyHint 单独居中. 信息层级清楚.
    //   - StatPill (exercises/sets count) 移除 — stepList header 已能看出动作数
    //   - WORKOUT kicker 移除 — nav title "Edit Workout" 重复
    /// Portrait stack. The list scrolls above Start. List + Section keeps
    /// native .onMove and .swipeActions. No accessibility identifier here:
    /// putting one on the Form is copied onto the collection view as well.
    private var portraitScrollingForm: some View {
        Form {
            if !isCreating || !draft.steps.isEmpty {
                Section {
                    muscleHeader(side: 224)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                workoutNameField
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            stepListSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, portraitScrollMargin, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(MasoColor.background.ignoresSafeArea())
    }

    /// Button sits under the form, not in a safe-area overlay. An overlay left
    /// Start on top of Leg Curl on the Duo inner portrait sheet.
    private var portraitScrollMargin: CGFloat {
        PlanDetailLayout.needsPortraitScrollClearance(width: windowSize.width, height: windowSize.height) ? 96 : 8
    }

    private var portraitDetailForm: some View {
        VStack(spacing: 0) {
            portraitScrollingForm
            bottomActionBar
        }
        .background(MasoColor.background.ignoresSafeArea())
    }

    /// Duo inner landscape and other wide-short windows. The exercise list is its
    /// own form beside the muscle map, and the CTA sits under that row so the
    /// last exercise can scroll clear of it.
    private func wideDetailForm(size: CGSize) -> some View {
        GeometryReader { geo in
            let offeredWidth = geo.size.width.isFinite && geo.size.width > 1 ? geo.size.width : 1
            let offeredHeight = geo.size.height.isFinite && geo.size.height > 1 ? geo.size.height : 1
            let sidebarCap = min(320, max(1, offeredWidth * 0.45))
            let sidebar = PlanDetailLayout.layoutLength(offeredWidth * 0.38, minimum: 1, maximum: sidebarCap, limit: sidebarCap)
            let muscleSide = PlanDetailLayout.layoutLength(offeredHeight * 0.34, minimum: 1, maximum: min(200, sidebar), limit: sidebar)
            wideColumns(sidebar: sidebar, muscleSide: muscleSide)
        }
    }

    private func wideColumns(sidebar: CGFloat, muscleSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if !isCreating || !draft.steps.isEmpty {
                        muscleHeader(side: muscleSide)
                    }
                    workoutNameField
                }
                .frame(width: sidebar, alignment: .top)
                Form { stepListSection }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 96, for: .scrollContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            bottomActionBar
        }
        .background(MasoColor.background.ignoresSafeArea())
    }

    private var workoutNameField: some View {
        TextField("Workout name", text: Binding(
            get: { draft.name },
            set: { draft.name = $0; commit() }
        ), axis: .vertical)
        .lineLimit(1...3)
        .submitLabel(.done)
        .padding()
        .glassCardBackground()
    }

    private var bottomActionBar: some View {
        bottomAction
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    private func muscleHeader(side: CGFloat) -> some View {
        HStack {
            Spacer(minLength: 0)
            MuscleVisualBlock(muscles: muscles, sideLength: side)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.top, side >= 200 ? -16 : 0)
        .padding(.bottom, 12)
        .accessibilityIdentifier("workout.detail.muscles")
    }

    private var canSaveNewWorkout: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.steps.isEmpty
    }

    @ViewBuilder
    private var bottomAction: some View {
        if isCreating {
            Button {
                guard canSaveNewWorkout else { return }
                draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.updatedAt = Date()
                data.updatePlan(draft)
                Haptics.tap()
                dismiss()
            } label: {
                TrainingCardActionLabel(title: "Save", icon: "plus", accent: MasoColor.accent)
            }
            .buttonStyle(.plain)
            .disabled(!canSaveNewWorkout)
            .opacity(canSaveNewWorkout ? 1 : 0.45)
            .accessibilityIdentifier("workout.create.save")
        } else if let onAddToSaved {
            VStack(spacing: 8) {
                addToPlansCTA(onAddToSaved)
                if let n = classicsDayCount, n > 1 {
                    Text(String(format: NSLocalizedString("Includes %lld training days — Save adds all of them", comment: "classics detail day note"), n))
                        .font(.footnote).foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            startWorkoutCTA
        }
    }

    /// 全宽 "Start workout" 大胶囊 CTA — body 主操作. 跟 toolbar 右上的小 Start 是同一个 action,
    /// 一冗余一隐性: 用户错过 toolbar 也不会错过这个; 已经知道流程的高频用户直接走 toolbar 一步到位.
    private var startWorkoutCTA: some View {
        Button(action: handleStart) {
            TrainingCardActionLabel(title: "Start workout", icon: "play.fill", accent: MasoColor.accent)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start workout")
        .accessibilityIdentifier("workout.start")
    }

    /// Isolated accessibility nodes. They must not wrap the form or the button,
    /// or SwiftUI copies the identifier onto those controls.
    private var detailAccessibilityProbes: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("page.workoutDetail")
                .accessibilityValue("\(Int(windowSize.width))x\(Int(windowSize.height))")
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("workout.detail.planSteps")
                .accessibilityValue(draft.steps.map(\.exerciseId).joined(separator: ","))
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(wideWindow ? "workout.detail.wide" : "workout.detail.stack")
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("workout.detail.list")
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    /// Tab 2 browse / Coach 预览的主 CTA — Save ↔ Saved 书签开关 (跟 AddToPlansButton 同一套
    /// bookmark 语言, coach-tab-design.md §2). 跟 startWorkoutCTA 同视觉规格 (实心 accent 胶囊).
    /// **两态都可点** — action 恒触发, toggle 语义由调用方决定 (已存再点 = unsave, 按钮随 plans 响应式翻回 Save).
    private func addToPlansCTA(_ action: @escaping (Plan) -> Void) -> some View {
        let saved = savedOverride ?? data.isPlanSaved(draft)
        return AddToPlansButton(isSaved: saved, action: { action(draft) })
            .disabled(saved)
            .padding(.top, 4)
    }

    /// 开始训练 — toolbar Start 和 body CTA 都走这. dismiss → 下一 runloop 调 onStart,
    /// 避免 sheet 还在动画时 push 新 sheet 出问题 (PlanPlayer 是 RootView 上的另一个 sheet).
    private func handleStart() {
        Haptics.tap()
        let plan = draft  // 抓快照 — dismiss 后 self 已经销毁, 不能再读 self.draft
        dismiss()
        DispatchQueue.main.async { onStart(plan) }
    }

    /// 右滑删除 step 的二次确认 — 跟 PlansScreen 同模式, 存待删 stepId, alert 弹.
    @ViewBuilder
    private var stepListSection: some View {
        WorkoutExercisesSection(
            items: draft.steps,
            useCardLayout: $useCardLayout,
            emptyTitle: "No exercises yet — tap “Add Exercise” to start",
            onMove: { source, destination in
                draft.steps.move(fromOffsets: source, toOffset: destination)
                commit()
                Haptics.tap()
            },
            onAddExercise: {
                Haptics.tap()
                showAddPicker = true
            }
        ) { step in
            if let exercise = data.exById[step.exerciseId] {
                if useCardLayout {
                    stepEntry(step: step, exercise: exercise)
                } else {
                    stepEntry(step: step, exercise: exercise)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDeleteStepId = step.id } label: {
                                Image(systemName: "trash.fill")
                            }
                            .tint(MasoColor.negative)
                            .accessibilityLabel(NSLocalizedString("Delete", comment: ""))
                            Button { editingStepID = step.id } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(MasoColor.accent)
                            .accessibilityLabel(NSLocalizedString("Edit", comment: ""))
                        }
                }
            }
        }
    }

    /// 单个 step 入口 — list / grid 共用.
    /// ZStack trick: 把 NavigationLink 包 EmptyView 隐到底层(.opacity 0), 自定义 row 显前面.
    /// 这样 List 不会因为 NavigationLink 自动加 disclosure chevron, 视觉干净.
    /// (PlanStepRow 已经自己在右侧加了 chevron — 默认 List chevron + 它自己的 = 重叠.)
    @ViewBuilder
    private func stepEntry(step stp: PlanStep, exercise ex: Exercise) -> some View {
        Group {
            if useCardLayout {
                Button { detailExercise = ex } label: {
                    WorkoutExerciseGridCard(detailLine: planStepDetailLine(stp), exercise: ex, onTapImage: { detailExercise = ex }, parameterStep: stp)
                }
                .buttonStyle(.plain)
            } else {
                Button { detailExercise = ex } label: {
                    WorkoutExerciseRow(detailLine: planStepDetailLine(stp), exercise: ex, onTapImage: { detailExercise = ex }, parameterStep: stp)
                }
            }
        }
        .accessibilityIdentifier(stp.id == draft.steps.last?.id ? "workout.exercise.last" : "workout.exercise.\(stp.exerciseId)")
        .contextMenu {
            Button { editingStepID = stp.id } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            Button { stepToReplaceId = stp.id } label: { Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath") }
            // 用 Label { Text } icon: { Image.foregroundStyle(.white) } 拆 init,
            // 强制 icon 走白色而不是系统 tint (accent 绿). label 文字保留默认.
            if canMoveUp(stp.id) {
                Button { moveStep(stp.id, by: -1) } label: {
                    Label {
                        Text("Move up")
                    } icon: {
                        Image(systemName: "arrow.up").foregroundStyle(.white)
                    }
                }
            }
            if canMoveDown(stp.id) {
                Button { moveStep(stp.id, by: 1) } label: {
                    Label {
                        Text("Move down")
                    } icon: {
                        Image(systemName: "arrow.down").foregroundStyle(.white)
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                pendingDeleteStepId = stp.id  // 走二次确认 alert, 跟右滑删除同路径
            } label: {
                // icon 统一强制白色 (跟 Move up/Down 一致). text 跟随 destructive role 红色.
                Label {
                    Text("Delete")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
        }
    }

    /// Step 上下移 + 删除 — 给 contextMenu 用. 改完直接 commit() 持久化.
    private func canMoveUp(_ id: String) -> Bool {
        guard let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return false }
        return idx > 0
    }
    private func canMoveDown(_ id: String) -> Bool {
        guard let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return false }
        return idx < draft.steps.count - 1
    }
    private func moveStep(_ id: String, by delta: Int) {
        guard let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0, newIdx < draft.steps.count else { return }
        let step = draft.steps.remove(at: idx)
        draft.steps.insert(step, at: newIdx)
        commit()
        Haptics.tap()
    }
    // (P3: 删了死代码 removeStep — 删除都走 pendingDeleteStepId 二次确认路径, 这个无引用.)


}


/// 把一个 step 的 sets / reps / weight / duration 拼成一行短文案
/// (row 和 card 都用同一份格式, 一处改两处生效)
// 单个 step 行 — 动作图 + 名字 + (sets × reps × weight 或 duration) + chevron
// MARK: - EditStepView — 改一个动作的 sets / reps / weight / rest

private struct EditStepView: View {
    let exercise: Exercise
    @Binding var step: PlanStep
    let onDelete: () -> Void
    var onReplace: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Form {
            paramSection
        }
        .scrollContentBackground(.hidden)
        .background(MasoColor.background)
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .tint(MasoColor.text)
        .alert("Remove this exercise?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(exercise.displayName)” will be removed from this workout. Past records are kept.")
        }
    }

    private var paramSection: some View {
        VStack(spacing: 12) {
            NativeIntegerParameterRow(title: "Sets", value: Binding(get: { step.sets }, set: { step.sets = $0; step.confirmParameter("sets") }), range: 1...10, isSuggested: step.isSuggested("sets"))
            Divider()
            if exercise.category == .strength {
                NativeIntegerParameterRow(title: "Reps", value: Binding(get: { step.reps ?? 0 }, set: { step.reps = $0; step.confirmParameter("reps") }), range: 0...50, isSuggested: step.isSuggested("reps"))
                Divider()
                NativeWeightParameterRow(title: ExerciseWeightReference.perDumbbell(exercise) ? "Weight per dumbbell" : "Weight", kilograms: Binding(get: { step.weight ?? 0 }, set: { step.weight = $0; step.confirmParameter("weight") }), isSuggested: step.isSuggested("weight"), isUnknown: step.weight == nil, allowsCalibration: ExerciseWeightReference.expectsLoad(exercise))
                CrossExerciseSuggestionBasis(suggestion: step.parameterSuggestions?["weight"])
            } else {
                NativeIntegerParameterRow(title: "Duration", value: Binding(get: { step.duration ?? 5 }, set: { step.duration = $0; step.confirmParameter("duration") }), range: 5...600, step: 5, suffix: "s", isSuggested: step.isSuggested("duration"))
            }
        }.font(.body).padding(MasoMetrics.cardPadding)
         .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }


}

// MARK: - ExercisePickerSheet — 选一个动作加进 plan
// 不再 private — PlanPlayer 的"替换动作"也复用同一个 sheet (训练中边练边换).

struct ExercisePickerSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void
    /// 选择页默认点整行确认；详情仅从独立 i 入口查看。
    var directPick: Bool = true
    /// 替换流程: 用原动作的"部位"预选 Part chip (movement + equipment 留空), 让用户落在
    /// "换个练同一部位的动作"的状态. nil = 不预选.
    var initialMuscle: MuscleGroup? = nil
    /// Concrete source ID gives replacements their training role and equipment context.
    var replacingExerciseId: String? = nil
    /// 多选模式 (自由训练): 点行切换勾选, 底部 Start CTA 把整组动作通过 onPickMultiple 交回.
    /// 单选默认点行直接选中；配置场景再打开该动作的参数页。
    var multiSelect: Bool = false
    var onPickMultiple: (([Exercise]) -> Void)? = nil
    /// multiSelect 底部 CTA 文案 (例 "Start workout"). nil → "Add".
    var startTitle: String? = nil
    var pickerTitle: LocalizedStringKey = ""
    var onFinishWorkout: (() -> Void)? = nil
    var workoutSummary: String? = nil
    var onPickConfigured: ((Exercise, PlanStep) -> Void)? = nil
    @State private var configuringExercise: Exercise? = nil

    @State private var query: String = ""
    /// 顶层 section 筛选 (nil = 全部). 6 个: chest/back/shoulders/arms/core/legs.
    @State private var muscleFilter: MuscleGroup? = nil
    /// 器械筛选 (nil = 不限). "other" + None 都归到 "other".
    @State private var equipmentFilter: String? = nil
    /// 动作家族筛选 (Press / Row / Fly / Curl / Dip …). nil = 全部.
    @State private var movementFilter: MovementFacet? = nil
    /// 已选动作 id (multiSelect 用; 单选模式忽略).
    @State private var selectedIds: Set<String> = []
    /// 右侧 i 查看详情，与整行选择热区分开。
    @State private var detailExercise: Exercise? = nil
    /// 搜索空结果时点"添加自己的动作" → 弹 CustomExerciseFormSheet (用当前搜索词预填名字).
    @State private var customFormOpen: Bool = false
    /// 当前展开的"变种组" key (= ExerciseGroup.id). 一次只展开一组.
    @State private var expandedGroupKey: String? = nil
    /// initialMuscle 只灌一次, 避免每次重绘覆盖用户后续操作.
    @State private var didSeedInitial: Bool = false

    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    // 注: equipment 列表 + display name 提到 Exercise model (Exercise.knownEquipments /
    // Exercise.equipmentDisplayName), 让 Library Browser / Quick workout / Plans picker 共用一份.

    /// filter 应用 helper — 同一逻辑用在 `filtered` 和各 availability 计算上.
    /// 传 nil 表示该维度不限制. 部位 / 器械 / 文本三者都是 AND 关系.
    private func applyFilters(
        _ arr: [Exercise],
        muscle: MuscleGroup?,
        equipment: String?,
        movement: MovementFacet? = nil,
        text: String?
    ) -> [Exercise] {
        var result = arr
        if let m = muscle {
            // 严格筛选 — 只匹配 primaryMuscles (主练肌), 不含 secondary/协同肌.
            // 例: deadlift primaryMuscles = [lowerBack], 选 "core" 时不会出现 (即使它 secondary 含 core).
            result = result.filter { ex in
                ex.primaryMuscles.contains(where: { $0.section == m })
            }
        }
        if let eq = equipment {
            result = result.filter { ex in
                if eq == "other" {
                    return ex.equipment == "other" || ex.equipment == nil
                }
                return ex.equipment == eq
            }
        }
        if let mv = movement {
            result = result.filter { $0.movementFacet == mv }
        }
        let words = exerciseSearchWords(text ?? "")
        if !words.isEmpty {
            // 多维分词搜索 — 动作家族 / 部位 / 器械 / 变体 任意组合.
            result = result.filter { $0.matchesSearch(words) }
        }
        return result
    }

    /// Browsing is curated; search and the explicit complete scope reach all IDs.
    private var sourceExercises: [Exercise] {
        data.visibleExerciseLibrary
    }

    private var filtered: [Exercise] {
        let arr = applyFilters(
            sourceExercises,
            muscle: muscleFilter,
            equipment: equipmentFilter,
            movement: movementFilter,
            text: query
        )
        // 收藏置顶 — 在 filter 之后排序, 让收藏的动作在当前 filter 结果里排最前.
        // 不截断 (曾经 prefix(200)): List 是 lazy 的; 截断会把字母序靠后的动作和自创动作静默切掉.
        return ExerciseSelectionPolicy.shared.sorted(arr, favoriteIDs: data.canonicalFavoriteExerciseIDs,
                                                     recentIDs: data.recentExerciseIDs)
    }

    /// filtered 按"基础名"折叠成 group. Picker 列表迭代这个, 而不是 flat filtered.
    /// "Bench Press" + "Bench Press (Machine)" + "Bench Press (Dumbbell)" → 1 个 group.
    /// "Speed Bench Press" 独立成自己的 group (它没括号, base = 自身).
    private var filteredGroups: [ExerciseGroup] {
        ExerciseGrouping.group(filtered,
            preferredExerciseIDs: ExerciseGrouping.exactSearchIDs(in: filtered, query: query), fullLibrary: data.visibleExerciseLibrary,
            previewLibrary: previewExercises, groupByName: true).sorted { a, b in
                if a.entryTitle == b.entryTitle { return a.id < b.id }
                return ExerciseNameSort.precedes(a.entryTitle, b.entryTitle)
            }
    }

    private var previewExercises: [Exercise] {
        applyFilters(data.visibleExerciseLibrary, muscle: muscleFilter, equipment: equipmentFilter,
                     movement: movementFilter, text: query)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var replacementRecommendations: [Exercise] {
        guard trimmedQuery.isEmpty, equipmentFilter == nil, movementFilter == nil,
              let id = replacingExerciseId, let original = data.exById[id] else { return [] }
        return ExerciseSelectionPolicy.shared.replacementCandidates(
            for: original, from: data.visibleExerciseLibrary, settings: data.settings,
            recentIDs: data.recentExerciseIDs, limit: 6)
    }

    private var personalShortcutExercises: [Exercise] {
        let ids = data.canonicalFavoriteExerciseIDs.union(data.recentExerciseIDs)
        return filtered.filter { ids.contains($0.id) }
    }

    // MARK: - filter availability — 两维 (部位 / 器械) 互相 narrow 时, 让用户知道哪些选项当前可选

    /// 当前 muscle/text filter (不算 equipment) 下还有动作的 equipment set.
    /// 用菜单项 "dim disabled" 视觉提示 — 让用户知道选了某 muscle 后哪些 equipment 是空集.
    private var availableEquipments: Set<String> {
        let arr = applyFilters(sourceExercises, muscle: muscleFilter, equipment: nil, movement: movementFilter, text: query)
        var out: Set<String> = []
        for ex in arr {
            // nil + "other" 都映射到 "other" chip
            out.insert(ex.equipment == nil ? "other" : ex.equipment!)
        }
        return out
    }

    /// 当前 equipment/text filter (不算 muscle) 下还有动作的 muscle section set.
    /// 用 primaryMuscles 跟 filter 实际行为对齐 — 不然选项显示"有"但点了 0 结果.
    private var availableMuscles: Set<MuscleGroup> {
        let arr = applyFilters(sourceExercises, muscle: nil, equipment: equipmentFilter, movement: movementFilter, text: query)
        var out: Set<MuscleGroup> = []
        for ex in arr {
            for sec in Self.muscleSections {
                if ex.primaryMuscles.contains(where: { $0.section == sec }) {
                    out.insert(sec)
                }
            }
        }
        return out
    }

    /// 给定肌群 section 下当前 (equipment + text) 还有动作的 movement family (有序) — 肌群子菜单用.
    private func movementsForSection(_ sec: MuscleGroup) -> [MovementFacet] {
        let arr = applyFilters(sourceExercises, muscle: sec, equipment: equipmentFilter, movement: nil, text: query)
        var set = Set<MovementFacet>()
        for ex in arr { if let mf = ex.movementFacet { set.insert(mf) } }
        return MovementFacet.ordered.filter { set.contains($0) }
    }

    var body: some View {
        AppNavigationStack {
            VStack(spacing: 0) {
                // 搜索 + Muscle / Equipment 筛选 — 用全 app 共享的 ExerciseSearchFilterBar
                // (跟 Exercises 子页同一组件, 钉在列表上方, 调一处两边都变).
                ExerciseSearchFilterBar(
                    query: $query,
                    muscleFilter: $muscleFilter,
                    movementFilter: $movementFilter,
                    equipmentFilter: $equipmentFilter,
                    muscleSections: Self.muscleSections,
                    availableMuscles: availableMuscles,
                    movementsFor: movementsForSection,
                    availableEquipments: availableEquipments
                )
                .accessibilityIdentifier("exercise.library.filters")
                if let workoutSummary {
                    Text(workoutSummary).font(.subheadline).foregroundStyle(MasoColor.textDim)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                exerciseList()

                // CTA 默认不显示, 选了动作才出现.
                if multiSelect && !selectedIds.isEmpty {
                    startBar
                }
            }
            .animation(.easeOut(duration: 0.22), value: muscleFilter)
            .animation(.easeOut(duration: 0.22), value: equipmentFilter)
            .animation(.easeOut(duration: 0.22), value: movementFilter)
            .animation(.easeOut(duration: 0.2), value: selectedIds.isEmpty)
            .sheet(item: $configuringExercise) { ex in
                OpenWorkoutExerciseSetup(exercise: ex) { step in
                    onPickConfigured?(ex, step)
                    dismiss()
                }
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
                .presentationDragIndicator(.visible)
            }
            // 搜索空 → "添加自己的动作" 表单 (预填搜索词). 创建后 multiSelect 自动勾选这个新动作.
            .sheet(isPresented: $customFormOpen) {
                CustomExerciseFormSheet(
                    initialName: trimmedQuery,
                    onCreated: { ex in if multiSelect { selectedIds.insert(ex.id) } }
                )
                .presentationDragIndicator(.visible)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // 小众库标题 — 让用户一眼知道"我在哪个库". 主库时不显示标题 (跟之前一致).
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search"))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                if let onFinishWorkout {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End this workout") { dismiss(); onFinishWorkout() }
                            .accessibilityIdentifier("open-workout.finish")
                    }
                }
            }
            .navigationTitle(pickerTitle)
            .toolbar {
                if multiSelect || onPickConfigured != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .tint(MasoColor.text)
            // initialMuscle (替换流程) 只灌一次, 之后用户操作不被覆盖.
            .onAppear {
                if !didSeedInitial {
                    didSeedInitial = true
                    if let m = initialMuscle { muscleFilter = m }
                }
            }
        }
    }

    /// multiSelect 底部 Start CTA (自由训练用) — 只在选了动作后才渲染 (caller 控制).
    @ViewBuilder
    private var startBar: some View {
        let picked = selectedIds.compactMap { data.exById[$0] }
        let base = startTitle ?? NSLocalizedString("Start", comment: "")
        Button(action: {
            guard !picked.isEmpty else { return }
            onPickMultiple?(picked)
            dismiss()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 14, weight: .heavy))
                Text(String(format: "%@ (%d)", base, picked.count))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(MasoColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.vertical, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 共用 exercise list

    /// Picker 单行 — canonical 或 variant 共用. 区别:
    ///   - canonical: tap 主体选中；i 单独打开详情；变种 disclosure 独立操作。
    ///   - variant: 行左侧多一道竖线缩进 + 一个 equipment SF Symbol (machine.fill / dumbbell.fill ...).
    ///             名字省略 base 前缀, 只显括号内的 "(Machine)" / "(Dumbbell, Decline)".
    @ViewBuilder
    private func exercisePickerRow(exercise ex: Exercise, isVariant: Bool, group: ExerciseGroup) -> some View {
        // 共用 GroupedExerciseRow — 跟 Exercise Library 同一份展示/收折逻辑. 这里只注入 picker 行为.
        GroupedExerciseRow(
            exercise: ex,
            isVariant: isVariant,
            group: group,
            isExpanded: expandedGroupKey == group.id,
            showDisclosure: !group.isSingleton,
            showVariantCategoryLabel: false,
            highlighted: multiSelect && selectedIds.contains(ex.id),
            selectionAtLeading: multiSelect,
            trailing: {
                if multiSelect {
                    Button { selectExercise(ex) } label: {
                        Image(systemName: selectedIds.contains(ex.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selectedIds.contains(ex.id) ? MasoColor.accent : MasoColor.textFaint.opacity(0.5))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(ex.displayName))
                    .accessibilityAddTraits(selectedIds.contains(ex.id) ? [.isSelected] : [])
                }
            },
            onTap: { selectExercise(ex) },
            onShowDetail: { detailExercise = ex },
            onToggleExpand: {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedGroupKey = (expandedGroupKey == group.id) ? nil : group.id
                }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                data.toggleFavorite(ex.id)
                Haptics.tap()
            } label: {
                Image(systemName: data.isFavorite(ex.id) ? "pin.slash.fill" : "pin.fill")
            }
            .tint(MasoColor.accent)
            .accessibilityLabel(NSLocalizedString(data.isFavorite(ex.id) ? "Unpin" : "Pin to top", comment: ""))
        }
    }

    private func selectExercise(_ exercise: Exercise) {
        if multiSelect {
            if selectedIds.contains(exercise.id) { selectedIds.remove(exercise.id) }
            else { selectedIds.insert(exercise.id) }
            Haptics.tap()
        } else if directPick {
            if onPickConfigured != nil { configuringExercise = exercise }
            else { onPick(exercise); dismiss() }
        } else {
            detailExercise = exercise
        }
    }


    @ViewBuilder
    private func exerciseList() -> some View {
        // List + 原生 .swipeActions — 替换自制 SwipeableRow.
        // 自制版跟 ScrollView 的 vertical pan 抢手势 → 上下滑动失效.
        List {
            if !replacementRecommendations.isEmpty {
                Section("Suggested replacements") {
                    ForEach(replacementRecommendations, id: \.id) { exercise in
                        let group = ExerciseGroup(baseName: exercise.name, canonical: exercise, variants: [])
                        exercisePickerRow(exercise: exercise, isVariant: true, group: group)
                    }
                }
            }
            if trimmedQuery.isEmpty, !personalShortcutExercises.isEmpty {
                NavigationLink {
                    ExerciseFamilyVersionsPage(title: NSLocalizedString("Pinned and recent", comment: ""),
                                               exercises: personalShortcutExercises) { exercise in
                        let group = ExerciseGroup(baseName: exercise.name, canonical: exercise, variants: [])
                        exercisePickerRow(exercise: exercise, isVariant: true, group: group)
                    }
                } label: {
                    Label("Pinned and recent", systemImage: "pin").foregroundStyle(MasoColor.text)
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("exercise.personal")
            }
            ForEach(filteredGroups) { group in
                // Canonical 行 — 折叠态唯一可见的一行. 跟旧 row 视觉一致 + 末尾多一个 "+N variants"
                // disclosure 胶囊 (仅有变种时). tap 主体选中；i 查看详情；disclosure 展开组。
                exercisePickerRow(
                    exercise: group.canonical,
                    isVariant: false,
                    group: group
                )

                // 展开时渲染变种 — 拆 "Variation"(动作) / "Equipment"(器械) 两段, 各自带小节头;
                // 每个变种作为独立 List row, 可独立 swipe pin, 缩进区分层级.
                if !group.isSingleton, expandedGroupKey == group.id {
                    groupedVariantSections(for: group, showAll: true, onCollapse: { expandedGroupKey = nil }) { variant in
                        exercisePickerRow(
                            exercise: variant,
                            isVariant: true,
                            group: group
                        )
                    }
                }
            }
            if filtered.isEmpty {
                VStack(spacing: 16) {
                    Text(NSLocalizedString("No exercises match your search", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                    // 找不到 → 一键创建自己的动作 (带搜索词预填名字). 主库 / 小众库都给这个入口.
                    Button(action: { customFormOpen = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .heavy))
                            Text(trimmedQuery.isEmpty
                                 ? NSLocalizedString("Add your own exercise", comment: "")
                                 : String(format: NSLocalizedString("Add “%@” as your own", comment: "create custom exercise from search"), trimmedQuery))
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(MasoColor.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(MasoColor.accent.opacity(0.14))
                        .overlay(Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }


        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        // P2-10: 任何 filter / 搜索 / 库切换变化 → 收起手风琴, 避免残留某组展开态 (尤其 orphan
        // group 的 id 含 filtered canonical, filter 变了 id 也变, 旧 expandedGroupKey 成孤儿).
        .onChange(of: query) { _, _ in expandedGroupKey = nil }
        .onChange(of: equipmentFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: muscleFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: movementFilter) { _, _ in expandedGroupKey = nil }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

struct OpenWorkoutExerciseSetup: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let onStart: (PlanStep) -> Void
    @State private var sets = 3
    @State private var reps = 10
    @State private var weight: Double = 0
    @State private var duration = 30
    @State private var seeded = false
    @State private var seed: PlanStep? = nil
    @State private var edited: Set<String> = []
    private func suggested(_ field: String) -> Bool { !edited.contains(field) && seed?.isSuggested(field) == true }
    private func input<T>(_ field: String, _ binding: Binding<T>) -> Binding<T> {
        Binding(get: { binding.wrappedValue }, set: { edited.insert(field); binding.wrappedValue = $0 })
    }

    var body: some View {
        AppNavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ExerciseMediaHero(exercise: exercise, width: geometry.size.width)
                        VStack(alignment: .leading, spacing: 16) {
                            Text(exercise.displayName).font(.title2.bold()).foregroundStyle(.primary)
                            VStack(spacing: 12) {
                                NativeIntegerParameterRow(title: "Sets", value: input("sets", $sets), range: 1...10, isSuggested: suggested("sets"))
                                Divider()
                                if exercise.category == .strength {
                                    NativeIntegerParameterRow(title: "Reps", value: input("reps", $reps), range: 1...100, isSuggested: suggested("reps"))
                                    Divider()
                                    NativeWeightParameterRow(title: ExerciseWeightReference.perDumbbell(exercise) ? "Weight per dumbbell" : "Weight", kilograms: Binding(get: { data.settings.weightUnit.toKg(weight) }, set: { edited.insert("weight"); weight = data.settings.weightUnit.fromKg($0) }), isSuggested: suggested("weight"), isUnknown: !edited.contains("weight") && seed?.weight == nil, allowsCalibration: ExerciseWeightReference.expectsLoad(exercise))
                                    CrossExerciseSuggestionBasis(suggestion: edited.contains("weight") ? nil : seed?.parameterSuggestions?["weight"])
                                } else {
                                    NativeIntegerParameterRow(title: "Duration", value: input("duration", $duration), range: 5...3600, step: 5, suffix: "s", isSuggested: suggested("duration"))
                                }
                            }.padding(MasoMetrics.cardPadding)
                             .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                        }.padding(.horizontal, MasoMetrics.pagePaddingHorizontal).padding(.bottom, 20)
                    }
                }.ignoresSafeArea(edges: .top)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .appUnobstructedMediaHeader()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Start workout", icon: "play.fill") {
                    var step = seed ?? data.makeSeededStep(for: exercise, stepId: UUID().uuidString)
                    for field in edited { step.confirmParameter(field) }
                    if edited.contains("sets") { step.sets = sets }
                    if edited.contains("reps") { step.reps = reps }
                    if edited.contains("weight") { step.weight = data.settings.weightUnit.toKg(weight) }
                    if edited.contains("duration") { step.duration = duration }
                    onStart(step)
                }.disabled(!weight.isFinite || weight < 0).padding(16)
            }
        }
        .onChange(of: reps) { _, value in
            guard edited.contains("reps"), !edited.contains("weight"), var step = seed,
                  step.weight == nil || step.parameterSuggestions?["weight"]?.isCrossExerciseEstimate == true else { return }
            step.reps = value; step.confirmParameter("reps")
            step = data.suggestingMissingParameters(for: step)
            seed = step; weight = data.settings.weightUnit.fromKg(step.weight ?? 0)
        }
        .onAppear {
            guard !seeded else { return }; seeded = true
            let step = data.makeSeededStep(for: exercise, stepId: UUID().uuidString)
            seed = step; sets = step.sets; reps = step.reps ?? 10
            weight = data.settings.weightUnit.fromKg(step.weight ?? 0)
            duration = step.duration ?? 30
        }
    }
}
