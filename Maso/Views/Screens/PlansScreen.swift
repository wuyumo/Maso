import SwiftUI

// MARK: - PlansScreen — Tab 2 内容 (新 IA, 2026-06)
//
// 结构 (用户确认的设计):
//   ┌ SAVED  (默认优先, 有 saved plan 才显示)  ── data.plans, 免费上限 "n/3"
//   │  · 每张 = WorkoutCard (start / 详情 / 长按删)
//   │  · "+ New workout" 入口
//   ┌ DISCOVER
//   │  · segmented [ AI · Community ]
//   │  · AI:        按你的偏好现生成的计划 → 每张可 Save / Save&Start
//   │  · Community: 社区精选 → 每张可 Save
//
// Exercises 库已移到 PlansTabScreen 右上角工具栏 (不在本页正文).
// 本 view 只渲染滚动正文; 导航栏 / 工具栏由 PlansTabScreen (NavigationStack) 提供.
struct PlansScreen: View {
    @Environment(DataStore.self) private var data
    let onStart: (Plan) -> Void
    /// 新建空白计划 — RootView 注入 (走 paywall gating + 共享 sheet 容器).
    let onNewPlan: () -> Void

    enum DiscoverMode: Hashable { case ai, community }
    @State private var discover: DiscoverMode = .ai
    /// 按偏好现生成的 AI 计划 (transient, 不进 data.plans 直到用户 Save).
    @State private var aiPlans: [Plan] = []
    @State private var detailPlan: Plan? = nil
    @State private var pendingDeletePlanId: String? = nil
    @State private var paywallPresented = false
    /// Community 筛选 (#filters): 等级 + 每周天数. nil = 全部.
    @State private var communityLevel: String? = nil
    @State private var communityDays: Int? = nil

    private var isPro: Bool { data.settings.isPro }

    var body: some View {
        // 左右滑动可在 AI / Community 两页间切换 (paged TabView, 跟顶部导航栏 segmented 双向绑定).
        TabView(selection: $discover.animation(.easeOut(duration: 0.22))) {
            aiPage.tag(DiscoverMode.ai)
            communityPage.tag(DiscoverMode.community)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // AI / Community 切页控件移进导航栏 principal — 跟右上角 Exercises/Settings 按钮同一行齐平.
        // 系统 .segmented 样式, 高度由导航栏统一控制 (自动跟那两个按钮对齐).
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $discover.animation(.easeOut(duration: 0.18))) {
                    Text("AI").tag(DiscoverMode.ai)
                    Text("Community").tag(DiscoverMode.community)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .background(MasoColor.background.ignoresSafeArea())
        // 每次进入按当前训练偏好现算 AI 计划 (改了 days/muscles/equipment 后回来即刷新).
        .onAppear { regenerateAI() }
        // PlanRationaleCard 改完偏好 (sheet 关) 仍在本页时, 也立即重算 AI 计划.
        .onChange(of: data.settings.weeklyTrainingDays) { _, _ in regenerateAI() }
        .onChange(of: data.settings.exercisesPerSession) { _, _ in regenerateAI() }
        .onChange(of: data.settings.defaultSetsPerExercise) { _, _ in regenerateAI() }
        .onChange(of: data.settings.trainingGoal) { _, _ in regenerateAI() }
        .onChange(of: data.settings.wantStrengthen) { _, _ in regenerateAI() }
        .onChange(of: data.settings.availableEquipment) { _, _ in regenerateAI() }
        .sheet(item: $detailPlan) { plan in
            PlanDetailSheet(
                initialPlan: plan,
                onStart: { p in detailPlan = nil; DispatchQueue.main.async { onStart(p) } },
                onAddToSaved: { p in addToSaved(p) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $paywallPresented) { PaywallScreen() }
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

    // MARK: - SAVED

    @ViewBuilder
    private var savedSection: some View {
        if data.plans.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(MasoColor.textFaint)
                Text("No saved plans yet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Text("Generate one with AI or browse the community below, then tap Save.")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .multilineTextAlignment(.center)
                newWorkoutButton.padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            HStack {
                sectionKicker("Saved")
                Spacer()
                if !isPro {
                    Text("\(data.plans.count)/\(DataStore.freeSavedPlansLimit)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(data.canSaveMorePlans ? MasoColor.textFaint : MasoColor.accent)
                }
            }
            ForEach(data.plans) { plan in
                WorkoutCard(
                    plan: plan,
                    exById: data.exById,
                    kicker: "",
                    onStart: { onStart(plan) },
                    onShowDetail: { detailPlan = plan },
                    prominentStart: false
                )
                .contextMenu {
                    Button(role: .destructive) { pendingDeletePlanId = plan.id } label: {
                        Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                    }
                }
            }
            newWorkoutButton
        }
    }

    private var newWorkoutButton: some View {
        Button(action: onNewPlan) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("New workout")
            }
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(MasoColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(MasoColor.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - DISCOVER pages (左右滑动切换)

    /// AI 页 — Training Preferences 卡 + 按偏好现算的 AI 计划卡 (点卡片预览, 详情页 "+" 加进 Saved).
    private var aiPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanRationaleCard()
                if aiPlans.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(aiPlans) { plan in
                        discoverPlanCard(plan, badge: "AI")
                    }
                }
                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 4)
        }
    }

    /// Community 页 — Level / Days 筛选 + 社区计划卡.
    private var communityPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                communityFilterRow
                let plans = filteredCommunityPlans
                if plans.isEmpty {
                    Text("No community plans match these filters.")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    ForEach(plans) { cp in communityCard(cp) }
                }
                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 4)
        }
    }

