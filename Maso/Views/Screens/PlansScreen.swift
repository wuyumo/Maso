import SwiftUI

// 我的训练 — plan 列表页 + 编辑入口
//
// 行为变化:
//   - 点行 → 打开 PlanDetailSheet
//   - sheet 内: 改 plan 名 / 改每个动作的 sets/reps/weight/rest / 删除动作 / 添加动作
//   - "开始训练" 按钮启动播放
//
// 编辑统统是 in-place 实时存:
//   - 改任一字段, 立刻 data.updatePlan(draft); 不需要"保存"按钮
//   - 关 sheet 不会丢东西; 跟 iOS 原生 Reminders / Notes 的编辑感觉一致
struct PlansScreen: View {
    @Environment(DataStore.self) private var data
    let onStart: (Plan) -> Void
    /// 新建训练 — 由 RootView 注入, 走 paywall gating + 共享的 sheet 容器
    let onNewPlan: () -> Void

    @State private var selectedPlan: Plan?
    @State private var paywallPresented: Bool = false
    /// 右滑删除前的二次确认 — 存待删 plan, alert 弹出. 用户确认才真删.
    @State private var pendingDeletePlanId: String? = nil

    var body: some View {
        // List 替代 ScrollView+VStack — 一举三得: 原生 .onMove 拖拽排序 + .swipeActions 右滑删除
        // + 清掉 List 默认样式后视觉跟原 VStack 几乎一致.
        List {
            // Pro 展示位 — Pro 用户隐藏
            if !data.settings.isPro {
                ProBanner { paywallPresented = true }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 28, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            // 标题行 — Plans 标题 + 右侧 + 按钮同一行
            HStack(spacing: 12) {
                Text("Plans")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Spacer()
                Button(action: onNewPlan) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .frame(width: 34, height: 34)
                        .background(MasoColor.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New workout")
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: data.settings.isPro ? MasoMetrics.pagePaddingTop : 0, leading: 0, bottom: 16, trailing: 0))
            .listRowBackground(Color.clear)

            // 计划列表 — .onMove 长按拖拽; .swipeActions 右滑删除 + alert 二次确认
            ForEach(data.plans) { plan in
                PlanRow(
                    plan: plan,
                    exById: data.exById,
                    onTap: { selectedPlan = plan },
                    onStart: { onStart(plan) },
                    onDelete: { pendingDeletePlanId = plan.id }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Delete — 红底; Edit — accent 绿 (Maso brand). 用 .tint 显式指定颜色,
                    // 否则被全 app 全局 .tint(MasoColor.text) 白色覆盖.
                    // allowsFullSwipe=false 防 full-swipe 直接删, 强制 tap → 再 confirm.
                    Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                        pendingDeletePlanId = plan.id
                    }
                    .tint(.red)
                    Button(NSLocalizedString("Edit", comment: "")) {
                        selectedPlan = plan  // 跟整行 tap 同流程, 弹 PlanDetailSheet
                    }
                    .tint(MasoColor.accent)
                }
            }
            .onMove { source, destination in
                data.reorderPlans(from: source, to: destination)
                Haptics.tap()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
        .contentMargins(.bottom, MasoMetrics.pageBottomInset, for: .scrollContent)
        .background(MasoColor.background.ignoresSafeArea())
        .alert("Delete plan?", isPresented: Binding(
            get: { pendingDeletePlanId != nil },
            set: { if !$0 { pendingDeletePlanId = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeletePlanId {
                    data.deletePlan(id)
                }
                pendingDeletePlanId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletePlanId = nil }
        } message: {
            Text("Your training history will be kept.")
        }
        .sheet(item: $selectedPlan) { plan in
            PlanDetailSheet(
                initialPlan: plan,
                onStart: { p in
                    selectedPlan = nil
                    DispatchQueue.main.async { onStart(p) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
        }
    }
}

// MARK: - ProBanner — 第一个 Tab 顶部的付费展示位
//
// 设计思路 (参考 Strava / Hevy / Apple 自家 App 顶部的 promotional cell):
//   - 整张可点的卡片, 视觉上跟普通 PlanRow 明显区分:
//     · accent 绿色细描边
//     · 内嵌一个 accent 色块 (装着 Maso M, 像个小 logo 卡)
//     · 顶部 radial 微辉光, 制造 premium 感
//   - 信息层次清楚:
//     · kicker "MASO PRO" 上方提示 (accent 绿, 小字, 大字距)
//     · 主标题 "Unlock everything" (黑色大字)
//     · 副标题 1 行总结主要价值 (淡灰)
//     · 右侧价格锚点 "from $2.50/mo" (绿色, 强调便宜)
//   - Pro 用户看不到这张卡 — Plans 顶部直接给 title
private struct ProBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 跟 Settings 页面的 logo 完全一致 — 40×40 MasoMarkIcon, accent 色, 无 shadow.
                // 让 brand 在两个页面上呈现规格一致, 不再因为"banner 大点小点"出现两种规格.
                MasoMarkIcon(color: MasoColor.accent)
                    .frame(width: 40, height: 40)

                // 中间文字栈 — kicker 行把"MASO PRO"和"FROM $2.50/mo"并排放, 节省纵向空间
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("MASO PRO")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                        Circle()
                            .fill(MasoColor.accent.opacity(0.6))
                            .frame(width: 3, height: 3)
                        Text("FROM $2.50/MO")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(MasoColor.accent)
                    }
                    Text("Unlock everything")
                        // 统一所有卡片标题为 17pt bold (跟 WorkoutCard / PlanRow 对齐, iOS HIG Headline)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                    Text("Unlimited plans · Full history · Custom moves")
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右侧 — 仅一个 chevron, 不再占文字宽度
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(MasoColor.accent)
            }
            .padding(MasoMetrics.cardPadding - 2)
            .background(
                ZStack {
                    MasoColor.surface
                    // 顶左微辉光, 让卡片有"高级感", 不是死的色块
                    RadialGradient(
                        colors: [MasoColor.accent.opacity(0.20), .clear],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 240
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.accent.opacity(0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan list row

private struct PlanRow: View {
    let plan: Plan
    let exById: [String: Exercise]
    let onTap: () -> Void
    /// 圆形播放按钮独立 action — tap 圆按钮 = 启动训练 (绕过 detail sheet).
    /// 跟整卡 tap (进 detail) 分开, 让"快速开练" 跟"编辑/查看" 两个意图清楚.
    let onStart: () -> Void
    /// "请求删除" callback — parent (PlansScreen) 接管二次确认 alert, 跟右滑删除走同一路径.
    /// PlanRow 自己不再 own confirm state.
    let onDelete: () -> Void

    private var muscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for s in plan.steps {
            guard let ex = exById[s.exerciseId] else { continue }
            for m in ex.muscleGroups where seen.insert(m).inserted {
                out.append(m)
            }
        }
        return out
    }

    var body: some View {
        // 统一布局 (跟 History SessionCard 同款):
        //   行1: plan name + 右箭头 (tap 进 detail)
        //   行2: exercises · sets meta
        //   行3: BodyHint 居中 + 右下角圆形播放按钮 (tap 启动训练)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(plan.name)
                    // 16pt bold — 跟 History tab SessionCard 一致, 紧凑列表标题.
                    // Today WorkoutCard 保留 20pt (hero 卡片凸显). 超长走默认 truncationMode .tail.
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            // 字号对齐 History SessionCard 的 subtitle: 12pt monospaced
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            // anatomy + 右下角播放按钮 同一行 (BodyHint 居中, button 绝对定位右下)
            ZStack(alignment: .bottomTrailing) {
                HStack {
                    Spacer()
                    BodyHint(
                        muscles: muscles,
                        height: 90,
                        region: detectBodyRegion(muscles)
                    )
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

                Button(action: onStart) {
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
                .accessibilityLabel("Start Workout")
            }
            .padding(.top, 4)
        }
        .padding(MasoMetrics.rowPaddingH)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // 长按整卡 → 删除菜单. parent (PlansScreen) 接管 confirm — 跟右滑删除走同一 alert.
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label {
                    Text("Delete Plan")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - PlanDetailSheet — 可编辑版 (RootView 也用它做新建)

struct PlanDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let initialPlan: Plan
    let onStart: (Plan) -> Void

    @State private var draft: Plan
    @State private var showAddPicker: Bool = false
    /// 删除整个 plan 的确认 alert. 走 sheet 的"…"菜单触发.
    @State private var confirmDelete: Bool = false
    /// 点 step 行 / 卡片图片缩略图弹的动作详情. tap 文字区域走 NavigationLink 进编辑页.
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 step / contextMenu Delete 的待删 stepId — alert 二次确认才真删.
    @State private var pendingDeleteStepId: String? = nil
    /// 右滑 Edit / NavigationLink tap 共用同一 navigation path — append stepId 触发 push 进编辑页.
    @State private var stepEditPath = NavigationPath()
    /// 动作列表的视图模式 — 单列 row (default) 还是 2 列 grid card.
    /// 持久化到 UserDefaults — 跨 sheet 开关 / app 重启都保留, 用户偏好一旦设定不会"忘".
    @AppStorage("planStepCardLayout") private var useCardLayout: Bool = false

    init(initialPlan: Plan, onStart: @escaping (Plan) -> Void) {
        self.initialPlan = initialPlan
        self.onStart = onStart
        self._draft = State(initialValue: initialPlan)
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

    var body: some View {
        // NavigationStack(path:) — 让 swipe Edit 能 programmatic push step 进编辑页 (跟 tap 整行
        // 走 NavigationLink 同终点). path 用 NavigationPath, append stepId 即触发 destination.
        NavigationStack(path: $stepEditPath) {
            // List + Section 让 stepListSection 里的 ForEach 能用原生 .onMove + .swipeActions.
            // ScrollView+VStack 不支持. 清掉 List 默认样式后视觉跟原来一致.
            List {
                Section {
                    headerCard
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 20, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                stepListSection
                Section {
                    addExerciseButton
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 32, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左侧 "…" overflow menu — 装 destructive 操作 (Delete Plan).
                // iOS 习惯把删除整个对象的操作放 toolbar menu, 不放主显眼按钮.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label {
                                Text("Delete Plan")
                            } icon: {
                                Image(systemName: "trash").foregroundStyle(.white)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
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
                    Text("Edit Workout")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                }
            }
            .alert("Delete this plan?", isPresented: $confirmDelete) {
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
            .alert("Delete exercise from plan?", isPresented: Binding(
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
            .navigationDestination(for: PlanStep.ID.self) { stepId in
                if let idx = draft.steps.firstIndex(where: { $0.id == stepId }),
                   let ex = data.exById[draft.steps[idx].exerciseId] {
                    EditStepView(
                        exercise: ex,
                        step: $draft.steps[idx],
                        onDelete: {
                            draft.steps.remove(at: idx)
                            commit()
                        }
                    )
                    .onChange(of: draft.steps[safe: idx]) { _, _ in commit() }
                }
            }
            .sheet(isPresented: $showAddPicker) {
                ExercisePickerSheet(
                    onPick: { ex in
                        let newStep = PlanStep(
                            id: "step-\(ex.id)-\(Int(Date().timeIntervalSince1970))",
                            exerciseId: ex.id,
                            sets: 3,
                            reps: ex.category == .strength ? 10 : nil,
                            weight: ex.category == .strength ? 0 : nil,
                            duration: ex.category != .strength ? 30 : nil,
                            restBetweenSets: 90,
                            rest: 0
                        )
                        draft.steps.append(newStep)
                        commit()
                        showAddPicker = false
                    }
                )
                .presentationDetents([.large])
            }
            // 点 PlanStepRow / Card 图片 → 弹动作详情 (跟其它 5 个列表共用 ExerciseDetailSheet).
            // 整行 tap 仍走 NavigationLink 进 EditStepView (改 sets/reps/weight). 图片是 Button,
            // hit-test 优先级高于 NavigationLink, 不会同时触发.
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
        }
    }

    // 把 draft 写回 data store
    private func commit() {
        draft.updatedAt = Date()
        data.updatePlan(draft)
    }

    // 顶部信息卡 — 简化版.
    // 之前: BodyHint 左 + WORKOUT kicker + TextField + 2 StatPills 信息密. 用户反馈"信息过多 + TextField 不明显".
    // 现在: TextField 独立一行带明显 input 样式 + BodyHint 单独居中. 信息层级清楚.
    //   - StatPill (exercises/sets count) 移除 — stepList header 已能看出动作数
    //   - WORKOUT kicker 移除 — nav title "Edit Workout" 重复
    private var headerCard: some View {
        VStack(spacing: 14) {
            // Plan name — 15pt regular (iOS HIG Subhead 字号), 比之前 .body (17pt) 小一档.
            // 视觉上跟 Settings row 输入风格一致 — 是普通可编辑文本, 不抢戏.
            // padding 也同步收 (12 → 10pt 垂直), 让输入框整体瘦一些.
            TextField("Workout name", text: Binding(
                get: { draft.name },
                set: { draft.name = $0; commit() }
            ))
            .font(.system(size: 15))
            .foregroundStyle(MasoColor.text)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MasoColor.borderSoft, lineWidth: 0.5)
            )

            // BodyHint — 这个 plan 的"练什么部位"视觉锚, 居中, 比之前 96pt 略大 (110) 给它点存在感.
            BodyHint(muscles: muscles, height: 110, region: .full)
        }
    }

    /// 右滑删除 step 的二次确认 — 跟 PlansScreen 同模式, 存待删 stepId, alert 弹.
    @ViewBuilder
    private var stepListSection: some View {
        Section {
            // Header — "EXERCISES" kicker + 右侧 list/grid 切换.
            HStack {
                Text("Exercises")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(MasoColor.textFaint)
                Spacer()
                layoutToggle
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if draft.steps.isEmpty {
                Text("No exercises yet — tap “Add Exercise” to start")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
            } else if useCardLayout {
                // 2 列 grid 模式 — 卡片纵向: 大图 + 名字 + 详情.
                // grid 不支持原生 .onMove / .swipeActions, 改动只走 contextMenu 路径.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(draft.steps) { stp in
                        if let ex = data.exById[stp.exerciseId] {
                            stepEntry(step: stp, exercise: ex)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                // 单列 row 模式 (default) — 支持原生拖拽排序 + 右滑删除 + alert 二次确认.
                ForEach(draft.steps) { stp in
                    if let ex = data.exById[stp.exerciseId] {
                        stepEntry(step: stp, exercise: ex)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Delete + Edit — tint 显式指定颜色 (全 app 全局 .tint MasoColor.text 白
                                // 会让默认 destructive 红底也变白). Edit 用 accent 绿跟 brand 一致.
                                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                                    pendingDeleteStepId = stp.id
                                }
                                .tint(.red)
                                Button(NSLocalizedString("Edit", comment: "")) {
                                    // programmatic push — 跟 NavigationLink tap 整行同 destination
                                    stepEditPath.append(stp.id)
                                }
                                .tint(MasoColor.accent)
                            }
                    }
                }
                .onMove { source, destination in
                    draft.steps.move(fromOffsets: source, toOffset: destination)
                    commit()
                    Haptics.tap()
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
        ZStack {
            // invisible navigation 触发器, 占满 row 区域接收 tap
            NavigationLink(value: stp.id) { EmptyView() }
                .opacity(0)

            // 实际渲染的 row / card — 显示在前面, NavigationLink 的 chevron 不会出来
            if useCardLayout {
                PlanStepCard(step: stp, exercise: ex, onTapImage: { detailExercise = ex })
            } else {
                PlanStepRow(step: stp, exercise: ex, onTapImage: { detailExercise = ex })
            }
        }
        .contextMenu {
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

    /// list / grid 切换 — 两个 icon 按钮, 当前 mode 高亮 accent, 另一个 textFaint.
    /// withAnimation spring 切换时 grid <-> list 之间动画平滑, 不"跳"
    private var layoutToggle: some View {
        // 共享组件 — 跟 SessionDetailSheet 用同一份, 视觉 + 行为统一.
        LayoutToggle(useCardLayout: Binding(
            get: { useCardLayout },
            set: { useCardLayout = $0 }
        ))
    }

    @ViewBuilder
    private func layoutButton(isGrid: Bool, icon: String) -> some View {
        // (旧 private helper, 现在不用了 — LayoutToggle 组件接管. 留下避免编译断 — 实际无引用.)
        let active = useCardLayout == isGrid
        Button(action: {
            guard !active else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                useCardLayout = isGrid
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(active ? MasoColor.text : MasoColor.textFaint)
                .frame(width: 26, height: 22)
                .background(
                    Capsule()
                        .fill(active ? MasoColor.accent.opacity(0.85) : Color.clear)
                )
        }
        .buttonStyle(.plain)
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
    private func removeStep(_ id: String) {
        draft.steps.removeAll { $0.id == id }
        commit()
        Haptics.tap()
    }

    private var addExerciseButton: some View {
        Button(action: { showAddPicker = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Add Exercise")
                    .font(.system(size: 13, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.text.opacity(0.18), style: .init(lineWidth: 1, dash: [5, 4]))
            )
            .foregroundStyle(MasoColor.textDim)
        }
        .buttonStyle(.plain)
    }
}


/// 把一个 step 的 sets / reps / weight / duration 拼成一行短文案
/// (row 和 card 都用同一份格式, 一处改两处生效)
private func planStepDetailLine(_ step: PlanStep) -> String {
    if let d = step.duration {
        return "\(pluralizedSets(step.sets)) · \(d)s"
    }
    let reps = step.reps.map { "\($0)" } ?? "?"
    if let w = step.weight, w > 0 {
        return "\(pluralizedSets(step.sets)) · \(formatWeight(w)) kg × \(reps)"
    }
    return "\(pluralizedSets(step.sets)) × \(reps)"
}

// 单个 step 行 — 动作图 + 名字 + (sets × reps × weight 或 duration) + chevron
private struct PlanStepRow: View {
    let step: PlanStep
    let exercise: Exercise
    /// 点图片 → 弹动作详情. parent 传 closure, sheet 在 parent 挂.
    var onTapImage: (() -> Void)? = nil

    private var detailLine: String { planStepDetailLine(step) }

    var body: some View {
        // 视觉跟"训练中" InlinePlaylist.playlistRow 完全对齐:
        //   - HStack spacing 14 (原 12)
        //   - 缩略图 56 + cornerRadius 8 (原 48 / 8)
        //   - VStack spacing 5 (原 4)
        //   - 名字 15pt bold (原 14)
        //   - detailLine 12pt monospaced — 保留单 Text, 内容跟 playlistRow 同信息密度
        //   - ExerciseTagsRow muscleLimit 1 (原默认 2) — 行更瘦
        //   - 删了右侧 chevron — playlistRow 没 chevron, "tap → navigate" 用户直觉知
        //   - cornerRadius 10 (原 12)
        //   - padding.vertical 10 (原 rowPaddingV)
        HStack(spacing: 14) {
            Button(action: { onTapImage?() }) {
                ExerciseImage(
                    category: exercise.category,
                    imageFolder: exercise.imageFolder,
                    cornerRadius: 8,
                    size: 56,
                    animated: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), exercise.displayName))
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                ExerciseTagsRow(
                    muscleGroups: exercise.muscleGroups,
                    equipment: exercise.equipment,
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

// 单个 step 卡片 — 纵向布局 (图大 + 名字 + 详情). LazyVGrid 2 列时用.
// 视觉跟 Spotify / Apple Music 的 grid item 一致 — 图占大头, 文字"贴"图下面.
private struct PlanStepCard: View {
    let step: PlanStep
    let exercise: Exercise
    /// 点图片 → 弹动作详情. parent 传 closure, sheet 在 parent 挂.
    var onTapImage: (() -> Void)? = nil

    private var detailLine: String { planStepDetailLine(step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 图: 正方形, 铺满卡片宽度. GeometryReader 拿到实际 cell 宽度后传给 ExerciseImage,
            // 不然 ExerciseImage 默认 size=48 太小, grid 里会缩成小图.
            // 包 Button — tap 图片优先于外层 NavigationLink, 走详情而非编辑.
            Button(action: { onTapImage?() }) {
                GeometryReader { geo in
                    ExerciseImage(
                        category: exercise.category,
                        imageFolder: exercise.imageFolder,
                        cornerRadius: 8,
                        size: geo.size.width,
                        animated: false
                    )
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), exercise.displayName))

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
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
                // 卡片宽度受限, 用 compact + muscleLimit 1 — 只显 1 个肌肉 + equipment.
                ExerciseTagsRow(
                    muscleGroups: exercise.muscleGroups,
                    equipment: exercise.equipment,
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

// MARK: - EditStepView — 改一个动作的 sets / reps / weight / rest

private struct EditStepView: View {
    let exercise: Exercise
    @Binding var step: PlanStep
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 动作头部 — 大图 hero + 名字 + tag.
                // 之前 64×64 缩略图太小, 用户在动作详情页是来看清这个动作的, 图应该 prominence.
                // full-width 正方形 (跟卡片宽度等高), animated:true 让用户看到动作的两帧流.
                GeometryReader { geo in
                    ExerciseImage(
                        category: exercise.category,
                        imageFolder: exercise.imageFolder,
                        cornerRadius: 16,
                        size: geo.size.width,
                        animated: true
                    )
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(2)
                    if let first = exercise.tags.first {
                        Text(first)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 参数编辑 section
                paramSection

                // 删除动作
                Button(role: .destructive, action: { confirmDelete = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                        Text("Delete Exercise")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(MasoColor.negative.opacity(0.18))
                    .foregroundStyle(MasoColor.negative)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Edit Exercise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
            }
        }
        .alert("Remove this exercise?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(exercise.displayName)” will be removed from this workout. Past records are kept.")
        }
    }

    @ViewBuilder
    private var paramSection: some View {
        VStack(spacing: 0) {
            // 组数 — 共用 (strength + cardio + flexibility)
            EditRow(label: "Sets") {
                NumStepperField(intValue: $step.sets, range: 1...10)
            }
            Divider().background(MasoColor.borderSoft)

            if exercise.category == .strength {
                EditRow(label: "Reps") {
                    NumStepperField(
                        intValue: Binding(
                            get: { step.reps ?? 0 },
                            set: { step.reps = max(0, $0) }
                        ),
                        range: 0...50
                    )
                }
                Divider().background(MasoColor.borderSoft)
                EditRow(label: "Weight") {
                    NumStepperField(
                        doubleValue: Binding(
                            get: { step.weight ?? 0 },
                            set: { step.weight = max(0, $0) }
                        ),
                        range: 0...300,
                        step: 2.5,
                        suffix: "kg",
                        decimal: true
                    )
                }
                Divider().background(MasoColor.borderSoft)
            } else {
                EditRow(label: "Duration") {
                    NumStepperField(
                        intValue: Binding(
                            get: { step.duration ?? 0 },
                            set: { step.duration = max(0, $0) }
                        ),
                        range: 5...600,
                        step: 5,
                        suffix: "s"
                    )
                }
                Divider().background(MasoColor.borderSoft)
            }

            EditRow(label: "Set rest") {
                NumStepperField(intValue: $step.restBetweenSets, range: 15...300, step: 15, suffix: "s")
            }
        }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EditRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MasoColor.text)
            Spacer()
            content()
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .frame(height: 56)
    }
}

// MARK: - ExercisePickerSheet — 选一个动作加进 plan

private struct ExercisePickerSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void

    @State private var query: String = ""
    /// 顶层 section 筛选 (nil = 全部). 6 个: chest/back/shoulders/arms/core/legs.
    @State private var muscleFilter: MuscleGroup? = nil
    /// 二级 sub-muscle 筛选 (只在 muscleFilter 有 subs 时可用). nil = 不细分.
    /// 切换 muscleFilter 时 reset 成 nil.
    /// 注: 这个不再"narrow" filter, 改成 sort hint — 选了 Mid Chest 不会把 chest 其他动作藏起来,
    /// 而是把命中 Mid Chest 的动作排到最前面.
    @State private var subFilter: MuscleGroup? = nil
    /// 器械筛选 (nil = 不限). 选了之后 narrow filter, 跟 muscle 是 AND 关系.
    /// 顺序按 yuhonas 数据频次: barbell (170) → dumbbell (123) → body only (111) → cable (81) →
    /// machine (67) → kettlebells (53) → bands (20) → 等. "other" + None 都归到 "other".
    @State private var equipmentFilter: String? = nil
    /// 顶部视图模式 — 默认 By Muscle (chip 列表), 切到 body map 是图选.
    @State private var mode: PickerMode = .list
    /// Body Map 模式下, 列表滚动进度 (0..1). 用来缩小 BodyHint 给列表腾空间.
    @State private var scrollProgress: CGFloat = 0
    /// tap 列表行 → 弹动作详情. 详情里点 "Add to workout" 才真正 onPick.
    @State private var detailExercise: Exercise? = nil

    enum PickerMode { case bodyMap, list }

    private static let bodyHintMaxHeight: CGFloat = 280
    private static let bodyHintMinHeight: CGFloat = 130
    /// Body Map 下 BodyHint 的当前 height — 跟 scrollProgress 线性插值.
    private var dynamicBodyHintHeight: CGFloat {
        let max = Self.bodyHintMaxHeight
        let min = Self.bodyHintMinHeight
        return max - (max - min) * scrollProgress
    }

    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    // 注: equipment 列表 + display name 提到 Exercise model (Exercise.knownEquipments /
    // Exercise.equipmentDisplayName), 让 Library Browser / Quick workout / Plans picker 共用一份.

    /// 三维 filter 应用 helper — 同一逻辑用在 `filtered` 和各 availability 计算上.
    /// 传 nil 表示该维度不限制. 三维都是 AND 关系.
    private func applyFilters(
        _ arr: [Exercise],
        muscle: MuscleGroup?,
        sub: MuscleGroup?,
        equipment: String?,
        text: String?
    ) -> [Exercise] {
        var result = arr
        if let m = muscle {
            result = result.filter { ex in
                ex.muscleGroups.contains(where: { $0.section == m })
            }
        }
        if let s = sub {
            // sub narrow — 选 Mid Chest 只看 mid chest 动作 (含解剖子节点匹配).
            // 之前是 sort hint, 跟 muscle / equipment 一致后改 narrow, 用户感知"映射关系"清晰.
            let anatomySubs = expandAnatomyMuscles([s])
            result = result.filter { ex in
                ex.muscleGroups.contains(s) ||
                ex.muscleGroups.contains(where: { anatomySubs.contains($0) })
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
        if let t = text?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty {
            result = result.filter { ex in
                ex.name.lowercased().contains(t) ||
                ex.displayName.lowercased().contains(t) ||
                ex.tags.contains(where: { $0.lowercased().contains(t) })
            }
        }
        return result
    }

    private var filtered: [Exercise] {
        let arr = applyFilters(
            data.exercises,
            muscle: muscleFilter,
            sub: subFilter,
            equipment: equipmentFilter,
            text: query
        )
        // 收藏置顶 — 在 filter 之后排序, 让收藏的动作在当前 filter 结果里排最前
        return Array(data.sortByFavorites(arr).prefix(200))
    }

    // MARK: - chip availability — 三维 filter 之间互相 narrow 时, 让用户知道哪些 chip 当前可选

    /// 当前 muscle/sub/text filter (不算 equipment) 下还有动作的 equipment set.
    /// 用 chip "dim disabled" 视觉提示 — 让用户知道选了某 muscle 后哪些 equipment 是空集.
    private var availableEquipments: Set<String> {
        let arr = applyFilters(data.exercises, muscle: muscleFilter, sub: subFilter, equipment: nil, text: query)
        var out: Set<String> = []
        for ex in arr {
            // nil + "other" 都映射到 "other" chip
            out.insert(ex.equipment == nil ? "other" : ex.equipment!)
        }
        return out
    }

    /// 当前 equipment/text filter (不算 muscle) 下还有动作的 muscle section set.
    private var availableMuscles: Set<MuscleGroup> {
        let arr = applyFilters(data.exercises, muscle: nil, sub: nil, equipment: equipmentFilter, text: query)
        var out: Set<MuscleGroup> = []
        for ex in arr {
            for sec in Self.muscleSections {
                if ex.muscleGroups.contains(where: { $0.section == sec }) {
                    out.insert(sec)
                }
            }
        }
        return out
    }

    /// 当前 muscle + equipment + text 下 (不算 subFilter), 哪些 sub-muscle 还有动作.
    /// 给 sub-muscle chip 用 dim 提示.
    private var availableSubMuscles: Set<MuscleGroup> {
        guard let section = muscleFilter else { return [] }
        let arr = applyFilters(data.exercises, muscle: section, sub: nil, equipment: equipmentFilter, text: query)
        var out: Set<MuscleGroup> = []
        for sub in section.sectionSubs {
            let anatomySubs = expandAnatomyMuscles([sub])
            if arr.contains(where: { ex in
                ex.muscleGroups.contains(sub) ||
                ex.muscleGroups.contains(where: { anatomySubs.contains($0) })
            }) {
                out.insert(sub)
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部一行: mode 切换 (两个 icon 按钮, 紧凑) + search bar (占余下宽度)
                HStack(spacing: 10) {
                    modeToggle
                    searchField
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .animation(.easeOut(duration: 0.2), value: mode)

                // Mode-specific content — 各自管 BodyHint / chips / list
                if mode == .bodyMap {
                    bodyMapModeContent
                } else {
                    listModeContent
                }
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex, onAdd: { onPick(ex) })
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add Exercise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
            }
        }
    }

    // MARK: - 顶部组件: mode 切换 + search bar

    @ViewBuilder
    private var modeToggle: some View {
        // By Muscle (list) 在左 = 默认选中; Body Map 在右
        HStack(spacing: 2) {
            modeButton(.list, icon: "list.bullet")
            modeButton(.bodyMap, icon: "figure")
        }
        .padding(2)
        .background(MasoColor.surface)
        .clipShape(Capsule())
    }

    private func modeButton(_ m: PickerMode, icon: String) -> some View {
        Button(action: { mode = m }) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(mode == m ? .black : MasoColor.textDim)
                .frame(width: 34, height: 28)
                .background(mode == m ? MasoColor.accent : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchField: some View {
        TextField("Search exercises…", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(MasoColor.surface)
            .clipShape(Capsule())
            .overlay(
                HStack {
                    Spacer()
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MasoColor.textFaint)
                        }
                        .padding(.trailing, 8)
                    }
                }
            )
    }

    // MARK: - Body Map mode 内容 (默认)
    //
    // 不展示 search bar — Body Map 是视觉选择, 用户用 search 就切去 list 模式.
    // BodyHint 大尺寸 (280pt) 给精确点击留位置; 列表滚动时同步缩小到 130pt, 给列表腾空间.
    /// 选中肌群的协同肌 — 让 Body Map 上选 chest 时 triceps 半亮 ("练胸会带到").
    /// MuscleSynergy 数据基于实际解剖学 + 复合动作激活模式 (port 自 web 端).
    private var bodyMapSynergists: [MuscleGroup] {
        guard let m = muscleFilter else { return [] }
        return Array(MuscleSynergy.synergists(for: [m]))
    }

    @ViewBuilder
    private var bodyMapModeContent: some View {
        VStack(spacing: 6) {
            BodyHint(
                muscles: muscleFilter.map { [$0] } ?? [],
                synergists: bodyMapSynergists,
                height: dynamicBodyHintHeight,
                onMuscleTap: { m in
                    if let section = m.section {
                        muscleFilter = section
                        subFilter = nil
                    }
                },
                coarseOnly: !data.settings.muscleDetailEnabled
            )
            .frame(maxWidth: .infinity)
            // 上下留白让 body map 不贴 search bar / 提示文字, 视觉呼吸更舒展
            .padding(.top, 18)
            .padding(.bottom, 10)
            .animation(.easeOut(duration: 0.15), value: dynamicBodyHintHeight)

            // 提示文字 / 当前选中 (固定高度避免抖动)
            HStack(spacing: 4) {
                if let m = muscleFilter {
                    Text(m.displayName)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                    Text("·")
                        .foregroundStyle(MasoColor.textFaint)
                    Button(action: {
                        muscleFilter = nil
                        subFilter = nil
                    }) {
                        Text("Clear")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Tap a muscle on the body to filter")
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                }
            }
            .frame(height: 18)
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

            // 器械筛选 — bodyMap mode 也提供, 让用户选完肌肉再 narrow 器械.
            // 跟 list mode 一致, 用 FilterMenuButton (Body Map 只暴露 equipment 一个 menu,
            // muscle 已经通过身体图选了, sub-muscle 在这里也没意义).
            HStack(spacing: 8) {
                let availE = availableEquipments
                FilterMenuButton(
                    title: NSLocalizedString("Equipment", comment: "filter button placeholder"),
                    allLabel: NSLocalizedString("Any equipment", comment: ""),
                    selected: $equipmentFilter,
                    options: Exercise.knownEquipments.map { eq in
                        FilterMenuOption(
                            value: eq,
                            label: Exercise.equipmentDisplayName(for: eq),
                            enabled: availE.contains(eq) || equipmentFilter == eq
                        )
                    }
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.bottom, 4)

            // 列表 — 滚动 offset 驱动 BodyHint 缩小
            exerciseList(scrollTrackingEnabled: true)
        }
    }

    // MARK: - By Muscle mode 内容 (filter menus + 列表)
    //
    // 之前是 muscle / sub / equipment 三行 chip 横向滚动 (占 ~100pt 纵向).
    // 改成一行 3 个 FilterMenuButton (~32pt 纵向) — 节省竖向空间, 列表区更大.
    // 选中 chip 用 accent 描边 + 当前值文字, 用户一眼看到当前 filter 状态.
    @ViewBuilder
    private var listModeContent: some View {
        VStack(spacing: 10) {
            filterMenusRow
        }
        .animation(.easeOut(duration: 0.2), value: muscleFilter)
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.bottom, 8)

        exerciseList(scrollTrackingEnabled: false)
    }

    /// 3 个 filter menu 一行 — Muscle / Sub (有 muscle 时才显) / Equipment.
    /// Sub menu 只在 muscleFilter != nil 且 muscleDetailEnabled 时显示, 因为 sub 是 muscle
    /// 的下级语义, 没选 major 时 sub 无意义.
    @ViewBuilder
    private var filterMenusRow: some View {
        HStack(spacing: 8) {
            let availM = availableMuscles
            FilterMenuButton(
                title: NSLocalizedString("Muscle", comment: "filter button placeholder"),
                allLabel: NSLocalizedString("All muscles", comment: ""),
                selected: Binding(
                    get: { muscleFilter },
                    set: { newVal in
                        muscleFilter = newVal
                        subFilter = nil  // 换 major → 清 sub
                    }
                ),
                options: Self.muscleSections.map { m in
                    FilterMenuOption(
                        value: m,
                        label: m.displayName,
                        enabled: availM.contains(m) || muscleFilter == m
                    )
                }
            )

            // Sub-muscle 菜单 — 仅当 detailEnabled + 已选 major + 该 major 有 sub 时显示
            if data.settings.muscleDetailEnabled,
               let section = muscleFilter, !section.sectionSubs.isEmpty {
                let availS = availableSubMuscles
                FilterMenuButton(
                    title: NSLocalizedString("Detail", comment: "sub-muscle filter placeholder"),
                    allLabel: String(format: NSLocalizedString("All %@", comment: ""), section.displayName),
                    selected: $subFilter,
                    options: section.sectionSubs.map { sub in
                        FilterMenuOption(
                            value: sub,
                            label: sub.displayName,
                            enabled: availS.contains(sub) || subFilter == sub
                        )
                    }
                )
                .transition(.opacity)
            }

            let availE = availableEquipments
            FilterMenuButton(
                title: NSLocalizedString("Equipment", comment: "filter button placeholder"),
                allLabel: NSLocalizedString("Any equipment", comment: ""),
                selected: $equipmentFilter,
                options: Exercise.knownEquipments.map { eq in
                    FilterMenuOption(
                        value: eq,
                        label: Exercise.equipmentDisplayName(for: eq),
                        enabled: availE.contains(eq) || equipmentFilter == eq
                    )
                }
            )

            Spacer(minLength: 0)
        }
    }

    // MARK: - 共用 exercise list

    @ViewBuilder
    private func exerciseList(scrollTrackingEnabled: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filtered) { ex in
                    // 视觉跟"训练中" InlinePlaylist.playlistRow 完全对齐 — 全 app 动作行统一规格.
                    Button(action: { detailExercise = ex }) {
                        HStack(spacing: 14) {
                            ExerciseImage(
                                category: ex.category,
                                imageFolder: ex.imageFolder,
                                cornerRadius: 8,
                                size: 56,
                                animated: false
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ex.displayName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(MasoColor.text)
                                    .lineLimit(1)
                                ExerciseTagsRow(
                                    muscleGroups: ex.muscleGroups,
                                    equipment: ex.equipment,
                                    muscleLimit: 1
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if data.isFavorite(ex.id) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(MasoColor.accent)
                            }
                        }
                        .padding(.horizontal, MasoMetrics.rowPaddingH)
                        .padding(.vertical, 10)
                        .background(MasoColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty {
                    Text("No exercises match your search")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.vertical, 32)
                }
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.bottom, 32)
        }
        // Body Map mode 启用 scroll tracking → BodyHint 跟着缩小
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { _, y in
            guard scrollTrackingEnabled else { return }
            // 0..120pt 拉动区间内, scrollProgress 从 0 → 1, BodyHint 从 280 → 130
            scrollProgress = min(1, max(0, y / 120))
        }
    }
}

private struct CategoryPill: View {
    let label: String
    let selected: Bool
    /// false 表示该 chip 在当前 filter 上下文下没有可选动作 — 灰显但仍可点
    /// (用户点了可看到 empty state, 引导他们清掉冲突 filter).
    var enabled: Bool = true
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? MasoColor.accent : MasoColor.surface)
                .foregroundStyle(selected ? .black : MasoColor.textDim)
                .clipShape(Capsule())
                .opacity(enabled || selected ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }
}

/// 二级 chip — 视觉权重比 `CategoryPill` 轻一档:
///   - 字号小 1pt (11 vs 12), weight semibold 而不是 bold
///   - 选中: accent 浅描边 + 轻底 (不是实心 accent), 文字 accent 色而不是黑色
///   - 未选: 透明底 + 灰描边
/// 让用户感知"这是 chest 之下的细分"而不是平行选项.
private struct SubCategoryPill: View {
    let label: String
    let selected: Bool
    /// false 表示该 chip 在当前 filter 上下文下没有可选动作 — 灰显但仍可点
    var enabled: Bool = true
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(selected ? MasoColor.accent : MasoColor.textDim)
                .background(selected ? MasoColor.accent.opacity(0.12) : Color.clear)
                .overlay(
                    Capsule().stroke(
                        selected ? MasoColor.accent.opacity(0.5) : MasoColor.borderSoft,
                        lineWidth: 0.8
                    )
                )
                .clipShape(Capsule())
                .opacity(enabled || selected ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
