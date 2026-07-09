import SwiftUI

/// routine 来源标签 — AI(✨) / Classics(🎗rosette). custom → 不渲染.
/// PlanRow(Routines tab) 与 WorkoutCard(Today) 共用, 视觉一致.
struct PlanSourceBadge: View {
    let source: PlanSource
    var body: some View {
        switch source {
        case .ai:       badge(icon: "sparkles", text: "AI")
        case .classics: badge(icon: "rosette", text: "Classics")
        case .custom:   EmptyView()
        }
    }
    @ViewBuilder private func badge(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .heavy))
            Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(MasoColor.accent)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(MasoColor.accent.opacity(0.18))
        .overlay(Capsule().stroke(MasoColor.accent.opacity(0.45), lineWidth: 0.5))
        .clipShape(Capsule())
        .fixedSize()
    }
}

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
    /// 紧凑排版 (Routines / My Plans 列表卡用): 标题 → 计数 → [小肌肉图 左 | 动作 chips 右] 横排,
    /// 比默认的"大居中肌肉图 + 计数 + chips 竖排"更密、更易扫. Today 英雄卡保持 false (大图突出).
    var compactLayout: Bool = false
    /// 书签态覆盖 — Coach 生成卡传 data.isCoachPlanSaved(plan) (savedIdMap 反查, 副本改名后不失灵).
    /// nil → 现状 data.isPlanSaved(plan) (签名匹配), 其它调用方不受影响.
    var savedOverride: Bool? = nil
    /// Coach 对话流专用 (coach-tab-design.md §1) — 长按动作 pill → 引用式定向反馈:
    /// 回调收动作显示名, CoachScreen 预填 composer "换掉 {动作名}" 并在发送时作 onlyModify 传给
    /// coachGenerate. nil (默认) = 不挂手势, 其它调用方零改动. 轻点不受影响 — 长按手势不成立时
    /// 事件照常落到整卡 onTapGesture (详情照常打开).
    var onExercisePillLongPress: ((String) -> Void)? = nil
    /// 等高轮播 (#today-carousel) 专用 — Today 轮播量测所有卡自然高取 max 后回写这里:
    /// 非 nil 时卡片拉伸到该高度, 且底部行 (chips + play) 前垫 Spacer 把播放键钉到右下角.
    /// nil (默认) = 自然高度, 其它调用方零改动.
    var fixedHeight: CGFloat? = nil

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

            // 标题行: [来源 badge: AI / Classics] + plan name + 右侧 chevron
            HStack(alignment: .center, spacing: 8) {
                PlanSourceBadge(source: plan.resolvedSource)
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

            // AI 理由 — LLM 给的"为什么这么排今天这套". 模板写不出这句自定义文案 →
            // 用户一眼看出"这是真 AI, 不是本地模板". 仅 .ai 计划有 rationale.
            if let rationale = plan.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.system(size: 12).italic())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.top, 6)
            }

            // Subtitle — exercises · sets, 紧挨标题 (所有 routine 卡统一: 标题 + 计数 在一起).
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 6)

            if compactLayout {
                // 紧凑版 — [小肌肉图 左 | 动作 chips 右] 同一行 (计数已上移到标题下共享区).
                HStack(alignment: .center, spacing: 12) {
                    MuscleVisualBlock(muscles: inferredMuscles, sideLength: 92)
                        .frame(width: 92, height: 92)
                    if !plan.steps.isEmpty {
                        LimitedFlowLayout(
                            spacing: 6,
                            maxRows: 999,
                            onTruncate: { _ in /* never truncates */ }
                        ) {
                            ForEach(Array(exercisePreview.enumerated()), id: \.offset) { _, item in
                                exercisePill(item)
                            }
                            ExercisePill(name: "")   // LimitedFlowLayout 约定的末位 overflow pill
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 12)
            } else {
            // Body Map — 居中摆放.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                MuscleVisualBlock(muscles: inferredMuscles, sideLength: 140)
                    .frame(width: 140, height: 140)   // 显式 frame (不用 .fixedSize) — List row 的
                    // nil-width sizing pass 下 .fixedSize 会回报无限 ideal 宽度, 整行连同后面都不渲染.
                Spacer(minLength: 0)
            }
            .padding(.top, 16)

            // 等高模式: 卡被外部拉到统一高度时, 多出来的空间垫在这里 —
            // 底部行连同 play 键沉到卡底 (播放键仍钉右下). 自然高度时 Spacer 为 0, 无感.
            if fixedHeight != nil {
                Spacer(minLength: 0)
            }

            // 底部行: 训练动作 chip list (左, 满宽) + Play 按钮 (右下角).
            // .bottom 对齐 → play 钉到行底, 右边距 = 下边距 = cardPadding (相等), 落在卡片右下角.
            HStack(alignment: .bottom, spacing: 12) {
                if !plan.steps.isEmpty {
                    LimitedFlowLayout(
                        spacing: 6,
                        maxRows: 999,  // 不截断, 显示所有 exercises
                        onTruncate: { _ in /* never truncates */ }
                    ) {
                        ForEach(Array(exercisePreview.enumerated()), id: \.offset) { _, item in
                            exercisePill(item)
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
                                // 弱: accent 半透明底 + accent play — 无描边环 (跟 Save 钮统一).
                                Circle()
                                    .fill(MasoColor.accent.opacity(0.18))
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
            }  // else (非紧凑版)

            // Tab 2 (Plans browse): 卡片底部 "Save" 主按钮 — 靠右下角 (跟其它卡的操作按钮位一致).
            if let addAction {
                AddToPlansButton(isSaved: savedOverride ?? data.isPlanSaved(plan), action: addAction)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.top, 14)
            }
        }
        .padding(.bottom, MasoMetrics.cardPadding)
        // 等高轮播: 统一高度在 background 之前生效 — surface 底随卡一起拉伸. nil 时是 no-op.
        .frame(height: fixedHeight)
        // 有 detail callback 时整张卡可点 (BodyHint hit-test 没接 onMuscleTap, 不冲突).
        // 用 contentShape + onTapGesture 而不是 Button — 避免 SwiftUI 给整卡套上 button style 改色.
        .contentShape(Rectangle())
        .onTapGesture { onShowDetail?() }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // emphasized (Today's Workout 主卡): 不再加描边/阴影/辉光 — 仅靠实心绿播放键
        // (vs My Plans 卡的半透明描边键) 区分主次, 保持干净.
    }

    /// 动作 pill + 可选长按手势 — 只有 Coach 卡 (onExercisePillLongPress 非 nil) 才挂手势,
    /// 避免给全 app 每个 pill 白加 gesture recognizer.
    @ViewBuilder
    private func exercisePill(_ item: (name: String, part: String?)) -> some View {
        if let onExercisePillLongPress {
            ExercisePill(name: item.name, part: item.part)
                .onLongPressGesture {
                    Haptics.tap()
                    onExercisePillLongPress(item.name)
                }
        } else {
            ExercisePill(name: item.name, part: item.part)
        }
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

/// Tab 2 / Coach 卡片底部主操作 — Save ↔ Saved 书签开关 (coach-tab-design.md §2).
/// 用 accent tinted 风格 (非实心): 它在卡片列表里重复出现, 实心会太吵; 详情页那个全宽 CTA 才用实心.
/// icon: bookmark (未存) ↔ bookmark.fill (已存). **两态都可点** — action 恒触发, toggle 语义由
/// 调用方决定 (Coach: 已存再点 = unsave; Classics 这类"存整套"的调用方自己 guard). 视觉沿用现状:
/// 未存 accent (可操作) / 已存灰 (已收藏态).
struct AddToPlansButton: View {
    /// 该计划是否已在"我的计划"里 — true → bookmark.fill 已存态 (仍可点, 再点由调用方 unsave).
    var isSaved: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11, weight: .bold))
                Text(isSaved ? "Saved" : "Save")
                    .font(.system(size: 13, weight: .bold))
            }
            // 包裹内容 (不撑满) → 小一号胶囊; 在卡片 VStack(.leading) 里自动靠左.
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            // 未存: accent 绿 (可操作); 已存: 灰 (状态感, 但依然可点切回).
            .foregroundStyle(isSaved ? MasoColor.textDim : MasoColor.accent)
            .background((isSaved ? MasoColor.textDim : MasoColor.accent).opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSaved)
    }
}