    // MARK: - Community filters (#filters)

    private var communityLevelOptions: [String] { Array(Set(CommunityPlans.all.map(\.levelKey))).sorted() }
    private var communityDayOptions: [Int] { Array(Set(CommunityPlans.all.map(\.frequencyDaysPerWeek))).sorted() }
    private var filteredCommunityPlans: [CommunityPlan] {
        CommunityPlans.all.filter {
            (communityLevel == nil || $0.levelKey == communityLevel) &&
            (communityDays == nil || $0.frequencyDaysPerWeek == communityDays)
        }
    }

    private var communityFilterRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button { communityLevel = nil } label: {
                    Label(NSLocalizedString("All levels", comment: ""), systemImage: communityLevel == nil ? "checkmark" : "")
                }
                ForEach(communityLevelOptions, id: \.self) { lv in
                    Button { communityLevel = lv } label: {
                        if communityLevel == lv { Label(NSLocalizedString(lv, comment: ""), systemImage: "checkmark") }
                        else { Text(LocalizedStringKey(lv)) }
                    }
                }
            } label: {
                filterChip(title: communityLevel.map { LocalizedStringKey($0) } ?? "Level", active: communityLevel != nil)
            }
            Menu {
                Button { communityDays = nil } label: {
                    Label(NSLocalizedString("Any frequency", comment: ""), systemImage: communityDays == nil ? "checkmark" : "")
                }
                ForEach(communityDayOptions, id: \.self) { d in
                    Button { communityDays = d } label: {
                        if communityDays == d { Label("\(d) days/week", systemImage: "checkmark") }
                        else { Text("\(d) days/week") }
                    }
                }
            } label: {
                filterChip(title: communityDays.map { LocalizedStringKey("\($0) days/wk") } ?? LocalizedStringKey("Days/week"), active: communityDays != nil)
            }
            Spacer()
        }
    }

    private func filterChip(title: LocalizedStringKey, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(active ? .black : MasoColor.text)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(active ? MasoColor.accent : MasoColor.surface)
        .clipShape(Capsule())
    }

    /// AI 生成的计划卡 — WorkoutCard 富展示. 点卡片 → 预览详情; 底部 "★ 添加到我的计划" → 直接存进 My Plans.
    private func discoverPlanCard(_ plan: Plan, badge: String) -> some View {
        WorkoutCard(
            plan: plan,
            exById: data.exById,
            kicker: badge,
            onStart: { detailPlan = plan },
            onShowDetail: { detailPlan = plan },
            prominentStart: false,
            addAction: { addToSaved(plan) }
        )
    }

    /// 社区精选卡 — 跟 AI 卡同款 WorkoutCard 排版 (肌肉图 + 动作 chip + 计数), 不再是单薄的文字行.
    /// kicker 用 cp.kicker (FULL BODY / STRENGTH / PUSH·PULL·LEGS …); 点卡片 → 预览; 底部星标按钮 → 存进 My Plans.
    private func communityCard(_ cp: CommunityPlan) -> some View {
        Group {
            if let plan = communityDisplayPlan(cp) {
                WorkoutCard(
                    plan: plan,
                    exById: data.exById,
                    kicker: cp.kicker,
                    onStart: { detailPlan = plan },
                    onShowDetail: { detailPlan = plan },
                    prominentStart: false,
                    addAction: { addToSaved(plan) }
                )
            }
        }
    }

    /// 社区 plan → 卡片展示用的 Plan. 取第一张 session (跟原有 add/preview 语义一致),
    /// 但标题改回整套项目名 (而非 materialize 默认的 "项目 · SessionA") — 跟原卡片标题保持一致.
    private func communityDisplayPlan(_ cp: CommunityPlan) -> Plan? {
        guard var plan = cp.materialize(byId: data.exById).first else { return nil }
        plan.name = NSLocalizedString(cp.nameKey, comment: "community plan name")
        return plan
    }

    // MARK: - Actions

    private func regenerateAI() {
        aiPlans = DataStore.tunedRecommendedPlans(
            forDays: data.settings.weeklyTrainingDays,
            settings: data.settings,
            exById: data.exById,
            sets: data.sets,
            now: Date()
        )
    }

    /// Discover 详情页右上角 "+" → 把这张(预览的)计划加进 Saved. 满额 → 弹 paywall. 完后关详情.
    private func addToSaved(_ plan: Plan) {
        let ok = data.savePlan(plan)
        detailPlan = nil
        if ok { Haptics.tap() } else { paywallPresented = true }
    }

    private func sectionKicker(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 12, weight: .bold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(MasoColor.textDim)
    }
}


