import SwiftUI

/// routine 来源标签 — AI(✨) / Classics(🎗rosette). custom → 不渲染.
/// PlanRow(Routines tab) 与 WorkoutCard(Today) 共用, 视觉一致.
struct PlanSourceBadge: View {
    let source: PlanSource
    var body: some View {
        switch source {
        case .ai:       badge(icon: "sparkles", text: "AI")
        case .classics: badge(icon: "rosette", text: "Classics")
        // 本地兜底 — 中性灰, 明确区别于 accent 绿的 AI/Classics (那两个是"给你的好东西",
        // 这个是"AI 没连上时的替代品", 用同色会误导).
        case .builtIn:  badge(icon: "wifi.slash", text: "Built-in", tint: MasoColor.textDim)
        case .custom:   EmptyView()
        }
    }
    @ViewBuilder private func badge(icon: String, text: LocalizedStringKey,
                                    tint: Color = MasoColor.accent) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .heavy))
            Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.18))
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 0.5))
        .clipShape(Capsule())
        .fixedSize()
    }
}

// 今日训练卡片 — Home 页核心元素
// 跟 web 端 WorkoutCard.tsx 对应: 显示 plan 名 + 推断肌群 BodyHint + 步骤摘要 + 大开始按钮
struct WorkoutCard: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var training

    let plan: Plan
    let exById: [String: Exercise]
    /// Caller 显式覆盖卡片顶部 kicker (e.g. "TODAY"). 默认 nil → 内部 derive:
    ///   - AI 生成 → 不显示 (AI badge 已表达)
    ///   - 该 plan 在用户的 plans 数组里 → "FROM YOUR PLAN" (今日推荐时让用户知道来自自己的计划)
    ///   - 其他 → 不显示
    /// 显式传 "" 可以强制不显示.
    var kicker: String? = nil
    var onStart: () -> Void
    /// 可选 — 整张卡可点查看 plan 详情 (动作列表 + sets/reps/weight).
    /// 当 caller 传了这个 callback, 卡片整体变成 button. 没传 → 纯展示.
    var onShowDetail: (() -> Void)? = nil
    /// Play 按钮视觉强度:
    ///   - true (默认): accent 胶囊 + 黑色图标和文案 (Today's Workout 主 CTA).
    ///   - false: accent 半透明胶囊 + accent 图标和文案 (其它计划卡, 弱化).
    var prominentStart: Bool = true
    /// 首页非今日卡沿用原尺寸与玻璃样式，只将次级按钮切到 iOS 系统蓝色。
    var secondaryActionAccent: Color? = nil
    /// Tab 2 (Plans browse) 专用 — 设了这个 callback → 卡片底部出现 "★ 添加到我的计划" 主按钮,
    /// 同时隐藏开始训练按钮 (browse 语境主操作是"加进我的计划"而非"开始"). Tab 1 不传 → 行为不变.
    var addAction: (() -> Void)? = nil
    /// 多日经典计划可在保存按钮上显示将加入的 routine 数量。
    var addActionRoutineCount: Int? = nil
    /// 计划浏览场景可将保存操作居中；其它调用点默认靠右。
    var centersAddAction = false
    /// Today's Workout 主卡专用 — true → accent 描边 + 绿色辉光, 跟弱化的 My Plans 计划卡拉开视觉层级
    /// (两者之前样式几乎一样, 容易混淆).
    var emphasized: Bool = false
    /// 右下角开始训练按钮是否显示. false → 不显示 (点卡片进详情页再 Start).
    /// Routines tab 的 Saved 计划卡用 false — 那语境主操作是"查看/管理计划", 不是即时开练.
    var showStart: Bool = true
    /// 紧凑卡使用较小的居中肌肉图；动作内容在详情中查看。
    var compactLayout: Bool = false
    /// Classics 分组内缩紧完整 routine 卡 (保留动作胶囊, 减少图与内边距).
    var denseLayout: Bool = false
    /// 书签态覆盖 — Coach 生成卡传 data.isCoachPlanSaved(plan) (savedIdMap 反查, 副本改名后不失灵).
    /// nil → 现状 data.isPlanSaved(plan) (签名匹配), 其它调用方不受影响.
    var savedOverride: Bool? = nil
    /// Chat results show every exercise; the home carousel keeps its compact summary.
    var showsExercisePills = false
    var embedded = false
    var showsSourceBadge = true
    var onExercisePillTap: ((Exercise) -> Void)? = nil
    /// 修订计划时传入对应的上一版, 在卡片里直接说明本次针对性调整.
    var previousPlan: Plan? = nil
    /// The newest chat result can target an exercise for a conversational swap.
    var onExercisePillLongPress: ((String) -> Void)? = nil
    /// 等高轮播 (#today-carousel) 专用 — Today 轮播量测所有卡自然高取 max 后回写这里:
    /// 非 nil 时卡片拉伸到该高度，动作区顶部对齐，播放键保留在右下角.
    /// nil (默认) = 自然高度, 其它调用方零改动.
    var fixedHeight: CGFloat? = nil
    var reservesKickerSpace = false
    /// Home passes this week’s explicit completion state; other surfaces keep their existing behavior.
    var completedOverride: Bool? = nil

    private var displayedPlan: Plan { data.routinePlanDefaults(plan) }

    private var isTraining: Bool {
        training.session?.planId == plan.id && training.session?.completed == false
    }
    private var trainedToday: Bool {
        completedOverride ?? data.sets.contains { $0.planId == plan.id && Calendar.current.isDateInToday($0.performedAt) }
    }

    private var muscleMapSideLength: CGFloat {
        showsExercisePills ? (denseLayout ? 112 : 132) : (compactLayout ? 92 : 140)
    }

    private var cardContentPadding: CGFloat { embedded ? 0 : (denseLayout ? 14 : MasoMetrics.cardPadding) }

    private var inferredMuscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for step in displayedPlan.steps {
            guard let ex = exById[step.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if seen.insert(m).inserted { out.append(m) }
            }
        }
        return out
    }

    /// 给"今日肌群"chip 用的肌群列表 — 把细分 (upperChest/midChest/...) 合并到大肌群,
    /// 用户视角看的是 ["Chest", "Triceps", "Glutes"] 而不是 ["Upper Chest", "Mid Chest", ...].
    /// 顺序按 inferredMuscles 出现的顺序, 但保留 major 优先级.
    ///
    /// 落点用共享 MuscleSelector.majorOf — 全 app 肌群归一的唯一入口.
    private var summarizedMuscles: [MuscleGroup] {
        let mapped: [MuscleGroup] = inferredMuscles.map { MuscleSelector.majorOf($0) }
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for m in mapped where m != .fullBody {
            if seen.insert(m).inserted { out.append(m) }
        }
        return out
    }

    /// 通过 plan.id 前缀判断这张是不是 AI 生成的 — AIWorkoutService 用 "plan-ai-..." 命名,
        /// 系统推荐用 "plan-full*/plan-bal*/plan-push*..." 命名, 用户自建用 "plan-new-...".
    /// 这样不需要 caller 显式传 flag, 卡片自己根据 id 表达"AI" 来源.
    private var isAIGenerated: Bool {
        plan.resolvedSource == .ai
    }

    /// 该 plan 是不是用户自己 plans 数组里挑的 (今日推荐走 pickTodayPlan 命中用户某条 plan).
    /// 用来在卡片顶部显示 "FROM YOUR PLAN" — 让用户明确"今日卡 = 我自己设的计划"而非随机生成.
    private var isFromUserPlan: Bool {
        data.plans.contains(where: { $0.id == plan.id })
    }

    /// 实际渲染的 kicker 文案. nil → 不渲染 kicker 行.
    /// 优先级: caller 显式覆盖 > AI 屏蔽 > Plan source > nil
    private var resolvedKicker: String? {
        // Caller 显式传值 (包括 "") — 完全交给 caller. 空串视为"强制不显示".
        if let k = kicker {
            return k.isEmpty ? nil : NSLocalizedString(k, comment: "WorkoutCard kicker")
        }
        // AI 已经有 badge, kicker 不重复表达来源
        if isAIGenerated { return nil }
        if isFromUserPlan {
            return NSLocalizedString("FROM YOUR PLAN", comment: "Today card source — user plan")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kicker 行 — 跟 Plans tab 的 TRAINING PREFERENCES kicker 完全对齐:
            // SF Symbol + accent 绿 10pt heavy + tracking 1.5. icon 选 figure.strengthtraining,
            // 跟 Today tab 自己的 tab icon 同款, 给"今日训练" section 一个视觉锚点.
            if resolvedKicker != nil || reservesKickerSpace || (showsSourceBadge && plan.resolvedSource != .custom) {
                HStack(spacing: 6) {
                    if let resolvedKicker {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 10, weight: .heavy))
                            Text(resolvedKicker)
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.5)
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(MasoColor.accent)
                    }
                    Spacer(minLength: 4)
                    if showsSourceBadge { PlanSourceBadge(source: plan.resolvedSource) }
                }
                .accessibilityHidden(resolvedKicker == nil && plan.resolvedSource == .custom)
                .padding(.horizontal, cardContentPadding)
                .padding(.top, denseLayout ? cardContentPadding : MasoMetrics.cardPadding + 2)   // kicker ↔ 卡边
                .padding(.bottom, denseLayout ? 6 : MasoMetrics.cardHeaderGap)
            }

            // 标题行: plan name + 右侧 chevron; source badge lives in the upper-right kicker row.
            HStack(alignment: .top, spacing: 8) {
                Text(plan.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    // Titles use their actual height so the subtitle stays attached.
                    // The shared carousel height keeps cards equal-height.
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if onShowDetail != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(MasoColor.textFaint)
                }
            }
            .padding(.horizontal, cardContentPadding)
            // 没 kicker 时, title 自己撑顶部留白
            .padding(.top, resolvedKicker == nil && !reservesKickerSpace ? cardContentPadding : 0)
            .contentShape(Rectangle())
            .applyIf(onExercisePillTap != nil && onShowDetail != nil) {
                $0.onTapGesture { onShowDetail?() }.accessibilityAddTraits(.isButton)
            }

            // (AI 理由 rationale 已从卡上移除 — owner: 卡上只留标题+计数, 理由仅在详情页标题下显示.)

            // Subtitle — exercises · sets, 紧挨标题 (所有 routine 卡统一: 标题 + 计数 在一起).
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .padding(.horizontal, cardContentPadding)
                .padding(.top, 4)

            MuscleVisualBlock(muscles: inferredMuscles, sideLength: muscleMapSideLength)
                .frame(width: muscleMapSideLength, height: muscleMapSideLength)
                .frame(maxWidth: .infinity,
                       maxHeight: reservesKickerSpace && fixedHeight != nil && !showsExercisePills ? .infinity : nil,
                       alignment: .center)
                .padding(.top, reservesKickerSpace && !showsExercisePills ? 20 : (denseLayout ? 8 : (compactLayout ? 12 : 20)))

            if showsExercisePills, !plan.steps.isEmpty {
                LimitedFlowLayout(spacing: 6, maxRows: 999, onTruncate: { _ in }) {
                    ForEach(displayedPlan.steps) { step in
                        if let exercise = exById[step.exerciseId] {
                            let section = exercise.primaryMuscles.first.map { $0.section ?? $0 }
                            exercisePill(exercise, section: section)
                        }
                    }
                    // LimitedFlowLayout treats its last child as an overflow indicator.
                    ExercisePill(name: "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, cardContentPadding)
                .padding(.top, denseLayout ? 8 : 12)
            }

            if let previousPlan {
                RoutineRevisionDetails(previous: previousPlan, current: plan, exById: exById)
                    .padding(.horizontal, cardContentPadding)
                    .padding(.top, denseLayout ? 10 : 14)
            }

            if fixedHeight != nil && !(reservesKickerSpace && !showsExercisePills) {
                Spacer(minLength: 0)
            }

            if addAction == nil && showStart {
                Button(action: onStart) {
                    startButtonLabel
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, cardContentPadding)
                .padding(.top, reservesKickerSpace && !showsExercisePills ? 24 : (denseLayout ? 12 : 16))
                .disabled(isTraining)
                .accessibilityLabel(isTraining ? "Training in progress" : (trainedToday ? "Train again" : "Start workout"))
                .accessibilityIdentifier("workout.card.start")
            }

            // Tab 2 (Plans browse): 卡片底部 "Save" 主按钮.
            if let addAction {
                AddToPlansButton(isSaved: savedOverride ?? data.isPlanSaved(plan),
                                 routineCount: addActionRoutineCount,
                                 action: addAction)
                    .disabled(savedOverride == true)
                    .frame(maxWidth: .infinity, alignment: centersAddAction ? .center : .trailing)
                    .padding(.horizontal, cardContentPadding)
                    .padding(.top, denseLayout ? 10 : 14)
            }
        }
        .padding(.bottom, cardContentPadding)
        // 等高轮播: 统一高度在 background 之前生效 — surface 底随卡一起拉伸. nil 时是 no-op.
        .frame(height: fixedHeight)
        // 有 detail callback 时整张卡可点 (BodyHint hit-test 没接 onMuscleTap, 不冲突).
        // 用 contentShape + onTapGesture 而不是 Button — 避免 SwiftUI 给整卡套上 button style 改色.
        .contentShape(Rectangle())
        .applyIf(onExercisePillTap == nil && onShowDetail != nil) { view in
            view.onTapGesture { onShowDetail?() }
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("workout.card.detail.\(plan.id)")
        }
        // Native glass gives routine cards a translucent, frosted surface.
        .applyIf(!embedded) { $0.glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)) }
    }

    /// 用图标 + 文案明确表达开始训练，保留今日推荐与其它 routine 的视觉层级。
    private var startButtonLabel: some View {
        let accent = prominentStart ? MasoColor.accent : (secondaryActionAccent ?? MasoColor.accent)
        return TrainingCardActionLabel(title: isTraining ? "Training in progress" : (trainedToday ? "Train again" : "Start workout"),
                                       icon: isTraining ? "figure.strengthtraining.traditional" : (trainedToday ? "arrow.clockwise" : "play.fill"),
                                       accent: accent, prominent: prominentStart && !isTraining)
    }

    @ViewBuilder
    private func exercisePill(_ exercise: Exercise, section: MuscleGroup?) -> some View {
        let pill = ExercisePill(
            name: exercise.displayName,
            part: section?.displayName,
            section: section,
            muscleIcon: data.settings.exerciseChipMuscleIcon
        )
        if let onExercisePillTap {
            Button { onExercisePillTap(exercise) } label: { pill }.buttonStyle(.plain)
        } else if let onExercisePillLongPress {
            pill.onLongPressGesture {
                Haptics.tap()
                onExercisePillLongPress(exercise.displayName)
            }
        } else {
            pill
        }
    }


}

