import SwiftUI

// 今日训练卡片 — Home 页核心元素
// 跟 web 端 WorkoutCard.tsx 对应: 显示 plan 名 + 推断肌群 BodyHint + 步骤摘要 + 大开始按钮
struct WorkoutCard: View {
    let plan: Plan
    let exById: [String: Exercise]
    var kicker: String = "Recommended"
    var onStart: () -> Void
    /// 可选 — 整张卡可点查看 plan 详情 (动作列表 + sets/reps/weight).
    /// 当 caller 传了这个 callback, 卡片整体变成 button. 没传 → 纯展示.
    var onShowDetail: (() -> Void)? = nil

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

    /// 今天会练的动作名预览 — 前 4 个 step. 超出在 UI 用 "+N more" chip 兜底.
    /// 跟 summarizedMuscles 不一样, 这个列具体动作 (e.g. "Bench Press") 而非部位 (e.g. "Chest").
    /// 用户视角更直接 — "今天要做什么"比"今天练什么部位"更可执行.
    private var exercisePreview: [String] {
        plan.steps.prefix(4).compactMap { step in
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.top, MasoMetrics.cardPadding + 8)

            // exercises · sets — 单行文字格式, 跟 Plans tab 的 PlanRow 一致 (不再用 pill capsule)
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 6)

            HStack {
                Spacer()
                // Today 卡片 BodyHint 比全局 large (260) 略小 — 用户反馈 260 偏大.
                // 220pt 视觉收敛但仍能清晰看出肌群分布. QuickWorkout 那边继续用全局 large.
                BodyHint(muscles: inferredMuscles, height: 220)
                Spacer()
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // 卡片底部: 列出今天会练的动作 (取前 4 个 step 的 exercise 名).
            // 之前显示"部位 chip" (Chest / Back / ...), 信息太抽象 — 用户更想知道"今天练什么动作".
            // 超过 4 个用 "+N more" 收尾, 避免 chip 撑爆.
            if !plan.steps.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(exercisePreview, id: \.self) { name in
                        ExercisePill(name: name)
                    }
                    if plan.steps.count > 4 {
                        ExercisePill(name: "+\(plan.steps.count - 4) more")
                    }
                }
                .padding(.leading, MasoMetrics.cardPadding)
                // 给 play 按钮让位: 36pt 圆 + 一点 buffer, 避免最后一行 chip 跟按钮重叠.
                .padding(.trailing, MasoMetrics.cardPadding + 44)
                .padding(.bottom, MasoMetrics.cardPadding + 4)
            }
        }
        // 有 detail callback 时整张卡可点 (BodyHint hit-test 没接 onMuscleTap, 不冲突).
        // 用 contentShape + onTapGesture 而不是 Button — 避免 SwiftUI 给整卡套上 button style 改色.
        .contentShape(Rectangle())
        .onTapGesture { onShowDetail?() }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // 右下角圆形 play 按钮 — 一键直接开练 (跳过详情 sheet 的 "Start" 二次点击).
        // chevron 留在右上保留"展开详情"入口, 两个入口 = 两个意图清晰区分.
        // 视觉跟 Plans tab 的 PlanRow play 按钮完全一致: 36×36 圆 + 12pt 三角.
        .overlay(alignment: .bottomTrailing) {
            Button(action: onStart) {
                ZStack {
                    Circle()
                        .fill(MasoColor.accent.opacity(0.18))
                        .overlay(
                            Circle().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5)
                        )
                        .frame(width: 36, height: 36)
                    // play.fill 三角的几何中心略偏左, +0.5pt 视觉补偿对齐圆心
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                        .offset(x: 0.5)
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