// MARK: - CommunityEntryRow — Plans 列表底部"社区精选" 入口

struct CommunityEntryRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
                    .frame(width: 36, height: 36)
                // DESIGN.md §2.2: 列表行 label 走正文 14pt bold (跟 PlanRow title 同档).
                Text("See what others train")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }
            .padding(MasoMetrics.rowPaddingH)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See what others train")
    }
}

/// "Exercise library" 入口行 — Plans tab 底部, 跟 CommunityEntryRow 同款 row. 显示动作总数,
/// tap → ExerciseLibraryBrowser sheet. 从 Settings 挪过来的, 因为这里离"我要给 plan 加动作"
/// 的动线只一步, 不用再绕回 Settings.
private struct LibraryEntryRow: View {
    let exerciseCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
                    .frame(width: 36, height: 36)
                Text("Exercise library")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Spacer()
                Text("\(exerciseCount)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }
            .padding(MasoMetrics.rowPaddingH)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exercise library")
    }
}

// MARK: - PlanRationaleCard — 解释为什么 plans 长这样
//
// 设计哲学 (style "A" — 冷静解释型):
//   - 不做激励 slogan, 给用户事实
//   - kicker (FOR YOU / 为你设计) + data row (每周 N · style · 重点 muscles) + 一句 rationale
//   - 数据全部从 settings 拿, 用户改了 onboarding 偏好 → card 自动更新
//   - Plan 列表空时不显示 (没东西可解释)
//
// rationale 副文案逻辑:
//   - 没填 wantStrengthen → 走 "全身均衡" 文案
//   - days >= 5 → 高频
//   - days 3-4 → 中频 (经典每周 2× / muscle)
//   - days 1-2 → 维持频率
struct PlanRationaleCard: View {
    @Environment(DataStore.self) private var data
    /// 右上角 pencil 按钮触发的"快捷训练设置"sheet
    @State private var showTrainingSettings = false

