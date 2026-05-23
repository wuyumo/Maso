import SwiftUI

// 今日训练卡片 — Home 页核心元素
// 跟 web 端 WorkoutCard.tsx 对应: 显示 plan 名 + 推断肌群 BodyHint + 步骤摘要 + 大开始按钮
struct WorkoutCard: View {
    @Environment(DataStore.self) private var data

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

    /// 被 LimitedFlowLayout 截断的 exercise pill 个数 — 用于动态构造 "+N more" 文案.
    /// Layout 在 placeSubviews 里通过 onTruncate callback async 写回, SwiftUI 下一轮 re-render
    /// 拿到正确数字. 一般 1-2 帧就稳定 (truncated 数收敛即停).
    @State private var truncatedCount: Int = 0

    private var inferredMuscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for step in plan.steps {
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

    /// 今天会练的动作名预览 — 全部 step 都拿到, LimitedFlowLayout 负责"最多 3 行 + 自动 +N".
    /// 跟 summarizedMuscles 不一样, 这个列具体动作 (e.g. "Bench Press") 而非部位 (e.g. "Chest").
    /// 用户视角更直接 — "今天要做什么"比"今天练什么部位"更可执行.
    private var exercisePreview: [String] {
        plan.steps.compactMap { step in
            // 用 displayName 而非 raw name — 中文环境下 chip 跟点开后的标题语言一致
            exById[step.exerciseId]?.displayName
        }
    }

    /// 通过 plan.id 前缀判断这张是不是 AI 生成的 — AIWorkoutService 用 "plan-ai-..." 命名,
        /// 系统推荐用 "plan-full*/plan-bal*/plan-push*..." 命名, 用户自建用 "plan-new-...".
    /// 这样不需要 caller 显式传 flag, 卡片自己根据 id 表达"AI" 来源.
    private var isAIGenerated: Bool {
        plan.id.hasPrefix("plan-ai-")
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
            // Kicker 行 — 表达来源 (FROM YOUR PLAN / 来自训练计划).
            // accent 绿小 caps + 大字距, 跟 TodayScreen 顶部"GOOD AFTERNOON"同款风格.
            // resolvedKicker == nil 时整行不渲染 (AI 生成 / 没匹配到 plan / caller 显式置空).
            if let kicker = resolvedKicker {
                Text(kicker)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.top, MasoMetrics.cardPadding + 8)
                    .padding(.bottom, 4)
            }

            // 标题行: [AI badge] + plan name + 右侧 chevron 进 detail
            HStack(alignment: .center, spacing: 8) {
                if isAIGenerated {
                    Text("AI")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(MasoColor.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MasoColor.accent.opacity(0.18))
                        .overlay(
                            Capsule().stroke(MasoColor.accent.opacity(0.45), lineWidth: 0.5)
                        )
                        .clipShape(Capsule())
                        .fixedSize()
                }
                Text(plan.name)
                    // 20pt bold (iOS HIG Title 3) — Today + Plans 卡片训练名统一这个字号,
                    // 凸显"卡片标题"层级. 超长走默认 truncationMode .tail (...).
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Spacer()
                if onShowDetail != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(MasoColor.textFaint)
                }
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            // 有 kicker 时, 上 padding 已经在 kicker 行给了, title 只给一点点隔行 spacing
            .padding(.top, resolvedKicker == nil ? MasoMetrics.cardPadding + 8 : 0)

            // exercises · sets — 单行文字格式, 跟 Plans tab 的 PlanRow 一致 (不再用 pill capsule)
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 6)

            // Muscle Map 区域 — 跟 SessionCard 共用 MuscleVisualBlock.
            // 左对齐 + 近正方形, 没照片 (WorkoutCard 不带 photo, 只渲染 muscle map).
            // ⚠️ 这块跟 SessionCard 的代码层面一致, 改这里也要同步改 SessionCard.
            MuscleVisualBlock(muscles: inferredMuscles, height: 110)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 14)
                .padding(.bottom, 14)

            // 卡片底部: 列出今天会练的动作.
            // 最多 3 行 — LimitedFlowLayout 自动挤"+N more" 占位在最后一行末尾
            // (空间不够会回吐 pill 给 "+N more" 让位).
            // 之前显示"部位 chip" (Chest / Back / ...), 信息太抽象 — 用户更想知道"今天练什么动作".
            if !plan.steps.isEmpty {
                LimitedFlowLayout(
                    spacing: 6,
                    maxRows: 3,
                    onTruncate: { newCount in
                        // Layout 算出"几个 pill 没放下" → 异步写回 state, 下一帧 overflow 文案就对了
                        if truncatedCount != newCount { truncatedCount = newCount }
                    }
                ) {
                    ForEach(Array(exercisePreview.enumerated()), id: \.offset) { _, name in
                        ExercisePill(name: name)
                    }
                    // 最后一个 subview 是 overflow indicator. Layout 没截断时不画.
                    ExercisePill(name: "+\(truncatedCount) more")
                }
                .padding(.leading, MasoMetrics.cardPadding)
                // 给 play 按钮让位: 56pt 大圆 + buffer, 避免 2 行 chip 跟按钮重叠.
                .padding(.trailing, MasoMetrics.cardPadding + 64)
                .padding(.bottom, MasoMetrics.cardPadding + 4)
            }
        }
        // 有 detail callback 时整张卡可点 (BodyHint hit-test 没接 onMuscleTap, 不冲突).
        // 用 contentShape + onTapGesture 而不是 Button — 避免 SwiftUI 给整卡套上 button style 改色.
        .contentShape(Rectangle())
        .onTapGesture { onShowDetail?() }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // 右下角 play 按钮 — 主 CTA, 一键直接开练 (跳过详情 sheet 的 "Start" 二次点击).
        // 尺寸 56pt ≈ 2 行 ExercisePill 高度 + spacing, 视觉占比跟左侧 2 行 chip block 对齐.
        // 实色 accent + 黑色 icon + glow shadow — 跟 PaywallScreen / startGapWorkout 的"主 CTA"风格一致.
        .overlay(alignment: .bottomTrailing) {
            Button(action: onStart) {
                ZStack {
                    Circle()
                        .fill(MasoColor.accent)
                        .frame(width: 56, height: 56)
                        .shadow(color: MasoColor.accent.opacity(0.45), radius: 12, y: 4)
                    // play.fill 三角的几何中心略偏左, +1pt 视觉补偿对齐圆心
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.black)
                        .offset(x: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(MasoMetrics.cardPadding)
            .accessibilityLabel("Start workout")
        }
    }
}

/// 动作名 chip — 半透底 capsule. 承载具体动作名字 (Bench Press / Squat / ...).
/// 限 1 行 + truncate, 长名 (e.g. "Decline Barbell Bench Press") 会自动截尾, 不撑爆 FlowLayout.
private struct ExercisePill: View {
    let name: String
    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.text.opacity(0.85))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
    }
}
