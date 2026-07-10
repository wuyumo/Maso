import SwiftUI

// Community — 精选训练计划 (MVP)
//
// 入口: PlansScreen 列表底部 "Browse community plans"
// 流程:
//   - sheet 弹出, 展示 CommunityPlans.all (8 张精选)
//   - 用户 tap "Add to my plans"
//     - 若 free + plans.count >= FreeLimit.maxPlans → 弹 paywall
//     - 否则 clone 进 data.plans → 显示 "Added" 1.2s → dismiss
//
// "发布" 功能不在 MVP — 顶部一行 disclaimer 占位.
struct CommunityScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    /// "Added" toast 状态 — set 完 1.2s 后 dismiss sheet
    @State private var addedToastVisible: Bool = false
    /// Free 用户撞 plan 上限时弹的 paywall
    @State private var paywallPresented: Bool = false
    /// tap 卡片打开详情 preview
    @State private var detailPlan: CommunityPlan? = nil
    /// 顶部筛选: 每周训练天数 (nil = 全部). 跟 levelFilter AND.
    @State private var daysFilter: Int? = nil
    /// 顶部筛选: 进阶程度 (nil = 全部). "Beginner" / "Intermediate" / "Advanced".
    @State private var levelFilter: String? = nil

    /// 难度顺序 — 筛选菜单选项 + 结果排序用.
    private static let levelOrder = ["Beginner", "Intermediate", "Advanced"]

    /// 是否有任一筛选生效 — 有则隐藏"每日精选 / 更多"分段, 改成单一筛选结果列表.
    private var isFiltering: Bool { daysFilter != nil || levelFilter != nil }

    /// 当前筛选命中的 plans (按 难度 → 天数 稳定排序, 让结果列表有序).
    private var filteredPlans: [CommunityPlan] {
        CommunityPlans.all.filter { plan in
            (daysFilter == nil || plan.frequencyDaysPerWeek == daysFilter)
            && (levelFilter == nil || plan.levelKey == levelFilter)
        }.sorted { a, b in
            let la = Self.levelOrder.firstIndex(of: a.levelKey) ?? 9
            let lb = Self.levelOrder.firstIndex(of: b.levelKey) ?? 9
            return la != lb ? la < lb : a.frequencyDaysPerWeek < b.frequencyDaysPerWeek
        }
    }

    /// 所有出现过的"天数"选项 (升序) — 菜单列表用.
    private var allDayOptions: [Int] {
        Set(CommunityPlans.all.map(\.frequencyDaysPerWeek)).sorted()
    }
    /// 当前 level 约束下还有 plan 的"天数" (菜单里 dim 掉空集).
    private var availableDays: Set<Int> {
        Set(CommunityPlans.all.filter { levelFilter == nil || $0.levelKey == levelFilter }
            .map(\.frequencyDaysPerWeek))
    }
    /// 当前天数约束下还有 plan 的"难度".
    private var availableLevels: Set<String> {
        Set(CommunityPlans.all.filter { daysFilter == nil || $0.frequencyDaysPerWeek == daysFilter }
            .map(\.levelKey))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 顶部: subtitle + publish coming-soon disclaimer
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Curated workout plans. Add any to your library.")
                            .font(.system(size: 14))
                            .foregroundStyle(MasoColor.textDim)
                            .fixedSize(horizontal: false, vertical: true)

                        // 之前: "Want to publish your plan? Coming soon." (被动等待)
                        // 现在: 主动指引到分享入口 (Plans 详情页的 Share 按钮),
                        // 让用户知道分享功能已经上线 + 操作路径.
                        Text("Want to share your plan? Open it in Plans → tap Share.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 8)

                    // 顶部筛选 — 每周训练天数 + 进阶程度 (FilterMenuButton 下拉, 跟全 app 一致).
                    filterRow

                    if isFiltering {
                        // 有筛选 → 单一结果列表 (隐藏每日轮播分段).
                        let results = filteredPlans
                        sectionHeader(LocalizedStringKey(
                            results.isEmpty
                            ? "No routines match"
                            : "\(results.count) \(results.count == 1 ? "routine" : "routines")"
                        ))
                        if results.isEmpty {
                            emptyFilterState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(results) { plan in
                                    CommunityPlanCard(plan: plan, onTapBody: { detailPlan = plan }, onAdd: { handleAdd(plan) })
                                }
                            }
                            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                        }
                    } else {
                        // 无筛选 → 每日精选 (按日期轮播) + 其余全部. 让用户每次来都先看到一批不同的"达人"计划.
                        let featured = CommunityPlans.featured(count: 6)
                        let featuredIds = Set(featured.map(\.id))
                        let more = CommunityPlans.all.filter { !featuredIds.contains($0.id) }

                        sectionHeader("Featured today")
                        LazyVStack(spacing: 12) {
                            ForEach(featured) { plan in
                                CommunityPlanCard(plan: plan, onTapBody: { detailPlan = plan }, onAdd: { handleAdd(plan) })
                            }
                        }
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                        sectionHeader("More programs")
                        LazyVStack(spacing: 12) {
                            ForEach(more) { plan in
                                CommunityPlanCard(plan: plan, onTapBody: { detailPlan = plan }, onAdd: { handleAdd(plan) })
                            }
                        }
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    }

                    Color.clear.frame(height: 24)
                }
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Classics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 顶栏规范: 浏览型 sheet 统一系统默认 Done (.confirmationAction) —
                // 去掉自定义字重/颜色, 跟 ClassicsSheet / PlateCalculator 等同一种写法.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
            .overlay(alignment: .top) {
                if addedToastVisible {
                    AddedToast()
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallScreen()
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $detailPlan) { plan in
                CommunityPlanDetailSheet(
                    plan: plan,
                    onAdd: {
                        detailPlan = nil
                        // 让 sheet 关一帧再 add — 不然 toast 跟 sheet 状态冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            handleAdd(plan)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(MasoColor.text)
    }

    @ViewBuilder
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(MasoColor.textDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 4)
    }

    /// 顶部两个筛选下拉 (每周天数 / 进阶程度) + 一个 Clear. 用全 app 共用的 FilterMenuButton.
    @ViewBuilder
    private var filterRow: some View {
        HStack(spacing: 8) {
            let availD = availableDays
            FilterMenuButton(
                title: NSLocalizedString("Days/wk", comment: "community filter — days per week"),
                allLabel: NSLocalizedString("Any frequency", comment: ""),
                selected: $daysFilter,
                options: allDayOptions.map { d in
                    FilterMenuOption(
                        value: d,
                        label: String(format: NSLocalizedString("%lld days", comment: "days-per-week option"), d),
                        enabled: availD.contains(d) || daysFilter == d
                    )
                }
            )

            let availL = availableLevels
            FilterMenuButton(
                title: NSLocalizedString("Level", comment: "community filter — difficulty"),
                allLabel: NSLocalizedString("Any level", comment: ""),
                selected: $levelFilter,
                options: Self.levelOrder.map { lvl in
                    FilterMenuOption(
                        value: lvl,
                        label: NSLocalizedString(lvl, comment: "difficulty level"),
                        enabled: availL.contains(lvl) || levelFilter == lvl
                    )
                }
            )

            Spacer(minLength: 0)

            if isFiltering {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) { daysFilter = nil; levelFilter = nil }
                }) {
                    Text(NSLocalizedString("Clear", comment: "clear filters"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MasoColor.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(MasoColor.textFaint)
            Text("No routines match these filters yet.")
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
    }

    private func handleAdd(_ plan: CommunityPlan) {
        // Free-cap check — 实例化后的 session 数会让总 plans 超 FreeLimit.maxPlans 也算撞墙
        // (一次性 add 一张 community plan, 但它可能包含 5 个 session = 5 张 Plan)
        let willAddCount = plan.sessions.count
        if !data.settings.isPro && data.plans.count + willAddCount > FreeLimit.maxPlans {
            paywallPresented = true
            return
        }

        let newPlans = plan.materialize(byId: data.exById)
        guard !newPlans.isEmpty else { return }

        data.plans.append(contentsOf: newPlans)
        data.save()

        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            addedToastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                addedToastVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                dismiss()
            }
        }
    }
}

// MARK: - CommunityPlanCard

private struct CommunityPlanCard: View {
    let plan: CommunityPlan
    let onTapBody: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // kicker
            Text(plan.kicker)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(MasoColor.accent)

            // 大标题
            Text(NSLocalizedString(plan.nameKey, comment: ""))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // 教练署名 — 给"达人计划"的感觉 (虚拟教练人设, 非真实网红).
            Text(CommunityPlans.coach(for: plan))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MasoColor.textFaint)

            // 副标题 (一行说明)
            Text(NSLocalizedString(plan.descKey, comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // chips: 频率 / 难度 / 动作数
            HStack(spacing: 6) {
                Chip(
                    text: String(
                        format: NSLocalizedString("%lld days/wk", comment: "frequency chip — days per week"),
                        plan.frequencyDaysPerWeek
                    )
                )
                Chip(text: NSLocalizedString(plan.levelKey, comment: "level chip"))
                Chip(
                    text: String(
                        format: NSLocalizedString("%lld exercises", comment: "exercise count chip"),
                        plan.totalExerciseCount
                    )
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            // CTA 右下
            HStack {
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add to my plans")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    // 卡内重复出现的小实心钮 → 次级玻璃 (同 Optimize with AI 的降级处置, 映射表②):
                    // iOS 26 = accent 低浓度玻璃 + accent 字; 旧系统保留实心 accent + 深字.
                    .foregroundStyle(systemGlassAvailable ? MasoColor.accent : MasoColor.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25), fallback: MasoColor.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to my plans")
            }
            .padding(.top, 4)
        }
        .padding(MasoMetrics.cardPadding - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // 整张卡 tap 弹详情 preview (Add 按钮自己有 hit area, 不冲突)
        .contentShape(Rectangle())
        .onTapGesture { onTapBody() }
    }
}

// MARK: - Chip

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// MARK: - CommunityPlanDetailSheet — 详情预览 (read-only, 横跨所有 session)

private struct CommunityPlanDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let plan: CommunityPlan
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header — kicker, title, description, chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.kicker)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                        Text(NSLocalizedString(plan.nameKey, comment: ""))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(NSLocalizedString(plan.descKey, comment: ""))
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            DetailChip(text: String(
                                format: NSLocalizedString("%lld days/wk", comment: ""),
                                plan.frequencyDaysPerWeek
                            ))
                            DetailChip(text: NSLocalizedString(plan.levelKey, comment: ""))
                            DetailChip(text: String(
                                format: NSLocalizedString("%lld exercises", comment: ""),
                                plan.totalExerciseCount
                            ))
                        }
                        // 频率 > session 数 → 说明这是"少数几套训练轮着练满一周"的结构 (e.g. StrongLifts:
                        // 2 套 A/B 一周练 3 次). 否则用户会以为"标 3 天却只有 2 天内容"是 bug.
                        if plan.sessions.count < plan.frequencyDaysPerWeek {
                            Text(String(
                                format: NSLocalizedString("Rotate these %lld workouts to train %lld days a week.", comment: "explains an alternating / repeating split"),
                                plan.sessions.count, plan.frequencyDaysPerWeek
                            ))
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.top, 4)

                    // Sessions list — 每个 session 一段 (kicker 标题 + 动作行)
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(plan.sessions.enumerated()), id: \.offset) { _, session in
                            SessionPreviewBlock(session: session, exById: data.exById)
                        }
                    }

                    // 底部 CTA — Add to my plans (跟卡内按钮同款绿胶囊)
                    Button(action: onAdd) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("Add to my plans")
                                .font(.system(size: 15, weight: .heavy))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        // 主 CTA 系统玻璃 (映射表①), 旧系统保留实心 accent.
                        .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.85), fallback: MasoColor.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(MasoColor.text)
    }
}