    var body: some View {
        let s = data.settings
        // wantStrengthen 折叠到 6 大 section (chest/back/shoulders/arms/core/legs) 显示,
        // 跟 "Muscles to focus" picker 的粒度一致.
        let majors = MuscleSelector.focusSummary(Set(s.wantStrengthen))
        let muscleNames = majors.prefix(3).map(\.displayName).joined(separator: " / ")
        let muscleSuffix = majors.count > 3 ? " +\(majors.count - 3)" : ""

        let daysStr = String(
            format: NSLocalizedString("%lld days / week", comment: "weekly training frequency"),
            s.weeklyTrainingDays
        )
        let dataParts: [String] = [
            daysStr,
            programStyleName(s.programStyle),
            majors.isEmpty ? "" : String(
                format: NSLocalizedString("Focus: %@", comment: "muscle focus list"),
                muscleNames + muscleSuffix
            )
        ].filter { !$0.isEmpty }
        let dataLine = dataParts.joined(separator: " · ")
        let explanation = rationale(days: s.weeklyTrainingDays, hasFocus: !majors.isEmpty)

        return VStack(alignment: .leading, spacing: 10) {
            // 顶行: 训练图标 + TRAINING PREFERENCES kicker + 右上角 pencil 入口.
            // 字号跟 WorkoutCard "FROM YOUR PLAN" 完全对齐 (10pt heavy + tracking 1.5), 三个 kicker
            // 在三个 tab 上视觉一致.
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(MasoColor.accent)
                Text("TRAINING PREFERENCES")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(MasoColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                // pencil 按钮 — 弹 TrainingSettingsSheet, 内容跟 Settings → Training 完全一致
                Button(action: { showTrainingSettings = true }) {
                    // 白色纯 icon — 无圆圈底、无边框 (用户要求, 比 "+" 弱一档).
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Adjust training preferences"))
            }
            Text(dataLine)
                // DESIGN.md §2.2: 正文 14pt bold — FOR YOU 卡的"数据行"是主要可读信息, 走正文规格
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation)
                // 副文案: 比正文小一档 12pt, 弱化用 textDim
                .font(.system(size: 12))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .padding(.vertical, MasoMetrics.cardPadding - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 视觉强化 (无底色 + 无炫光版):
        //   - 不要 .background — 整卡透到页面背景 (跟 MuscleStatusOverviewCard 同款 hero 处理)
        //   - 0.5pt borderHero 描边 — 跟 MuscleStatusOverviewCard 同款, 比 borderSoft 强一档
        //     让卡片边在 large title 渐变区也看得清楚.
        //   - 不要 shadow — 描边足够
        .overlay(
            RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                .stroke(MasoColor.borderHero, lineWidth: 0.5)
        )
        // 整张卡也可点 — pencil 是显式 affordance, 但用户点空白处也算 "想改"
        .contentShape(Rectangle())
        .onTapGesture { showTrainingSettings = true }
        .sheet(isPresented: $showTrainingSettings) {
            TrainingSettingsSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func programStyleName(_ style: ProgramStyle) -> String {
        switch style {
        case .fullBody:
            return NSLocalizedString("Full-body", comment: "training program style")
        case .balanced:
            return NSLocalizedString("Upper-lower split", comment: "training program style")
        case .split:
            return NSLocalizedString("Body-part split", comment: "training program style")
        }
    }

    /// 根据 frequency + 是否有 focus 选副文案. 4 个 bucket.
    private func rationale(days: Int, hasFocus: Bool) -> String {
        if !hasFocus {
            return NSLocalizedString(
                "Full-body coverage — each muscle group rotates through the week.",
                comment: "rationale when no focus muscle set"
            )
        }
        if days >= 5 {
            return NSLocalizedString(
                "High frequency — focus muscles hit 2–3× per week, accessories rotate for recovery.",
                comment: "rationale: 5+ days/week"
            )
        } else if days >= 3 {
            return NSLocalizedString(
                "Each focus muscle is trained 2× per week — enough stimulus, full recovery between.",
                comment: "rationale: 3-4 days/week"
            )
        } else {
            return NSLocalizedString(
                "2× per week is enough to maintain steady progress — focus muscles rotate in.",
                comment: "rationale: 1-2 days/week"
            )
        }
    }
}

// MARK: - Plan list row

struct PlanRow: View {
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
        // 紧凑横排布局: 左侧肌肉图 + 右侧文字, 播放键钉在卡片右下角.
        //   左: MuscleVisualBlock (72pt)
        //   右: plan name (16pt bold) + 小 chevron  →  meta subtitle
        //   右下角: 圆形播放键, 距右边缘 & 底边等距 (各 12pt)
        // 高度由肌肉图主导 (~72pt) + 垂直 padding, 比原"竖排三行"版本矮约 50pt.
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .center, spacing: 14) {

                // ── 左: 肌肉图 ──
                MuscleVisualBlock(muscles: muscles, sideLength: 72)
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                // ── 右: 文字区 (tap → detail) ──
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(plan.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
            }
            // padding 放 HStack 上 (而不是整张卡), 这样下面播放键的 .padding(12) 是相对
            // 卡片外缘算的 → 距右 & 距底都正好 12pt, 完全对称.
            .padding(.horizontal, MasoMetrics.cardPadding - 2)
            .padding(.vertical, 12)

            // ── 播放键 — 钉在卡片右下角, 距右边缘 & 底边等距 (各 12pt) ──
            Button(action: onStart) {
                ZStack {
                    Circle()
                        .fill(MasoColor.accent.opacity(0.18))
                        .overlay(Circle().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5))
                        .frame(width: 28, height: 28)
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                        .offset(x: 0.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Workout")
            .padding(12)
        }
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
    /// Discover 用 — 非 nil 时右上角显示系统默认 "+" 加进 Saved (并隐藏 …/Delete 菜单, 因为这张还没拥有).
    let onAddToSaved: ((Plan) -> Void)?

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
    /// Share plan — 点 toolbar 分享按钮 → 拉起 UIActivityViewController 分享 maso:// 链接.
    @State private var shareURL: URL? = nil
    /// Share encode 失败时弹的简单 alert (理论上不会触发).
    @State private var shareFailed: Bool = false
    /// 右滑"替换动作"流程: stepId set 非 nil 时弹 ExercisePickerSheet 让用户挑新动作,
    /// 选完后只换 exerciseId, 保留 sets/reps/weight 等参数 (用户调过的负荷不要被替换抹掉).
    /// 跟 showAddPicker (append) 走两套 sheet, 语义清楚.
    @State private var stepToReplaceId: String? = nil

    init(initialPlan: Plan, onStart: @escaping (Plan) -> Void, onAddToSaved: ((Plan) -> Void)? = nil) {
        self.initialPlan = initialPlan
        self.onStart = onStart
        self.onAddToSaved = onAddToSaved
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
                        // top 28 — 标题离顶部留多点空间, 不顶着导航栏 (之前 12 太挤).
                        .listRowInsets(EdgeInsets(top: 28, leading: 0, bottom: 20, trailing: 0))
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
            // 不显示 nav title — 用户要求 Edit Workout 系列页面都不要标题
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 拥有的计划 (Today/Saved): 左侧 "…" overflow menu — Share / Delete.
                if onAddToSaved == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                handleSharePlan()
                            } label: {
                                Label("Share plan", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Delete Plan", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
                // Tab 2 browse 预览: 主操作 = body 的 "★ Add to my plans" 大 CTA, 顶栏不再放 "+" (去重).
                // 顶栏 Start 胶囊也删了 — body 大 CTA 够显眼; iOS sheet 自带下拉关闭, 不需要 Done.
            }
            // Share sheet — UIActivityViewController 桥. shareURL 设了就弹, 取消/分享完置 nil.
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let url = shareURL {
                    ShareActivityView(activityItems: [url])
                        .presentationDetents([.medium, .large])
                }
            }
            .alert("Couldn't create share link", isPresented: $shareFailed) {
                Button("OK", role: .cancel) {}
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
                // 添加动作 = 多选勾选 (跟 Free Workout 一致), 一次可选多个 → 底部 "Add (N)" 一并加入.
                ExercisePickerSheet(
                    onPick: { _ in },   // multiSelect 模式不走单选回调
                    multiSelect: true,
                    onPickMultiple: { exercises in
                        for (i, ex) in exercises.enumerated() {
                            draft.steps.append(PlanStep(
                                id: "step-\(ex.id)-\(Int(Date().timeIntervalSince1970))-\(i)",
                                exerciseId: ex.id,
                                sets: 3,
                                reps: ex.category == .strength ? 10 : nil,
                                weight: ex.category == .strength ? 0 : nil,
                                duration: ex.category != .strength ? 30 : nil,
                                restBetweenSets: 90,
                                rest: 0
                            ))
                        }
                        commit()
                        showAddPicker = false
                    },
                    startTitle: NSLocalizedString("Add", comment: "add selected exercises CTA")
                )
                .presentationDetents([.large])
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
                    }()
                )
                .presentationDetents([.large])
            }
            // 点 PlanStepRow / Card 图片 → 弹动作详情 (跟其它 5 个列表共用 ExerciseDetailSheet).
            // 整行 tap 仍走 NavigationLink 进 EditStepView (改 sets/reps/weight). 图片是 Button,
            // hit-test 优先级高于 NavigationLink, 不会同时触发.
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            .tint(MasoColor.text)
        }
    }

    // 把 draft 写回 data store
    private func commit() {
        draft.updatedAt = Date()
        data.updatePlan(draft)
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
            weight: old.weight,
            duration: old.duration,
            restBetweenSets: old.restBetweenSets,
            rest: old.rest
        )
        commit()
    }

