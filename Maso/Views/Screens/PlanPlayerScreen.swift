import SwiftUI

// 训练播放器 — 跟 web 端 PlanPlayer.tsx 1:1
// 结构 (从上到下):
//   - DragHandle (向下拖动收起)
//   - TimelineBar (进度条)
//   - "..." 菜单按钮 (右上角, 浮在 stage 上)
//   - Stage (ExerciseStage 或 RestStage)
//   - Controls (← / 主按钮 / 播放列表 toggle)
//   - InlinePlaylist (可展开, 在 Controls 下方)
struct PlanPlayerScreen: View {
    @Environment(TrainingSessionStore.self) private var store
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    // 训练时默认打开播放列表 — 让用户一眼看到"还剩什么 + 整体进度", 点 ☰ 收起.
    /// Playlist drawer 的内容高度 (不含 bottom safe area). 用户拖把手直接改这个值.
    /// 区间: [playlistMinHeight, playlistMaxHeight]. 默认 = playlistDefaultHeight (跟之前
    /// playlistExpanded=true 时的高度对齐).
    @State private var playlistHeight: CGFloat = PlanPlayerScreen.playlistDefaultHeight
    /// 拖拽开始时的 baseline — DragGesture.onChanged 只给 translation, 需要锚定起点.
    @State private var playlistDragStartHeight: CGFloat = 0
    /// 兼容旧逻辑: playlistExpanded 是从 height 派生的 bool. RestCountdown 圆环大小 / 文案等
    /// 还用这个 bool 决定显示, 不重写所有调用点.
    private var playlistExpanded: Bool { playlistHeight > Self.playlistMinHeight + 40 }

    /// 休息圆环的紧凑度 0..1 — playlistHeight 从 min → default 线性映射. RestCountdown 用它
    /// 连续 resize 圆环 (替代 playlistExpanded bool), 让圆环大小跟 drawer 同步变, 消除 toggle 抖动.
    private var restRingCompactT: CGFloat {
        let lo = Self.playlistMinHeight
        let hi = Self.playlistDefaultHeight
        // 上限不再 clamp 到 1: 拖过 default 高度后继续增大 → 圆环继续缩小 (RestCountdown 有下限),
        // 否则 playlist 拖很高时圆环停在 140 不动, 会跟 drawer 顶部重叠.
        return max(0, (playlistHeight - lo) / max(1, hi - lo))
    }
    /// 拖把手高度档位
    static let playlistMinHeight: CGFloat = 56        // 仅 handle + "PLAYLIST" header, 不见任何 row
    static let playlistDefaultHeight: CGFloat = 254   // 跟旧 expanded 视觉高度对齐
    @State private var endConfirmOpen: Bool = false
    /// 完成流: "保存修改到 routine?" 确认页已做完决定 (保存或跳过) → 进分享卡完成页.
    /// 训练完成且 canSaveChangesToPlan 时, 这个标志 false → 先渲确认页.
    @State private var planSaveDecisionMade: Bool = false
    /// 点 InlinePlaylist 行图片 → 弹该动作详情. sheet from sheet 是 iOS 18+ 支持的.
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 step 的二次确认 — 跟 PlanDetailSheet 同模式, 存待删 stepId, alert 弹.
    @State private var pendingDeleteStepId: String? = nil
    /// 右滑编辑 step — 存 stepId 拉 EditCurrentStepSheet, 用 store.updateStep 改 session-local.
    @State private var editingStepId: String? = nil
    /// 替换动作 — Edit sheet 里点 "Replace exercise" 把目标 stepId 存这, 然后弹 ExercisePickerSheet.
    /// 编辑 sheet 先 dismiss 再 set 这个值 (sheet from sheet 会 race), 用 0.32s 延迟串接.
    @State private var replacingStepId: String? = nil
    /// "+ Add exercise" footer (在 playlist 末尾) → 弹 ExercisePickerSheet, 选完调 store.appendStep.
    @State private var addStepPickerOpen: Bool = false

    /// sheet(item:) 需要 Identifiable, String 自身不 conform — 包一层.
    private struct StepIdentifier: Identifiable, Hashable {
        let id: String
    }

    // MARK: - Layout constants (训练中 ZStack 几何真相, 共享给圆环 + 渐变 + 进度条)
    //
    // 把进度条 / 圆环 / 底部 info+controls 的位置参数集中放这, 让"进度条固定 + 渐变固定 +
    // 圆环居中"三个目标基于同一组数字, 改一处就同步全部.
    //
    // 几何模型 (从 ZStack 顶往下):
    //   0 ──────────── sheet drag indicator (~20pt, 系统自带)
    //   12 ─────────── TimelineBar (训练进度条, padding.top 12)
    //   50 ─────────── headerReservedHeight = drag indicator + TimelineBar 占位
    //   |
    //   |  [exercise: 背景图]
    //   |  [rest: 倒计时圆环居中区]
    //   |
    //   ZStack 高 - bottomReservedHeight ───── 底部 info+controls 区顶 (渐变开始)
    //     |
    //     | padding.top: bottomInnerTopPadding (渐变从这开始 fade out)
    //     | middle filler (固定 120pt, exercise infoSection / rest hint 占同样高度)
    //     | spacing 22
    //     | Controls (~84pt: 12 top padding + 48 max button + 24 bottom padding)
    //     |
    //   ZStack 底
    //
    // bottomReservedHeight = bottomInnerTopPadding + middleFillerHeight + 22 + 84
    //                     = 140 + 120 + 22 + 84 = 366
    //
    // (Color.black 60pt 是 background 延伸到 home indicator, 不算 inner content)

    /// 顶部预留 — sheet drag indicator + 进度条占位. 圆环上边界对齐这个 y.
    static let headerReservedHeight: CGFloat = 50

    /// 中间填充固定高 — exercise / rest 共用. 必须装得下 infoSection 的 BodyHint+name+chips.
    static let middleFillerHeight: CGFloat = 120

    /// 底部 inner content 顶部 padding — 渐变从此处开始 fade out.
    static let bottomInnerTopPadding: CGFloat = 140

    /// 底部预留 — info+controls inner content 总高. 圆环下边界对齐这个 y.
    /// 公式: bottomInnerTopPadding + middleFillerHeight + 22 (spacing) + 84 (Controls 高度).
    static let bottomReservedHeight: CGFloat = 140 + 120 + 22 + 84