private struct DetailChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

/// Session preview — kicker ("PUSH DAY") + 该 session 的 exercise 行列表
private struct SessionPreviewBlock: View {
    let session: CommunitySession
    let exById: [String: Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString(session.nameKey, comment: "").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(MasoColor.accent)
            VStack(spacing: 8) {
                ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                    StepRow(step: step, exercise: exById[step.exerciseId])
                }
            }
        }
    }
}

/// 单条动作 row — image thumbnail + name + sets×reps + rest
private struct StepRow: View {
    let step: CommunityStep
    let exercise: Exercise?

    var body: some View {
        HStack(spacing: 12) {
            if let ex = exercise {
                ExerciseImage(
                    category: ex.category,
                    imageFolder: ex.imageFolder,
                    photoURL: ex.photoURL,
                    cornerRadius: 8,
                    size: 44,
                    animated: false
                )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MasoColor.surfaceHi)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "questionmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MasoColor.textFaint)
                    )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise?.displayName ?? step.exerciseId)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Text(stepMeta)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var stepMeta: String {
        var parts: [String] = []
        if let reps = step.reps {
            parts.append("\(step.sets)×\(reps)")
        } else if let dur = step.duration {
            parts.append("\(step.sets)×\(dur)s")
        } else {
            parts.append("\(step.sets) sets")
        }
        parts.append("· \(step.restBetweenSets)s rest")
        return parts.joined(separator: " ")
    }
}

// MARK: - AddedToast

private struct AddedToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MasoColor.accent)
            Text("Added")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MasoColor.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MasoColor.surfaceHi)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
