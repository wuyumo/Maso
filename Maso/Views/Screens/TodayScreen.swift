import SwiftUI

struct TodayScreen: View {
    @Environment(DataStore.self) private var data
    let onStart: (Plan) -> Void
    /// 拉起"自由训练" flow — Today 卡片下方按钮触发, 走 QuickWorkout sheet 选肌肉 / 动作 / 开练
    let onFreeWorkout: () -> Void
    /// 标题行右上角齿轮 → 弹 Settings sheet (RootView 持有 sheet state)
    let onOpenSettings: () -> Void

    /// 卡片 tap → 弹 plan detail sheet 查看动作 + 每组 sets/reps/weight
    @State private var detailPlan: Plan? = nil
    /// 顶部 ProBanner tap → 弹 paywall (跟以前 Plans tab 上的 banner 同款)
    @State private var paywallPresented: Bool = false
    /// 肌肉状态卡上的"训练日历"按钮 → 弹 WorkoutCalendarScreen
    @State private var showCalendar: Bool = false

    private var suggested: Plan? {
        // 优先 AI 生成的今日计划; 没有 (AI 关闭 / API key 未填 / 网络失败) → fallback 系统推荐
        data.aiTodayPlan ?? data.todayRecommendedPlan
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let key: String
        switch h {
        case 0..<5:   key = "Late Night"
        case 5..<12:  key = "Good Morning"
        case 12..<18: key = "Good Afternoon"
        default:      key = "Good Evening"
        }
        // 走 NSLocalizedString — Text("...") 的 LocalizedStringKey 自动查表只对字面量生效,
        // 这里返回的是 var, 必须显式查表才能拿到译文
        return NSLocalizedString(key, comment: "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Pro 展示位 — Pro 用户隐藏. 之前在 Plans tab 顶部, tab 重排后挪到 Today.
                if !data.settings.isPro {
                    ProBanner { paywallPresented = true }
                        .padding(.top, 24)
                }

                // 肌肉状态横版卡 — 移到 "Today's Workout" 标题之上, 当作页面真正的 hero.
                // 横向布局: 左 BodyHint 近正方形 + 右 legend 竖排 + 训练日历 / Train the gaps 按钮.
                MuscleStatusOverviewCard(
                    lastMap: lastMap,
                    gapMuscles: gapMuscles,
                    onShowCalendar: { showCalendar = true },
                    onStartGapWorkout: startGapWorkout
                )
                .padding(.top, data.settings.isPro ? MasoMetrics.pagePaddingTop : 4)

                // Title row 跟 settings 齿轮同行, alignment 用 .top 让齿轮顶部跟 "GOOD AFTERNOON" 对齐.
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(MasoColor.accent)
                        Text("Today's Workout")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    // Settings 齿轮 — 跟 Plans + 按钮同款样式 (text + surface bg + 34×34 圆)
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .frame(width: 34, height: 34)
                            .background(MasoColor.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }

                if let plan = suggested {
                    // kicker 不传 — WorkoutCard 内部自动 derive (FROM YOUR PLAN / AI / nil).
                    WorkoutCard(
                        plan: plan,
                        exById: data.exById,
                        onStart: { onStart(plan) },
                        onShowDetail: { detailPlan = plan }
                    )
                } else {
                    Text("No training plans yet")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.vertical, 60)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // 自由训练入口 — 不依赖今日推荐. 用户想完全自定义 / 临时加练时走这条.
                // 去掉 accent 描边: 之前的 25% accent 边框让它跟 WorkoutCard 视觉对立感太强,
                // 改成纯 surface 卡片 (跟 WorkoutCard 同卡片底色) — 入口归入口, 不喧宾夺主.
                Button(action: onFreeWorkout) {
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(MasoColor.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Free workout")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(MasoColor.text)
                            Text("Pick your own exercises and go")
                                .font(.system(size: 11))
                                .foregroundStyle(MasoColor.textDim)
                                .lineLimit(1)
                        }
                        Spacer()
                        // 跟 PlanPlayer 主播放按钮的中央三角形一致 (play.fill).
                        // 颜色 / 尺寸保留原 chevron 设置, 只换 symbol 形状 → 视觉语义统一为"开始训练".
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.vertical, 14)
                    .background(MasoColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                }
                .buttonStyle(.plain)

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        .background(MasoColor.background.ignoresSafeArea())
        // 详情 sheet — 复用 PlanDetailSheet, 用户在里面可看每个动作的 sets/reps/weight,
        // 也能编辑 (跟 Plans tab 进入是同款体验).
        // onStart 回调走 TodayScreen 自己的 onStart, 让用户在 detail 内开练也走统一入口.
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
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
        }
        .sheet(isPresented: $showCalendar) {
            WorkoutCalendarScreen(
                sessionDates: workoutDateSet(),
                totalSetsThisWeek: totalSetsThisWeek,
                streakDaysCount: currentStreakDays
            )
        }
    }

    // MARK: - 肌肉状态 + 训练日历计算 helpers
    //
    // 从 HistoryScreen 移过来的实现 — 现在两个屏都用同一份. 长期应该把这些挪到
    // MuscleStatusCompute / DataStore extension, 暂时复制一份避免大改.

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

    private func workoutDateSet() -> Set<Date> {
        let cal = Calendar.current
        return Set(data.sets.map { cal.startOfDay(for: $0.performedAt) })
    }

    private var totalSetsThisWeek: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        return data.sets.filter { $0.performedAt >= cutoff }.count
    }

    private var currentStreakDays: Int {
        let cal = Calendar.current
        let days = workoutDateSet()
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        while days.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
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
            for ex in data.exercises where ex.category == .strength {
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
        let plan = Plan(
            id: "plan-catchup",
            name: name,
            steps: steps,
            createdAt: now,
            updatedAt: now
        )
        data.updatePlan(plan)
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