    var body: some View {
        VStack(spacing: 0) {
            if store.session == nil || (store.session != nil && store.segments.isEmpty) {
                // Empty state — segments 为空时不能让用户看到全黑空屏 (bug fallback).
                // 给一个明确的"没有训练数据"提示 + Close 按钮逃出.
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(MasoColor.textDim)
                    Text("This workout has no exercises yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                    Text("Add some exercises to the plan first, then start training.")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: { store.end(); dismiss() }) {
                        Text("Close")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 32).padding(.vertical, 12)
                            .background(MasoColor.text)
                            .foregroundStyle(MasoColor.background)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
            } else if store.session?.completed == true {
                // 完成流: 训练中改过 routine 参数 (canSaveChangesToPlan) → 先进"保存修改?"确认页
                // (展示训练组列表 + 突出修改项), 用户做完保存/不保存决定后才进分享卡完成页.
                // 没改过 / 自由训练 → 直接完成页.
                // RoutineDiff.hasChanges 兜住 planParamsDirty 的粗粒度 (改了又改回去 / 保存了
                // 相同值也会置脏) — 真实 diff 为空就不弹确认页, 不让用户看一张"全无修改"的页面.
                if canSaveChangesToPlan && !planSaveDecisionMade,
                   let sessionPlan = store.plan,
                   let originalPlan = data.plans.first(where: { $0.id == sessionPlan.id }),
                   RoutineDiff.hasChanges(original: originalPlan, session: sessionPlan, exById: data.exById) {
                    SaveChangesConfirmView(
                        originalPlan: originalPlan,
                        sessionPlan: sessionPlan,
                        exById: data.exById,
                        onSave: {
                            saveChangesToCurrentPlan()
                            withAnimation(.easeInOut(duration: 0.25)) { planSaveDecisionMade = true }
                        },
                        onSkip: {
                            withAnimation(.easeInOut(duration: 0.25)) { planSaveDecisionMade = true }
                        }
                    )
                    .transition(.opacity)
                } else {
                // CompletedView 自带纯黑全屏底; 不再外包 Spacer (会让 sheet 默认 systemBackground 透出)
                // 如果 store.plan 是自由训练 (autoGenerated == true 且未入 data.plans), 给"Save as plan"按钮
                let shareBundle = completedShareBundle
                CompletedView(
                    planName: store.plan?.name ?? "",
                    durationSeconds: completedDurationSeconds,
                    setCount: store.session?.completedSets.count ?? 0,
                    prCount: completedPRCount,
                    muscles: completedMuscles,
                    exerciseNames: completedExerciseNames,
                    exerciseCount: completedExerciseCount,
                    sessionId: completedSessionId,
                    workoutDetail: shareBundle.detail,
                    importPayload: MasoLinks.appStore,
                    totalVolumeKg: shareBundle.volume,
                    dateLabel: completedDateLabel,
                    onSavePlan: canSaveCurrentPlan ? { saveCurrentPlanToLibrary() } : nil,
                    onClose: {
                        store.endedExplicitly = true
                        store.end()
                        dismiss()
                    }
                )
                .transition(.opacity)
                }
            } else if let seg = store.currentSegment {
                // Stage — 图片真正"贴顶": 直接放在 ZStack 最底层 fills stage 区,
                // DragHandle + TimelineBar 作为前景叠加层 (带黑色渐变 scrim 增加可读性)
                ZStack(alignment: .top) {
                    // 1) 背景: 当前动作图 (rest 段 = 黑底).
                    //    底部 64pt 留给 controls 区 — 让图片不跟按钮粘住, 视觉呼吸感更好.
                    //    info + controls 区位置不变 (它们各自钉底, 不受这个 padding 影响).
                    backgroundLayer
                        .padding(.bottom, 64)

                    // 2) 底部叠加: info + controls — exercise / rest 共用同一框架.
                    //    中间填充 .frame(height: FIXED) — exercise BodyHint + rest hint 占据
                    //    完全相同的 120pt 高度. Controls 位置 + 底部渐变开始位置, 在两态切换 /
                    //    playlist 展开收起 / 不同设备的所有场景下完全固定.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 22) {
                            Group {
                                if seg.isRest {
                                    restNextExerciseHint(seg: seg)
                                } else {
                                    infoSection(seg: seg)
                                }
                            }
                            // FIXED HEIGHT 120 — 不是 minHeight, 确保 exercise / rest 占据完全
                            // 相同纵向空间. 120 足够装下 infoSection (BodyHint 80 + 文字 ~40).
                            .frame(height: Self.middleFillerHeight, alignment: .center)

                            Controls(
                                seg: seg,
                                playing: store.session?.playing ?? true,
                                canGoBack: store.canSkipBack,
                                onBack: { store.skipBackToPrevExercise() },
                                onPrimary: { handlePrimary(seg: seg) },
                                onTogglePlay: { store.togglePlay() },
                                onEnd: { endConfirmOpen = true }
                            )
                        }
                        .padding(.top, Self.bottomInnerTopPadding)
                        .background(bottomInfoGradient)
                    }

                    // 3) 顶部进度条已移除 — 进度现在拆成竖条放在 playlist 每个动作左侧 (见 InlinePlaylist
                    //    verticalSetBar). 顶部只留一层很浅的渐变让 sheet drag indicator 在动图上可见.
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 90)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                    // 4) 最顶层: rest 段倒计时圆环 — 必须在底部渐变 + TimelineBar 之上,
                    //    否则圆环被 bottomInfoGradient 的 fade-out 区盖住一半.
                    //    位置: 在"训练图 (背景图)"几何中心横竖向居中 —
                    //    backgroundLayer 占 (0, ZStack 高 - 64) 区域 (padding.bottom 64),
                    //    圆环 padding.bottom 64 抵消, Spacer 均分让圆环在背景图中点.
                    if seg.isRest {
                        // 圆环垂直居中在 [sheet 顶部, "Up Next" 文字顶部] 之间 → 上下间距相等.
                        // "Up Next" hint top ≈ stageHeight - 196 (= bottomReservedHeight 366
                        // - bottomInnerTopPadding 140 = filler 顶 226, hint 在 120 filler 里居中
                        // 再上移 ~30). 用这个底部 padding 让圆环中心落在该空间中点.
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            restCountdownRing(seg: seg)
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 196)
                        .allowsHitTesting(false)  // 透传 tap, 不挡下层 Controls / 进度条
                    }
                }
                .frame(maxHeight: .infinity)
                .clipped()

                playlistDrawer
            }
        }
        // 钉死内容宽度 = 屏宽 — 修"训练态 vs 休息态 playlist 整体宽差 ~2.7pt/边": 训练态全屏动作大图
        // 的 intrinsic 宽略溢出屏宽, 把外层 VStack 撑宽 → 下方 playlist drawer (maxWidth .infinity) 跟着变宽;
        // 休息态(图 + 黑 mask)不溢出. cap 到屏宽后两态宽度一致, 切换不再"轻微收窄又放宽".
        .frame(maxWidth: UIScreen.main.bounds.width)
        // sheet 整体背景用纯黑 — Home Indicator 区延续 .black, 跟 TabBar/MiniBar 一致.
        // (之前用 MasoColor.background = #121212, rest 段 Controls 之下会透出微弱灰, 跟 .black 有色差.)
        .background(Color.black.ignoresSafeArea())
        // 整 sheet content 也 ignore bottom safe area — 让 playlistDrawer 真 anchor 到 hardware
        // bottom edge, content 延伸到 home indicator 区. stage / controls 区自己有 Color.black
        // .ignoresSafeArea bg 处理 home indicator, 不受影响.
        .ignoresSafeArea(.container, edges: .bottom)
        // 点 playlist 行图片 → 弹动作详情. iOS 18+ 支持 sheet 内嵌 sheet.
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
            .presentationDragIndicator(.visible)
        }
        // 右滑 Edit → 弹 EditAnyStepSheet (session-local 改 sets/reps/weight/duration).
        // Binding<String?> identity 用 stepId, 通过 plan.steps 找具体 step 实例.
        .sheet(item: Binding(
            get: { editingStepId.map { StepIdentifier(id: $0) } },
            set: { editingStepId = $0?.id }
        )) { idWrapper in
            if let plan = store.plan,
               let step = plan.steps.first(where: { $0.id == idWrapper.id }),
               let ex = data.exById[step.exerciseId] {
                EditCurrentStepSheet(
                    exercise: ex,
                    initialSets: step.sets,
                    initialReps: step.reps,
                    initialWeight: step.weight,
                    initialDuration: step.duration,
                    initialSetReps: step.setReps,
                    initialSetWeights: step.setWeights,
                    onSave: { newSets, newReps, newWeight, newDuration, newSetReps, newSetWeights in
                        store.updateStep(
                            idWrapper.id,
                            sets: newSets,
                            reps: newReps,
                            weight: newWeight,
                            duration: newDuration,
                            setReps: newSetReps,
                            setWeights: newSetWeights,
                            exById: data.exById,
                            defaultRest: data.settings.defaultRestSeconds,
                            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
                        )
                    },
                    onReplace: { replacingStepId = idWrapper.id }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        // 替换动作 picker — 训练中任何 Edit sheet 里点 "Replace exercise" 走这里.
        // 进 sheet 后选完一个 exercise → store.replaceStepExercise → 自动 mark planParamsDirty,
        // 训练完成时会先进 SaveChangesConfirmView 确认页, 让用户决定是否把替换持久化到 plan.
        .sheet(item: Binding(
            get: { replacingStepId.map { StepIdentifier(id: $0) } },
            set: { replacingStepId = $0?.id }
        )) { idWrapper in
            ExercisePickerSheet(onPick: { newEx in
                store.replaceStepExercise(
                    idWrapper.id,
                    newExerciseId: newEx.id,
                    exById: data.exById,
                    defaultRest: data.settings.defaultRestSeconds,
                    defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
                )
                replacingStepId = nil
            },
            directPick: true,  // J4: 替换 = 选了就换, 不先弹详情
            // 替换流程: 预选原动作的部位 (动作 + 器械留空), 落在"换个练同部位的动作".
            initialMuscle: {
                guard let exId = store.plan?.steps.first(where: { $0.id == idWrapper.id })?.exerciseId,
                      let ex = data.exById[exId] else { return nil }
                return ex.primaryMuscles.first?.section
            }())
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // "+ Add exercise" — playlist 末尾点了之后选动作, 多选勾选 (跟 Free Workout 一致),
        // 底部 "Add (N)" 一并 appendStep 到末尾.
        .sheet(isPresented: $addStepPickerOpen) {
            ExercisePickerSheet(
                onPick: { _ in },   // multiSelect 模式不走单选回调
                multiSelect: true,
                onPickMultiple: { exercises in
                    for ex in exercises {
                        store.appendStep(
                            exercise: ex,
                            settings: data.settings,
                            exById: data.exById,
                            defaultRest: data.settings.defaultRestSeconds,
                            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
                        )
                    }
                    addStepPickerOpen = false
                },
                startTitle: NSLocalizedString("Add", comment: "add selected exercises CTA")
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // 训练中右滑 playlist 行 → 二次确认 → 调 store.deleteStep (session-local).
        // 跟 PlanDetailSheet 一致的 UX, 只是这里删的是 session-local plan, 不影响 data.plans.
        .alert("Delete exercise?", isPresented: Binding(
            get: { pendingDeleteStepId != nil },
            set: { if !$0 { pendingDeleteStepId = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteStepId {
                    store.deleteStep(
                        id,
                        exById: data.exById,
                        defaultRest: data.settings.defaultRestSeconds,
                        defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
                    )
                }
                pendingDeleteStepId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteStepId = nil }
        } message: {
            Text("This only removes it from the current workout. Save changes at the end to update the plan.")
        }
        .alert("End this workout?", isPresented: $endConfirmOpen) {
            // 用户在训练中改了参数 (sets/reps/weight/duration/顺序) → 多给一个"保存并结束"选项,
            // 让修改持久化到 plan. 不脏 / 自由训练 → 老 2-button 流程.
            if canSaveChangesToPlan {
                Button("Save changes & end") {
                    saveChangesToCurrentPlan()
                    store.endedExplicitly = true
                    store.end()
                    dismiss()
                }
                Button("End without saving", role: .destructive) {
                    store.endedExplicitly = true
                    store.end()
                    dismiss()
                }
            } else {
                Button("End", role: .destructive) {
                    store.endedExplicitly = true
                    store.end()
                    dismiss()
                }
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            // 提示文案 — dirty 状态下说明改动是 session-local 默认不保存
            if canSaveChangesToPlan {
                Text("You changed sets, reps, weight, or order during this workout. Save the changes back to the plan?")
            } else {
                Text("Sets you've completed will be kept.")
            }
        }
        // 新一次训练 (completed 回到 false / session 换新) → 重置确认页决定标志,
        // 否则上一场做过的决定会让下一场 dirty 完成直接跳过确认页.
        .onChange(of: store.session?.completed == true) { _, isCompleted in
            if !isCompleted { planSaveDecisionMade = false }
        }
        // SessionTickerView 移到了 RootView 顶层 — sheet 关掉后 MiniBar 还得 tick.
    }

    /// 背景层 — exercise 段铺当前图, rest 段纯黑
    @ViewBuilder
    private var backgroundLayer: some View {
        if let seg = store.currentSegment {
            switch seg.kind {
            case .exercise(let ex, _, _, _, _, _, _):
                FullBleedExerciseImage(exercise: ex)
            case .rest:
                // 休息段背景: 显示"下一个动作"的静图 + 暗化 mask, 提前给用户预览要换什么器械.
                // 之前是纯黑 — 信息量太少, 用户得脑补下一个是什么. 现在直接看图.
                // 休息时用静图 (animated: false) — 大背景反复 cross-fade 在休息这个"放松"
                // 语境下视觉太吵, 静态一张图给"看清下一动作"就够了.
                if let next = nextExerciseSeg() {
                    ZStack {
                        FullBleedExerciseImage(exercise: next, animated: false)
                        // 暗化 mask — 让上面的倒计时圆环 / "Up Next" 文字读起来舒服
                        Color.black.opacity(0.55)
                    }
                } else {
                    Color.black  // 最后一段 rest (理论上不存在, 兜底)
                }
            }
        } else {
            MasoColor.background
        }
    }

    /// 信息区 — 仅 exercise 段调. rest 段走 restCountdownRing + restNextExerciseHint 各自渲染.
    @ViewBuilder
    private func infoSection(seg: Segment) -> some View {
        switch seg.kind {
        case .exercise(let ex, let setN, let total, let reps, let weight, let dur, let countdown):
            ExerciseInfo(
                exercise: ex,
                setNumber: setN, totalSets: total,
                reps: reps, weight: weight,
                duration: dur,
                isCountdown: countdown,
                remaining: store.remainingSeconds,
                // tap "Replace exercise" 入口 → 通过共享 replacingStepId 状态拉 ExercisePickerSheet.
                onRequestReplace: { replacingStepId = seg.stepId }
            )
        case .rest:
            EmptyView()  // rest 段不通过 infoSection 渲染, 走专门的 restCountdownRing
        }
    }

    /// 判断当前 rest 段是 "组间休息" 还是 "动作切换休息"
    /// - 看 rest 之前的 exercise segment vs rest 之后的 exercise segment, stepId 不同 = 动作切换
    private func isCrossExerciseRest(currentSegment seg: Segment) -> Bool {
        guard let s = store.session else { return false }
        let i = s.segmentIndex
        // 找当前 rest 之前最近的 exercise
        var prevStepId: String?
        var j = i - 1
        while j >= 0 {
            if store.segments[j].isExercise { prevStepId = store.segments[j].stepId; break }
            j -= 1
        }
        // 找当前 rest 之后最近的 exercise
        var nextStepId: String?
        var k = i + 1
        while k < store.segments.count {
            if store.segments[k].isExercise { nextStepId = store.segments[k].stepId; break }
            k += 1
        }
        guard let p = prevStepId, let n = nextStepId else { return false }
        return p != n
    }

    private func nextExerciseSeg() -> Exercise? {
        guard let s = store.session else { return nil }
        for i in (s.segmentIndex + 1)..<store.segments.count {
            if case .exercise(let ex, _, _, _, _, _, _) = store.segments[i].kind { return ex }
        }
        return nil
    }

    /// 下一个动作 segment 的目标 reps / weight — 休息屏 "Up Next" 提前显示, 让用户休息时心里有数.
    private func nextExerciseTargets() -> (reps: Int?, weight: Double?) {
        guard let s = store.session else { return (nil, nil) }
        for i in (s.segmentIndex + 1)..<store.segments.count {
            if case .exercise(_, _, _, let reps, let weight, _, _) = store.segments[i].kind {
                return (reps, weight)
            }
        }
        return (nil, nil)
    }

    /// 下一个动作 segment 的 stepId — 给休息屏的"小编辑入口"用,
    /// 让用户能在休息时改下一动作的 sets/reps/weight, 不用等开始那一组才意识到要改.
    private func nextExerciseStepId() -> String? {
        guard let s = store.session else { return nil }
        for i in (s.segmentIndex + 1)..<store.segments.count {
            if case .exercise = store.segments[i].kind {
                return store.segments[i].stepId
            }
        }
        return nil
    }

    // MARK: - Rest screen pieces (extracted so countdown can sit dead-center,
    // hint + controls share the bottom gradient backdrop跟 exercise 段一致)

    /// 休息倒计时圆环 — 单独出来, 嵌在 上下 Spacer 之间, 真居中.
    /// 不再带"下一动作"信息 (那个移到 restNextExerciseHint 跟 Controls 一起钉底)
    @ViewBuilder
    private func restCountdownRing(seg: Segment) -> some View {
        if case .rest(let dur) = seg.kind {
            RestCountdown(
                durationTotal: dur,
                endsAt: store.session?.endsAt,
                pausedRemaining: store.session?.pausedRemaining,
                isCrossExercise: isCrossExerciseRest(currentSegment: seg),
                compactT: restRingCompactT
            )
        }
    }

    /// 下一动作提示 — 跟 Controls 一起钉底, 共享渐变遮罩背景
    @ViewBuilder
    private func restNextExerciseHint(seg: Segment) -> some View {
        if let next = nextExerciseSeg() {
            let nextStepId = nextExerciseStepId()
            let targets = nextExerciseTargets()
            RestNextHint(
                next: next,
                nextReps: targets.reps,
                nextWeight: targets.weight,
                isCrossExercise: isCrossExerciseRest(currentSegment: seg),
                // 小编辑入口 — 跟 playlist 的 onEdit 一样用 editingStepId 触发 EditAnyStepSheet,
                // 复用已有 sheet (line ~224), 不需要新 sheet 通道.
                onEdit: nextStepId.map { id in { editingStepId = id } }
            )
        }
    }

    /// 底部 info+controls 区的渐变遮罩 — exercise / rest 段共用一份, 让两态切换时
    /// 渐变位置 + 强度 100% 一致, 视觉零跳动.
    ///
    /// 设计:
    ///   - 上半 5-stop 渐变 (clear → 0.35 → 0.78 → 0.96 → black) 让背景图自然过渡到黑色 controls 区
    ///   - 底部 60pt 实色 Color.black + ignoresSafeArea(.bottom) 延伸到 home indicator,
    ///     home indicator 区跟 controls 底色无缝连接
    private var bottomInfoGradient: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.35), location: 0.16),
                    .init(color: .black.opacity(0.78), location: 0.38),
                    .init(color: .black.opacity(0.96), location: 0.62),
                    .init(color: .black, location: 0.85),
                ],
                startPoint: .top, endPoint: .bottom
            )
            Color.black
                .frame(height: 60)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func handlePrimary(seg: Segment) {
        switch seg.kind {
        case .exercise(_, _, _, _, _, _, true):
            store.togglePlay()
        default:
            store.advance { rec in data.recordSet(rec) }
        }
    }

    /// 当前 keyWindow 的 bottom safe area inset (home indicator 区高度).
    /// iPhone 14+ ≈ 34pt, 旧 iPhone (home button) = 0pt. Dynamic, 不 hardcode.
    private var bottomSafeArea: CGFloat {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 34
    }

    @ViewBuilder
    private var playlistDrawer: some View {
        // GeometryReader 取屏幕高 → 算 max playlist height (不能让 playlist 高到把训练图挤没了).
        // 留至少 200pt 给上方 ZStack (训练图 / TimelineBar / rest 圆环), 这样视觉永远"两段都在屏内".
        GeometryReader { _ in EmptyView() }
            .frame(width: 0, height: 0)
        VStack(spacing: 0) {
            // 顶部拖把手 + "PLAYLIST" header. 整块一起接 DragGesture: 用户拖手柄或 header 都生效.
            playlistDragHandleBar
                .background(
                    Color(red: 10/255, green: 10/255, blue: 10/255)
                )

            InlinePlaylist(
                plan: store.plan,
                exById: data.exById,
                currentStepId: currentStepId,
                currentSet: currentSetNumber,
                completedSetsByStep: completedSetsByStep,
                onJump: { stepId in
                    if let idx = store.segments.firstIndex(where: {
                        if case .exercise = $0.kind, $0.stepId == stepId { return true }
                        return false
                    }) {
                        store.setIndex(idx)
                    }
                },
                onTapImage: { ex in detailExercise = ex },
                onReorder: { source, destination in
                    store.reorderSteps(
                        from: source,
                        to: destination,
                        exById: data.exById,
                        defaultRest: data.settings.defaultRestSeconds,
                        defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
                    )
                },
                onDelete: { stepId in
                    pendingDeleteStepId = stepId  // 走二次确认 alert
                },
                onEdit: { stepId in
                    editingStepId = stepId  // 弹 EditAnyStepSheet
                },
                onReplace: { stepId in
                    replacingStepId = stepId  // 弹 ExercisePickerSheet 换一个动作
                },
                onAddStep: { addStepPickerOpen = true },
                showHeader: false,  // 自定义 dragHandleBar 已经做了 header, InlinePlaylist 内部别再渲一次
                // J5: 竖向进度条 + 动作间休息行的数据源
                segments: store.segments,
                currentIndex: store.session?.segmentIndex ?? 0,
                completedSets: store.session?.completedSets ?? [],
                onJumpSegment: { idx in store.setIndex(idx) }
            )
        }
        // 总高度 = 拖把手区 + 用户拖出来的内容高度 + home indicator safe area.
        // .clipped() 让 InlinePlaylist 被 frame 裁掉超出部分 — height 越小, List 显示的 row 越少.
        // maxWidth: .infinity 钉住宽度 — 防止 play/pause 切换时音频会话状态变动引起
        // 系统 safe area 微调, 导致 List 宽度抖动 (左右轻微摆动).
        .frame(maxWidth: .infinity)
        // 封顶到 playlistMaxHeight (= min(屏高55%, 内容高)) — 默认 254 在短计划下也不会
        // 高过内容露出纯黑空洞. 拖拽已在 clamp 里限到 maxHeight, 这里兜住初始/tap 档位.
        .frame(height: min(playlistHeight, playlistMaxHeight) + bottomSafeArea)
        .clipped()
        .background(
            Color(red: 10/255, green: 10/255, blue: 10/255)
                .ignoresSafeArea(.container, edges: .bottom)
        )
        .ignoresSafeArea(.container, edges: .bottom)
        // 注意: drawer 上不再挂 .animation(value: playlistExpanded). 之前那条 spring 会在用户
        // 拖到 minHeight+40 临界值时把 playlistExpanded bool 翻面 → 触发 spring 重排 → 跟正在
        // 跟手的 drag.onChanged 抢这一帧 frame, 视觉上就是抖动.
        // tap-to-toggle 路径用显式 withAnimation 包 height 写入, 仍能 spring 切档; drag 路径
        // 不进任何动画事务, 严格跟手指.
    }

    /// 拖把手栏: 顶部细短胶囊 + "PLAYLIST" kicker. 整块都接 DragGesture, 上下拖即可改 playlist 高度.
    /// 单击切档: min ↔ default 两态. 跟系统 sheet drag indicator 视觉一致, 但比它高度大一点 (这里
    /// 是真交互, 系统的那条只是装饰).
    private var playlistDragHandleBar: some View {
        VStack(spacing: 0) {
            // 短胶囊把手 — 比系统 sheet drag indicator (36×5) 略大一点 (44×6), 训练时戴手套 / 出汗
            // 也能精准抓到.
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 44, height: 6)
                .padding(.top, 10)
                .padding(.bottom, 6)
            // "PLAYLIST" header 跟拖把手合并到这同一栏 — 之前 InlinePlaylist 内部还有一份 header,
            // 用 showHeader: false 关掉避免双份.
            HStack {
                Text("Playlist")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(MasoColor.textFaint)
                Spacer()
                if (store.plan?.steps.count ?? 0) > 1 {
                    Text("Long press to reorder")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MasoColor.textFaint.opacity(0.7))
                }
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(playlistResizeGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playlist drawer drag handle")
        .accessibilityHint("Drag up to expand, down to collapse. Tap to toggle.")
    }

    /// playlist 高度拖拽手势 — tap 和 drag 全部走这一份 DragGesture(minimumDistance: 0).
    /// 不再用单独的 .onTapGesture, 原因: tap + drag 同时挂在一个 View 上, SwiftUI 在两者之间
    /// 逐帧仲裁 + tap 触发的 spring 还在跑时 drag 接管, 两套动画事务打架 → 抖动.
    /// 单 gesture + 自分发 (translation 小 = tap; 大 = drag) 彻底切断仲裁路径.
    ///
    /// coordinateSpace 必须 .global — 把手自身随 drawer 高度变化往上/下移动, .local 下
    /// translation 相对"正在移动的 view"计算: 拖 10pt → drawer 长高 10pt → 把手上移 10pt →
    /// 下一帧 local translation 被回吐归零 → 高度弹回 → 又长高… 每帧在两个高度间振荡 = 抖动
    /// (用户实录视频里的症状). global 空间里手指位移跟 view 移动解耦, 严格跟手.
    ///
    /// 拖拽更新走 `Transaction.disablesAnimations = true` 显式拒收任何继承动画 (RestCountdown
    /// 那条 .animation(value: playlistExpanded) 不会再回头影响 height frame).
    private var playlistResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                // 死区: 位移 ≤ 10pt 当作"还在判断 tap", 不动 height. 越过死区后, 锚定 startHeight,
                // 之后每帧直接 set height. 已经锚定过的 (startHeight != 0) 永远继续跟手, 不再走判断.
                guard playlistDragStartHeight != 0 || abs(dy) > 10 else { return }
                if playlistDragStartHeight == 0 {
                    playlistDragStartHeight = playlistHeight
                }
                let proposed = playlistDragStartHeight - dy
                let clamped = max(Self.playlistMinHeight, min(playlistMaxHeight, proposed))
                // 显式禁用动画 — 上一个 tap 留下的 spring transaction 不能渗透到这一帧.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    playlistHeight = clamped
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let wasDrag = playlistDragStartHeight != 0
                playlistDragStartHeight = 0
                // 没真拖动 (translation 没出 10pt 死区) → 当作 tap 切档 min ↔ default.
                // P3: 死区从 3 → 10pt, 拇指轻点常带几 pt 位移, 3pt 太小会被误判为拖动.
                if !wasDrag && abs(dy) <= 10 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        playlistHeight = playlistExpanded ? Self.playlistMinHeight : Self.playlistDefaultHeight
                    }
                }
                store.noteActivity()  // P2-9: 拖把手 = 用户在场, 别被 6h idle 误判完成
                Haptics.tap()
            }
    }

    /// playlist 内容的自然高度 (拖把手 + 所有动作行 + 动作间休息行 + "+ Add" footer).
    /// 给 drawer 高度封顶用 — drawer 不能高过内容, 否则内容下方露出一块纯黑空洞 (#4 用户报).
    /// 估算值 (避免深层 GeometryReader): 行高跟实际接近, 默认计划都有动作间休息 → 常见场景准.
    private var playlistContentHeight: CGFloat {
        let steps = store.plan?.steps.count ?? 0
        guard steps > 0 else { return Self.playlistMinHeight }
        let handleH: CGFloat = 56       // 拖把手 + "PLAYLIST" header (= playlistMinHeight)
        let exerciseRowH: CGFloat = 84  // 缩略图/进度环 + 名字 + 肌群/器械 tag
        let restRowH: CGFloat = 28      // "Rest m:ss" 动作间休息行
        let footerH: CGFloat = 60       // "+ Add exercise"
        let crossRests = max(0, steps - 1)
        return handleH + CGFloat(steps) * exerciseRowH + CGFloat(crossRests) * restRowH + footerH
    }

    /// playlist 高度上限 — 既保证上方训练图至少留 200pt, 又封顶到内容高度
    /// (drawer 高过内容会在内容下方露纯黑空洞 → #4).
    private var playlistMaxHeight: CGFloat {
        let screenH = UIScreen.main.bounds.height
        let screenMax = max(Self.playlistDefaultHeight, screenH * 0.55)
        return min(screenMax, playlistContentHeight)
    }

    /// rest 段之后第一个 exercise 段 (= "UP NEXT" 那一组). 休息时 playlist 按它渲染 →
    /// 跟休息结束、那组开始时完全一致, 消除 rest→set 自动切换瞬间的"高亮跳 / 缩略图↔进度环"闪动.
    private var upcomingExerciseSegment: Segment? {
        guard let idx = store.session?.segmentIndex else { return nil }
        let segs = store.segments
        var i = idx + 1
        while i < segs.count {
            if segs[i].isExercise { return segs[i] }
            i += 1
        }
        return nil
    }

    private var currentStepId: String? {
        // exercise 段用自己的; rest 段指向"即将要做的那组"动作, 让 playlist 训练组 / 休息态完全一致.
        if store.currentSegment?.isExercise == true { return store.currentSegment?.stepId }
        return upcomingExerciseSegment?.stepId ?? store.currentSegment?.stepId
    }
    private var currentSetNumber: Int? {
        if case .exercise(_, let setN, _, _, _, _, _) = store.currentSegment?.kind { return setN }
        // rest 段: 用"即将要做的那组"的组号, 跟 currentStepId 同源 → 休息态 playlist = 下一组的 playlist.
        if case .exercise(_, let setN, _, _, _, _, _) = upcomingExerciseSegment?.kind { return setN }
        return nil
    }

    // MARK: - Save plan (自由训练完成后的 "保存为计划" 入口)

    /// 当前 plan 是临时自由训练 (autoGenerated 标志 + 尚未入 data.plans) → 可保存
    private var canSaveCurrentPlan: Bool {
        guard let plan = store.plan, plan.autoGenerated else { return false }
        return !data.plans.contains(where: { $0.id == plan.id })
    }

    /// 把当前临时 plan 保存到用户的 plan library
    @State private var planSavedFlash: Bool = false  // 显示"已保存"短暂 toast
    private func saveCurrentPlanToLibrary() {
        guard let plan = store.plan else { return }
        var p = plan
        p.autoGenerated = false  // 用户主动保存 — 不再算作 auto
        p.updatedAt = Date()
        data.updatePlan(p)
        // 保存即"决定已做" — 不设的话 plan 刚入库会让 canSaveChangesToPlan 实时翻 true
        // (planParamsDirty 还挂着), 完成页会被换成一张全无修改的确认页 (审查发现的反应性陷阱).
        planSaveDecisionMade = true
        Haptics.tap()
        planSavedFlash = true
    }

    // MARK: - Save changes to existing plan (训练中改了参数 → 持久化到原 plan)

    /// 是否可以"保存修改到训练计划".
    /// 条件: plan 已存在于 data.plans (自由训练/Catch-up 是 ephemeral, 不入库, 自动排除 —
    /// 它们走自己的 "Save as plan" 流程), 且 store.planParamsDirty (用户在训练中改了
    /// sets/reps/weight/duration/顺序).
    /// 注意不看 autoGenerated: onboarding/AI 生成的计划也在库里, 用户训练中的修改同样该能保存
    /// (之前多了 !autoGenerated 条件, 导致 AI 计划的修改在完成时被静默丢弃).
    private var canSaveChangesToPlan: Bool {
        guard let plan = store.plan,
              data.plans.contains(where: { $0.id == plan.id }),
              store.planParamsDirty else {
            return false
        }
        return true
    }

    /// 把 store.plan (session-local 改过的副本) 写回 DataStore.plans, 持久化用户的修改.
    /// updatedAt 刷新让该 plan 在 Plans tab 排在前面.
    private func saveChangesToCurrentPlan() {
        guard let plan = store.plan else { return }
        var p = plan
        p.updatedAt = Date()
        data.updatePlan(p)
        Haptics.tap()
    }

    // MARK: - Share data 计算 (给 CompletedView 的分享卡用)

    /// 训练时长 (秒) — 从 session.startedAt 到现在
    private var completedDurationSeconds: Int {
        guard let started = store.session?.startedAt else { return 0 }
        // P3: 用"最后一组的时间"而非 live Date() 作为终点 —— 否则 6h idle 自动完成 / 用户
        // 把完成屏挂着不关, 时长会虚高到几小时. 取本场 (performedAt >= startedAt) 最后一组的
        // 时间; 没有任何记录 (空完成) 才 fallback 到 now.
        let lastSetAt = data.sets
            .filter { $0.performedAt >= started }
            .map(\.performedAt)
            .max()
        let end = lastSetAt ?? Date()
        return max(0, Int(end.timeIntervalSince(started)))
    }

    /// 本次训练涉及的肌群 (从 plan.steps dedupe)
    private var completedMuscles: [MuscleGroup] {
        guard let plan = store.plan else { return [] }
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for step in plan.steps {
            guard let ex = data.exById[step.exerciseId] else { continue }
            for m in ex.muscleGroups where seen.insert(m).inserted {
                out.append(m)
            }
        }
        return out
    }

    /// 本次训练 PR 数 — 从 data.sets 过滤本次 session 范围内的 set, isPR 检测.
    private var completedPRCount: Int {
        guard let session = store.session else { return 0 }
        let started = session.startedAt
        let recent = data.sets.filter { $0.planId == session.planId && $0.performedAt >= started }
        return recent.filter { data.isPR($0) }.count
    }

    /// 本次训练的前几个动作名 (分享卡 chip 用).
    private var completedExerciseNames: [String] {
        guard let plan = store.plan else { return [] }
        var seen = Set<String>()
        var names: [String] = []
        for step in plan.steps {
            guard let ex = data.exById[step.exerciseId], seen.insert(ex.id).inserted else { continue }
            names.append(ex.displayName)
        }
        return names
    }

    /// 本次训练动作数 (唯一 exercise 数) — 跟 SessionSummary.exerciseCount 同义.
    private var completedExerciseCount: Int {
        guard let plan = store.plan else { return 0 }
        return Set(plan.steps.map { $0.exerciseId }).count
    }

    /// sessionId — 跟 HistoryScreen.groupedSessions 同公式生成. 给分享卡持久化照片用.
    /// 公式: "\(planId)-\(Int(startOfDay(startedAt).timeIntervalSince1970))"
    private var completedSessionId: String? {
        guard let session = store.session else { return nil }
        let day = Calendar.current.startOfDay(for: session.startedAt)
        return "\(session.planId)-\(Int(day.timeIntervalSince1970))"
    }

    /// 本次 session 真正完成的 SetRecord (过滤到本场).
    private var completedSessionSets: [SetRecord] {
        guard let session = store.session else { return [] }
        return data.sets.filter { $0.planId == session.planId && $0.performedAt >= session.startedAt }
    }

    /// 分享卡详情 bundle — 逐组明细 (动作概要用) + 总容量 (kg).
    /// QR 现在是 App Store 下载链 (MasoLinks.appStore), 导入走 OCR 读卡上动作名+组数, 不再编 maso:// 深链.
    private var completedShareBundle: (detail: [WorkoutExerciseDetail], volume: Double) {
        let sets = completedSessionSets
        guard !sets.isEmpty else { return ([], 0) }
        let built = WorkoutShareBuilder.build(
            sessionSets: sets,
            orderHint: store.plan?.steps ?? [],
            exById: data.exById,
            planName: store.plan?.name ?? ""
        )
        let volume = sets.reduce(0.0) { $0 + ((($1.weight ?? 0)) * Double($1.reps ?? 0)) }
        return (built.detail, volume)
    }

    /// 分享卡日期行 — 本场 session 开始日 (e.g. "2026-06-09 周二" zh / "Mon, Jun 9" en).
    private var completedDateLabel: String? {
        guard let session = store.session else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: LanguageManager.shared.effectiveLanguage.rawValue)
        f.setLocalizedDateFormatFromTemplate("yyyyMMMdEEE")
        return f.string(from: session.startedAt)
    }

    /// 每个 step 已完成的组数 —— stepId → completedSets.count.
    /// 只统计用户**真正点了"打勾"**的组 (session.completedSets), 不算 setIndex 跳过的.
    /// 比如用户从 step 1 跳到 step 5, step 1-4 都不算完成 (除非他们之前打过勾).
    private var completedSetsByStep: [String: Int] {
        guard let s = store.session else { return [:] }
        var out: [String: Int] = [:]
        for done in s.completedSets {
            out[done.stepId, default: 0] += 1
        }
        return out
    }
}

