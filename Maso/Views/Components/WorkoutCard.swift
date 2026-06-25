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
    /// Play 按钮视觉强度:
    ///   - true (默认): 实心 accent 圆 + 黑色 play + 阴影 (Today's Workout 主 CTA, 强).
    ///   - false: accent 半透明底 + accent play + 细描边 (My Plans 计划卡, 弱化).
    var prominentStart: Bool = true
    /// Tab 2 (Plans browse) 专用 — 设了这个 callback → 卡片底部出现 "★ 添加到我的计划" 主按钮,
    /// 同时隐藏右下角的 play 圆钮 (browse 语境主操作是"加进我的计划"而非"开始"). Tab 1 不传 → 行为不变.
    var addAction: (() -> Void)? = nil
    /// Today's Workout 主卡专用 — true → accent 描边 + 绿色辉光, 跟弱化的 My Plans 计划卡拉开视觉层级
    /// (两者之前样式几乎一样, 容易混淆).
    var emphasized: Bool = false
    /// 右下角 play 圆钮是否显示. false → 不显示 (点卡片进详情页再 Start).
    /// Routines tab 的 Saved 计划卡用 false — 那语境主操作是"查看/管理计划", 不是即时开练.
    var showStart: Bool = true

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

    /// 动作名预览 + 各自主练部位 — 全部 step 都拿到, LimitedFlowLayout 负责换行.
    /// chip 里动作名 (e.g. "Bench Press") + 主练部位 (e.g. "Chest") 一起显示, 一眼看清这个 routine 覆盖哪些部位.
    /// 部位 = 主肌肉归到的大区 (MuscleGroup.section: Chest/Back/Shoulders/Arms/Core/Legs);
    /// fullBody 等无 section 时退回该肌肉本身名.
    private var exercisePreview: [(name: String, part: String?)] {
        plan.steps.compactMap { step in
            guard let ex = exById[step.exerciseId] else { return nil }
            // 用 displayName 而非 raw name — 中文环境下 chip 跟点开后的标题语言一致
            let part = ex.primaryMuscles.first.map { ($0.section ?? $0).displayName }
            return (ex.displayName, part)
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
            // Kicker 行 — 跟 Plans tab 的 TRAINING PREFERENCES kicker 完全对齐:
            // SF Symbol + accent 绿 10pt heavy + tracking 1.5. icon 选 figure.strengthtraining,
            // 跟 Today tab 自己的 tab icon 同款, 给"今日训练" section 一个视觉锚点.
            if let kicker = resolvedKicker {
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                    Text(kicker)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(MasoColor.accent)
                    Spacer()
                }
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, MasoMetrics.cardPadding - 2)
                .padding(.bottom, 4)
            }

            // 标题行: [AI badge] + plan name + 右侧 chevron
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Spacer()
                if onShowDetail != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(MasoColor.textFaint)
                }
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            // 没 kicker 时, title 自己撑顶部留白
            .padding(.top, resolvedKicker == nil ? MasoMetrics.cardPadding - 2 : 0)

            // Body Map — 居中摆放.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                MuscleVisualBlock(muscles: inferredMuscles, sideLength: 140)
                    .frame(width: 140, height: 140)   // 显式 frame (不用 .fixedSize) — List row 的
                    // nil-width sizing pass 下 .fixedSize 会回报无限 ideal 宽度, 整行连同后面都不渲染.
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            // Subtitle — exercises · sets, 现在在 Muscle Map 下面 (用户要求).
            // 视觉路径: 看肌肉图认部位 → 数字看量 (动作数/组数) → 看 chip 看具体动作.
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 16)  // P3: 统一卡内竖向节奏为 16 (之前这处是一次性 12)

            // 底部行: 训练动作 chip list (左, 满宽) + Play 按钮 (右, 垂直居中跟 chip 行).
            // 用户要求: play 按钮挪到训练动作那两行的右边.
            HStack(alignment: .center, spacing: 12) {
                if !plan.steps.isEmpty {
                    LimitedFlowLayout(
                        spacing: 6,
                        maxRows: 999,  // 不截断, 显示所有 exercises
                        onTruncate: { _ in /* never truncates */ }
                    ) {
                        ForEach(Array(exercisePreview.enumerated()), id: \.offset) { _, item in
                            ExercisePill(name: item.name, part: item.part)
                        }
                        // LimitedFlowLayout 要求最后一个 subview 是 overflow pill,
                        // maxRows 999 永远不截断, 这个空 pill 会被 place 到屏外.
                        ExercisePill(name: "")
                    }
                } else {
                    Spacer()
                }

                // Tab 2 browse (addAction 非 nil): play 圆钮隐藏, 主操作改为底部全宽"添加"按钮.
                // showStart=false (Saved 计划卡): 也隐藏 play 钮, 点卡片进详情页 Start.
                if addAction == nil && showStart {
                    Button(action: onStart) {
                        ZStack {
                            if prominentStart {
                                // 强: 实心 accent + 黑 play + 阴影 — Today's Workout 主 CTA.
                                Circle()
                                    .fill(MasoColor.accent)
                                    .frame(width: 44, height: 44)
                                    .shadow(color: MasoColor.accent.opacity(0.35), radius: 6, y: 0)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(.black)
                                    .offset(x: 1)
                            } else {
                                // 弱: accent 半透明底 + accent play + 细描边 — My Plans 计划卡.
                                Circle()
                                    .fill(MasoColor.accent.opacity(0.18))
                                    .overlay(Circle().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(MasoColor.accent)
                                    .offset(x: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("Start workout")
                }
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.top, 16)

            // Tab 2 (Plans browse): 卡片底部全宽 "★ 添加到我的计划" 主按钮.
            if let addAction {
                AddToPlansButton(isSaved: data.isPlanSaved(plan), action: addAction)
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.top, 14)
            }
        }
        .padding(.bottom, MasoMetrics.cardPadding)
        // 有 detail callback 时整张卡可点 (BodyHint hit-test 没接 onMuscleTap, 不冲突).
        // 用 contentShape + onTapGesture 而不是 Button — 避免 SwiftUI 给整卡套上 button style 改色.
        .contentShape(Rectangle())
        .onTapGesture { onShowDetail?() }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // emphasized (Today's Workout 主卡): 不再加描边/阴影/辉光 — 仅靠实心绿播放键
        // (vs My Plans 卡的半透明描边键) 区分主次, 保持干净.
    }
}

/// 动作名 chip — 半透底 capsule. 主练部位 (Chest / Back / ...) 在前 + 具体动作名字 (Bench Press / ...) 在后.
/// 部位用 accent 绿 + 小一号字, 作前缀标签; 动作名白色, 跟部位在颜色 + 字号上都有明显差别, 一眼区分"部位 vs 动作".
/// 各自限 1 行, 长名自动截尾, 不撑爆 FlowLayout.
private struct ExercisePill: View {
    let name: String
    var part: String? = nil
    var body: some View {
        // DESIGN.md §2.2: chip 类小标签走 11pt + 紧凑 padding. 部位前缀再小 1pt (10pt) 拉开层级.
        HStack(spacing: 5) {
            if let part, !part.isEmpty {
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

/// Tab 2 (AI / Classics browse) 卡片底部主操作 — "Save" (存进 My Routines).
/// 用 accent tinted 风格 (非实心): 它在卡片列表里重复出现, 实心会太吵; 详情页那个全宽 CTA 才用实心.
/// 文案 "Save" → 已存态 "✓ Saved" (灰, 不可再点). 未存态无 icon, 已存态用 checkmark — 去掉了原书签 icon.
struct AddToPlansButton: View {
    /// 该计划是否已在"我的计划"里 — true → 按钮变"已添加"态 (灰 ✓, 不可再点).
    var isSaved: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: { if !isSaved { action() } }) {
            HStack(spacing: 6) {
                if isSaved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(isSaved ? "Saved" : "Save")
                    .font(.system(size: 13, weight: .bold))
            }
            // 包裹内容 (不撑满) → 小一号胶囊; 在卡片 VStack(.leading) 里自动靠左.
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            // 未添加: accent 绿 (可操作); 已添加: 灰 (状态, 非操作).
            .foregroundStyle(isSaved ? MasoColor.textDim : MasoColor.accent)
            .background((isSaved ? MasoColor.textDim : MasoColor.accent).opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSaved)
        .animation(.easeOut(duration: 0.2), value: isSaved)
    }
}