    /// Share — 编码 draft 成 maso:// URL → 弹系统 share sheet.
    /// encode 失败 (理论不会, Plan 一直 Codable) → 弹 alert 兜底, 不静默.
    private func handleSharePlan() {
        guard let url = PlanShareCodec.shareURL(for: draft) else {
            shareFailed = true
            return
        }
        Haptics.tap()
        shareURL = url
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

            // Muscle map — Edit Workout 顶部居中 (跟 PlanRow / SessionCard 列表行的左对齐不同).
            // 这里没有右侧 play/replay 按钮压在同一行, 单纯展示 plan 命中的肌群; 居中视觉更
            // 端正, 不会"左重右空"。fixedSize 阻止 MuscleVisualBlock 撑全宽 (它默认 maxWidth: .infinity).
            HStack {
                Spacer(minLength: 0)
                MuscleVisualBlock(muscles: muscles, sideLength: 110)
                    .fixedSize()
                Spacer(minLength: 0)
            }

            // 主 CTA — body 显眼位置, 实心 accent 胶囊 (Apple Music / Apple Fitness detail 同套路).
            //   - 拥有的计划 (Tab 1): "Start workout"
            //   - Tab 2 browse 预览 (onAddToSaved != nil): "★ Add to my plans" — browse 主操作是加进我的计划.
            if let onAddToSaved {
                addToPlansCTA(onAddToSaved)
            } else {
                startWorkoutCTA
            }
        }
    }

    /// 全宽 "Start workout" 大胶囊 CTA — body 主操作. 跟 toolbar 右上的小 Start 是同一个 action,
    /// 一冗余一隐性: 用户错过 toolbar 也不会错过这个; 已经知道流程的高频用户直接走 toolbar 一步到位.
    private var startWorkoutCTA: some View {
        Button(action: handleStart) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("Start workout")
                    .font(.system(size: 15, weight: .heavy))
            }
            // 不撑满 — 胶囊只包住 图标 + 文字 (用户要求). VStack(.center) 让它居中.
            .padding(.vertical, 13)
            .padding(.horizontal, 28)
            .background(MasoColor.accent)
            .foregroundStyle(.black)
            .clipShape(Capsule())
            .shadow(color: MasoColor.accent.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)  // 跟 muscle map 之间留 18pt (VStack spacing 14 + 4) — 视觉分组
    }

    /// Tab 2 browse 预览的主 CTA — "★ Add to my plans". 跟 startWorkoutCTA 同视觉规格 (实心 accent 胶囊),
    /// icon/文案/action 不同. action (= onAddToSaved) 内部负责 save + 关 sheet (满额弹 paywall).
    private func addToPlansCTA(_ action: @escaping (Plan) -> Void) -> some View {
        // 已添加 → "✓ Added to My Plans" 灰态 + 不可点, 跟卡片外的"已添加"按钮状态保持一致.
        let saved = data.isPlanSaved(draft)
        return Button { if !saved { action(draft) } } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "checkmark" : "star.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text(saved ? "Added to My Plans" : "Add to my plans")
                    .font(.system(size: 15, weight: .heavy))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 28)
            .background(saved ? MasoColor.surfaceHi : MasoColor.accent)
            .foregroundStyle(saved ? MasoColor.textDim : .black)
            .clipShape(Capsule())
            .shadow(color: saved ? .clear : MasoColor.accent.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
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
                                // icon-only → 圆形按钮; tint 走 design.md (negative 红粉 / accent 绿).
                                // 顺序 (从右往左, 因为是 trailing edge): Delete → Edit → Replace
                                Button(role: .destructive) {
                                    pendingDeleteStepId = stp.id
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .tint(MasoColor.negative)
                                .accessibilityLabel(NSLocalizedString("Delete", comment: ""))

                                Button {
                                    // programmatic push — 跟 NavigationLink tap 整行同 destination
                                    stepEditPath.append(stp.id)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .tint(MasoColor.accent)
                                .accessibilityLabel(NSLocalizedString("Edit", comment: ""))

                                // 替换动作 — 弹 ExercisePickerSheet, 选完只替换 exerciseId,
                                // sets/reps/weight 等用户调过的参数全部保留 (替换是"动作换, 强度不变").
                                Button {
                                    stepToReplaceId = stp.id
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .tint(MasoColor.accent)
                                .accessibilityLabel(NSLocalizedString("Replace exercise", comment: ""))
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

    // (P3: 删了死代码 layoutButton — LayoutToggle 组件早接管了, 这个 helper 无任何引用.)

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
                    photoURL: exercise.photoURL,
                    customImageData: exercise.customImageData,
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
                        photoURL: exercise.photoURL,
                        customImageData: exercise.customImageData,
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
                        photoURL: exercise.photoURL,
                        customImageData: exercise.customImageData,
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
        // 不显示 nav title — 用户要求 Edit Workout 系列页面都不要标题
        .navigationBarTitleDisplayMode(.inline)
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
            }
            // "Set rest" 行已移除 — 组间 / 跨动作休息一律跟随 Settings → Training Preferences,
            // 不再 per-plan 存 (expandPlan 也忽略 step 里的 rest 字段).
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
// 不再 private — PlanPlayer 的"替换动作"也复用同一个 sheet (训练中边练边换).

struct ExercisePickerSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void
    /// J4: true = 点动作行直接确认 (onPick + dismiss), 不先弹详情. 替换动作流程用这个.
    var directPick: Bool = false
    /// 替换流程: 用原动作的"部位"预选 Part chip (movement + equipment 留空), 让用户落在
    /// "换个练同一部位的动作"的状态. nil = 不预选.
    var initialMuscle: MuscleGroup? = nil
    /// 多选模式 (自由训练): 点行切换勾选, 底部 Start CTA 把整组动作通过 onPickMultiple 交回.
    /// 单选 (默认) 保持 tap → 详情 / directPick 路径.
    var multiSelect: Bool = false
    var onPickMultiple: (([Exercise]) -> Void)? = nil
    /// multiSelect 底部 CTA 文案 (例 "Start workout"). nil → "Add".
    var startTitle: String? = nil

    @State private var query: String = ""
    /// 顶层 section 筛选 (nil = 全部). 6 个: chest/back/shoulders/arms/core/legs.
    @State private var muscleFilter: MuscleGroup? = nil
    /// 器械筛选 (nil = 不限). "other" + None 都归到 "other".
    @State private var equipmentFilter: String? = nil
    /// 已选动作 id (multiSelect 用; 单选模式忽略).
    @State private var selectedIds: Set<String> = []
    /// tap 列表行 → 弹动作详情. 详情里点 "Add to workout" 才真正 onPick.
    @State private var detailExercise: Exercise? = nil
    /// 小众动作模式 — false (默认): 主库. true: 只看小众库 (从底部入口进).
    @State private var nicheMode: Bool = false
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
        if let t = text?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty {
            result = result.filter { ex in
                ex.name.lowercased().contains(t) ||
                ex.displayName.lowercased().contains(t) ||
                ex.tags.contains(where: { $0.lowercased().contains(t) })
            }
        }
        return result
    }

    /// 当前模式下作为 base 的动作集合 — 主库 (data.userLibrary: 非 niche + adopted niche + custom)
    /// 或小众库 (data.unadoptedNicheExercises: 仍然在 niche stash 里没采纳的).
    /// 两个集合永远无重叠 — 用户采纳一个 niche 后, 它从 unadopted 里消失, 在 userLibrary 里出现.
    private var sourceExercises: [Exercise] {
        nicheMode
            ? data.unadoptedNicheExercises
            : data.userLibrary
    }

    private var filtered: [Exercise] {
        let arr = applyFilters(
            sourceExercises,
            muscle: muscleFilter,
            equipment: equipmentFilter,
            text: query
        )
        // 收藏置顶 — 在 filter 之后排序, 让收藏的动作在当前 filter 结果里排最前
        return Array(data.sortByFavorites(arr).prefix(200))
    }

    /// filtered 按"基础名"折叠成 group. Picker 列表迭代这个, 而不是 flat filtered.
    /// "Bench Press" + "Bench Press (Machine)" + "Bench Press (Dumbbell)" → 1 个 group.
    /// "Speed Bench Press" 独立成自己的 group (它没括号, base = 自身).
    private var filteredGroups: [ExerciseGroup] {
        ExerciseGrouping.group(filtered)
    }

    /// 是不是处于"主动筛选"状态 (有搜索词 / equipment 选定) — 此时所有 group 强制展开,
    /// 用户能直接看见命中的具体变种, 不用每个 group 自己点 disclosure.
    /// 仅 muscle / sub filter 选了不算 (那两个筛肌肉, 不太关心变种).
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var forceExpandAll: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || equipmentFilter != nil
    }

    // MARK: - filter availability — 两维 (部位 / 器械) 互相 narrow 时, 让用户知道哪些选项当前可选

    /// 当前 muscle/text filter (不算 equipment) 下还有动作的 equipment set.
    /// 用菜单项 "dim disabled" 视觉提示 — 让用户知道选了某 muscle 后哪些 equipment 是空集.
    private var availableEquipments: Set<String> {
        let arr = applyFilters(sourceExercises, muscle: muscleFilter, equipment: nil, text: query)
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
        let arr = applyFilters(sourceExercises, muscle: nil, equipment: equipmentFilter, text: query)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索 + Muscle / Equipment 筛选 — 用全 app 共享的 ExerciseSearchFilterBar
                // (跟 Exercises 子页同一组件, 钉在列表上方, 调一处两边都变).
                ExerciseSearchFilterBar(
                    query: $query,
                    muscleFilter: $muscleFilter,
                    equipmentFilter: $equipmentFilter,
                    muscleSections: Self.muscleSections,
                    availableMuscles: availableMuscles,
                    availableEquipments: availableEquipments
                )
                exerciseList()

                // CTA 默认不显示, 选了动作才出现.
                if multiSelect && !selectedIds.isEmpty {
                    startBar
                }
            }
            .animation(.easeOut(duration: 0.22), value: muscleFilter)
            .animation(.easeOut(duration: 0.22), value: equipmentFilter)
            .animation(.easeOut(duration: 0.2), value: selectedIds.isEmpty)
            .sheet(item: $detailExercise) { ex in
                // 详情里的 "Add" — multiSelect 加入勾选; 否则走 onPick (加到 plan / 替换).
                ExerciseDetailSheet(exercise: ex, onAdd: {
                    if multiSelect { selectedIds.insert(ex.id) } else { onPick(ex) }
                })
            }
            // 搜索空 → "添加自己的动作" 表单 (预填搜索词). 创建后 multiSelect 自动勾选这个新动作.
            .sheet(isPresented: $customFormOpen) {
                CustomExerciseFormSheet(
                    initialName: trimmedQuery,
                    onCreated: { ex in if multiSelect { selectedIds.insert(ex.id) } }
                )
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // 小众库标题 — 让用户一眼知道"我在哪个库". 主库时不显示标题 (跟之前一致).
            .navigationTitle(nicheMode ? NSLocalizedString("Rare exercises", comment: "") : "")
            .toolbar {
                if multiSelect {
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

    /// 列表末尾的"切换库"入口 — 主库 ↔ 小众库. 模式不同, 文案与图标都不一样, 用户一眼能看出
    /// 现在按下去会去哪边. tap 后切换 nicheMode + 清掉所有筛选 (两个库的肌群 / 器械分布差很多,
    /// 沿用旧筛选很容易跳进去就 "No exercises match" 一片空).
    @ViewBuilder
    private var nicheToggleFooter: some View {
        let nicheCount = data.exercises.filter { $0.isNiche }.count
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                nicheMode.toggle()
                muscleFilter = nil
                equipmentFilter = nil
                query = ""
            }
            Haptics.tap()
        }) {
            HStack(spacing: 12) {
                Image(systemName: nicheMode ? "arrow.uturn.backward" : "questionmark.diamond")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(MasoColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(nicheMode
                         ? NSLocalizedString("Back to standard library", comment: "")
                         : NSLocalizedString("Browse rare exercises", comment: ""))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Text(nicheMode
                         ? NSLocalizedString("Return to the everyday library", comment: "")
                         : String(format: NSLocalizedString("%d specialized / unusual exercises (foam rollers, battle ropes, machine isolations, etc.)", comment: ""), nicheCount))
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 14)
            .background(MasoColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.borderSoft, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
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
    ///   - canonical: tap 主体打开 detail; 末尾若有变种, 显 "+N" disclosure 胶囊.
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
            showDisclosure: !group.isSingleton && !forceExpandAll,
            showVariantCategoryLabel: false,
            highlighted: multiSelect && selectedIds.contains(ex.id),
            trailing: {
                if multiSelect {
                    Image(systemName: selectedIds.contains(ex.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selectedIds.contains(ex.id) ? MasoColor.accent : MasoColor.textFaint.opacity(0.5))
                }
            },
            onTap: {
                if multiSelect {
                    if selectedIds.contains(ex.id) { selectedIds.remove(ex.id) } else { selectedIds.insert(ex.id) }
                    Haptics.tap()
                } else if directPick {
                    onPick(ex); dismiss()
                } else {
                    detailExercise = ex
                }
            },
            onTapImage: { detailExercise = ex },
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


    @ViewBuilder
    private func exerciseList() -> some View {
        // List + 原生 .swipeActions — 替换自制 SwipeableRow.
        // 自制版跟 ScrollView 的 vertical pan 抢手势 → 上下滑动失效.
        List {
            ForEach(filteredGroups) { group in
                // Canonical 行 — 折叠态唯一可见的一行. 跟旧 row 视觉一致 + 末尾多一个 "+N variants"
                // disclosure 胶囊 (仅有变种时). tap 主体 → 弹 detail; tap disclosure → toggle 组.
                exercisePickerRow(
                    exercise: group.canonical,
                    isVariant: false,
                    group: group
                )

                // 展开时渲染变种 — 拆 "Variation"(动作) / "Equipment"(器械) 两段, 各自带小节头;
                // 每个变种作为独立 List row, 可独立 swipe pin, 缩进区分层级.
                if group.variants.isEmpty == false,
                   forceExpandAll || expandedGroupKey == group.id {
                    groupedVariantSections(for: group) { variant in
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
                    Text(nicheMode
                         ? NSLocalizedString("No rare exercises match your search", comment: "")
                         : NSLocalizedString("No exercises match your search", comment: ""))
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

            // 列表末尾的"切换库"入口 — 主库结尾邀请进小众库, 小众库结尾邀请回主库.
            // 用 list footer 而不是浮动按钮: 让用户在自然滚到底时遇到这个入口, 没在找的时候不打扰.
            nicheToggleFooter
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 24, leading: MasoMetrics.pagePaddingHorizontal,
                                          bottom: 24, trailing: MasoMetrics.pagePaddingHorizontal))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // P2-10: 任何 filter / 搜索 / 库切换变化 → 收起手风琴, 避免残留某组展开态 (尤其 orphan
        // group 的 id 含 filtered canonical, filter 变了 id 也变, 旧 expandedGroupKey 成孤儿).
        .onChange(of: query) { _, _ in expandedGroupKey = nil }
        .onChange(of: equipmentFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: muscleFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: nicheMode) { _, _ in expandedGroupKey = nil }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

// MARK: - ShareActivityView — UIActivityViewController 桥
//
// 用于"分享计划"功能 — 把 maso:// URL 丢给系统 share sheet, 用户选 Messages/AirDrop/Copy/...
// (跟 SettingsScreen 里的 ShareSheet 是同款桥, 但放这里方便 PlanDetailSheet 直接用,
//  不想跨文件依赖私有类型.)
private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