// MARK: - 背景图 (full-bleed) + 底部信息区

/// 当前动作的图片 — 铺满整个 sheet 背后, scaleAspectFill
private struct FullBleedExerciseImage: View {
    let exercise: Exercise
    /// 是否双帧 cross-fade 动画. 默认 true (跟训练中页面一致).
    /// 休息页面用 false (静图) — 休息时大动图反复 fade 在背景视觉太吵, 静图给"看清楚下一动作"就够.
    var animated: Bool = true

    var body: some View {
        ZStack {
            // 兜底渐变 (loading / failure)
            categoryGradient
            // 实际图片 — animated=true 双帧 cross-fade; false 只渲染 frame 0 静图.
            if let folder = exercise.imageFolder {
                FullBleedFrameImage(folder: folder, animated: animated)
            }
        }
    }

    private var categoryGradient: LinearGradient {
        let colors: [Color] = {
            switch exercise.category {
            case .strength, .hypertrophyFocus, .calisthenics:
                return [Color.green.opacity(0.4), Color.black]
            case .cardio, .plyometric:
                return [Color.pink.opacity(0.4), Color.black]
            case .flexibility, .stretching, .mobility:
                return [Color.orange.opacity(0.4), Color.black]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Full-bleed 两帧 cross-fade — 全屏背景版.
/// 改为共享 CrossFadeFrames 组件: 共用 UIImage cache + GeometryReader + 严格 frame 锚定,
/// 不再各自挂 AsyncImage + Timer, 像素位置稳定, 不闪不抖.
private struct FullBleedFrameImage: View {
    let folder: String
    /// false → 只渲染 frame 0, 不挂 timer, 不加载 frame 1. 休息页面背景用.
    var animated: Bool = true

    var body: some View {
        CrossFadeFrames(folder: folder, animated: animated)
    }
}

/// 动作信息区 — 紧贴控件上方
/// BodyHint + name + chips, 文字白色 / chip 半透明黑底, 在渐变背景上易读
private struct ExerciseInfo: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var store
    let exercise: Exercise
    let setNumber: Int
    let totalSets: Int
    let reps: Int?
    let weight: Double?
    let duration: Int?
    let isCountdown: Bool
    let remaining: Int?
    /// "替换动作" 回调 — 通过 EditCurrentStepSheet 的 onReplace 触发. parent 用它弹 ExercisePickerSheet.
    var onRequestReplace: (() -> Void)? = nil

    /// 杠铃配重计算器 — 点 weight pill 弹起
    @State private var plateCalcOpen: Bool = false
    /// 训练中编辑参数 — 点右侧 slider icon 弹起
    @State private var editOpen: Bool = false

    /// "上次同动作" — 兑现 plan 理念 2 "历史即计划".
    /// nil = 第一次做这个动作 (没历史)
    private var lastSetSummary: String? {
        guard let last = data.lastSet(forExerciseId: exercise.id) else { return nil }
        // 同一段训练里 (这一次的 sets), 不算 — 用户自己的记录, 不是"上次"
        // 简单判断: 上次 performedAt 在 30 分钟前以内 → 大概率是本场训练, skip
        if Date().timeIntervalSince(last.performedAt) < 1800 { return nil }
        let dateLabel = relativeDay(last.performedAt)
        if let w = last.weight, w > 0, let r = last.reps {
            return String(format: NSLocalizedString("Last: %@ kg × %d (%@)", comment: ""), formatWeight(w), r, dateLabel)
        } else if let r = last.reps {
            return String(format: NSLocalizedString("Last: × %d (%@)", comment: ""), r, dateLabel)
        } else if let d = last.duration {
            return String(format: NSLocalizedString("Last: %ds (%@)", comment: ""), d, dateLabel)
        }
        return nil
    }

    /// 单个指标块: 大数值 + 60% 透明的字样标签. 文字带阴影, 在动图背景上可读.
    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(MasoColor.text)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.text.opacity(0.6))  // 字样 60% 透明
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
        .fixedSize()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            BodyHint(
                muscles: exercise.muscleGroups,
                height: MasoMetrics.bodyHintPlayer,
                region: detectBodyRegion(exercise.muscleGroups),
                square: true
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                // "上次同动作" 摘要 — 没历史时不渲染. 兑现"历史即计划".
                if let summary = lastSetSummary {
                    Text(summary)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(MasoColor.accent.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                // 指标行: SETS / REPS / WEIGHT (+ countdown TIME), 每个数值下带 60% 透明的字样标签.
                // weight 块可点 → 杠铃配重计算器. 末尾 pencil → 完整编辑 sheet.
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    metric(value: "\(setNumber)/\(totalSets)", label: NSLocalizedString("Sets", comment: ""))
                    if let r = reps {
                        metric(value: "\(r)", label: NSLocalizedString("Reps", comment: ""))
                    }
                    if let w = weight, w > 0 {
                        Button(action: { plateCalcOpen = true }) {
                            metric(value: "\(formatWeight(w)) kg", label: NSLocalizedString("Weight", comment: ""))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(NSLocalizedString("Plate calculator", comment: ""))
                    }
                    if isCountdown, let remaining {
                        metric(value: formatRemaining(remaining), label: NSLocalizedString("Time", comment: ""))
                    }
                    Spacer(minLength: 0)
                    Button(action: {
                        Haptics.tap()
                        editOpen = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MasoColor.text)
                            .frame(width: 28, height: 24)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("Edit exercise parameters", comment: ""))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .sheet(isPresented: $plateCalcOpen) {
            if let w = weight, w > 0 {
                PlateCalculatorSheet(targetWeight: w, unit: .kg)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $editOpen) {
            EditCurrentStepSheet(
                exercise: exercise,
                initialSets: totalSets,
                initialReps: reps,
                initialWeight: weight,
                initialDuration: duration,
                onSave: { newSets, newReps, newWeight, newDuration, newSetReps, newSetWeights in
                    store.updateCurrentStep(
                        sets: newSets,
                        reps: newReps,
                        weight: newWeight,
                        duration: newDuration,
                        setReps: newSetReps,
                        setWeights: newSetWeights,
                        exById: data.exById,
                        defaultRest: data.settings.defaultRestSeconds,
                        defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
                    )
                },
                onReplace: onRequestReplace
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

}

/// 休息区 — 上方倒计时圆环 + 下方下一段提示
/// 圆环 stroke 细一点 (3pt), 边缘随时间逐渐 trim 消失
/// 用 TimelineView 强制每 0.5s 重渲, 保证倒计时 + 圆环都在跳
/// 倒计时圆环 — 单独抽出来, 给 parent 用 Spacer 上下包夹做真居中.
/// "Up Next" 信息搬到 RestNextHint 独立渲染, 跟 Controls 一起钉底.
private struct RestCountdown: View {
    let durationTotal: Int
    let endsAt: Date?
    let pausedRemaining: TimeInterval?
    let isCrossExercise: Bool
    /// 紧凑度 0..1 — 0 = 圆环最大 (playlist 收到最小); 1 = 紧凑 (playlist 撑大). 连续值跟
    /// playlistHeight 线性, 让圆环大小跟 drawer 高度在"同一个动画事务"里平滑变化 → 不抖.
    let compactT: CGFloat

    private static let ringWidth: CGFloat = 3
    private static let baseRing: CGFloat = 220

    /// 整组件统一缩放因子 — playlist 越大越小 (1.0 → 0.44). 用一个 scaleEffect 把"圆环 + 描边 +
    /// REST 文字 + 数字"整体一起缩 (用户要求: 缩小是整体缩, 不是各部件分别算尺寸); frame 同步收窄,
    /// 让 layout footprint 也跟着小 → drawer 拖高时不重叠.
    private var restScale: CGFloat { max(0.44, 1 - 0.36 * compactT) }

    private func remainingFloat(at date: Date) -> Double {
        if let p = pausedRemaining { return max(0, p) }
        guard let endsAt = endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(date))
    }

    private func progress(_ remaining: Double) -> CGFloat {
        guard durationTotal > 0 else { return 0 }
        return max(0, min(1, CGFloat(remaining) / CGFloat(durationTotal)))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let rem = remainingFloat(at: ctx.date)
            let prog = progress(rem)
            // 整组件按 baseRing 渲染, 再统一 scaleEffect + frame 缩放 → 圆环/文字一起整体缩.
            ringView(remaining: Int(ceil(rem)), progress: prog)
                .scaleEffect(restScale, anchor: .center)
                .frame(width: Self.baseRing * restScale, height: Self.baseRing * restScale)
        }
    }

    private func ringView(remaining: Int, progress: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(MasoColor.text.opacity(0.12), lineWidth: Self.ringWidth)
                .frame(width: Self.baseRing, height: Self.baseRing)
            Circle()
                .trim(from: max(0, 1 - progress), to: 1)
                .stroke(
                    MasoColor.accent,
                    style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: Self.baseRing, height: Self.baseRing)
            VStack(spacing: 4) {
                Text(isCrossExercise ? "Switching" : "Rest")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(MasoColor.accent)
                Text(formatRemaining(remaining))
                    .font(.system(size: 64, weight: .bold).monospacedDigit())
                    .foregroundStyle(MasoColor.text)
            }
        }
    }
}

/// 下一动作 hint — kicker + 动作名. 跟 Controls 同框, 共享底部渐变遮罩背景.
/// 字号 18pt + 黑色 shadow → 在 next-exercise 动图上读得清楚.
private struct RestNextHint: View {
    let next: Exercise
    /// 下一动作的目标 reps / weight — 让用户休息时提前知道下一组上多少.
    var nextReps: Int? = nil
    var nextWeight: Double? = nil
    let isCrossExercise: Bool
    /// 小编辑入口 — 让用户在休息时改下一动作的 sets/reps/weight. nil → 不渲染.
    var onEdit: (() -> Void)? = nil

    /// "× 8 · 60 kg" 这种目标摘要; 都没有则 nil.
    private var targetLine: String? {
        var parts: [String] = []
        if let r = nextReps { parts.append("× \(r)") }
        if let w = nextWeight, w > 0 { parts.append("\(formatWeight(w)) kg") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(isCrossExercise ? "Next Exercise" : "Up Next")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.accent)
            HStack(alignment: .center, spacing: 8) {
                Text(next.displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                if let onEdit {
                    // 22pt 小铅笔 — 跟动作名同行靠右, 半透圆底让它在动图上仍可读.
                    Button(action: { Haptics.tap(); onEdit() }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.text)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("Edit next exercise", comment: ""))
                }
            }
            // 下一组目标 — × reps · weight kg. 让用户休息时就知道下一组上多少.
            if let targetLine {
                Text(targetLine)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(MasoColor.text.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
    }
}

private struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(MasoColor.text)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(.black.opacity(0.45))
            .clipShape(Capsule())
    }
}

// MARK: - Controls

private struct Controls: View {
    let seg: Segment
    let playing: Bool
    let canGoBack: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void
    let onTogglePlay: () -> Void
    let onEnd: () -> Void

    /// 主按钮"庆祝动效"触发器 — 每次点 +1, 让 halo overlay 重新跑动画.
    /// 比 Bool toggle 好: 连点几次也能每次都触发, 不会被合并掉.
    @State private var celebrateTrigger: Int = 0

    /// 统一布局: 动作段与休息段共用同一套 4 按钮等距排布
    /// X 取消 / ◀ 上一段 / ● 主操作 (48×48 accent, 比侧 36×36 略大) / ☰ 播放列表
    /// 第 1 + 第 4 用线条 SF Symbol (粗体 .heavy weight), 看起来"线条更粗"
    /// 主按钮通过 icon 区分:
    ///   - 动作段非倒计时 → ✓ "完成本组"
    ///   - 动作段倒计时   → ▶/⏸ "播放/暂停"
    ///   - 休息段        → ▶| "跳过休息"  (forward.end.fill — 一个三角加一根杠)
    ///
    /// 高度: 恢复默认 — 之前为了"触控更舒展"拉到 28/40, 视觉太占地方;
    /// 改回 12/24 让图片区还原原来的呼吸空间.
    var body: some View {
        // 3 个按钮: Cancel · Back · Primary. 用 4 个 Spacer 包夹 (bookend) — 让 4 段 flex 缝隙
        // 平均分配剩余水平空间, cancel 离左边距 == primary 离右边距, 视觉对称.
        //
        // 之前末尾用过 fixed 36pt Spacer 占位, 但那样 primary 被推回偏左, cancel 像贴在左边缘.
        // 改用全 flex Spacer 后, 三个按钮均匀分布在 row 中间, 两侧都有等宽呼吸.
        HStack(spacing: 0) {
            Spacer()
            cancelBtn
            Spacer()
            backBtn
            Spacer()
            primaryBtn
            Spacer()
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .padding(.top, 4)     // 顶部留更小间距 — 按钮栏跟上方 info 区贴更紧, 视觉收得稳
        .padding(.bottom, 24)
    }

    /// 主操作按钮 — 48×48 accent 圆 + 庆祝动效:
    ///   - 按下时 scale 0.92 (PressScaleStyle)
    ///   - 松手/点完成时, halo 圆环 1×→2.6× 同时透明度 0.8→0 扩散开 (HaloRing)
    ///   - 主按钮 quick pulse: 1.0 → 1.12 → 1.0 用 spring 收回 (overshoot 一下)
    /// 全部触发器走 celebrateTrigger int 计数 — 连点连发, 不会被 SwiftUI 合并掉.
    /// 主按钮是不是"完成本组" (✓). 只有它放庆祝动效 (pulse + halo);
    /// 播放/暂停 (倒计时段) 和跳过休息不放 — 否则点暂停按钮会弹一下, 看着像抖动.
    private var isPrimaryComplete: Bool {
        if case .exercise(_, _, _, _, _, _, let countdown) = seg.kind { return !countdown }
        return false
    }

    private var primaryBtn: some View {
        Button(action: {
            onPrimary()
            if isPrimaryComplete { celebrateTrigger &+= 1 }
        }) {
            if seg.isRest {
                // 休息跳过 — 无圆圈的 accent 纯图标. 图标大小跟"上一动作"按钮一致 (size 15),
                // 但 frame 固定成 42×42 (= exercise primary 圆的 footprint), 这样 exercise↔rest
                // 切换时主按钮槽位宽高完全不变 → 按钮栏不再左右抖.
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            } else {
                ZStack {
                    // halo 圆环 — 在按钮下层向外扩散, 给"完成 / 突破"感
                    HaloRing(trigger: celebrateTrigger)
                    // 主按钮圆 48 → 42 (缩小一号, 跟侧三按钮比例更协调)
                    Circle().fill(MasoColor.accent).frame(width: 42, height: 42)
                        .shadow(color: MasoColor.accent.opacity(0.35), radius: 12, y: 4)
                    primaryIcon
                        // icon 16 → 14 — 跟缩小后的圆按钮比例一致
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.black)
                }
                // 按钮本身的 pulse — 触发后短暂放大再收回
                .modifier(PrimaryPulseModifier(trigger: celebrateTrigger))
            }
        }
        .buttonStyle(PrimaryPressScaleStyle())
        .accessibilityLabel(primaryLabel)
    }

    // 共用 4 个小按钮 (X 取消, ◀ 上一段, ☰ 播放列表)
    // 全部整体缩小一号: icon 字号 -2, frame 40 → 36
    private var cancelBtn: some View {
        Button(action: onEnd) {
            // stop.fill — 跟主按钮的 play/pause 形成 transport controls 隐喻.
            // 字号 / 字重 / 颜色 跟 backward.end.fill (上一动作) 完全一致, 视觉对称.
            Image(systemName: "stop.fill")
                .font(.system(size: 14))
                .foregroundStyle(MasoColor.textDim)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End workout")
    }
    private var backBtn: some View {
        Button(action: {
            Haptics.tap()  // 轻触反馈 — 跟其它操作按钮的触觉语言一致
            onBack()
        }) {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 14))
                .foregroundStyle(MasoColor.textDim)
                .frame(width: 36, height: 36)
                .opacity(canGoBack ? 1.0 : 0.3)
        }
        .buttonStyle(.plain)
        .disabled(!canGoBack)
        .accessibilityLabel("Previous")
    }
    @ViewBuilder
    private var primaryIcon: some View {
        switch seg.kind {
        case .exercise(_, _, _, _, _, _, true):
            Image(systemName: playing ? "pause.fill" : "play.fill")
        case .rest:
            // "一个三角形加一个杠" — App 内统一的跳过图标
            Image(systemName: "forward.end.fill")
        case .exercise:
            Image(systemName: "checkmark")
        }
    }

    private var primaryLabel: String {
        // .accessibilityLabel 接 String, 不走 LocalizedStringKey lookup —
        // 在这里就用 NSLocalizedString 显式查表, 让 VoiceOver 念出对应语言的文案.
        switch seg.kind {
        case .exercise(_, _, _, _, _, _, true):
            return playing
                ? NSLocalizedString("Pause", comment: "")
                : NSLocalizedString("Resume", comment: "")
        case .rest:
            return NSLocalizedString("Skip rest", comment: "")
        case .exercise:
            return NSLocalizedString("Complete set", comment: "")
        }
    }
}

// MARK: - 主按钮庆祝动效组件

/// 按下时按钮 scale 0.92, 松手回 1.0 — 跟系统按钮的按压视觉一致.
private struct PrimaryPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.5),
                       value: configuration.isPressed)
    }
}

/// 主按钮点击后 quick pulse — 1.0 → 1.12 → 1.0 用 spring 收回, 给"完成"动作一个小弹.
/// trigger 是计数器, 每次 +1 都会让 onChange 跑一遍动画 (不会被合并).
private struct PrimaryPulseModifier: ViewModifier {
    let trigger: Int
    @State private var pulseScale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulseScale)
            .onChange(of: trigger) { _, _ in
                // 先放大到 1.12 (50ms), 然后 spring 收回 1.0 (overshoot 一下)
                withAnimation(.easeOut(duration: 0.06)) {
                    pulseScale = 1.12
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                        pulseScale = 1.0
                    }
                }
            }
    }
}