/// Compact, readable comparison shown only on AI revised routine cards.
private struct RoutineRevisionDetails: View {
    struct Change: Identifiable {
        enum Kind: Equatable { case added, removed, adjusted }
        let id: String
        let kind: Kind
        let name: String
        let detail: String?
    }

    let previous: Plan
    let current: Plan
    let exById: [String: Exercise]

    private var changes: [Change] {
        var oldByExercise = Dictionary(grouping: previous.steps, by: \.exerciseId)
        let newByExercise = Dictionary(grouping: current.steps, by: \.exerciseId)
        var result: [Change] = []

        for step in current.steps {
            let name = exById[step.exerciseId]?.displayName ?? step.exerciseId
            guard var oldMatches = oldByExercise[step.exerciseId], !oldMatches.isEmpty else {
                result.append(Change(id: "added-\(step.id)", kind: .added, name: name, detail: nil))
                continue
            }
            let old = oldMatches.removeFirst()
            oldByExercise[step.exerciseId] = oldMatches
            let before = targetSummary(old)
            let after = targetSummary(step)
            if before != after {
                result.append(Change(id: "adjusted-\(step.id)", kind: .adjusted, name: name,
                                     detail: "\(before) → \(after)"))
            }
        }

        for step in previous.steps where oldByExercise[step.exerciseId]?.contains(where: { $0.id == step.id }) == true {
            let name = exById[step.exerciseId]?.displayName ?? step.exerciseId
            result.append(Change(id: "removed-\(step.id)", kind: .removed, name: name, detail: nil))
            oldByExercise[step.exerciseId]?.removeAll(where: { $0.id == step.id })
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 10, weight: .bold))
                Text("Changes from previous routine")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
            }
            .foregroundStyle(MasoColor.accent)

            if changes.isEmpty {
                Text("This routine stayed the same")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
            } else {
                ForEach(changes) { change in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(label(for: change.kind))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(change.kind == .removed ? MasoColor.textDim : MasoColor.accent)
                        Text(change.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MasoColor.text)
                        if let detail = change.detail {
                            Text(detail)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(MasoColor.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(MasoColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func label(for kind: Change.Kind) -> LocalizedStringKey {
        switch kind {
        case .added: "Added"
        case .removed: "Removed"
        case .adjusted: "Adjusted"
        }
    }

    private func targetSummary(_ step: PlanStep) -> String {
        if let duration = step.duration, step.reps == nil {
            return "\(step.sets) × \(duration)s"
        }
        let reps = step.reps.map(String.init) ?? "–"
        var summary = "\(step.sets) × \(reps)"
        if let weight = step.weight, weight > 0 {
            summary += " · \(weight.formatted(.number.precision(.fractionLength(0...1)))) kg"
        }
        return summary
    }
}

/// 动作名 chip — 半透底 capsule. 主练部位 (Chest / Back / ...) 在前 + 具体动作名字 (Bench Press / ...) 在后.
/// 部位用 accent 绿 + 小一号字, 作前缀标签; 动作名白色, 跟部位在颜色 + 字号上都有明显差别, 一眼区分"部位 vs 动作".
/// 各自限 1 行, 长名自动截尾, 不撑爆 FlowLayout.
private struct ExercisePill: View {
    let name: String
    var part: String? = nil
    /// 部位大区枚举 — "肌肉图示"模式画 MuscleRegionIcon 用 (nil = 无部位, 两种模式都不显示前缀).
    var section: MuscleGroup? = nil
    /// true → 部位前缀用迷你肌肉图代替文字 (settings.exerciseChipMuscleIcon, owner 的可切换偏好).
    var muscleIcon: Bool = false
    var body: some View {
        // DESIGN.md §2.2: chip 类小标签走 11pt + 紧凑 padding. 部位前缀再小 1pt (10pt) 拉开层级.
        HStack(spacing: 5) {
            if muscleIcon, let section {
                // 迷你肌肉部位图 — 跟 Exercises 索引 rail 同一份 MuscleRegionIcon (聚焦该区的
                // 精细分块); accent 主体 + 弱化衬托, 16pt 与 10pt 文字前缀占位相近, 不撑高 chip.
                MuscleRegionIcon(region: section,
                                 focusColor: MasoColor.accent,
                                 surroundColor: MasoColor.accent.opacity(0.28),
                                 size: 16)
                    .accessibilityLabel(Text(section.displayName))
            } else if let part, !part.isEmpty {
                Text(part)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
                    .lineLimit(1)
            }
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MasoColor.text.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(MasoColor.surfaceHi)
        .clipShape(Capsule())
    }
}

/// Tab 2 / Coach 卡片底部主操作 — Save ↔ Saved 书签开关 (coach-tab-design.md §2).
/// 使用 iOS bordered 小按钮; 在卡片列表中保持轻量, 主页面仍由动作卡片承载视觉重点.
/// icon: plus (未存) ↔ checkmark (已存). **两态都可点** — action 恒触发, toggle 语义由
/// 调用方决定 (Coach: 已存再点 = unsave; Classics 这类"存整套"的调用方自己 guard). 视觉沿用现状:
/// 未存 accent (可操作) / 已存灰 (已收藏态).
struct AddToPlansButton: View {
    /// 该计划是否已在"我的计划"里 — true → checkmark 已存态 (仍可点, 再点由调用方 unsave).
    var isSaved: Bool = false
    /// Classics 整套保存时显示包含的 routine 数量；nil 时使用通用文案。
    var routineCount: Int? = nil
    var titleOverride: String? = nil
    var action: () -> Void

    private var title: String {
        if let titleOverride { return NSLocalizedString(titleOverride, comment: "routine save state") }
        guard let routineCount else {
            return NSLocalizedString(isSaved ? "Saved to routines" : "Save to routines", comment: "")
        }
        let key: String
        if routineCount == 1 {
            key = isSaved ? "Saved %lld routine" : "Save %lld routine"
        } else {
            key = isSaved ? "Saved %lld routines" : "Save %lld routines"
        }
        return String(format: NSLocalizedString(key, comment: ""), Int64(routineCount))
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSaved ? "checkmark" : "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MasoColor.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassCapsuleButtonBackground(fallback: MasoColor.surfaceHi)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSaved)
    }
}

/// Shared horizontal stack for generated plans and the first-run preview.
struct PlanCardCarousel<Card: View>: View {
    let plans: [Plan]
    var horizontalInset: CGFloat = 0
    var onSelectionChange: (String) -> Void = { _ in }
    @ViewBuilder var card: (Int, Plan) -> Card
    @State private var position: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                    card(index, plan)
                        .accessibilityIdentifier("plan.carousel.card.\(index)")
                        .containerRelativeFrame(.horizontal) { width, _ in
                            max(0, width - horizontalInset * 2 - (plans.count > 1 ? 32 : 0))
                        }
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.97, anchor: .center)
                        }
                        .id(plan.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position)
        .onChange(of: position) { _, value in
            if let value { onSelectionChange(value) }
        }
    }
}
