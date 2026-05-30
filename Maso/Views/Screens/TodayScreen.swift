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

    private var suggested: Plan? {
        // 默认推用户自己的 plans (pickTodayPlan: LRU 挑最久没练那张) —
        // 这些 plan 是用户在 Plans tab 见过、可能调过的, 心智模型上是"我的训练计划",
        // 比 AI 当场生成的陌生 plan 更可信任. AI 路径只在用户 plans 为空时兜底.
        data.todayRecommendedPlan ?? data.aiTodayPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // (ProBanner 已挪到 HistoryScreen 顶部 — Today tab 不再展示.)

                // 肌肉状态 hero 卡
                MuscleStatusOverviewCard(
                    fatigueMap: fatigueMap,
                    gapMuscles: gapMuscles,
                    onStartGapWorkout: startGapWorkout
                )

                // 撤掉外面的 "Today's Workout" section title — 现在直接作为 kicker 进卡内.

                if let plan = suggested {
                    // kicker 显式传 "Today's Workout" — 替代之前内部 derive 出来的 "FROM YOUR PLAN".
                    // 跟 MuscleStatusOverviewCard 的 "MUSCLE STATUS" 同款样式 (textDim 灰小 caps),
                    // 当作"section 标签"贴在卡顶, 用户一眼知道这块卡片对应哪个 section.
                    WorkoutCard(
                        plan: plan,
                        exById: data.exById,
                        kicker: "Today's Workout",
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
                            // DESIGN.md §2.2: 列表行 label = 正文 14pt bold (跟 PlanRow / Community 同档)
                            Text("Free workout")
                                .font(.system(size: 14, weight: .bold))
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
        // 页面底色 #121212 — 跟 Plans / Library 等系统 tab 一致, 不再透出 NavigationStack 默认
        // 纯黑底. ignoresSafeArea 让底色延伸到 home indicator 区, scroll 到顶 / 到底都不露黑边.
        .background(MasoColor.background.ignoresSafeArea())
        // iOS 默认导航栏 — 大标题 "Today" + 右上角 settings gear. NavigationStack 自带 material
        // blur 在滚动时叠加在这个底色上, 跟 Plans 视觉同款.
        .screenHeader("Today") {
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