/// 主按钮外的扩散圆环 — 1.0 → 2.6 scale + 0.8 → 0 opacity, 600ms 衰减.
/// trigger 走计数器 — 每点一次都重新动画. allowsHitTesting(false) 确保它不挡按钮的 tap.
private struct HaloRing: View {
    let trigger: Int
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.0

    var body: some View {
        Circle()
            .stroke(MasoColor.accent.opacity(0.55), lineWidth: 2)
            .frame(width: 42, height: 42)  // 跟 primaryBtn 圆同步缩到 42
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                // 重置到起点 — 不带动画
                scale = 1.0
                opacity = 0.8
                // 扩散 + 淡出 — easeOut 600ms
                withAnimation(.easeOut(duration: 0.6)) {
                    scale = 2.6
                    opacity = 0
                }
            }
    }
}

// MARK: - InlinePlaylist (简化版)

/// 进度环命中区用的扇形 Shape — 从圆心到对应弧段的饼形, 让每组的 tap 区域足够大.
/// 各扇形互不重叠 (按 fraction 划分整圆), tap 精确落到对应那一组.
private struct RingWedge: Shape {
    let startFraction: Double
    let endFraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.move(to: c)
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(startFraction * 360 - 90),
                 endAngle: .degrees(endFraction * 360 - 90),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

private struct InlinePlaylist: View {
    let plan: Plan?
    let exById: [String: Exercise]
    let currentStepId: String?
    let currentSet: Int?
    /// stepId → 已完成组数. 让每行都能显示 "x/total" 的进度.
    let completedSetsByStep: [String: Int]
    let onJump: (String) -> Void
    /// 点行图片 → 弹动作详情. parent (PlanPlayerScreen) 接收, 在它身上挂 sheet.
    var onTapImage: ((Exercise) -> Void)? = nil
    /// 长按拖拽排序 — IndexSet 是被拖的行 (单个), Int 是目标位置.
    /// nil = 不支持排序 (e.g. 训练已完成 / 空 plan).
    var onReorder: ((IndexSet, Int) -> Void)? = nil
    /// 右滑删除 — 传 stepId. parent 接管二次确认 alert + 调 store.deleteStep.
    /// nil = 不支持删除 (跟 onReorder 一致, parent 可选传).
    var onDelete: ((String) -> Void)? = nil
    /// 右滑编辑 — 传 stepId. parent 拉 EditStepSheet 改 sets/reps/weight/duration (session-local).
    var onEdit: ((String) -> Void)? = nil
    /// 左滑替换 — 传 stepId. parent 弹 ExercisePickerSheet 让用户换一个动作.
    var onReplace: ((String) -> Void)? = nil
    /// playlist 末尾的 "+ Add exercise" 入口 — parent 接管 ExercisePickerSheet 拉起 + store.appendStep.
    /// nil → 不显示 footer 行.
    var onAddStep: (() -> Void)? = nil
    /// 是否在内部渲 "PLAYLIST" header 行. false → caller (PlanPlayer 的 dragHandleBar) 自己渲, 避免重复.
    var showHeader: Bool = true
    /// J5: 竖向进度条需要的 — 全部 segments + 当前 segment index + 真做完的 set 集合 +
    /// 按 segment index 跳转. 竖条每段 = 一组, tap = 跳到那一组 (跟旧顶部 TimelineBar 同逻辑).
    var segments: [Segment] = []
    var currentIndex: Int = 0
    var completedSets: Set<TrainingSessionStore.CompletedSet> = []
    var onJumpSegment: ((Int) -> Void)? = nil

