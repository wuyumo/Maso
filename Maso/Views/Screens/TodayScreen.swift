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

    /// 卡片 tap → 弹 plan detail sheet 查看动作 + 每组 sets/reps/weight (WorkoutCard + PlanRow 共用)
    @State private var detailPlan: Plan? = nil
    /// 删 plan 的二次确认 (从原 Plans 页迁来).
    @State private var pendingDeletePlanId: String? = nil
    /// 社区精选 sheet (从原 Plans 页迁来).
    @State private var communityPresented: Bool = false

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
        // ScrollView + LazyVStack — 复杂 hero 卡 (WorkoutCard 里有自定义 Layout) 在 List row 的
        // nil-width sizing pass 下会塌. ScrollView 给的是确定宽度, 渲染稳. 计划行的删/改改走长按
        // contextMenu (代替 List 的右滑); 排序暂不提供 (原 Plans 页的拖拽随 List 一起去掉了).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ── 训练状态 ── (MuscleStatusOverviewCard 自带 "MUSCLE STATUS" kicker)
                MuscleStatusOverviewCard(
                    fatigueMap: fatigueMap,
                    gapMuscles: gapMuscles,
                    onStartGapWorkout: startGapWorkout
                )

                // ── 今日推荐 ── (WorkoutCard 自带 "TODAY'S WORKOUT" kicker)
                if let plan = suggested {
                    WorkoutCard(
                        plan: plan,
                        exById: data.exById,
                        kicker: "Today's Workout",
                        onStart: { onStart(plan) },
                        onShowDetail: { detailPlan = plan }
                    )
                }

                // ── 我的训练 ── section header (kicker + restore? + 新建入口) — 原 Plans 页移过来.
                myPlansHeader.padding(.top, 4)

                if data.plans.isEmpty {
                    plansEmptyState
                } else {
                    PlanRationaleCard()
                    ForEach(data.plans) { plan in
                        PlanRow(
                            plan: plan,
                            exById: data.exById,
                            onTap: { detailPlan = plan },
                            onStart: { onStart(plan) },
                            onDelete: { pendingDeletePlanId = plan.id }
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

                // ── 入口: 自由训练 + 社区 (并排两块) ──
                HStack(spacing: 12) {
                    entryCard(icon: "dumbbell.fill", title: "Free workout", action: onFreeWorkout)
                    entryCard(icon: "person.2.fill", title: "Community", action: { communityPresented = true })
                }
                .padding(.top, 4)

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        .background(MasoColor.background.ignoresSafeArea())
        // 自定义页头: greeting kicker + "Today" 26pt + 齿轮 (DESIGN.md §4.2).
        .screenHeader("Today", kicker: greeting) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
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
        }
        .sheet(isPresented: $communityPresented) {
            CommunityScreen()
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

    /// "MY PLANS" 小标题 + 右侧 (restore 可选) + 新建 "+".
    private var myPlansHeader: some View {
        HStack(spacing: 14) {
            Text("My plans")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
            Spacer()
            if hasNoRecommendedPlans {
                Button(action: restoreRecommendedPlans) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                }
                .accessibilityLabel(NSLocalizedString("Restore recommended", comment: ""))
            }
            Button(action: onNewPlan) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
            }
            .accessibilityLabel("New workout")
        }
    }

    private var plansEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(MasoColor.textFaint)
            Text("No plans yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MasoColor.text)
            Text("Create your own workout, or restore the recommended set.")
                .font(.system(size: 12))
                .foregroundStyle(MasoColor.textDim)
                .multilineTextAlignment(.center)
            Button(action: onNewPlan) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New workout")
                }
                .font(.system(size: 14, weight: .heavy))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(MasoColor.accent)
                .foregroundStyle(.black)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// 并排的小入口卡 (自由训练 / 社区).
    private func entryCard(icon: String, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // 图标弱化 — 从 accent 绿 + heavy 改成 textDim 灰 + medium, 不抢眼 (这俩是次级入口).
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MasoColor.textDim)
                // 标题行带向右 chevron — 提示可点进 (跟 PlanRow 的 chevron 同款样式).
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
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