    private var steps: [PlanStep] {
        plan?.steps ?? []
    }

    /// 某 step 的所有 exercise segment (按 set 顺序) + 它们在 segments 里的原始 index.
    /// 竖向进度条用 — 每个 set 一段.
    private func exerciseSegments(forStepId stepId: String) -> [(idx: Int, setN: Int)] {
        var out: [(Int, Int)] = []
        for (i, seg) in segments.enumerated() {
            guard seg.stepId == stepId else { continue }
            if case .exercise(_, let setN, _, _, _, _, _) = seg.kind {
                out.append((i, setN))
            }
        }
        return out
    }

    /// 某 step 之后、下一动作之前的"组间(动作间)休息"时长. 没有 → nil (最后一个动作).
    /// 直接从 segments 扫: 该 step 最后一个 exercise seg 之后、下一个 *不同 step* 的 exercise seg
    /// 之前的那个 rest seg.
    private func crossRestDuration(afterStepId stepId: String) -> Int? {
        // 找该 step 最后一个 exercise seg 的位置
        var lastIdx: Int? = nil
        for (i, seg) in segments.enumerated() where seg.stepId == stepId && seg.isExercise {
            lastIdx = i
        }
        guard let last = lastIdx else { return nil }
        // 从它之后找: 先遇到 rest 记下时长, 遇到 *不同 step* 的 exercise 就返回该时长
        var restDur: Int? = nil
        for i in (last + 1)..<segments.count {
            let seg = segments[i]
            if case .rest(let d) = seg.kind { restDur = d }
            else if seg.isExercise {
                return seg.stepId != stepId ? restDur : nil  // 下一个是别的动作才算"动作间休息"
            }
        }
        return nil
    }

    /// 进度环 — 替代旧顶部 TimelineBar / 竖条. 一组一段弧, 当前=白 / 做完=accent / 其它=灰,
    /// 从顶部顺时针. 点某段弧 → 跳到那一组 (跟旧顶部进度条每段同逻辑, 只是变成环形).
    /// 中心显示总组数 (替代旧 "x/total" 分数). 只在"当前动作"那一行替换缩略图 (caller 控制).
    @ViewBuilder
    private func progressRing(stepId: String) -> some View {
        let segs = exerciseSegments(forStepId: stepId)
        let n = max(segs.count, 1)
        let gap: Double = n > 1 ? 0.06 : 0   // 段间留 6% 空隙, lineCap .round 让缺口柔和
        ZStack {
            // 视觉环 — padding 让 5pt 描边不被 56 frame 裁切
            ZStack {
                Circle()
                    .stroke(MasoColor.textFaint.opacity(0.18), lineWidth: 5)
                ForEach(Array(segs.enumerated()), id: \.element.idx) { i, item in
                    let color = setBarColor(idx: item.idx, stepId: stepId, setN: item.setN)
                    Circle()
                        .trim(from: Double(i) / Double(n) + gap / 2,
                              to: Double(i + 1) / Double(n) - gap / 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))   // trim 0 起点转到正上方 12 点
                        // 颜色必须即刻切换 (白→绿 / 绿→白) — 禁掉任何继承动画,
                        // 否则切换动作时进度弧会短暂过渡到错误颜色 (闪烁).
                        .animation(nil, value: color)
                }
            }
            .padding(2.5)
            // 中心: 总组数
            Text("\(segs.count)")
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(MasoColor.text)
            // 命中区 — 每组一个扇形 Button (扇形互不重叠 → tap 精确落到对应组).
            // 在外层 onJump Button 之内, 但子 Button 优先级高于父 (跟缩略图 Button 同模式).
            ForEach(Array(segs.enumerated()), id: \.element.idx) { i, item in
                Button(action: { onJumpSegment?(item.idx) }) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(RingWedge(startFraction: Double(i) / Double(n),
                                                endFraction: Double(i + 1) / Double(n)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("Set %d", comment: ""), item.setN))
            }
        }
        .frame(width: 56, height: 56)
    }

    private func setBarColor(idx: Int, stepId: String, setN: Int) -> Color {
        // 三态用"亮度梯度 + 单一品牌色"区分, 即使只出现其中两态也一眼分得清:
        //   已完成 = 实心绿 (accent)   —— 达成
        //   正在进行 = 亮白 (text)      —— 此刻的焦点 (最亮, 不再是跟绿色撞色的浅绿)
        //   未做     = 暗灰 (0.35)       —— 还没到, 隐退
        // 之前 "浅绿(进行) vs 实绿(完成)" 同色系难区分 → 现在进行态换成纯白, 跟绿/灰拉开.
        // 颜色切换走 .animation(nil) 即刻生效, 不会有过渡闪烁.
        if completedSets.contains(.init(stepId: stepId, setN: setN)) {
            return MasoColor.accent           // 已完成 = 绿
        }
        if stepId == currentStepId, let cs = currentSet, setN == cs {
            return MasoColor.text             // 正在进行 = 亮白
        }
        return MasoColor.textFaint.opacity(0.35)  // 未做 = 暗灰
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)
                HStack {
                    Text("Playlist")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(MasoColor.textFaint)
                    Spacer()
                    // 提示文案 — 让用户知道可拖动排序 (iOS list 长按拖移交互对训练者来说不一定明显)
                    if onReorder != nil && steps.count > 1 {
                        Text("Long press to reorder")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MasoColor.textFaint.opacity(0.7))
                    }
                }
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.vertical, 8)
            }
            // 用原生 List + .onMove 让长按拖拽排序"自带":
            //   - List 默认 systemGroupedBackground 浅灰底 → scrollContentBackground(.hidden)
            //     + 父 VStack 自己上深色底铺
            //   - listRowSeparator 隐掉 (跟之前 ScrollView+VStack 无分割线视觉一致)
            //   - listRowInsets 清 0 (用 cell 内自己的 padding)
            //   - listRowBackground transparent (cell 内自己有 isCurrent 高亮)
            List {
                ForEach(steps) { step in
                    if let ex = exById[step.exerciseId] {
                        playlistRow(step: step, ex: ex)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            // 左滑 (trailing) 展开三个操作 — 从左到右视觉顺序: 编辑 | 替换 | 删除.
                            // SwiftUI trailing swipeActions: 第一个定义的按钮 = 最靠近右边缘 (最右),
                            // 最后定义的 = 最左. 想呈现 Edit(左) Replace(中) Delete(右):
                            //   代码顺序: Delete → Replace → Edit.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // 最右 — 删除 (破坏性, 红色)
                                Button(role: .destructive) {
                                    onDelete?(step.id)
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .tint(MasoColor.negative)
                                .accessibilityLabel(NSLocalizedString("Delete", comment: ""))

                                // 中间 — 替换动作 (换成另一个动作). caller 没传 onReplace 时整个按钮不出现.
                                if let onReplace {
                                    Button {
                                        onReplace(step.id)
                                    } label: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    .tint(.orange)
                                    .accessibilityLabel(NSLocalizedString("Replace", comment: ""))
                                }

                                // 最左 — 编辑 sets/reps/weight/duration
                                Button {
                                    onEdit?(step.id)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .tint(MasoColor.accent)
                                .accessibilityLabel(NSLocalizedString("Edit", comment: ""))
                            }
                    }
                }
                .onMove { source, destination in
                    onReorder?(source, destination)
                    Haptics.tap()
                }
                // "+ Add exercise" footer — parent 传了 onAddStep 才显示. 训练中临时加一个动作走这里.
                if let onAddStep {
                    Button(action: onAddStep) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(MasoColor.accent)
                            Text("Add exercise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MasoColor.text)
                            Spacer()
                        }
                        .padding(.horizontal, MasoMetrics.rowPaddingH)
                        .padding(.vertical, 12)
                        .background(MasoColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: MasoMetrics.rowPaddingH,
                                              bottom: 8, trailing: MasoMetrics.rowPaddingH))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // 隐藏纵向滚动条 — 关键修复"左右轻微摆动": List 默认在内容变化/重绘 (e.g. 暂停切换)
            // 时短暂显示滚动条, iOS 会把内容右侧 inset ~3pt 给滚动条腾位 → 行整体左移再弹回,
            // 视觉就是横向摆动. 隐藏后内容宽度恒定.
            .scrollIndicators(.hidden)
            // List 默认 environment editMode 是 inactive — onMove 在 inactive 下走"长按拖动"
            // 模式 (iOS 16+), 不需要进入显式 edit mode 才能拖. 用户长按行 ~0.5s 即可开始拖.
        }
        // 不透明 — playlist 背景必须跟"身后是什么"无关. 之前 0.85 半透 → 训练态透出动作大图
        // (偏红), 休息态透出"下一动作图 + 黑 mask" (偏暗), 两态 playlist 底色不一致, 行边缘 AA
        // 跟着变, 切换时看着像"item 收窄又放宽". 钉成纯不透明深色 → 两态完全一致.
        .background(Color(red: 10/255, green: 10/255, blue: 10/255))
    }

    private func playlistRow(step: PlanStep, ex: Exercise) -> some View {
        let isCurrent = step.id == currentStepId
        let done = progressN(for: step)
        // 已完成 step: progress 达到 sets 上限, 且不是当前行 (current 的 progress 是"正在做的组数",
        // 临界点 step.sets - 1 → step.sets 那一刻是用户做完最后一组的 transition, 此时 step 仍是 current).
        let isCompleted = !isCurrent && done >= step.sets && step.sets > 0
        // 进度环显示条件: 当前动作 OR 已经练过几组的动作 (done > 0). 这样切到别的动作后,
        // 之前练过的那几组在它自己那一行的环上仍标绿、看得见. 完全没碰过的动作才显缩略图.
        let showsRing = isCurrent || done > 0
        // Button 包整行处理 jump, 图片单独 Button 优先级高于外层, tap 图 → 详情而不是 jump.
        // 整体调大一档 (跟 iOS HIG 列表 cell 64pt 视觉一致): 图片 40→56, 名字 13→15pt,
        // 当前指示圆 6→7, 行内 spacing + padding 同步放大.
        return VStack(spacing: 0) {
            Button(action: { onJump(step.id) }) {
            HStack(spacing: 14) {
                // 当前动作 + 练过几组的动作: 缩略图位置换成进度环 (一组一段弧, 点段=跳到那一组);
                // 完全没碰过的动作才保留缩略图. 进度环让"哪几组练过"在每个动作上都看得见.
                if showsRing {
                    progressRing(stepId: step.id)
                } else {
                    Button(action: { onTapImage?(ex) }) {
                        ExerciseImage(
                            category: ex.category,
                            imageFolder: ex.imageFolder,
                            photoURL: ex.photoURL,
                            customImageData: ex.customImageData,
                            cornerRadius: 8,
                            size: 56,
                            animated: false  // 列表行不动, 节省 CPU + 减少干扰
                        )
                        // 已完成 step 缩略图整体淡化 — 暗示"这一项已经过了, 不再是焦点".
                        .opacity(isCompleted ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), ex.displayName))
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        if isCompleted {
                            // 微妙的"已完成" affordance: 实心圆 + 内嵌对勾 (跟 current 的纯实心圆区分).
                            // 14pt 半透 accent — 不抢戏, 但扫一眼就能看见.
                            ZStack {
                                Circle().fill(MasoColor.accent.opacity(0.85)).frame(width: 14, height: 14)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.black)
                            }
                        } else if isCurrent {
                            Circle().fill(MasoColor.accent).frame(width: 7, height: 7)
                        }
                        Text(ex.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            // 已完成: 文字色降到 textDim + strikethrough — 视觉立刻区分 "已过去"
                            .strikethrough(isCompleted, color: MasoColor.textDim)
                    }
                    HStack(spacing: 5) {
                        // 显示进度环的行 (当前 / 练过的) 组数由环展示, 这里不重复;
                        // 只有显缩略图的行 (没碰过的) 才直接显示总组数.
                        if !showsRing {
                            Text(String(format: NSLocalizedString("%d sets", comment: "total sets"), step.sets))
                                .font(.system(size: 12).monospacedDigit())
                        }
                        if let r = step.reps { Text("× \(r)").font(.system(size: 12).monospacedDigit()) }
                        if let w = step.weight, w > 0 { Text("· \(formatWeight(w)) kg").font(.system(size: 12).monospacedDigit()) }
                    }
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                    // muscle + equipment 标签 — 训练中也能一眼看出"下一组是练什么 / 用什么器械".
                    // row 整体放大后, tags 也用正常尺寸 (非 compact).
                    ExerciseTagsRow(
                        muscleGroups: ex.muscleGroups,
                        equipment: ex.equipment,
                        muscleLimit: 1
                    )
                    .opacity(isCompleted ? 0.55 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, MasoMetrics.rowPaddingH)
            .padding(.vertical, 10)  // row padding 加大让 56pt 缩略图四周呼吸更舒展
            .background(isCurrent ? MasoColor.accent.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // 整行点击热区: 没有 contentShape 时, Color.clear 背景区域不响应 tap,
            // 用户只能点到文字 / 缩略图. 加 contentShape 让整个 rect 都可点.
            .contentShape(Rectangle())
            .foregroundStyle(
                isCurrent ? MasoColor.accent
                : (isCompleted ? MasoColor.textDim : MasoColor.text)
            )
            }
            .buttonStyle(.plain)
          // J3: 动作间休息 — 显示在两动作之间, 不可拖排序 (它是 step 行尾部元素, 跟着动作走).
          if let restSec = crossRestDuration(afterStepId: step.id) {
              restRow(seconds: restSec)
          }
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
    }

    /// 动作间休息行 — 细、淡、居中, hourglass + 时长. 纯展示, 不参与排序 / 跳转.
    @ViewBuilder
    private func restRow(seconds: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 9, weight: .heavy))
            Text(String(format: NSLocalizedString("Rest %@", comment: "rest between exercises"), formatRemaining(seconds)))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(MasoColor.textFaint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    /// 当前 step 用 currentSet (正在做的那组); 否则用已完成组数 (默认 0).
    private func progressN(for step: PlanStep) -> Int {
        if step.id == currentStepId, let s = currentSet { return s }
        return completedSetsByStep[step.id, default: 0]
    }
}

// MARK: - Drag handle + Completed view

private struct DragHandle: View {
    var body: some View {
        Capsule().fill(.white.opacity(0.3))
            .frame(width: 48, height: 4)
            .padding(.top, 8).padding(.bottom, 6)
    }
}

// 训练完成屏 — 简化版
//   - 没有"已完成"小字 kicker
//   - 标题统一显示 "训练完成", plan 名作为副标题 (淡色, 在标题下)
//   - 大圆 ✓ + 标题 + 副标题, 整体居中, 视觉重心放在主标题
// MARK: - 完成流第一步: "保存修改到 routine?" 确认页

/// routine diff 引擎 — SaveChangesConfirmView 渲染 + PlanPlayerScreen 的完成流 gate 共用.
/// 必须是同一份逻辑: gate 说"有修改"页面就必须能高亮出至少一行, 反之亦然.
private enum RoutineDiff {
    /// 一行 = 一个训练组 (step) 的 diff 结果.
    struct Row: Identifiable {
        enum Kind { case unchanged, modified, added, removed, replaced }
        let id: String
        let kind: Kind
        /// 现动作名 (replaced = 新动作名; removed = 原动作名)
        let name: String
        /// replaced 时的旧动作名
        let oldName: String?
        /// modified/replaced 时的旧参数概要 (跟 summary 不同才显示箭头对比)
        let oldSummary: String?
        /// 现参数概要 (removed 行 = 原参数概要)
        let summary: String
        /// 相对顺序变了 (最小移动集合 — LIS 之外的才标)
        let moved: Bool

        var isChanged: Bool { kind != .unchanged || moved }
    }

    /// 完成流 gate 用 — diff 里存在至少一个会被高亮的行.
    static func hasChanges(original: Plan, session: Plan, exById: [String: Exercise]) -> Bool {
        rows(original: original, session: session, exById: exById).contains { $0.isChanged }
    }

    static func rows(original: Plan, session: Plan, exById: [String: Exercise]) -> [Row] {
        // uniquingKeysWith: 防御重复 step id — 导入的分享计划 (PlanShareCodec) 不重生成 step id,
        // 构造过的链接可能带重复 id; uniqueKeysWithValues 会直接 crash.
        let origById = Dictionary(original.steps.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let sessionIds = Set(session.steps.map(\.id))
        let movedIds = movedStepIds(original: original, session: session)

        var out: [Row] = []
        for step in session.steps {
            let name = exById[step.exerciseId]?.displayName ?? step.exerciseId
            guard let orig = origById[step.id] else {
                out.append(.init(id: step.id, kind: .added, name: name, oldName: nil,
                                 oldSummary: nil, summary: stepSummary(step), moved: false))
                continue
            }
            let moved = movedIds.contains(step.id)
            // 组间休息变化在概要里只在变化时附带, 避免常态噪音
            let restChanged = orig.restBetweenSets != step.restBetweenSets
            if orig.exerciseId != step.exerciseId {
                out.append(.init(id: step.id, kind: .replaced, name: name,
                                 oldName: exById[orig.exerciseId]?.displayName ?? orig.exerciseId,
                                 oldSummary: stepSummary(orig, includeRest: restChanged),
                                 summary: stepSummary(step, includeRest: restChanged), moved: moved))
            } else if paramsDiffer(orig, step) {
                let oldS = stepSummary(orig, includeRest: restChanged)
                let newS = stepSummary(step, includeRest: restChanged)
                if oldS == newS {
                    // 参数确实有差但渲染不出可见区别 (e.g. 概要里不展示的字段) — 不标 Updated,
                    // 否则用户看到"高亮了却找不到哪里变了"的幻影行. 保存时这些字段照常写入.
                    out.append(.init(id: step.id, kind: .unchanged, name: name, oldName: nil,
                                     oldSummary: nil, summary: newS, moved: moved))
                } else {
                    out.append(.init(id: step.id, kind: .modified, name: name, oldName: nil,
                                     oldSummary: oldS, summary: newS, moved: moved))
                }
            } else {
                out.append(.init(id: step.id, kind: .unchanged, name: name, oldName: nil,
                                 oldSummary: nil, summary: stepSummary(step), moved: moved))
            }
        }
        // 被删掉的 step — 插回原 plan 里的位置附近, 让用户在熟悉的顺序里看到"少了哪个"
        for (origIdx, orig) in original.steps.enumerated() where !sessionIds.contains(orig.id) {
            let name = exById[orig.exerciseId]?.displayName ?? orig.exerciseId
            out.insert(.init(id: orig.id, kind: .removed, name: name, oldName: nil,
                             oldSummary: nil, summary: stepSummary(orig), moved: false),
                       at: min(origIdx, out.count))
        }
        return out
    }

    /// 最小"被移动"集合 — 共同 step 在 session 顺序下的原 index 序列, 不在最长递增子序列
    /// (LIS) 里的就是被移动的. 这样"把一个动作拖到最前"只标那一个, 不会把全列表都标 Moved.
    private static func movedStepIds(original: Plan, session: Plan) -> Set<String> {
        let origIndexById = Dictionary(
            original.steps.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        let common = session.steps.compactMap { step -> (id: String, origIdx: Int)? in
            guard let oi = origIndexById[step.id] else { return nil }
            return (step.id, oi)
        }
        guard common.count > 1 else { return [] }
        // O(n²) LIS — plan steps 数量级很小 (<20), 不值得上 O(n log n)
        var lisLen = [Int](repeating: 1, count: common.count)
        var prev = [Int](repeating: -1, count: common.count)
        var bestEnd = 0
        for i in 0..<common.count {
            for j in 0..<i where common[j].origIdx < common[i].origIdx && lisLen[j] + 1 > lisLen[i] {
                lisLen[i] = lisLen[j] + 1
                prev[i] = j
            }
            if lisLen[i] > lisLen[bestEnd] { bestEnd = i }
        }
        var inLIS = Set<String>()
        var cursor = bestEnd
        while cursor != -1 {
            inLIS.insert(common[cursor].id)
            cursor = prev[cursor]
        }
        return Set(common.map(\.id)).subtracting(inLIS)
    }

    /// 参数级比较 — 逐组比"有效值", 把表示性噪音归一掉:
    ///   - setReps [12,12,12] (每项等于统一值) ≡ reps 12 + setReps nil
    ///   - weight 0 ≡ nil (appendStep 写 0, EditCurrentStepSheet 写 nil — 两个入口表示不一致)
    ///   - [nil,nil] ≡ nil
    private static func paramsDiffer(_ a: PlanStep, _ b: PlanStep) -> Bool {
        if a.sets != b.sets || a.duration != b.duration ||
           a.restBetweenSets != b.restBetweenSets || a.rest != b.rest { return true }
        for n in 1...max(a.sets, 1) {
            if a.repsForSet(n) != b.repsForSet(n) { return true }
            if a.durationForSet(n) != b.durationForSet(n) { return true }
            let aw = a.weightForSet(n).flatMap { $0 > 0 ? $0 : nil }
            let bw = b.weightForSet(n).flatMap { $0 > 0 ? $0 : nil }
            if aw != bw { return true }
        }
        return false
    }

    /// 一个 step 的参数概要 — "3 × 12 · 38 kg" / 逐组不同 "3 × 12/12/10 · 38/38/40 kg" /
    /// 计时段 "3 × 30s". includeRest 时附 "· rest 90s" (只在 rest 被改时开, 避免常态噪音).
    static func stepSummary(_ step: PlanStep, includeRest: Bool = false) -> String {
        var out: String
        if let d = step.duration, d > 0, step.reps == nil, step.setReps == nil {
            // 逐组不同时长 (60s/45s/30s) → 列出每组; 全组同时长 → 统一 "3 × 30s".
            if step.setDurations?.contains(where: { $0 != nil }) == true {
                let ds = (1...max(step.sets, 1)).map { n in step.durationForSet(n).map { durationLabel($0) } ?? "–" }
                out = "\(step.sets) × " + ds.joined(separator: "/")
            } else {
                out = "\(step.sets) × " + durationLabel(d)
            }
        } else {
            out = "\(step.sets)"
            if step.setReps?.contains(where: { $0 != nil }) == true {
                let reps = (1...max(step.sets, 1)).map { n in step.repsForSet(n).map(String.init) ?? "–" }
                out += " × " + reps.joined(separator: "/")
            } else if let r = step.reps {
                out += " × \(r)"
            } else {
                out = String(format: NSLocalizedString("%d sets", comment: ""), step.sets)
            }
            if step.setWeights?.contains(where: { $0 != nil }) == true {
                let ws = (1...max(step.sets, 1)).map { n in step.weightForSet(n).map { formatWeight($0) } ?? "–" }
                out += " · " + ws.joined(separator: "/") + " kg"
            } else if let w = step.weight, w > 0 {
                out += " · \(formatWeight(w)) kg"
            }
            // 罕见的 reps + duration 并存 (e.g. 计时辅助的力量段) — duration 也得进概要,
            // 否则"只改了 duration"会被上面的 oldS == newS 降级藏掉.
            if step.setDurations?.contains(where: { $0 != nil }) == true {
                let ds = (1...max(step.sets, 1)).map { n in step.durationForSet(n).map { durationLabel($0) } ?? "–" }
                out += " · " + ds.joined(separator: "/")
            } else if let d = step.duration, d > 0 {
                out += " · " + durationLabel(d)
            }
        }
        if includeRest {
            out += " · " + String(format: NSLocalizedString("rest %@", comment: "rest suffix in diff summary"),
                                  durationLabel(step.restBetweenSets))
        }
        return out
    }

    private static func durationLabel(_ secs: Int) -> String {
        if secs >= 60 {
            let m = secs / 60, s = secs % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        return "\(secs)s"
    }
}

/// 训练完成时, 若用户在训练中改过 routine 参数 (sets/reps/weight/duration/顺序/增删/替换),
/// 先进这个确认页让用户决定要不要把改动保存回 plan — 之后才进 CompletedView (分享卡).
/// 展示整个 routine 的训练组列表, 修改项突出显示 (旧值 → 新值 / 新增 / 移除 / 替换 / 顺序).
private struct SaveChangesConfirmView: View {
    let originalPlan: Plan
    let sessionPlan: Plan
    let exById: [String: Exercise]
    let onSave: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 头部 — 跟 CompletedView 同语言: 圆形 icon + 标题 + 说明
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(MasoColor.accent.opacity(0.16)).frame(width: 72, height: 72)
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(MasoColor.accent)
                }
                .padding(.bottom, 18)
                Text("Save changes to this routine?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .multilineTextAlignment(.center)
                Text(sessionPlan.name)
                    .font(.system(size: 13))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                    .padding(.top, 6)
                Text("You adjusted this routine during the workout. Save the adjustments for next time?")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)

            // routine 训练组列表 — 修改项突出, 未改项隐退
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        changeRow(row)
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)

            // 底部按钮 — 主: 保存到 routine; 次: 不保存 (跟 CompletedView 的按钮风格一致)
            VStack(spacing: 10) {
                Button(action: onSave) {
                    Text("Save to routine")
                        .font(.system(size: 15, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MasoColor.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onSkip) {
                    Text("Don't save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MasoColor.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MasoColor.surface)
                        .overlay(
                            Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.8)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: 行渲染

    @ViewBuilder
    private func changeRow(_ row: RoutineDiff.Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                // 名称行 — replaced 显示 旧名 → 新名; removed 整行划掉
                HStack(spacing: 6) {
                    if let oldName = row.oldName {
                        Text(oldName)
                            .font(.system(size: 14, weight: .semibold))
                            .strikethrough(true, color: MasoColor.textFaint)
                            .foregroundStyle(MasoColor.textFaint)
                            .lineLimit(1)
                            .layoutPriority(-1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    Text(row.name)
                        .font(.system(size: 14, weight: .bold))
                        .strikethrough(row.kind == .removed, color: MasoColor.textDim)
                        .foregroundStyle(row.kind == .removed ? MasoColor.textDim : MasoColor.text)
                        .lineLimit(1)
                }
                // 参数行 — 改过: 旧值划掉 → 新值 accent; 没改: 单行淡色
                if let old = row.oldSummary, old != row.summary {
                    HStack(spacing: 6) {
                        Text(old)
                            .font(.system(size: 12).monospacedDigit())
                            .strikethrough(true, color: MasoColor.textFaint)
                            .foregroundStyle(MasoColor.textFaint)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MasoColor.textFaint)
                        Text(row.summary)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(MasoColor.accent)
                    }
                } else {
                    Text(row.summary)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(MasoColor.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 状态 badge — 只给修改项, 未改的行保持干净
            if row.isChanged {
                badge(for: row)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(row.isChanged ? MasoColor.accent.opacity(row.kind == .removed ? 0 : 0.08) : Color.clear)
        .background(row.kind == .removed ? MasoColor.negative.opacity(0.07) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    row.kind == .removed
                        ? MasoColor.negative.opacity(0.4)
                        : (row.isChanged ? MasoColor.accent.opacity(0.45) : MasoColor.borderSoft),
                    lineWidth: row.isChanged ? 1 : 0.6
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(row.isChanged ? 1 : 0.55)
    }

    @ViewBuilder
    private func badge(for row: RoutineDiff.Row) -> some View {
        let (text, color): (String, Color) = {
            switch row.kind {
            case .added:     return (NSLocalizedString("Added", comment: "diff badge"), MasoColor.accent)
            case .removed:   return (NSLocalizedString("Removed", comment: "diff badge"), MasoColor.negative)
            case .replaced:  return (NSLocalizedString("Replaced", comment: "diff badge"), .orange)
            case .modified:  return (NSLocalizedString("Updated", comment: "diff badge"), MasoColor.accent)
            case .unchanged: return (NSLocalizedString("Moved", comment: "diff badge"), MasoColor.textDim)
            }
        }()
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    // MARK: Diff 计算 — 共享引擎 (跟完成流 gate 的 hasChanges 同一份逻辑)

    private var rows: [RoutineDiff.Row] {
        RoutineDiff.rows(original: originalPlan, session: sessionPlan, exById: exById)
    }
}

private struct CompletedView: View {
    @Environment(DataStore.self) private var data
    let planName: String
    let durationSeconds: Int
    let setCount: Int
    let prCount: Int
    let muscles: [MuscleGroup]
    /// 训练涉及的动作名 (顺序保留 plan.steps), 给分享卡 chip 用.
    var exerciseNames: [String] = []
    var exerciseCount: Int = 0
    /// sessionId — 用来在 DataStore 持久化照片. nil = 无法生成 id (session 状态异常).
    var sessionId: String? = nil
    /// 分享卡逐组实测明细 + maso:// 深链 payload (QR) + 总容量 + 日期 — caller (有 store 的
    /// PlanPlayerScreen) 算好传入, 让 CompletedView 保持纯 view.
    var workoutDetail: [WorkoutExerciseDetail] = []
    var importPayload: String? = nil
    var totalVolumeKg: Double = 0
    var dateLabel: String? = nil
    /// 自由训练 (临时 plan) 完成时 caller 传非 nil — 显示 "Save as plan" 按钮.
    /// 用户点了 → onSavePlan() 触发 caller 把 plan 写入 data.plans.
    /// (routine 内参数修改的保存已前移到 SaveChangesConfirmView 确认页, 不再出现在这里.)
    let onSavePlan: (() -> Void)?
    let onClose: () -> Void

    @State private var planSaved: Bool = false
    /// P2-17: 有未保存的 plan 改动时, "关闭"按钮走二次确认, 避免误触丢弃.
    @State private var confirmDiscard: Bool = false

    /// 是否存在"还没保存的 plan" (自由训练没存) — 决定 Skip 是否需要二次确认.
    private var hasUnsavedPlanChanges: Bool {
        onSavePlan != nil && !planSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // 圆 ✓
            ZStack {
                Circle().fill(MasoColor.accent).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.black)
            }
            .padding(.bottom, 28)
            // 主标题 — 固定文案"Workout Complete", 不再用 plan 名当标题
            Text("Workout Complete")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(MasoColor.text)
            // 副标题 — 这次完成的 plan 名 (淡色, 仅 plan 非空时显示)
            if !planName.isEmpty {
                Text(planName)
                    .font(.system(size: 14))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)
            }
            // 操作按钮 — 主 "Share workout" (大胶囊 accent 实色), 次 "Close" (下方文字按钮).
            // 设计意图: 训练完成时分享比直接关闭更有价值 (记录 / 社交反馈), 所以主 CTA 给分享;
            // 关闭次要, 用文字按钮形式 (无背景, 灰色) 让"跳过分享"也清晰但不抢眼.
            VStack(spacing: 12) {
                // 主 CTA — Share workout (拉起 ShareCustomizeSheet).
                // 详情卡: 逐组实测明细 + 肌肉图 + 三项数据 + maso:// 深链 QR. 两个模式渲染同一张卡,
                // 仅 .editing 时给 onTapAdd (让用户加照片), .rendering 不带占位 UI.
                ShareImageButton(
                    previewTitle: NSLocalizedString("My Workout", comment: ""),
                    defaultSections: ShareSections(workout: true),
                    initialPhoto: sessionId.flatMap { data.sessionPhoto(forSessionId: $0) },
                    shareContent: { photo, onTapAdd, mode in
                        let isEditing: Bool = { if case .editing = mode { return true }; return false }()
                        WorkoutDetailShareCard(
                            dateLabel: dateLabel,
                            planName: planName,
                            muscles: muscles,
                            detail: workoutDetail,
                            setCount: setCount,
                            totalVolumeKg: totalVolumeKg,
                            durationLabel: durationLabel,
                            qrPayload: importPayload,
                            userPhoto: photo,
                            onTapAddPhoto: isEditing ? onTapAdd : nil
                        )
                    },
                    onPersistPhoto: { image in
                        guard let id = sessionId else { return }
                        if let image {
                            data.setSessionPhoto(image, forSessionId: id)
                        } else {
                            data.removeSessionPhoto(forSessionId: id)
                        }
                    }
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .heavy))
                        Text("Share workout")
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MasoColor.accent)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }

                // 次 CTA 行 — Skip 左, Save as plan 右 (并排, 等宽).
                // 没 onSavePlan 时 Skip 单独占满全行. 文案就叫 "Skip", 无 icon.
                HStack(spacing: 10) {
                    Button(action: {
                        // P2-17: 有未保存改动 → 二次确认再丢弃; 否则直接关.
                        if hasUnsavedPlanChanges { confirmDiscard = true } else { onClose() }
                    }) {
                        Text(NSLocalizedString("Skip", comment: "completed page close button"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(MasoColor.surface)
                            .overlay(
                                Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.8)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .alert(NSLocalizedString("Discard changes?", comment: ""), isPresented: $confirmDiscard) {
                        Button(NSLocalizedString("Discard", comment: ""), role: .destructive) { onClose() }
                        Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
                    } message: {
                        Text("Your edits to this workout's exercises won't be saved to the plan. Completed sets are already recorded.")
                    }

                    if let save = onSavePlan {
                        Button(action: {
                            save()
                            withAnimation { planSaved = true }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: planSaved ? "checkmark" : "plus.square.on.square")
                                    .font(.system(size: 12, weight: .heavy))
                                Text(planSaved
                                     ? NSLocalizedString("Saved", comment: "")
                                     : NSLocalizedString("Save as plan", comment: ""))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(planSaved ? MasoColor.textDim : MasoColor.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(MasoColor.accent.opacity(planSaved ? 0.05 : 0.12))
                            .overlay(
                                Capsule().stroke(MasoColor.accent.opacity(planSaved ? 0.2 : 0.4), lineWidth: 0.8)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(planSaved)
                    }
                }
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 36)

            Spacer()
        }
        // 整屏纯黑底 — 覆盖 sheet 默认的 systemBackground (避免出现灰色 material)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Share helper data (for UnifiedShareCard)

    /// "12m 30s" / "30s" — duration label for ShareStat.
    private var durationLabel: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// 每个 anatomy 直接肌肉 → 最近一次被训练的时间.
    /// 公式跟 HistoryScreen.muscleLastTrainedMap 同义.
    private func muscleLastTrainedMap() -> [MuscleGroup: Date] {
        var map: [MuscleGroup: Date] = [:]
        for s in data.sets {
            guard let ex = data.exById[s.exerciseId] else { continue }
            let expanded = expandAnatomyMuscles(ex.muscleGroups)
            for m in expanded {
                if let prev = map[m], prev > s.performedAt { continue }
                map[m] = s.performedAt
            }
        }
        return map
    }

    /// 衰减映射 — 跟 HistoryScreen.opacityFor 同义.
    private var muscleOpacityClosure: (MuscleGroup) -> Double? {
        let lastMap = muscleLastTrainedMap()
        return { m in
            guard let last = lastMap[m] else { return nil }
            let days = Date().timeIntervalSince(last) / 86400
            if days < 1 { return 1.0 }
            if days < 2 { return 0.6 }
            if days < 3 { return 0.3 }
            return nil
        }
    }

    /// 本周训练 session 数 — 不同日历日算 1 次
    private var workoutsThisWeekCount: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let days = Set(data.sets.filter { $0.performedAt >= cutoff }.map { cal.startOfDay(for: $0.performedAt) })
        return days.count
    }

    /// 本周总组数
    private var totalSetsThisWeek: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        return data.sets.filter { $0.performedAt >= cutoff }.count
    }

    /// 本周练到的大肌群 section 数
    private var muscleSectionsHitThisWeek: Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        var sections = Set<MuscleGroup>()
        for set in data.sets where set.performedAt >= cutoff {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let s = m.section { sections.insert(s) }
            }
        }
        return sections.count
    }

    /// 连续训练天数 (相对今天)
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

    /// 用户有训练的日历日集合
    private func workoutDateSet() -> Set<Date> {
        let cal = Calendar.current
        var out: Set<Date> = []
        for s in data.sets {
            out.insert(cal.startOfDay(for: s.performedAt))
        }
        return out
    }
}

// MARK: - 训练中编辑当前 step 参数

/// 训练中编辑当前动作 — sets / reps / weight / duration.
/// 改动是 session-local: 影响当前训练的剩余 segments, 不写回 DataStore.plans
/// (用户如果想长期改, 走 Plan 编辑器). 已完成的组按 (stepId, setN) 保留绿色标记.
///
/// 字段显示策略:
///   - Sets 总是显示 (Stepper, 范围 1...30)
///   - 力量类: 显示 Reps + Weight, 隐藏 Duration
///   - 非力量 (cardio / flexibility): 显示 Duration, 隐藏 Reps + Weight
///     (除非 step 已有 reps/weight, 那就也显示给用户改)
private struct EditCurrentStepSheet: View {
    let exercise: Exercise
    let initialSets: Int
    let initialReps: Int?
    let initialWeight: Double?
    let initialDuration: Int?
    let initialSetReps: [Int?]?
    let initialSetWeights: [Double?]?
    /// #3: onSave 多带逐组数组 (setReps / setWeights). 关掉逐组时传 nil.
    let onSave: (Int, Int?, Double?, Int?, [Int?]?, [Double?]?) -> Void
    /// 可选: "替换动作" — caller 传了才显示 row. tap 后 sheet dismiss → caller 弹 ExercisePickerSheet.
    /// 单独 callback 让 caller 控制选 ex 后的逻辑 (调 store.replaceStepExercise).
    var onReplace: (() -> Void)? = nil

    // 全部用数字 state — 0 = 清空字段 (save 时映射回 nil).
    // weight step 2.5kg (健身房 plate 实际增量, 1.25kg × 2 = 2.5kg), reps step 1, duration step 5s.
    @State private var sets: Int
    @State private var reps: Int
    @State private var weight: Double
    @State private var duration: Int
    /// #3: "每组不同重量/次数" 开关 + 逐组值 (0 = 空, save 时映射 nil). 长度跟 sets 同步.
    @State private var perSetEnabled: Bool
    @State private var perSetReps: [Int]
    @State private var perSetWeights: [Double]
    /// P2-6: 用户点了 "Replace exercise" → dismiss 自己, 等真正消失 (.onDisappear) 再回调
    /// onReplace 让 parent 弹 picker. 一次性 flag 防双击.
    @State private var replaceRequested: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(
        exercise: Exercise,
        initialSets: Int,
        initialReps: Int?,
        initialWeight: Double?,
        initialDuration: Int?,
        initialSetReps: [Int?]? = nil,
        initialSetWeights: [Double?]? = nil,
        onSave: @escaping (Int, Int?, Double?, Int?, [Int?]?, [Double?]?) -> Void,
        onReplace: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        let nSets = max(1, initialSets)
        self.initialSets = nSets
        self.initialReps = initialReps
        self.initialWeight = initialWeight
        self.initialDuration = initialDuration
        self.initialSetReps = initialSetReps
        self.initialSetWeights = initialSetWeights
        self.onSave = onSave
        self.onReplace = onReplace
        self._sets = State(initialValue: nSets)
        // 没初始值就给合理默认 — reps 10 / weight 0 / duration 30. 用户自己 -/+ 调.
        let r0 = initialReps ?? 10
        let w0 = initialWeight ?? 0
        self._reps = State(initialValue: r0)
        self._weight = State(initialValue: w0)
        self._duration = State(initialValue: initialDuration ?? 30)
        // 逐组: 有任一覆盖数组 → 默认开. 逐组初值: 覆盖项优先, 否则统一值.
        let hasPerSet = (initialSetReps?.isEmpty == false) || (initialSetWeights?.isEmpty == false)
        self._perSetEnabled = State(initialValue: hasPerSet)
        self._perSetReps = State(initialValue: (0..<nSets).map { i in
            (initialSetReps?.indices.contains(i) == true ? initialSetReps![i] : nil) ?? r0
        })
        self._perSetWeights = State(initialValue: (0..<nSets).map { i in
            (initialSetWeights?.indices.contains(i) == true ? initialSetWeights![i] : nil) ?? w0
        })
    }

    /// 是否显示 Reps + Weight 字段. 力量类总显示; 非力量类只有 step 已存在这俩字段时显示.
    private var showsRepsWeight: Bool {
        exercise.category == .strength || initialReps != nil || initialWeight != nil
    }

    /// 是否显示 Duration. #3: duration 仅给"没有 reps/weight"的动作 (stretch / 计时类),
    /// 跟 reps/weight 互斥 —— 重训动作不再显示 duration.
    private var showsDuration: Bool {
        !showsRepsWeight
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 底色铺满整个 navigation 容器, 跟 Settings / MusclesPickerSheet 一致.
                // ignoresSafeArea 让 home indicator 区也是 MasoColor.background, 不露 sheet 默认浅灰底.
                MasoColor.background.ignoresSafeArea()
                Form {
                    // Sets — 始终显示. 用 Stepper 风格 — label + 大字号 value, 自带 -/+
                    Section {
                        intStepperRow(label: "Sets", value: $sets, range: 1...30)
                    }
                    .listRowBackground(MasoColor.surface)

                    if showsRepsWeight {
                        Section {
                            Toggle(isOn: $perSetEnabled.animation(.easeOut(duration: 0.2))) {
                                Text("Different per set")
                                    .foregroundStyle(MasoColor.text)
                            }
                            .tint(MasoColor.accent)
                        }
                        .listRowBackground(MasoColor.surface)

                        if perSetEnabled {
                            Section {
                                ForEach(perSetReps.indices, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        Text("Set \(i + 1)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(MasoColor.textDim)
                                            .frame(width: 44, alignment: .leading)
                                        Spacer(minLength: 0)
                                        NumStepperField(intValue: $perSetReps[i], range: 1...50, suffix: "rep", fieldWidth: 64)
                                        NumStepperField(doubleValue: $perSetWeights[i], range: 0...500, step: 2.5, suffix: "kg", decimal: true, fieldWidth: 78)
                                    }
                                }
                            } header: {
                                Text("Reps × weight per set")
                            }
                            .listRowBackground(MasoColor.surface)
                        } else {
                            Section {
                                intStepperRow(label: "Reps", value: $reps, range: 1...50)
                                weightStepperRow(label: "Weight", value: $weight, range: 0...500, step: 2.5)
                            }
                            .listRowBackground(MasoColor.surface)
                        }
                    }

                    if showsDuration {
                        Section {
                            intStepperRow(label: "Duration", value: $duration, range: 5...600, step: 5, suffix: "s")
                        }
                        .listRowBackground(MasoColor.surface)
                    }

                    // 替换动作 — 单独 section. caller 没传 onReplace 就不显示.
                    // tap → dismiss self → caller 弹 ExercisePickerSheet (异步串接, 让 transition 干净).
                    if onReplace != nil {
                        Section {
                            Button(action: {
                                // P2-6: 一次性 guard 防双击重复触发; 用 onDisappear 串接 (sheet 真正
                                // 收完才弹 picker), 不再靠固定延迟猜 dismiss 时机, 慢设备也稳.
                                guard !replaceRequested else { return }
                                replaceRequested = true
                                Haptics.tap()
                                dismiss()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(MasoColor.accent)
                                    Text("Replace exercise")
                                        .foregroundStyle(MasoColor.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(MasoColor.textFaint)
                                }
                            }
                        }
                        .listRowBackground(MasoColor.surface)
                    }

                    // 提示: 改动只影响本次训练
                    Section {
                        Text("Changes apply to this session only. To save permanently, edit the plan.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .listRowBackground(MasoColor.surface)
                }
                // Form 自带 systemGroupedBackground 浅灰底 — 隐掉, 走我们 ZStack 的 MasoColor.background
                .scrollContentBackground(.hidden)
                // sets 改变 → 同步逐组数组长度 (补/裁), 防 ForEach 越界 + 让新组继承上一组的值.
                .onChange(of: sets) { _, n in resizePerSet(to: max(1, n)) }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            // 顶部 nav bar 同色, 否则会有一道 system tint 横条
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // 0 = 清空字段 (用户用 - 减到 0 = 不想要这个字段了, save 成 nil).
                        // duration 仅在"非 reps/weight 动作"时存 (showsDuration) — 重训动作强制 nil.
                        let d: Int? = (showsDuration && duration > 0) ? duration : nil
                        if perSetEnabled && showsRepsWeight {
                            let n = max(1, sets)
                            let setR: [Int?] = (0..<n).map { i in
                                (i < perSetReps.count && perSetReps[i] > 0) ? perSetReps[i] : nil
                            }
                            let setW: [Double?] = (0..<n).map { i in
                                (i < perSetWeights.count && perSetWeights[i] > 0) ? perSetWeights[i] : nil
                            }
                            // 统一值用第一组当 fallback (expandPlan 在数组缺项时回退到它).
                            let r0 = perSetReps.first.flatMap { $0 > 0 ? $0 : nil }
                            let w0 = perSetWeights.first.flatMap { $0 > 0 ? $0 : nil }
                            onSave(n, r0, w0, d, setR, setW)
                        } else {
                            let r: Int? = reps > 0 ? reps : nil
                            let w: Double? = weight > 0 ? weight : nil
                            onSave(sets, r, w, d, nil, nil)
                        }
                        Haptics.tap()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        // sheet 容器底色 (含 home indicator 区) — iOS 16.4+
        .presentationBackground(MasoColor.background)
        // P2-6: sheet 真正消失后再触发 replace — 比固定 0.32s 延迟稳, 慢设备 / reduce-motion 都 OK.
        .onDisappear {
            if replaceRequested { onReplace?() }
        }
    }

    /// 把逐组数组补/裁到 n 组 — 补的项继承末组(或统一)值, 多的截掉. sets 变化时调.
    private func resizePerSet(to n: Int) {
        while perSetReps.count < n { perSetReps.append(perSetReps.last ?? reps) }
        while perSetWeights.count < n { perSetWeights.append(perSetWeights.last ?? weight) }
        if perSetReps.count > n { perSetReps.removeLast(perSetReps.count - n) }
        if perSetWeights.count > n { perSetWeights.removeLast(perSetWeights.count - n) }
    }

    /// Int 字段行 — 左 label, 右统一步进控件 NumStepperField (圆形 −/+ + 可输入数字框),
    /// 跟训练中"动作详情页" / Settings 同款. 全 app 数字步进控件统一走这一种.
    @ViewBuilder
    private func intStepperRow(label: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, suffix: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(MasoColor.text)
            Spacer()
            NumStepperField(intValue: value, range: range, step: step, suffix: suffix)
        }
    }

    /// Double 字段行 (重量) — 同 intStepperRow, 走 NumStepperField. step 2.5 = plate 增量 (1.25kg×2).
    @ViewBuilder
    private func weightStepperRow(label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(MasoColor.text)
            Spacer()
            NumStepperField(doubleValue: value, range: range, step: step, suffix: "kg", decimal: true)
        }
    }
}
