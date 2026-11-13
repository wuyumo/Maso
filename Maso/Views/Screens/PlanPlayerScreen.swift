import SwiftUI
import StoreKit

private struct PlayerLayoutBoundsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, last in last })
    }
}

// Training player: one media stage, a top queue, and fixed transport controls.
struct PlanPlayerScreen: View {
    @Environment(TrainingSessionStore.self) private var store
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var playerScenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Apple Music 式下拉关闭 — 训练中拖动顶部 handle, 整屏跟手下移; 过阈值松手 → 关 (最小化回 mini-bar,
    /// session 继续跑). fullScreenCover 没有系统 grabber, 这是自定义的关闭手势.
    @State private var heartAssistUndo: TrainingSessionStore.PlaybackUndo?
    @State private var heartAssistUndoSession: String?
    @State private var heartAssistUndoWasRest = false
    @State private var heartAssistSuppressedUntil = Date.distantPast

    @State private var dragDownOffset: CGFloat = 0
    @State private var playerSafeArea = EdgeInsets()
    private var youtubeExerciseID: String? { store.youtubePlayback.exerciseID }

    /// 是否处于"训练中"段 (非空 / 未完成 / 有当前 segment) — 只有这态才显示下拉 handle + 允许下拉关闭.
    private var isActiveTraining: Bool {
        guard let s = store.session, !store.segments.isEmpty else { return false }
        return s.completed != true && store.currentSegment != nil
    }

    private var topSafeArea: CGFloat { playerSafeArea.top }

    /// 内容后面那层全屏黑背板的不透明度 — 随下拉进度平滑淡出 (smoothstep 缓动): 内容整体下滑、
    /// 顶部露出缝隙, 缝隙里的背板逐步变透明 → 后面的 app (标签页) 渐渐透出 (Apple Music 式收起).
    /// 180pt 内从 1 → 0; 松手未关时 dragDownOffset 弹回 0, opacity 随之回 1 (重新盖住 app).
    private var backdropOpacity: Double {
        guard dragDownOffset > 0 else { return 1 }
        let p = min(1, Double(dragDownOffset) / 180)
        let eased = p * p * (3 - 2 * p)   // smoothstep: 平滑 S 曲线
        return 1 - eased
    }

    /// 下拉时 sheet 顶部圆角 — 0 (贴顶, 平时方角保持 full-bleed) → 40 (脱离顶部, Apple Music 式圆角).
    /// 前 60pt 内 ramp 到位然后保持; 松手未关时随 dragDownOffset 弹回 0.
    private var dragCornerRadius: CGFloat {
        guard isActiveTraining, dragDownOffset > 0 else { return 0 }
        return 40 * min(1, dragDownOffset / 60)
    }

    /// Apple Music 式下拉关闭手势 — 复用在 handle + 整个动作图区域: 下拉整屏跟手, 过阈值松手 → 关.
    /// ⚠️ 必须用 .global 坐标系: body 被 .offset(dragDownOffset) 跟手下移, 若手势用默认 .local,
    ///    view 一移局部坐标系也移、translation 被自身位移抵消 → 每帧在 0↔offset 间振荡 → 整屏闪动.
    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in dragDownOffset = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 110 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { dragDownOffset = 0 }
                }
            }
    }

    @ScaledMetric(relativeTo: .body) private var playerInfoHeight: CGFloat = 260
    @ScaledMetric(relativeTo: .title2) private var playerTitleHeight: CGFloat = 44
    @State private var playlistExpanded = false
    @State private var restEditorPresented = false
    @State private var editingRestSeconds = 90
    @State private var editingSwitchSeconds = 120
    @State private var confirmRestDefaults = false
    @State private var endConfirmOpen: Bool = false
    /// 完成流: "保存修改到 routine?" 确认页已做完决定 (保存或跳过) → 进分享卡完成页.
    /// 训练完成且 canSaveChangesToPlan 时, 这个标志 false → 先渲确认页.
    @State private var planSaveDecisionMade: Bool = false
    @State private var openWorkoutSaveCompleted = false
    @State private var sessionReportDidEnd = false
    /// Playlist 右侧 i 打开详情；头像和名称始终选择动作。
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 step 的二次确认 — 跟 PlanDetailSheet 同模式, 存待删 stepId, alert 弹.
    @State private var pendingDeleteStepId: String? = nil
    /// 右滑编辑 step — 存 stepId 拉 EditCurrentStepSheet, 用 store.updateStep 改 session-local.
    @State private var editingStepId: String? = nil
    @State private var replacementAfterEdit: String? = nil
    /// 替换动作 — Edit sheet 里点 "Replace exercise" 把目标 stepId 存这, 然后弹 ExercisePickerSheet.
    /// 参数页先关闭，再由 onDismiss 打开选择页；选择完成只返回训练。
    @State private var replacingStepId: String? = nil
    @State private var replacementUsesAllMuscles = false
    @State private var pendingReplacement: (stepId: String, exerciseId: String)? = nil
    /// "+ Add exercise" footer (在 playlist 末尾) → 弹 ExercisePickerSheet, 选完调 store.appendStep.
    @State private var addStepPickerOpen: Bool = false
    /// P0#5-①: 休息屏"刚才: 8 × 55 kg · 调整"入口 — 存正在修正的那条 SetRecord, 弹 AdjustLastSetSheet.
    @State private var adjustingRecord: SetRecord? = nil
    // ("已记录 · 撤销" toast 已整体移除 — owner 反馈气泡干扰; 误记补救走休息屏"刚才 · Adjust".)

    /// sheet(item:) 需要 Identifiable, String 自身不 conform — 包一层.
    private struct StepIdentifier: Identifiable, Hashable {
        let id: String
    }

    // The footer is outside the changing stage so queue/rest changes cannot move it.
    static let handleClearance: CGFloat = 21

    var body: some View {
        GeometryReader { geometry in
            playerContent
                .onChange(of: geometry.safeAreaInsets, initial: true) { _, insets in
                    playerSafeArea = insets
                }
        }
        .preferredColorScheme(store.session?.completed == true ? .dark : nil)
        .toolbarColorScheme(store.session?.completed == true ? .dark : nil, for: .navigationBar)
    }

    private var playerContent: some View {
        ZStack {
            // 下拉收起时露出的"sheet 之外"黑背板 — 不随内容下滑, 随下拉进度平滑淡出,
            // 让后面的 app (标签页) 从顶部缝隙逐步透出. 需配合 RootView 的 .presentationBackground(.clear).
            if isActiveTraining {
                MasoColor.background
                    .opacity(backdropOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

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
                .background(MasoColor.background.ignoresSafeArea())
            } else if store.session?.completed == true && store.isOpenWorkout && !openWorkoutSaveCompleted {
                OpenWorkoutCompletionView(
                    durationMinutes: completedDurationSeconds / 60,
                    setCount: store.session?.completedSets.count ?? 0,
                    exerciseCount: completedExerciseCount,
                    onDone: { name in
                        if let name { saveOpenWorkout(name: name) }
                        openWorkoutSaveCompleted = true
                        planSaveDecisionMade = true
                    }
                )
            } else if store.awaitingExercise {
                VStack(spacing: 20) {
                    Text("What would you like to train next?").font(.title2.bold())
                    Text(openWorkoutSummary).font(.subheadline).foregroundStyle(MasoColor.textDim)
                    Button("Add next exercise") { addStepPickerOpen = true }
                        .nativeGlassProminentButtonStyle()
                        .controlSize(.large).tint(MasoColor.accent).foregroundStyle(.black)
                        .accessibilityIdentifier("open-workout.add-next")
                    Button("End this workout") { store.finishEarly() }
                        .nativeGlassButtonStyle()
                        .controlSize(.large).tint(MasoColor.text)
                        .accessibilityIdentifier("open-workout.end")
                    Button("Minimize workout") { dismiss() }
                        .nativeGlassButtonStyle()
                        .controlSize(.large).tint(MasoColor.text)
                        .accessibilityIdentifier("open-workout.minimize")
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MasoColor.background)
                .onAppear { addStepPickerOpen = true }
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
                CompletedView(
                    planName: store.plan?.name ?? "",
                    durationSeconds: completedDurationSeconds,
                    sessionRecords: completedSessionSets,
                    onSavePlan: canSaveCurrentPlan && !openWorkoutSaveCompleted ? {
                        saveCurrentPlanToLibrary()
                        openWorkoutSaveCompleted = true
                    } : nil,
                    onClose: { endFinishedSessionOnce() }
                )
                .transition(.opacity)
                }
            } else if let seg = store.currentSegment {
                activePlayer(seg: seg)

            }
        }
        // Keep the media stage and fixed transport within the same full-screen bounds.
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(MasoColor.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .overlay {
            if isActiveTraining && store.heartRate.warningPending && store.heartRate.hasEscalatedWarning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if store.heartRate.freshBPM(at: context.date) != nil {
                        Color.red.opacity(0.12).ignoresSafeArea().allowsHitTesting(false)
                            .accessibilityIdentifier("workout.heart.escalated-background")
                    }
                }
            }
        }
        // 先把整屏内容 (图 + 上/下渐变 + controls) 压成单层再裁剪 — 否则回弹时 clip 每帧重栅格化,
        // 会把 controls 那层 .background 渐变丢一帧 → 闪现图底原色. compositingGroup 把渐变烘进同层.
        .overlayPreferenceValue(PlayerLayoutBoundsKey.self) { anchors in
            GeometryReader { geometry in
                if isActiveTraining && (store.heartRate.warningPending || (!inlineYouTubeActive && !playlistExpanded)),
                   let media = anchors["media"], let heading = anchors["heading"] {
                    let bottom = max(0, min(geometry[media].maxY, geometry[heading].minY))
                    WorkoutHeartRateButton()
                        .environment(\.layoutDirection, layoutDirection)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, MasoMetrics.cardPadding).padding(.bottom, 12)
                        .frame(width: geometry.size.width, height: bottom, alignment: .bottomTrailing)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = heartAssistUndo, heartAssistUndoSession == store.workoutSessionID,
               store.session?.playbackUndo?.last == undo, store.canUndoPlayback {
                HStack(spacing: 12) {
                    Text(heartAssistUndoWasRest ? LocalizedStringKey("Rest skipped automatically") : LocalizedStringKey("Set logged automatically"))
                        .font(.footnote.weight(.semibold))
                    Button("Undo") {
                        if store.workoutSessionID == heartAssistUndoSession, store.session?.playbackUndo?.last == undo {
                            _ = store.undoPlayback { data.removeSetRecord(id: $0) }
                            heartAssistSuppressedUntil = Date().addingTimeInterval(60)
                        }
                        heartAssistUndo = nil
                    }.font(.footnote.weight(.bold)).foregroundStyle(MasoColor.accent)
                }.padding(.horizontal, 16).padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, bottomSafeArea + 12)
                    .accessibilityIdentifier("workout.heart.assist.undo")
            }
        }
        .task(id: heartAssistUndo) {
            guard let undo = heartAssistUndo else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled && heartAssistUndo == undo { heartAssistUndo = nil }
        }
        .compositingGroup()
        // 下拉脱离顶部时给 sheet 顶部上圆角 (Apple Music 式). 始终应用同一形状 (无结构切换) →
        // 不跳变、手势不被取消; 形状底边延伸出屏 → 永不裁底部 home indicator.
        .clipShape(TopRoundedSheetShape(radius: dragCornerRadius))
        // Apple Music 式: 整屏跟手下移 (拖顶部 handle). 完成/空态不参与 (各有自己的关闭按钮).
        .offset(y: isActiveTraining ? dragDownOffset : 0)
        // 顶部 Drag Handle — 落在 Dynamic Island 下方, 居中. 拖它下拉 → 关 (最小化回 mini-bar).
        .overlay(alignment: .top) {
            if isActiveTraining {
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 40, height: 5)
                    .accessibilityIdentifier("workout.handle")
                    .padding(.vertical, 10)
                    .padding(.horizontal, 44)
                    .contentShape(Rectangle())
                    .padding(.top, topSafeArea - 4)     // 比之前下移一点, 别太贴岛
                    .offset(y: dragDownOffset)          // handle 跟着整屏一起下移
                    .gesture(dismissDragGesture)
                    .ignoresSafeArea(edges: .top)
            }
        }
        // Playlist 右侧 i → 动作详情。
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
            .presentationDragIndicator(.visible)
        }
        // P0#5-①: 修正刚落库那组 — 小 sheet 双 stepper 调 reps/weight (无重量动作调 reps/时长),
        // 写回 DataStore 里那条 SetRecord. 不动 plan/segments, 只改"已经练完的事实".
        .sheet(item: $adjustingRecord) { rec in
            AdjustLastSetSheet(record: rec) { newReps, newWeight, newDuration, confirmedSixRM in
                data.updateSetRecord(id: rec.id, reps: newReps, weight: newWeight, duration: newDuration,
                                     sixRMConfirmed: confirmedSixRM)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        // 右滑 Edit → 弹 EditAnyStepSheet (session-local 改 sets/reps/weight/duration).
        // Binding<String?> identity 用 stepId, 通过 plan.steps 找具体 step 实例.
        .sheet(item: Binding(
            get: { editingStepId.map { StepIdentifier(id: $0) } },
            set: { editingStepId = $0?.id }
        ), onDismiss: {
            if let step = replacementAfterEdit {
                replacementAfterEdit = nil
                DispatchQueue.main.async { replacingStepId = step }
            }
        }) { idWrapper in
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
                    initialParameterStep: step,
                    onConfirmParameters: { store.confirmParameters(stepId: step.id, fields: $0) },
                    onSave: { newSets, newReps, newWeight, newDuration, newSetReps, newSetWeights in
                        if newWeight != step.weight || newSetWeights != step.setWeights {
                            data.rememberWeight(newWeight ?? newSetWeights?.compactMap { $0 }.first, for: ex)
                        }
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
                        // R3: 同步开 → 训练中改的参数即时传播到所有含该动作的 routine.
                        propagateParamsIfSyncing(stepId: idWrapper.id)
                    },
                    onReplace: { replacementAfterEdit = idWrapper.id },
                    syncsGlobally: data.settings.globalExerciseParamSyncEnabled
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        // 替换动作 picker — 训练中任何 Edit sheet 里点 "Replace exercise" 走这里.
        // 进 sheet 后选完一个 exercise → store.replaceStepExercise → 自动 mark planParamsDirty,
        // 训练完成时会先进 SaveChangesConfirmView 确认页, 让用户决定是否把替换持久化到 plan.
        .sheet(item: Binding(
            get: { replacingStepId.map { StepIdentifier(id: $0) } },
            set: { replacingStepId = $0?.id }
        ), onDismiss: {
            defer { replacementUsesAllMuscles = false }
            guard let replacement = pendingReplacement else { return }
            pendingReplacement = nil
            if let currentID = store.plan?.steps.first(where: { $0.id == replacement.stepId })?.exerciseId {
                data.rememberExplicitVariantChoice(from: currentID, to: replacement.exerciseId)
            }
            store.replaceStepExercise(replacement.stepId, newExerciseId: replacement.exerciseId, suggestedStep: data.exById[replacement.exerciseId].map { data.makeSeededStep(for: $0, stepId: replacement.stepId) },
                                      exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                                      defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds)
        }) { idWrapper in
            ExercisePickerSheet(onPick: { newEx in
                guard pendingReplacement == nil else { return }
                pendingReplacement = (idWrapper.id, newEx.id)
                replacingStepId = nil
            },
            directPick: true,  // J4: 替换 = 选了就换, 不先弹详情
            // 替换流程: 预选原动作的部位 (动作 + 器械留空), 落在"换个练同部位的动作".
            initialMuscle: {
                guard !replacementUsesAllMuscles else { return nil }
                guard let exId = store.plan?.steps.first(where: { $0.id == idWrapper.id })?.exerciseId,
                      let ex = data.exById[exId] else { return nil }
                return ex.primaryMuscles.first?.section
            }(),
            replacingExerciseId: replacementUsesAllMuscles ? nil : store.plan?.steps.first(where: { $0.id == idWrapper.id })?.exerciseId)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // "+ Add exercise" — playlist 末尾点了之后选动作, 多选勾选 (跟 Free Workout 一致),
        // 底部 "Add (N)" 一并 appendStep 到末尾.
        .sheet(isPresented: $addStepPickerOpen) {
            if store.isOpenWorkout {
                ExercisePickerSheet(
                    onPick: { ex in
                        store.appendStep(exercise: ex, settings: data.settings, exById: data.exById,
                            defaultRest: data.settings.defaultRestSeconds,
                            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds,
                            suggestedStep: data.makeSeededStep(for: ex, stepId: UUID().uuidString))
                        addStepPickerOpen = false
                    },
                    directPick: true,
                    pickerTitle: "What would you like to train next?",
                    onFinishWorkout: {
                        addStepPickerOpen = false
                        store.finishEarly()
                    },
                    workoutSummary: openWorkoutSummary,
                    onPickConfigured: { ex, step in
                        store.appendStep(exercise: ex, settings: data.settings, exById: data.exById,
                            defaultRest: data.settings.defaultRestSeconds,
                            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds,
                            suggestedStep: step)
                        if let id = store.plan?.steps.last?.id {
                            store.updateStep(id, sets: step.sets, reps: step.reps, weight: step.weight,
                                duration: step.duration, exById: data.exById,
                                defaultRest: data.settings.defaultRestSeconds,
                                defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds)
                        }
                        addStepPickerOpen = false
                    }
                )
                .presentationDetents([.large])
            } else {
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
                            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds,
                            suggestedStep: data.makeSeededStep(for: ex, stepId: UUID().uuidString)
                        )
                    }
                    addStepPickerOpen = false
                },
                startTitle: NSLocalizedString("Add", comment: "add selected exercises CTA")
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            }
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
                        defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds,
                        removeRecords: { exId, planId, since, count in
                            data.removeRecords(exerciseId: exId, planId: planId, since: since, count: count)
                        }
                    )
                }
                pendingDeleteStepId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteStepId = nil }
        } message: {
            Text("This only removes it from the current workout. Save changes at the end to update the plan.")
        }
        .alert("End this workout?", isPresented: $endConfirmOpen) {
            // P1#13: 打过勾的场次, 提前收工默认走"完成流" — finishEarly() 把 session 标 completed,
            // 本 view 原地切到正常完成页 (真实统计/PR/分享; dirty 时完成流自带"保存修改?"确认页,
            // 覆盖了旧 Save 分支). "放弃"降级为破坏性次按钮. 埋点: finishEarly 内部 trackFinish("early").
            // 零完成组 (误开训练想全身而退) → 维持原分支.
            if store.session?.completedSets.isEmpty == false {
                Button("Finish & end") {
                    store.finishEarly()   // 不 dismiss — completed=true 让本 view 切完成流
                }
                Button("Discard workout", role: .destructive) {
                    store.discard { data.discardWorkout($0, recordIDs: $1) }
                    dismiss()
                }
            } else if canSaveChangesToPlan {
                // 零完成组但改过参数 — 完成流走不到 (没有可展示的成果), 保留"保存并结束"通道.
                Button("Save changes & end") {
                    saveChangesToCurrentPlan()
                    store.endedExplicitly = true
                    store.end()
                    dismiss()
                }
                Button("End without saving", role: .destructive) {
                    store.discard { data.discardWorkout($0, recordIDs: $1) }
                    dismiss()
                }
            } else {
                Button("End", role: .destructive) {
                    store.discard { data.discardWorkout($0, recordIDs: $1) }
                    dismiss()
                }
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            // 提示文案 — 三分支各说各的后果
            if store.session?.completedSets.isEmpty == false {
                Text("Finish saves this workout. Discard removes it from history.")
            } else if canSaveChangesToPlan {
                Text("You changed sets, reps, weight, or order during this workout. Save the changes back to the plan?")
            } else {
                Text("This workout won’t be saved.")
            }
        }
        // 新一次训练 (completed 回到 false / session 换新) → 重置确认页决定标志,
        // 否则上一场做过的决定会让下一场 dirty 完成直接跳过确认页.
        .onChange(of: data.sets) { _, _ in store.refreshLoadSuggestions(using: data) }
        .onChange(of: store.plan, initial: true) { _, _ in store.refreshLoadSuggestions(using: data) }
        .onChange(of: store.session?.completed == true) { _, isCompleted in
            if !isCompleted { planSaveDecisionMade = false }
        }
        .sheet(isPresented: $restEditorPresented) {
            AppNavigationStack {
                Form {
                    Stepper(value: $editingRestSeconds, in: 15...300, step: 15) {
                        LabeledContent("Set rest", value: Duration.seconds(editingRestSeconds).formatted(.time(pattern: .minuteSecond)))
                    }.accessibilityIdentifier("workout.rest.duration")
                    Stepper(value: $editingSwitchSeconds, in: 0...600, step: 15) {
                        LabeledContent("Exercise rest", value: Duration.seconds(editingSwitchSeconds).formatted(.time(pattern: .minuteSecond)))
                    }.accessibilityIdentifier("workout.rest.switching")
                }
                .navigationTitle("Rest").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { restEditorPresented = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { confirmRestDefaults = true }
                            .accessibilityIdentifier("workout.rest.save")
                    }
                }
                .alert("Save rest settings?", isPresented: $confirmRestDefaults) {
                    Button("Save") {
                        data.settings.defaultRestSeconds = editingRestSeconds
                        data.settings.defaultBetweenExerciseRestSeconds = editingSwitchSeconds
                        data.save()
                        store.applyRestPreferences(setRest: editingRestSeconds, switchingRest: editingSwitchSeconds, exById: data.exById)
                        restEditorPresented = false
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Save to Training Preferences and apply to all workouts?")
                }
            }.presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .onChange(of: backgroundExercise?.id) { _, _ in store.youtubePlayback.stop() }
        .onChange(of: playerScenePhase) { _, phase in
            if phase == .background { store.youtubePlayback.enteredBackground() }
        }
        // SessionTickerView 移到了 RootView 顶层 — sheet 关掉后 MiniBar 还得 tick.
        }   // ZStack (背板 + 内容)
        // Give the player itself full-screen bounds before its draggable content is clipped.
        // Ignoring only the inner VStack can leave the status-bar region on the black backdrop.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private func activePlayer(seg: Segment) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let headerTop = topSafeArea + Self.handleClearance + 8
                let infoHeight = min(playerInfoHeight, 300)
                let infoTop = max(headerTop, geo.size.height - infoHeight)
                // The media stage ends at the bottom of the title row, including that row.
                // Match PlayerExerciseInfoLayout's centered title / spacing / parameter slots.
                let titleBottom = infoTop + (infoHeight - (playerTitleHeight + PlayerExerciseInfoMetrics.spacing + PlayerExerciseInfoMetrics.parameterHeight)) / 2 + playerTitleHeight
                let mediaAreaHeight = max(0, min(geo.size.height, titleBottom))
                // Wide or short windows must keep the square inside the available stage.
                let mediaSide = min(geo.size.width, mediaAreaHeight)
                let mediaTop = (mediaAreaHeight - mediaSide) / 2
                // Both layers reach the plain UI background at the title's top edge.
                let titleTop = max(0, titleBottom - playerTitleHeight)
                let backdropHeight = min(geo.size.height, titleTop)
                let fadeEnd = max(0, min(1, (titleTop - mediaTop) / max(1, mediaSide)))
                let fadeStart = min(0.70, fadeEnd * 0.70)
                let topFadeEnd = min(0.18, fadeStart)
                // Wide or short windows keep the square stage narrower than the
                // screen; soften those side edges into the blurred backdrop.
                let needsSideFade = (geo.size.width - mediaSide) > 1
                let sideFadeEnd: CGFloat = 0.18
                ZStack(alignment: .topLeading) {
                    trainingMediaBackdrop
                        .frame(width: geo.size.width, height: backdropHeight)
                        .clipped()
                        .mask {
                            LinearGradient(stops: [.init(color: .white, location: 0),
                                                   .init(color: .white, location: 0.55),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .opacity(playlistExpanded || inlineYouTubeActive ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    backgroundLayer
                        .frame(width: mediaSide, height: mediaSide)
                        .anchorPreference(key: PlayerLayoutBoundsKey.self, value: .bounds) { ["media": $0] }
                        // Fade the top and bottom gradually into the blurred extension.
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0),
                                                   .init(color: .white.opacity(0.45), location: min(0.07, topFadeEnd)),
                                                   .init(color: .white, location: topFadeEnd),
                                                   .init(color: .white, location: fadeStart),
                                                   .init(color: .clear, location: fadeEnd),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .mask {
                            if needsSideFade {
                                LinearGradient(stops: [.init(color: .clear, location: 0),
                                                       .init(color: .white.opacity(0.45), location: sideFadeEnd * 0.4),
                                                       .init(color: .white, location: sideFadeEnd),
                                                       .init(color: .white, location: 1 - sideFadeEnd),
                                                       .init(color: .white.opacity(0.45), location: 1 - sideFadeEnd * 0.4),
                                                       .init(color: .clear, location: 1)],
                                               startPoint: .leading, endPoint: .trailing)
                            } else {
                                Color.white
                            }
                        }
                        .position(x: geo.size.width / 2, y: mediaTop + mediaSide / 2)
                        .opacity(playlistExpanded || inlineYouTubeActive ? 0 : 1)
                        .accessibilityHidden(playlistExpanded || inlineYouTubeActive)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("workout.media.square")

                    if !playlistExpanded {
                        Color.clear.contentShape(Rectangle())
                            .gesture(dismissDragGesture)
                    }
                    VStack(spacing: 0) {
                        if playlistExpanded {
                            // Same shared geometry, with no hidden buttons or titles in the AX tree.
                            PlayerExerciseInfoLayout(compact: false) {
                                Color.clear
                            } status: {
                                Color.clear
                            } parameters: {
                                Color.clear
                            }
                        } else if seg.isRest {
                            restNextExerciseHint(seg: seg)
                        } else {
                            infoSection(seg: seg)
                        }
                    }
                    .frame(width: geo.size.width, height: infoHeight)
                    .offset(y: max(headerTop, geo.size.height - infoHeight))
                    // Preserve parameter anchors so the overlaid progress never changes position.
                    .opacity(playlistExpanded ? 0 : 1)
                    .allowsHitTesting(!playlistExpanded)
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(playlistExpanded)

                    if seg.isRest && !playlistExpanded && !inlineYouTubeActive {
                        let availableHeight = max(0, geo.size.height - headerTop - infoHeight)
                        restCountdownRing(seg: seg, available: CGSize(width: geo.size.width, height: availableHeight))
                            .frame(width: geo.size.width, height: availableHeight)
                            .offset(y: headerTop)
                    }


                }
                .clipped()
            }
            VStack(spacing: 0) {
                Color.clear.frame(height: 26).allowsHitTesting(false)
                controlsBar(seg: seg)
                    .anchorPreference(key: PlayerLayoutBoundsKey.self, value: .bounds) { ["controls": $0] }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workout.controls")
                PlayerTransportRow {
                    Group {
                        if let exercise = backgroundExercise,
                           ExerciseMediaPolicy.youtubeID(exercise.videoURL) != nil,
                           let url = exercise.videoURL {
                            Button {
                                Haptics.tap()
                                store.noteActivity()
                                if inlineYouTubeActive { store.youtubePlayback.stop() }
                                else { store.youtubePlayback.select(exercise: exercise) }
                                playlistExpanded = false
                            } label: {
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(inlineYouTubeActive ? MasoColor.accent : MasoColor.textDim)
                                    .frame(width: 44, height: 44)
                                    .applyIf(inlineYouTubeActive) {
                                        $0.glassCircleButtonBackground(fallback: MasoColor.surfaceHi)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Watch tutorial")
                            .accessibilityAddTraits(inlineYouTubeActive ? .isSelected : [])
                            .accessibilityIdentifier("workout.youtube")

                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    }
                } center: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Duration.seconds(max(0, Int(context.date.timeIntervalSince(store.session?.startedAt ?? context.date)))), format: .time(pattern: .minuteSecond))
                            .foregroundStyle(MasoColor.textDim)
                            .font(.caption.monospacedDigit())
                    }
                    .frame(height: 44)
                    .accessibilityIdentifier("workout.elapsed")
                } trailing: {
                    Button {
                        Haptics.tap()
                        store.noteActivity()
                        store.youtubePlayback.stop()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88)) {
                            playlistExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(playlistExpanded ? MasoColor.accent : MasoColor.textDim)
                            .frame(width: 44, height: 44)
                            .applyIf(playlistExpanded) { $0.glassCircleButtonBackground(fallback: MasoColor.surfaceHi) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("This workout")
                    .accessibilityAddTraits(playlistExpanded ? .isSelected : [])
                    .accessibilityIdentifier("workout.playlist.toggle")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, max(12, bottomSafeArea) + 20)
            .background(MasoColor.background)
        }
        .overlayPreferenceValue(PlayerLayoutBoundsKey.self) { anchors in
            GeometryReader { geometry in
                if inlineYouTubeActive, !playlistExpanded,
                   let heading = anchors["heading"],
                   let exercise = backgroundExercise, let url = exercise.videoURL,
                   let videoID = ExerciseMediaPolicy.youtubeID(url) {
                    // Capsule ends at safe-area top + (-4 + 10 + 5), before its hit padding.
                    let handleBottom = topSafeArea + 11
                    let titleTop = geometry[heading].minY
                    let availableHeight = max(0, titleTop - handleBottom)
                    PlayerInlineYouTubeView(videoID: videoID, sourceURL: url, playback: store.youtubePlayback)
                        .id(exercise.id)
                        .frame(width: geometry.size.width,
                               height: min(availableHeight, max(200, geometry.size.width * 9 / 16)))
                        .position(x: geometry.size.width / 2, y: (handleBottom + titleTop) / 2)
                }
                // The progress/media overlay spans the stage on regular-width
                // windows. Put the label-only Rest hit target in that same layer.
                if let label = anchors["restLabel"], !playlistExpanded, !inlineYouTubeActive {
                    let bounds = geometry[label]
                    Button {
                        editingRestSeconds = data.settings.defaultRestSeconds
                        editingSwitchSeconds = data.settings.defaultBetweenExerciseRestSeconds
                        restEditorPresented = true
                    } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
                    .accessibilityLabel("Edit rest time")
                    .accessibilityIdentifier("workout.rest.edit")
                }
                if let controls = anchors["controls"] {
                    let controlsTop = geometry[controls].minY
                    let center = anchors["parameters"].map { (geometry[$0].maxY + controlsTop) / 2 } ?? (controlsTop - 32)
                    let parameterBounds = anchors["parameters"].map { geometry[$0] }
                    if playlistExpanded {
                        let listTop = topSafeArea + Self.handleClearance + 8
                        let listBottom = center - 28
                        playlistContent
                            .frame(width: geometry.size.width, height: max(0, listBottom - listTop), alignment: .top)
                            .clipped()
                            .position(x: geometry.size.width / 2, y: (listTop + max(listTop, listBottom)) / 2)
                    }
                    exerciseProgress
                        .frame(width: parameterBounds?.width ?? max(0, geometry.size.width - 2 * MasoMetrics.cardPadding), height: 44)
                        .position(x: parameterBounds?.midX ?? geometry.size.width / 2, y: center)
                }
            }
            .zIndex(20)
        }
    }

    /// Equal-width segments follow action occurrences, never muscle or exercise IDs.
    /// Fill only actual completed sets, so skipping ahead cannot claim completion.
    /// Long-press drag reorders those same plan steps; a tap still jumps.
    private var exerciseProgress: some View {
        let planSteps = store.plan?.steps ?? []
        let visible: [(planIndex: Int, step: PlanStep)] = planSteps.enumerated().compactMap { index, step in
            store.segments.contains { $0.isExercise && $0.stepId == step.id } ? (planIndex: index, step: step) : nil
        }
        let completed = store.session?.completedSets ?? []
        let pending = store.nextUnfinishedSegment()
        return WorkoutExerciseProgressBar(
            steps: visible,
            segments: store.segments,
            completed: completed,
            pendingStepId: pending?.stepId,
            pendingSegmentId: pending?.id,
            currentIsExercise: store.currentSegment?.isExercise == true,
            isPlaying: store.session?.playing == true,
            title: { data.exById[$0.exerciseId]?.displayName ?? $0.exerciseId },
            onJump: { stepId in
                Haptics.tap()
                _ = store.jumpToFirstUnfinishedStep(stepId: stepId)
            },
            onReorder: { source, destination in
                reorderWorkoutSteps(from: source, to: destination)
                Haptics.tap()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workout")
        .accessibilityValue(Text("\(completed.count)/\(store.segments.filter(\.isExercise).count)"))
        .accessibilityIdentifier("workout.progress")
    }

    private var inlineYouTubeActive: Bool {
        youtubeExerciseID != nil && youtubeExerciseID == backgroundExercise?.id
    }

    /// Current and upcoming exercises use one media path; rest only adds a readability scrim.
    private var backgroundExercise: Exercise? {
        guard let segment = store.currentSegment else { return nil }
        if case .exercise(let exercise, _, _, _, _, _, _) = segment.kind { return exercise }
        return nextExerciseSeg()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let exercise = backgroundExercise {
            FullBleedExerciseImage(exercise: exercise, playbackEnabled: !inlineYouTubeActive && store.currentSegment?.isRest != true, contentMode: .fit)
                .overlay {
                    if store.currentSegment?.isRest == true {
                        Color.black.opacity(0.55)
                    }
                }
        } else {
            MasoColor.background
        }
    }

    /// A static, softly blurred poster extends the media colors behind the header.
    /// The live media itself remains a single, uncropped player.
    private var trainingMediaBackdrop: some View {
        ZStack {
            MasoColor.background
            if let exercise = backgroundExercise {
                if let bytes = exercise.customImageData, let image = UIImage(data: bytes) {
                    ExerciseAspectFillPhoto(image: image)
                } else if let url = ExerciseDemoService.shared.files[exercise.id] {
                    ExerciseDemoThumbnail(url: url, fallback: CoreExerciseDemos.thumbnail(exercise.id))
                } else if let image = CoreExerciseDemos.thumbnail(exercise.id) {
                    ExerciseAspectFillPhoto(image: image)
                }
            }
        }
        .blur(radius: 32)
        .overlay(Color.black.opacity(0.36))
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
                compact: false,
                // tap "Replace exercise" 入口 → 通过共享 replacingStepId 状态拉 ExercisePickerSheet.
                onRequestReplace: { replacingStepId = seg.stepId },
                onRequestOtherExercise: {
                    replacementUsesAllMuscles = true
                    replacingStepId = seg.stepId
                },
                onSelectVariant: { selectVariant($0, stepId: seg.stepId) },
                onAdjustParameter: { adjustParameter($0, by: $1, stepId: seg.stepId) }
            )
        case .rest:
            EmptyView()  // rest 段不通过 infoSection 渲染, 走专门的 restCountdownRing
        }
    }

    private func adjustParameter(_ parameter: WorkoutParameter, by direction: Int, stepId: String) {
        Haptics.selection()
        store.adjustParameter(parameter, by: direction, stepId: stepId, unit: data.settings.weightUnit,
                              exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                              defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds)
        if let edited = store.plan?.steps.first(where: { $0.id == stepId }), let planID = store.plan?.id {
            data.confirmMatchingSuggestions(from: edited, in: planID)
            data.syncExerciseParams(from: edited)
        }
    }

    private func selectVariant(_ exercise: Exercise, stepId: String) {
        Haptics.selection()
        if let currentID = store.plan?.steps.first(where: { $0.id == stepId })?.exerciseId {
            data.rememberExplicitVariantChoice(from: currentID, to: exercise.id)
        }
        store.replaceStepExercise(stepId, newExerciseId: exercise.id,
                                  suggestedStep: data.makeSeededStep(for: exercise, stepId: stepId), exById: data.exById,
                                  defaultRest: data.settings.defaultRestSeconds,
                                  defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds)
    }

    /// 判断当前 rest 段是 "组间休息" 还是 "动作切换休息"
    /// - 看 rest 之前的 exercise segment vs rest 之后的 exercise segment, stepId 不同 = 动作切换
    private func isCrossExerciseRest(currentSegment seg: Segment) -> Bool {
        guard let s = store.session else { return false }
        let i = s.segmentIndex
        guard store.segments.indices.contains(i) else { return false }
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
    private func nextExerciseTargets() -> (reps: Int?, weight: Double?, setNumber: Int?, totalSets: Int?) {
        guard let s = store.session else { return (nil, nil, nil, nil) }
        for i in (s.segmentIndex + 1)..<store.segments.count {
            if case .exercise(_, let number, let total, let reps, let weight, _, _) = store.segments[i].kind {
                return (reps, weight, number, total)
            }
        }
        return (nil, nil, nil, nil)
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
    private func restCountdownRing(seg: Segment, available: CGSize) -> some View {
        if case .rest(let dur) = seg.kind {
            RestCountdown(
                durationTotal: dur,
                endsAt: store.session?.endsAt,
                pausedRemaining: store.session?.pausedRemaining,
                isCrossExercise: isCrossExerciseRest(currentSegment: seg),
                available: available,
                onEdit: {
                    editingRestSeconds = data.settings.defaultRestSeconds
                    editingSwitchSeconds = data.settings.defaultBetweenExerciseRestSeconds
                    restEditorPresented = true
                }
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
                compact: false,
                nextReps: targets.reps,
                nextWeight: targets.weight,
                nextSetNumber: targets.setNumber,
                nextTotalSets: targets.totalSets,
                onSelectVariant: { variant in
                    if let stepId = nextStepId { selectVariant(variant, stepId: stepId) }
                },
                onRequestOtherExercise: {
                    if let stepId = nextStepId {
                        replacementUsesAllMuscles = true
                        replacingStepId = stepId
                    }
                },
                onAdjustParameter: { parameter, direction in
                    if let stepId = nextStepId { adjustParameter(parameter, by: direction, stepId: stepId) }
                },
                isCrossExercise: isCrossExerciseRest(currentSegment: seg),
                // 小编辑入口 — 跟 playlist 的 onEdit 一样用 editingStepId 触发 EditAnyStepSheet,
                // 复用已有 sheet (line ~224), 不需要新 sheet 通道.
                onEdit: nextStepId.map { id in { editingStepId = id } }
            )
        }
    }



    private func handlePrimary(seg: Segment) {
        switch seg.kind {
        case .exercise(_, _, _, _, _, _, true):
            store.togglePlay()
        case .exercise(_, _, _, _, _, _, false):
            // ✓ 记组. (撤销 toast 已移除 — owner 反馈气泡干扰; 误记走休息屏"刚才 · Adjust" 修正.)
            store.advance { rec in data.recordSet(rec) }
        default:
            store.advance { rec in data.recordSet(rec) }
        }
    }

    private var bottomSafeArea: CGFloat { playerSafeArea.bottom }

    private var playlistContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This workout")
                    .font(.title2.bold()).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { addStepPickerOpen = true } label: {
                    Label("Add exercise", systemImage: "plus")
                        .font(.caption.weight(.semibold)).lineLimit(1)
                }
                .nativeGlassButtonStyle().controlSize(.small)
                .accessibilityIdentifier("workout.queue.add")
                .layoutPriority(1)
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            InlinePlaylist(
                plan: store.plan,
                exById: data.exById,
                currentStepId: currentStepId,
                currentSet: currentSetNumber,
                completedSetsByStep: completedSetsByStep,
                // 跳到该动作下一组未完成的 set (跳过 rest, 不重置休息计时).
                onJump: { stepId in store.jumpToStep(stepId: stepId) },
                onTapImage: { ex in detailExercise = ex },
                onReorder: { source, destination in
                    reorderWorkoutSteps(from: source, to: destination)
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
                onAddStep: nil,
                showHeader: false,
                // J5: 竖向进度条 + 动作间休息行的数据源
                segments: store.segments,
                currentIndex: store.session?.segmentIndex ?? 0,
                completedSets: store.session?.completedSets ?? [],
                onJumpSegment: { idx in store.setIndex(idx) },
                isResting: store.currentSegment?.isRest == true,
                isPlaying: store.session?.playing == true,
                restEndsAt: store.session?.endsAt,
                restTotal: currentRestTotalSeconds,
                activeRestAfterStepId: activeRestAfterStepId
            )
            .accessibilityIdentifier("workout.playlist.list")
        }
    }

    /// Playlist rows and progress segments both call this. The move is the session plan only.
    private func reorderWorkoutSteps(from source: IndexSet, to destination: Int) {
        store.reorderSteps(
            from: source,
            to: destination,
            exById: data.exById,
            defaultRest: data.settings.defaultRestSeconds,
            defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds
        )
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

    /// 当前休息段的总时长 (秒) — 给播放列表里活动休息行的进度条用. 非休息 → nil.
    private var currentRestTotalSeconds: Int? {
        if case .rest(let d) = store.currentSegment?.kind { return d }
        return nil
    }

    /// 当前正在进行的"动作间休息"挂在哪个 step 之后 → 让播放列表把那条 rest 行高亮.
    /// 仅当当前段是 *动作间* 休息 (跨动作) 时非 nil; 组间休息 (同动作两组之间) 不在列表里单独成行,
    /// 由进度环的"下一组呼吸"表达, 不走这里.
    private var activeRestAfterStepId: String? {
        guard let seg = store.currentSegment, seg.isRest,
              isCrossExerciseRest(currentSegment: seg) else { return nil }
        let idx = store.session?.segmentIndex ?? 0
        var i = idx - 1
        while i >= 0 {
            if store.segments[i].isExercise { return store.segments[i].stepId }
            i -= 1
        }
        return nil
    }

    // MARK: - Save plan (自由训练完成后的 "保存为计划" 入口)

    private var openWorkoutSummary: String {
        "\(pluralizedExercises(completedExerciseCount)) · \(pluralizedSets(store.session?.completedSets.count ?? 0)) · \(completedDurationSeconds / 60)m"
    }

    private func saveOpenWorkout(name: String) {
        guard var plan = store.plan, let session = store.session else { return }
        let order = session.completionOrder ?? []
        plan.steps = order.compactMap { id in
            guard var step = plan.steps.first(where: { $0.id == id }) else { return nil }
            let count = session.completedSets.filter { $0.stepId == id }.count
            guard count > 0 else { return nil }
            let completed = session.completedSets.filter { $0.stepId == id }.map(\.setN).sorted()
            let source = step
            step.sets = count
            step.setReps = completed.map { source.repsForSet($0) }
            step.setWeights = completed.map { source.weightForSet($0) }
            step.setDurations = completed.map { source.durationForSet($0) }
            if let last = data.sets.first(where: {
                $0.planId == session.planId && $0.exerciseId == step.exerciseId && $0.performedAt >= session.startedAt
            }) {
                step.reps = last.reps
                step.weight = last.weight
                step.duration = last.duration
            }
            return step
        }
        guard !plan.steps.isEmpty else { return }
        plan.name = name
        plan.autoGenerated = false
        plan.updatedAt = Date()
        data.updatePlan(plan)
    }

    /// 当前 plan 是临时自由训练 (autoGenerated 标志 + 尚未入 data.plans) → 可保存
    private var canSaveCurrentPlan: Bool {
        guard let plan = store.plan, plan.autoGenerated else { return false }
        return !data.plans.contains(where: { $0.id == plan.id })
    }

    /// 把当前临时 plan 保存到用户的 plan library
    @State private var planSavedFlash: Bool = false  // 显示"已保存"短暂 toast
    /// Exit and swipe-down both dismiss the report sheet, so ending lives here once.
    private func endFinishedSessionOnce() {
        guard !sessionReportDidEnd else { return }
        sessionReportDidEnd = true
        store.endedExplicitly = true
        store.end()
        dismiss()
    }

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
    /// 底部控制条 — 抽出整段 Controls(...) 调用, 给 player body 表达式减负 (否则类型检查超时).
    @ViewBuilder
    private func controlsBar(seg: Segment) -> some View {
        Controls(
            seg: seg,
            playing: store.session?.playing ?? true,
            canGoBack: store.canUndoPlayback,
            onBack: { handleBack() },
            onPrimary: { handlePrimary(seg: seg) },
            onTogglePlay: { store.togglePlay() },
            onEnd: { endConfirmOpen = true }
        )
        .background {
            HeartRateAutomaticObserver(segment: seg, suppressedUntil: heartAssistSuppressedUntil) { sample in
                guard data.settings.workoutHeartRateAutomaticEnabled == true, data.settings.workoutHeartRateEnabled == true,
                      playerScenePhase == .active, Date() >= heartAssistSuppressedUntil,
                      (!seg.isRest || !store.heartRate.warningPending),
                      store.currentSegment?.id == seg.id, store.session?.playing == true,
                      store.heartRate.latest?.id == sample.id, Date().timeIntervalSince(sample.date) <= 20 else { return }
                let priorCount = store.session?.playbackUndo?.count ?? 0
                let sessionID = store.workoutSessionID
                handlePrimary(seg: seg)
                if let session = store.session, (session.playbackUndo?.count ?? 0) > priorCount,
                   let undo = session.playbackUndo?.last {
                    heartAssistUndo = undo
                    heartAssistUndoSession = sessionID
                    heartAssistUndoWasRest = seg.isRest
                }
            }.id(seg.id)
        }
    }

    /// Undo the most recent set/rest transition and its exact completion record.
    private func handleBack() {
        store.undoPlayback { data.removeSetRecord(id: $0) }
    }

    /// R3: 同步开 → 把刚改过的 step 参数传播到所有含该动作的计划. 抽成方法 (内联会撑爆 sheet 表达式类型检查).
    private func propagateParamsIfSyncing(stepId: String) {
        guard let edited = store.plan?.steps.first(where: { $0.id == stepId }), let planID = store.plan?.id else { return }
        data.confirmMatchingSuggestions(from: edited, in: planID)
        data.syncExerciseParams(from: edited)
    }

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

    /// 本次训练动作数 (唯一 exercise 数) — 跟 SessionSummary.exerciseCount 同义.
    private var completedExerciseCount: Int {
        guard let plan = store.plan else { return 0 }
        return Set(plan.steps.map { $0.exerciseId }).count
    }

    /// 本次 session 真正完成的 SetRecord (过滤到本场).
    private var completedSessionSets: [SetRecord] {
        guard let session = store.session else { return [] }
        if let ids = session.recordedSetIDs, !ids.isEmpty {
            let matched = data.sets.filter { ids.contains($0.id) && $0.performedAt <= Date() }
            if !matched.isEmpty { return matched.sorted { $0.performedAt < $1.performedAt } }
        }
        if let key = store.workoutSessionID {
            let matched = data.sets.filter { $0.workoutSessionID == key && $0.performedAt <= Date() }
            if !matched.isEmpty { return matched.sorted { $0.performedAt < $1.performedAt } }
        }
        return data.sets.filter { $0.planId == session.planId && $0.performedAt >= session.startedAt && $0.performedAt <= Date() }
            .sorted { $0.performedAt < $1.performedAt }
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
/// sheet 顶部圆角裁剪形状 — **始终应用** (无 if/else 结构切换, 故下拉时不跳变、手势不被取消).
/// 关键: 底边向下延伸 400pt, 这样无论 clipShape 按 safe-area 还是全屏计算, 底部 home indicator
/// 区永远落在 path 内 → 永不被裁 (playlist 一路延续到屏幕最底, 下拉中也不露黑).
/// radius=0 (静止) = 直角全出血; radius>0 (下拉) = 顶部上圆角. animatableData 让圆角平滑过渡.
private struct TopRoundedSheetShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let extended = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + 400)
        return UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: radius
        ).path(in: extended)
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
    var compact = false
    /// "替换动作" 回调 — 通过 EditCurrentStepSheet 的 onReplace 触发. parent 用它弹 ExercisePickerSheet.
    var onRequestReplace: (() -> Void)? = nil
    var onRequestOtherExercise: (() -> Void)? = nil
    var onSelectVariant: ((Exercise) -> Void)? = nil
    var onAdjustParameter: ((WorkoutParameter, Int) -> Void)? = nil

    @State private var editOpen = false
    @State private var replacementRequested = false
    @State private var detailOpen = false

    /// 单个指标块: 大数值 + 60% 透明的字样标签. 文字带阴影, 在动图背景上可读.
    private func metric(value: String, label: String, parameter: WorkoutParameter) -> some View {
        PlayerParameterValue(value: value, label: label, parameter: parameter, onAdjust: onAdjustParameter,
            isSuggested: parameter != .duration && store.currentSegment.flatMap { segment in store.plan?.steps.first { $0.id == segment.stepId } }?.isSuggested(parameter.rawValue) == true,
            needsCalibration: parameter == .weight && weight == nil && ExerciseWeightReference.expectsLoad(exercise))
    }

    private var parameterDivider: some View {
        PlayerParameterDivider()
    }

    private var metricsRow: some View {
        HStack(alignment: .center, spacing: 0) {
            metric(value: "\(setNumber)/\(totalSets)", label: NSLocalizedString("Sets", comment: ""), parameter: .sets)
            if let r = reps {
                parameterDivider.accessibilityIdentifier("workout.parameter.divider.reps")
                metric(value: "\(r)", label: NSLocalizedString("Reps", comment: ""), parameter: .reps)
            }
            if weight != nil || ExerciseWeightReference.expectsLoad(exercise) {
                parameterDivider.accessibilityIdentifier("workout.parameter.divider.weight")
                metric(value: weight.map(weightLabel) ?? "", label: NSLocalizedString("Weight", comment: ""), parameter: .weight)
            }
            if isCountdown, let remaining {
                parameterDivider
                metric(value: formatRemaining(remaining), label: NSLocalizedString("Time", comment: ""), parameter: .duration)
            }
        }
    }

    var body: some View {
        PlayerExerciseInfoLayout(compact: compact) {
            PlayerExerciseHeading(exercise: exercise, compact: compact, onDetail: { detailOpen = true },
                                  onSelectVariant: onSelectVariant, onRequestReplace: onRequestOtherExercise)
        } status: {
            EmptyView()
        } parameters: {
            PlayerParameterPanel(title: "Edit exercise parameters") {
                Haptics.tap(); editOpen = true
            } content: { metricsRow }
        }
        .sheet(isPresented: $detailOpen) {
            ExerciseDetailSheet(exercise: exercise)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $editOpen, onDismiss: {
            if replacementRequested {
                replacementRequested = false
                DispatchQueue.main.async { onRequestReplace?() }
            }
        }) {
            // P1#10: 这个入口之前漏传 initialSetReps/initialSetWeights (对比播放列表右滑入口) →
            // perSetEnabled=false → Save 时 onSave(..., nil, nil) 把逐组配置静默压平 (金字塔组
            // 60/70/80 被抹), 全局同步再把破坏传播到所有 routine. 改成与播放列表入口同构造:
            // 从 store.plan 取当前 step, 逐组数组一并带上. (segment 传入的 reps/weight 是逐组
            // 解析值, 只作 step 意外缺失时的兜底.)
            let step = store.currentSegment.flatMap { seg in
                store.plan?.steps.first(where: { $0.id == seg.stepId })
            }
            EditCurrentStepSheet(
                exercise: exercise,
                initialSets: step?.sets ?? totalSets,
                initialReps: step?.reps ?? reps,
                initialWeight: step?.weight ?? weight,
                initialDuration: step?.duration ?? duration,
                initialSetReps: step?.setReps,
                initialSetWeights: step?.setWeights,
                initialParameterStep: step,
                onConfirmParameters: { fields in
                    if let id = step?.id { store.confirmParameters(stepId: id, fields: fields) }
                },
                onSave: { newSets, newReps, newWeight, newDuration, newSetReps, newSetWeights in
                    let editedStepId = store.currentSegment?.stepId
                    if newWeight != step?.weight || newSetWeights != step?.setWeights {
                        data.rememberWeight(newWeight ?? newSetWeights?.compactMap { $0 }.first, for: exercise)
                    }
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
                    // R3: 同步开 → 训练中改的参数即时传播到所有含该动作的 routine.
                    if let sid = editedStepId, let edited = store.plan?.steps.first(where: { $0.id == sid }),
                       let planID = store.plan?.id {
                        data.confirmMatchingSuggestions(from: edited, in: planID)
                        data.syncExerciseParams(from: edited)
                    }
                },
                onReplace: onRequestReplace == nil ? nil : { replacementRequested = true },
                syncsGlobally: data.settings.globalExerciseParamSyncEnabled
            )
            .presentationDetents([.medium])
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
    /// 调用方 (GeometryReader) 实测的可用净空 = [拖把手底, 底部信息区内容顶] 之间.
    /// 组件尺寸完全由它推导 → footprint 恒 ≤ 它, 数学上不可能与上下元素重叠.
    let available: CGSize
    let onEdit: () -> Void

    private static let ringWidth: CGFloat = 3
    /// 圆环最大直径 (空间充裕时的观感尺寸).
    static let baseRing: CGFloat = 220
    /// 组件与上下刚性元素之间强制留的净距 (每侧).
    static let safeGap: CGFloat = 10

    /// 三档降级阈值 (作用于 budget):
    ///   ≥ full  : 环 + REST 字样 + 数字 (完整)
    ///   ≥ ring  : 较小圆环、文字入口与数字
    ///   <  ring : 去掉环，保留文字入口与数字
    private static let fullThreshold: CGFloat = 132
    private static let ringThreshold: CGFloat = 92

    /// 本帧的尺寸预算 = 可用高度扣掉上下安全间隙, 再夹到宽度和最大环径.
    /// 组件所有部件 (环径 / 字号) 都从它等比推导, 因此 footprint 永远装得进 available.
    private var budget: CGFloat {
        min(Self.baseRing,
            max(0, available.height - Self.safeGap * 2),
            max(0, available.width - 32))
    }

    private enum Tier { case full, ring, bare }
    private var tier: Tier {
        if budget >= Self.fullThreshold { return .full }
        if budget >= Self.ringThreshold { return .ring }
        return .bare
    }

    /// 数字字号 — 按 budget 等比推导. 三档系数都保证文字盒 (≈ 字号 × 1.2) 装得进 budget:
    /// full 0.29×1.2=0.35 / ring 0.34×1.2=0.41 / bare 0.66×1.2=0.79, 均 < 1.
    private var numberFont: CGFloat {
        switch tier {
        case .full: return budget * 0.29   // 220 → 64pt, 与原视觉一致
        case .ring: return budget * 0.34   // 环内无 REST 字样, 数字可占更多
        case .bare: return budget * 0.48   // 保留文字入口的空间
        }
    }

    private func remainingFloat(at date: Date) -> Double {
        if let p = pausedRemaining { return max(0, p) }
        guard let endsAt = endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(date))
    }

    private func progress(_ remaining: Double) -> CGFloat {
        guard durationTotal > 0 else { return 0 }
        return max(0, min(1, CGFloat(remaining) / CGFloat(durationTotal)))
    }

    // Keep the interactive label outside the ticking subtree: a short touch must
    // not be cancelled by the 10 Hz clock rebuilding its button on large screens.
    var body: some View {
        Group {
            if tier == .bare {
                countdownContent
            } else {
                ZStack {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        let value = progress(remainingFloat(at: context.date))
                        ZStack {
                            Circle().stroke(MasoColor.text.opacity(0.12), lineWidth: Self.ringWidth)
                            Circle().trim(from: max(0, 1 - value), to: 1)
                                .stroke(MasoColor.text, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                    countdownContent
                }.frame(width: budget, height: budget)
            }
        }
    }

    private var countdownContent: some View {
        VStack(spacing: 4) {
            restLabel
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(formatRemaining(Int(ceil(remainingFloat(at: context.date)))))
                    .accessibilityIdentifier("workout.rest.countdown")
                    .font(.system(size: numberFont, weight: .bold).monospacedDigit())
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }.fixedSize()
        }
    }

    private var restLabel: some View {
        Button(action: onEdit) {
            HStack(spacing: 4) {
                Text(isCrossExercise ? "Switching" : "Rest")
                    .tracking(2)
                    .textCase(.uppercase)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .font(.system(size: min(11, budget * 0.15), weight: .bold))
            .foregroundStyle(MasoColor.text.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit rest time")
        .anchorPreference(key: PlayerLayoutBoundsKey.self, value: .bounds) { ["restLabel": $0] }
        .accessibilityHidden(true)
    }


}

/// 下一动作 hint — kicker + 动作名. 跟 Controls 同框, 共享底部渐变遮罩背景.
/// 字号 18pt + 黑色 shadow → 在 next-exercise 动图上读得清楚.
private struct RestNextHint: View {
    @Environment(TrainingSessionStore.self) private var store
    let next: Exercise
    @State private var detailOpen = false
    var compact = false
    /// 下一动作的目标 reps / weight — 让用户休息时提前知道下一组上多少.
    var nextReps: Int? = nil
    var nextWeight: Double? = nil
    var nextSetNumber: Int? = nil
    var nextTotalSets: Int? = nil
    var onSelectVariant: ((Exercise) -> Void)? = nil
    var onRequestOtherExercise: (() -> Void)? = nil
    var onAdjustParameter: ((WorkoutParameter, Int) -> Void)? = nil
    let isCrossExercise: Bool
    /// 小编辑入口 — 让用户在休息时改下一动作的 sets/reps/weight. nil → 不渲染.
    var onEdit: (() -> Void)? = nil

    /// "× 8 · 60 kg" 这种目标摘要; 都没有则 nil.
    private var targetLine: String? {
        var parts: [String] = []
        if let r = nextReps { parts.append("× \(r)") }
        if let w = nextWeight, w > 0 { parts.append("\(weightLabel(w))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func suggested(_ parameter: String) -> Bool {
        guard let current = store.session?.segmentIndex,
              let segment = store.segments.dropFirst(current + 1).first(where: { segment in
                  if case .exercise(let ex, _, _, _, _, _, _) = segment.kind { return ex.id == next.id }
                  return false
              }) else { return false }
        return store.plan?.steps.first { $0.id == segment.stepId }?.isSuggested(parameter) == true
    }

    var body: some View {
        PlayerExerciseInfoLayout(compact: compact) {
            PlayerExerciseHeading(exercise: next, compact: compact, onDetail: { detailOpen = true },
                                  onSelectVariant: onSelectVariant, onRequestReplace: onRequestOtherExercise)
        } status: {
            Text(isCrossExercise ? "Next Exercise" : "Up Next")
                .font(.system(size: 11, weight: .bold)).tracking(2).textCase(.uppercase)
                .foregroundStyle(MasoColor.accent).lineLimit(1)
        } parameters: {
            if let onEdit {
                PlayerParameterPanel(title: "Edit next exercise", onEdit: { Haptics.tap(); onEdit() }) {
                    HStack(alignment: .center, spacing: 0) {
                        if let number = nextSetNumber, let total = nextTotalSets {
                            PlayerParameterValue(value: "\(number)/\(total)", label: NSLocalizedString("Sets", comment: ""), parameter: .sets, onAdjust: onAdjustParameter, isSuggested: suggested("sets"))
                        }
                        if let reps = nextReps {
                            if nextTotalSets != nil { PlayerParameterDivider().accessibilityIdentifier("workout.parameter.divider.reps") }
                            PlayerParameterValue(value: "\(reps)", label: NSLocalizedString("Reps", comment: ""), parameter: .reps, onAdjust: onAdjustParameter, isSuggested: suggested("reps"))
                        }
                        if nextWeight != nil || ExerciseWeightReference.expectsLoad(next) {
                            if nextTotalSets != nil || nextReps != nil { PlayerParameterDivider().accessibilityIdentifier("workout.parameter.divider.weight") }
                            PlayerParameterValue(value: nextWeight.map(weightLabel) ?? "", label: NSLocalizedString("Weight", comment: ""), parameter: .weight, onAdjust: onAdjustParameter, isSuggested: suggested("weight"), needsCalibration: nextWeight == nil && ExerciseWeightReference.expectsLoad(next))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $detailOpen) {
            ExerciseDetailSheet(exercise: next)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(MasoColor.text)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(MasoColor.background.opacity(0.6))
            .clipShape(Capsule())
    }
}

// MARK: - Controls

/// Both footer rows share identical columns, even when the YouTube link is absent.
private struct PlayerTransportRow<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: () -> Center
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            leading().frame(width: 44, height: 44)
            Spacer(minLength: 0)
            center().frame(width: 72)
            Spacer(minLength: 0)
            trailing().frame(width: 44, height: 44)
            Spacer(minLength: 0)
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, MasoMetrics.cardPadding)
    }
}

private struct HeartRateAutomaticObserver: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let segment: Segment
    let suppressedUntil: Date
    let onAutomatic: (WorkoutHeartSample) -> Void
    @State private var detector = WorkoutHeartAutomaticDetector()

    private var eligible: Bool {
        guard data.settings.workoutHeartRateAutomaticEnabled == true,
              data.settings.workoutHeartRateEnabled == true,
              store.session?.playing == true, store.currentSegment?.id == segment.id,
              scenePhase == .active, Date() >= suppressedUntil else { return false }
        if case .exercise(_, _, _, _, _, _, let countdown) = segment.kind { return !countdown }
        return segment.isRest && !store.heartRate.warningPending
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
        .onChange(of: store.heartRate.latest) { _, sample in
            guard eligible, let sample, sample.sessionID == store.workoutSessionID,
                  sample.date >= (store.session?.segmentEnteredAt ?? .distantFuture) else { return }
            if detector.observe(sample, phase: segment.isRest ? .rest : .exercise, now: Date()) {
                DispatchQueue.main.async { onAutomatic(sample) }
            }
        }
        .onChange(of: eligible) { _, enabled in
            if !enabled { detector = WorkoutHeartAutomaticDetector() }
        }
    }
}

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

    /// P0#5-③: ✓ 落组后 ~300ms 冷却 — ✓ 点完主按钮原位立刻变"跳过休息",
    /// 手抖双击的第二下会顺手把休息也跳了 (= 记组 + 跳休息). 冷却期内主按钮吞事件
    /// (不改外观, 只挡 300ms 内的第二下; 只有 ✓ 触发冷却, 播放/暂停/跳过不受影响).
    @State private var primaryCooldownUntil: Date = .distantPast

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
        PlayerTransportRow {
            backBtn
        } center: {
            primaryBtn
        } trailing: {
            cancelBtn
        }
        .padding(.top, 2)     // 顶部留更小间距 — 按钮栏跟上方 info 区贴更紧, 视觉收得稳
        .padding(.bottom, 12)
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
            // P0#5-③: 冷却期内吞掉第二下 (✓ 后原位变"跳过休息", 双击 = 记组+跳休息).
            guard Date() >= primaryCooldownUntil else { return }
            if isPrimaryComplete { primaryCooldownUntil = Date().addingTimeInterval(0.3) }
            onPrimary()
            if isPrimaryComplete { celebrateTrigger &+= 1 }
        }) {
            primaryIcon
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
                .glassCircleButtonBackground(tint: MasoColor.accent.opacity(0.85), fallback: MasoColor.accent)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .accessibilityLabel(primaryLabel)
        .accessibilityIdentifier("workout.primary")
    }

    // 共用 4 个小按钮 (X 取消, ◀ 上一段, ☰ 播放列表)
    // 全部整体缩小一号: icon 字号 -2, frame 40 → 36
    private var cancelBtn: some View {
        Button(action: onEnd) {
            // stop.fill — 跟主按钮的 play/pause 形成 transport controls 隐喻.
            // 字号 / 字重 / 颜色 跟 backward.end.fill (上一动作) 完全一致, 视觉对称.
            Image(systemName: "stop.fill")
                .font(.system(size: 18))
                .foregroundStyle(MasoColor.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("End workout")
        .accessibilityIdentifier("workout.end")
    }
    private var backBtn: some View {
        Button(action: {
            Haptics.tap()  // 轻触反馈 — 跟其它操作按钮的触觉语言一致
            onBack()
        }) {
            // Retain transport styling; the action now undoes the previous transition.
            Image(systemName: "backward.end.fill")
                .font(.system(size: 18))
                .foregroundStyle(MasoColor.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(!canGoBack)
        .accessibilityLabel("Undo")
        .accessibilityIdentifier("workout.previous")
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
    /// 右侧 i 打开动作详情，头像和名称都选择本行。
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
    /// 当前段是否是休息 — 决定: ① 进度环里"下一组"那段弧做白色呼吸 (而非实色),
    /// ② 活动的动作间休息行高亮 + 进度条.
    var isResting: Bool = false
    var isPlaying: Bool = true
    /// 当前休息的结束时刻 + 总时长 — 给活动休息行画倒计时进度条用.
    var restEndsAt: Date? = nil
    var restTotal: Int? = nil
    /// 哪一行的"动作间休息"是当前正在进行的 (= 该 step 之后那条 rest 行高亮). nil = 没有活动休息行.
    var activeRestAfterStepId: String? = nil

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
        let gap: Double = n > 1 ? min(0.06, 0.28 / Double(n)) : 0   // 段间留 6% 空隙, lineCap .round 让缺口柔和
        ZStack {
            // 视觉环 — padding 让 5pt 描边不被 56 frame 裁切
            ZStack {
                ForEach(Array(segs.enumerated()), id: \.element.idx) { i, item in
                    let color = setBarColor(idx: item.idx, stepId: stepId, setN: item.setN)
                    // 休息时 "下一组" (= 当前白色那段, 还没做) 做白色呼吸; 真到那组开练才变实白.
                    let breathing = !isResting && isPlaying
                        && stepId == currentStepId && currentSet == item.setN
                        && !completedSets.contains(.init(stepId: stepId, setN: item.setN))
                    Circle()
                        .trim(from: Double(i) / Double(n) + gap / 2,
                              to: Double(i + 1) / Double(n) - gap / 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))   // trim 0 起点转到正上方 12 点
                        // 颜色必须即刻切换 (白→绿 / 绿→白) — 禁掉任何继承动画,
                        // 否则切换动作时进度弧会短暂过渡到错误颜色 (闪烁).
                        .animation(nil, value: color)
                        .modifier(BreathingArc(active: breathing))
                }
            }
            .padding(2.5)
            // 中心: 总组数
            Text("\(segs.filter { completedSets.contains(.init(stepId: stepId, setN: $0.setN)) }.count)/\(segs.count)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.queue.progress.\(stepId)")
        .accessibilityValue("\(segs.filter { completedSets.contains(.init(stepId: stepId, setN: $0.setN)) }.count)/\(segs.count)")
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
            return isResting ? MasoColor.accent.opacity(0.4) : MasoColor.accent
        }
        return MasoColor.textFaint.opacity(0.35)  // 未做 = 暗灰
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                DragHandle().frame(maxWidth: .infinity)
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
                            // 左滑 (trailing) 展开两个操作: Edit(左) Delete(右).
                            // (Replace 已从左滑移除 — 改到 Edit sheet 顶部入口, 见 EditCurrentStepSheet.)
                            // SwiftUI trailing swipeActions: 第一个定义 = 最右, 最后定义 = 最左.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // 最右 — 删除 (破坏性, 红色)
                                Button(role: .destructive) {
                                    onDelete?(step.id)
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .tint(MasoColor.negative)
                                .accessibilityLabel(NSLocalizedString("Delete", comment: ""))

                                // 最左 — 编辑 sets/reps/weight/duration (含 Replace exercise 入口)
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
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: onAddStep) {
                            TrainingCardActionLabel(title: "Add Exercise", icon: "plus",
                                                    accent: MasoColor.text, prominent: false)
                                .glassCapsuleButtonBackground(fallback: MasoColor.surfaceHi)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
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
        .background(MasoColor.background)
    }

    private func playlistRow(step: PlanStep, ex: Exercise) -> some View {
        let isCurrent = step.id == currentStepId
        // Keep the ongoing exercise marked through its own set rests. Between exercises,
        // only the rest row is active; do not mark the upcoming exercise as started.
        let highlightCurrent = isCurrent && (!isResting || activeRestAfterStepId == nil)
        let done = progressN(for: step)
        // 已完成 step: progress 达到 sets 上限, 且不是当前行 (current 的 progress 是"正在做的组数",
        // 临界点 step.sets - 1 → step.sets 那一刻是用户做完最后一组的 transition, 此时 step 仍是 current).
        let isCompleted = !isCurrent && done >= step.sets && step.sets > 0
        // 进度环显示条件: 当前动作 OR 已经练过几组的动作 (done > 0). 这样切到别的动作后,
        // 之前练过的那几组在它自己那一行的环上仍标绿、看得见. 完全没碰过的动作才显缩略图.
        let showsRing = isCurrent || (done > 0 && done < step.sets)
        // Main row selects the exercise. The separate i is the only detail entry.
        // Keep the current marker visible through rests between this exercise's sets.
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
              Button(action: { onJump(step.id) }) {
              HStack(spacing: 14) {
                Circle().fill(highlightCurrent ? MasoColor.accent : .clear)
                    .frame(width: 7, height: 7)
                    .fixedSize()
                    .accessibilityHidden(true)
                // 当前动作 + 练过几组的动作: 缩略图位置换成进度环 (一组一段弧, 点段=跳到那一组);
                // 完全没碰过的动作才保留缩略图. 进度环让"哪几组练过"在每个动作上都看得见.
                if showsRing {
                    progressRing(stepId: step.id)
                } else {
                    ExerciseImage(
                            category: ex.category, exerciseID: ex.id,
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
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        if isCompleted {
                            // 微妙的"已完成" affordance: 实心圆 + 内嵌对勾 (跟 current 的纯实心圆区分).
                            // 14pt 半透 accent — 不抢戏, 但扫一眼就能看见.
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(MasoColor.accent)
                        }
                        ExerciseTitleLabel(exercise: ex)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            .foregroundStyle(highlightCurrent ? MasoColor.accent : (isCompleted ? MasoColor.textDim : MasoColor.text))
                            // 已完成: 文字色降到 textDim + strikethrough — 视觉立刻区分 "已过去"
                            .strikethrough(isCompleted, color: MasoColor.textDim)
                    }
                    HStack(spacing: 5) {
                        // 显示进度环的行 (当前 / 练过的) 组数由环展示, 这里不重复;
                        // 只有显缩略图的行 (没碰过的) 才直接显示总组数.
                        if !showsRing {
                            Text(String(format: NSLocalizedString("%d sets", comment: "total sets"), step.sets))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(step.isSuggested("sets") ? MasoColor.parameterSuggestion : MasoColor.textDim)
                        }
                        if let r = step.reps { Text("× \(r)").font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(step.isSuggested("reps") ? MasoColor.parameterSuggestion : MasoColor.textDim) }
                        if let w = step.weight, w > 0 { Text("· \(weightLabel(w))").font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(step.isSuggested("weight") ? MasoColor.parameterSuggestion : MasoColor.textDim) }
                    }
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                    if ExerciseWeightReference.needsCalibration(step, exercise: ex) {
                        Text("First-use calibration").font(.caption2).foregroundStyle(MasoColor.textDim)
                            .accessibilityIdentifier("parameters.weight.calibration")
                    }
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
            .padding(.vertical, 8)  // row padding 加大让 56pt 缩略图四周呼吸更舒展

            // 整行点击热区: 没有 contentShape 时, Color.clear 背景区域不响应 tap,
            // 用户只能点到文字 / 缩略图. 加 contentShape 让整个 rect 都可点.
            .contentShape(Rectangle())
            .foregroundStyle(MasoColor.text)
              }
              .buttonStyle(.borderless)
              if let onTapImage {
                  ExerciseDetailInfoButton(exercise: ex) { onTapImage(ex) }
              }
            }
          // J3: 动作间休息 — 显示在两动作之间, 不可拖排序 (它是 step 行尾部元素, 跟着动作走).
          if let restSec = crossRestDuration(afterStepId: step.id) {
              restRow(seconds: restSec, isActive: isResting && activeRestAfterStepId == step.id)
          }
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .accessibilityIdentifier("workout.queue.row.\(step.id)")
    }

    /// 动作间休息行 — active/passive **固定同一总高 34pt**: ✓ 跨动作时 isActive 翻面, 两态
    /// 高度不同会让下方所有行下移再弹回 (列表上下跳, 用户报). 统一高度后切换只变样式不变布局.
    static let restRowHeight: CGFloat = 34
    ///   - 非活动 (isActive=false): 细、淡、居中, hourglass + 总时长. 纯展示.
    ///   - 活动中 (正在这条休息上, isActive=true): 高亮 (半透明白底) + 倒计时文字.
    @ViewBuilder
    private func restRow(seconds: Int, isActive: Bool) -> some View {
        if isActive, let endsAt = restEndsAt {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let remaining = max(0, endsAt.timeIntervalSince(ctx.date))
                // R1: 播放列表里休息位的进度条已去除 — 仅保留高亮底 + 倒计时文字 (其余样式与之前一致).
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9, weight: .heavy))
                    Text(String(format: NSLocalizedString("Rest %@", comment: "rest between exercises"),
                                formatRemaining(Int(ceil(remaining)))))
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .tracking(0.5)
                }
                .foregroundStyle(MasoColor.text)   // 休息中文字改白
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .frame(height: Self.restRowHeight - 4)
                .background(MasoColor.text.opacity(0.14))   // 高亮底改半透明白
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(height: Self.restRowHeight)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9, weight: .heavy))
                Text(String(format: NSLocalizedString("Rest %@", comment: "rest between exercises"), formatRemaining(seconds)))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(MasoColor.textFaint)
            .frame(maxWidth: .infinity)
            .frame(height: Self.restRowHeight)
        }
    }

    /// 当前 step 用 currentSet (正在做的那组); 否则用已完成组数 (默认 0).
    private func progressN(for step: PlanStep) -> Int {
        if step.id == currentStepId, let s = currentSet { return s }
        return completedSetsByStep[step.id, default: 0]
    }
}

/// The thin workout bar. Visual size stays the existing 4pt capsules; the 44pt row is the hit target.
/// Long-press then drag uses the playlist move. A tap still jumps, and leaving the bar cancels.
private struct WorkoutExerciseProgressBar: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let steps: [(planIndex: Int, step: PlanStep)]
    let segments: [Segment]
    let completed: Set<TrainingSessionStore.CompletedSet>
    let pendingStepId: String?
    let pendingSegmentId: String?
    let currentIsExercise: Bool
    let isPlaying: Bool
    let title: (PlanStep) -> String
    let onJump: (String) -> Void
    let onReorder: (IndexSet, Int) -> Void

    /// Gesture callbacks can arrive before the next SwiftUI state flush, so the
    /// live drag is kept on a reference. `drag` is the rendered copy.
    @State private var dragSession = DragSession()
    @State private var drag: Drag?
    @State private var suppressTapUntil = Date.distantPast

    private final class DragSession {
        var value: Drag?
    }

    private struct Drag {
        var sourceIndex: Int
        var origin: CGPoint
        var location: CGPoint
        var finalIndex: Int
        var inside: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let slot = steps.isEmpty ? 0 : max(0, (width - WorkoutProgressReorder.spacing * CGFloat(max(0, steps.count - 1))) / CGFloat(steps.count))
            let pitch = slot + WorkoutProgressReorder.spacing
            let rtl = layoutDirection == .rightToLeft
            HStack(spacing: WorkoutProgressReorder.spacing) {
                ForEach(Array(steps.enumerated()), id: \.element.step.id) { index, item in
                    segment(item.step, index: index, pitch: pitch, rightToLeft: rtl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(WorkoutProgressReorderGesture(
                enabled: steps.count > 1,
                onBegan: { origin in
                    let source = WorkoutProgressReorder.slotIndex(
                        x: origin.x, count: steps.count, width: width,
                        rightToLeft: rtl)
                    let value = Drag(sourceIndex: source, origin: origin, location: origin, finalIndex: source, inside: true)
                    dragSession.value = value
                    drag = value
                    suppressTapUntil = Date().addingTimeInterval(30)
                    Haptics.tap()
                },
                onChanged: { location in
                    guard var value = dragSession.value else { return }
                    value.location = location
                    if let landing = WorkoutProgressReorder.landingIndex(
                        count: steps.count, location: location, size: geo.size, rightToLeft: rtl) {
                        if value.finalIndex != landing { Haptics.selection() }
                        value.finalIndex = landing
                        value.inside = true
                    } else {
                        value.finalIndex = value.sourceIndex
                        value.inside = false
                    }
                    dragSession.value = value
                    drag = value
                },
                onEnded: { location, cancelled in
                    let finished = dragSession.value
                    dragSession.value = nil
                    drag = nil
                    suppressTapUntil = Date().addingTimeInterval(0.45)
                    guard let finished, !cancelled else { return }
                    guard let landing = WorkoutProgressReorder.landingIndex(
                        count: steps.count, location: location, size: geo.size, rightToLeft: rtl),
                          let move = WorkoutProgressReorder.planMove(
                            visiblePlanIndices: steps.map(\.planIndex),
                            from: finished.sourceIndex, toFinalIndex: landing) else { return }
                    onReorder(move.source, move.destination)
                }
            ))
        }
        .frame(height: 44)
        .animation(nil, value: drag?.location.x)
    }

    private func segment(_ step: PlanStep, index: Int, pitch: CGFloat, rightToLeft: Bool) -> some View {
        let sets = segments.filter { $0.isExercise && $0.stepId == step.id }
        let done = sets.filter { segment in
            if case .exercise(_, let number, _, _, _, _, _) = segment.kind {
                return completed.contains(.init(stepId: step.id, setN: number))
            }
            return false
        }.count
        let shift = drag.map { drag in
            drag.sourceIndex == index
                ? drag.location.x - drag.origin.x
                : WorkoutProgressReorder.neighborOffset(
                    index: index, source: drag.sourceIndex, finalIndex: drag.inside ? drag.finalIndex : drag.sourceIndex,
                    pitch: pitch, rightToLeft: rightToLeft)
        } ?? 0
        return Button {
            guard Date() >= suppressTapUntil, done != sets.count else { return }
            onJump(step.id)
        } label: {
            GeometryReader { geometry in
                if step.id == pendingStepId {
                    HStack(spacing: min(1, geometry.size.width / CGFloat(max(1, sets.count * 3)))) {
                        ForEach(sets) { segment in
                            let isComplete: Bool = {
                                if case .exercise(_, let number, _, _, _, _, _) = segment.kind {
                                    return completed.contains(.init(stepId: step.id, setN: number))
                                }
                                return false
                            }()
                            Rectangle().fill(isComplete ? MasoColor.accent : segment.id == pendingSegmentId ? (currentIsExercise ? MasoColor.accent : MasoColor.accent.opacity(0.4)) : MasoColor.text.opacity(0.18))
                                .modifier(BreathingArc(active: !isComplete && segment.id == pendingSegmentId && currentIsExercise && isPlaying))
                                .frame(maxWidth: .infinity)
                        }
                    }.clipShape(Capsule())
                } else {
                    Capsule().fill(MasoColor.text.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule().fill(MasoColor.accent)
                                .frame(width: geometry.size.width * CGFloat(done) / CGFloat(max(1, sets.count)))
                        }
                }
            }.frame(height: 4)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: shift)
        .zIndex(drag?.sourceIndex == index ? 1 : 0)
        .accessibilityIdentifier("workout.progress.\(step.id)")
        .accessibilityLabel(Text(title(step)))
        .accessibilityValue(Text("\(done)/\(sets.count)"))
        .accessibilityHint(Text(progressHint(canJump: done != sets.count)))
        .modifier(ProgressReorderActions(canMoveEarlier: index > 0, canMoveLater: index + 1 < steps.count, earlier: { move(from: index, toFinalIndex: index - 1) }, later: { move(from: index, toFinalIndex: index + 1) }))
    }

    private func progressHint(canJump: Bool) -> String {
        let reorder = NSLocalizedString("Long press and drag to reorder", comment: "Workout progress segment")
        guard canJump else { return reorder }
        let jump = NSLocalizedString("Jump to first unfinished set", comment: "Workout progress segment")
        return "\(jump) \(reorder)"
    }

    private func move(from index: Int, toFinalIndex final: Int) {
        guard let move = WorkoutProgressReorder.planMove(
            visiblePlanIndices: steps.map(\.planIndex), from: index, toFinalIndex: final) else { return }
        onReorder(move.source, move.destination)
    }
}

/// VoiceOver alternative to the long-press drag. End segments omit the action that would no-op.
private struct ProgressReorderActions: ViewModifier {
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let earlier: () -> Void
    let later: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if canMoveEarlier && canMoveLater {
            content
                .accessibilityAction(named: Text("Move earlier")) { earlier() }
                .accessibilityAction(named: Text("Move later")) { later() }
        } else if canMoveEarlier {
            content.accessibilityAction(named: Text("Move earlier")) { earlier() }
        } else if canMoveLater {
            content.accessibilityAction(named: Text("Move later")) { later() }
        } else {
            content
        }
    }
}

/// 让一段进度弧做"白色呼吸" — 仅 active (休息中 + 是即将开练的那组弧) 时启用:
/// opacity 在 ~0.35↔1.0 间缓慢往复, 暗示"下一组待开始"; 到那组真正开练 active 变 false → 恢复实色.
private struct BreathingArc: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var dim = false
    func body(content: Content) -> some View {
        content
            .opacity(active && !reduceMotion ? (dim ? 0.35 : 1.0) : 1.0)
            .onAppear { if active { startPulse() } }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { withAnimation(nil) { dim = false } }
                else if active { startPulse() }
            }
            .onChange(of: active) { _, now in
                if now {
                    startPulse()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { dim = false }
                }
            }
    }
    private func startPulse() {
        guard !reduceMotion else { return }
        dim = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            dim = true
        }
    }
}

// MARK: - Drag handle + Completed view

private struct DragHandle: View {
    var body: some View {
        Capsule().fill(.white.opacity(0.35))
            .frame(width: 40, height: 5)
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
                out += " · \(weightLabel(w))"
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
        GeometryReader { geometry in
            let compact = geometry.size.height < 600
            let listHeight = min(geometry.size.height * 0.46,
                                 max(40, geometry.size.height - (compact ? 320 : 400)))
        VStack(spacing: 0) {
            // 头部 — 跟 CompletedView 同语言: 圆形 icon + 标题 + 说明
            VStack(spacing: 0) {
                if geometry.size.height >= 400 {
                ZStack {
                    Circle().fill(MasoColor.accent.opacity(0.16)).frame(width: compact ? 48 : 72, height: compact ? 48 : 72)
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(MasoColor.accent)
                }
                .padding(.bottom, compact ? 12 : 18)
                }
                Text("Save changes to this routine?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("workout.saveChanges.title")
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
            .padding(.top, compact ? 12 : 28)
            .padding(.horizontal, 32)

            // routine 训练组列表 — 修改项突出, 未改项隐退
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { row in
                        changeRow(row)
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.vertical, 18)
            }
            .frame(height: listHeight)
            .clipped()
            .scrollIndicators(.visible)
            Spacer(minLength: 0)

            // 底部按钮 — 主: 保存到 routine; 次: 不保存 (跟 CompletedView 的按钮风格一致)
            VStack(spacing: 10) {
                Button(action: onSave) {
                    decisionButtonLabel("Save to routine", primary: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout.saveChanges.save")
                Button(action: onSkip) {
                    decisionButtonLabel("Don't save", primary: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout.saveChanges.skip")
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.saveChanges")
    }

    private func decisionButtonLabel(_ title: LocalizedStringKey, primary: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primary ? Color.black : MasoColor.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .glassCapsuleButtonBackground(tint: primary ? MasoColor.accent.opacity(0.85) : nil,
                                          fallback: primary ? MasoColor.accent : MasoColor.surface)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.saveChanges.row.\(row.id)")
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
    @Environment(TrainingSessionStore.self) private var store
    @State private var showWorkoutReport = false
    let planName: String
    let durationSeconds: Int
    /// Sets that belong to this completion, already isolated from other same-day workouts.
    var sessionRecords: [SetRecord] = []
    /// 自由训练 (临时 plan) 完成时 caller 传非 nil — 显示 "Save as plan" 按钮.
    /// 用户点了 → onSavePlan() 触发 caller 把 plan 写入 data.plans.
    /// (routine 内参数修改的保存已前移到 SaveChangesConfirmView 确认页, 不再出现在这里.)
    let onSavePlan: (() -> Void)?
    let onClose: () -> Void

    @State private var planSaved: Bool = false
    /// App Store 评分请求 — iOS 原生 (系统决定真正何时/是否弹). 在训练完成的正向时刻请求一次.
    @Environment(\.requestReview) private var requestReview
    /// Celebration runs once for this completion page, not when sharing is dismissed.
    @State private var didCelebrate = false
    @State private var celebrationStarted = Date()
    @State private var animationFinished = false
    @State private var celebrationFeedback = WorkoutCelebrationFeedback()
    @Environment(\.scenePhase) private var scenePhase
    private let celebration = WorkoutCelebrationConfiguration.approved
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Exiting an unsaved temporary workout preserves the save decision.
    @State private var showSavePrompt = false
    /// 练满 2 次时软问一次"要不要开召回提醒" (正向时刻, 全生命周期一次).
    @State private var showReminderOffer = false

    /// 训练真正结束 (分享页关 / 自由训练存盘后) → 关播放器. 在这个正向时刻按里程碑做两件事之一:
    ///   - 练满 2 次且没开提醒 → 软问"要不要开召回提醒" (关播放器交给 alert 按钮).
    ///   - 否则练满 3 次 → 请求一次 App Store 评分.
    /// 两个里程碑错开 (2 / 3 次) + 各自全生命周期一次, 不会同一场训练撞车.
    private func closeAndMaybeReview() {
        if data.shouldOfferReminderPrompt() {
            showReminderOffer = true
            return
        }
        if data.shouldOfferReview() { requestReview() }
        onClose()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: animationFinished)) { context in
            let elapsed = animationFinished ? celebration.duration : didCelebrate ? max(0, context.date.timeIntervalSince(celebrationStarted)) : -1
            let frame = celebration.frame(at: elapsed, reducedMotion: reduceMotion)
            ZStack {
                MasoColor.background.ignoresSafeArea()
                if didCelebrate && !reduceMotion {
                    WorkoutCelebrationConfetti(configuration: celebration, elapsed: elapsed).ignoresSafeArea()
                }
                VStack(spacing: 20) {
                    Spacer()
                    WorkoutCelebrationSymbol(configuration: celebration, frame: frame)
                    Text("Workout complete")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .opacity(frame.titleOpacity)
                    Text(planName).font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(frame.titleOpacity)
                    Spacer()
                    VStack(spacing: 8) {
                        WorkoutReportButton(title: "Workout report", keepsIntrinsicWidth: true) { showWorkoutReport = true }
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("workout.completed.report")
                        Button {
                            if onSavePlan != nil && !planSaved { showSavePrompt = true }
                            else { closeAndMaybeReview() }
                        } label: {
                            TrainingCardActionLabel(title: "Exit", icon: "", accent: MasoColor.text,
                                                    prominent: false, fillsWidth: true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workout.completed.exit")
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.vertical, MasoMetrics.cardPadding)
            }
        }
            .task {
                guard !didCelebrate else { return }
                celebrationFeedback.prepare(celebration)
                celebrationStarted = Date()
                didCelebrate = true
                do {
                    try await Task.sleep(for: .seconds(celebration.anchor))
                    try Task.checkCancellation()
                    if scenePhase == .active { celebrationFeedback.play() }
                    try await Task.sleep(for: .seconds(max(0, celebration.duration - celebration.anchor)))
                    animationFinished = true
                } catch { animationFinished = true }
            }
            .onDisappear { celebrationFeedback.cancel() }
            .onChange(of: showWorkoutReport) { _, presented in if presented { celebrationFeedback.cancel() } }
            .sheet(isPresented: $showWorkoutReport) {
                AppNavigationStack {
                    WorkoutSessionReportScreen(
                        records: sessionRecords,
                        workoutName: planName,
                        presentation: .finish,
                        onSavePlan: onSavePlan,
                        onExit: {
                            showWorkoutReport = false
                            onClose()
                        }
                    )
                }
                .frame(maxWidth: ProcessInfo.processInfo.environment["MASO_TEST_NARROW"] == "1" ? 320 : .infinity)
                .sessionReportSheetChrome()
            }
            // 自由训练 (onSavePlan 非 nil): 分享页关掉后问一次是否存为 plan.
            .alert(NSLocalizedString("Save as plan?", comment: ""), isPresented: $showSavePrompt) {
                Button(NSLocalizedString("Save as plan", comment: "")) {
                    onSavePlan?()
                    planSaved = true
                    closeAndMaybeReview()
                }
                Button(NSLocalizedString("Don't Save", comment: ""), role: .cancel) { onClose() }
            } message: {
                Text(NSLocalizedString("Keep this workout as a reusable routine.", comment: ""))
            }
            // 召回提醒软提示 — 召回提醒默认开; 练满 2 次的正向时刻请求一次系统通知权限 (软提示先行, 提升授权率).
            // 同意 → 申请权限 (拒则弹回关) + 排程; "Not now" → 明确婉拒 → 关掉开关. 全本地通知, 跟"不打扰"品牌一致.
            .alert(NSLocalizedString("Want a nudge when you're recovered?", comment: ""), isPresented: $showReminderOffer) {
                Button(NSLocalizedString("Turn on reminders", comment: "")) {
                    Task { @MainActor in
                        let granted = await WorkoutReminderScheduler.shared.requestAuthorization()
                        data.settings.workoutRemindersEnabled = granted
                        if granted { data.rescheduleWorkoutReminders() }
                        onClose()
                    }
                }
                Button(NSLocalizedString("Not now", comment: ""), role: .cancel) {
                    data.settings.workoutRemindersEnabled = false   // 默认开 → 用户在此明确婉拒即关掉
                    data.rescheduleWorkoutReminders()               // 清掉可能已排的待发提醒
                    onClose()
                }
            } message: {
                Text(NSLocalizedString("Masso can remind you to train once your muscles have recovered — all on your device. You can change this anytime in Settings.", comment: ""))
            }
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

    /// 最近练过 recency 热图 — 绿=这场/最近练到 (跟恢复热图的绿=可练不冲突: 全 app 绿恒等于"练").
    private var muscleStyleClosure: (MuscleGroup) -> (Color, Double)? {
        let lastMap = muscleLastTrainedMap()
        return { m in
            guard let last = lastMap[m] else { return nil }
            let days = Date().timeIntervalSince(last) / 86400
            if days < 1 { return (MasoColor.accent, 1.0) }
            if days < 2 { return (MasoColor.accent, 0.6) }
            if days < 3 { return (MasoColor.accent, 0.3) }
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
struct EditCurrentStepSheet: View {
    let exercise: Exercise
    var initialParameterStep: PlanStep? = nil
    var onConfirmParameters: ((Set<String>) -> Void)? = nil
    @State private var editedParameters: Set<String> = []
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
    /// R3: 全局同步开时, 改动会写进所有含该动作的计划 — 底部提示据此说真话 (否则文案与行为矛盾).
    var syncsGlobally: Bool = false

    // Initial optionals retain unknown values on an untouched Save. Zero load is valid.
    // Numeric state backs native fields; the edited set controls explicit confirmation.
    @State private var sets: Int
    @State private var reps: Int
    @State private var weight: Double
    @State private var duration: Int
    /// #3: "每组不同重量/次数" 开关 + 逐组值 (0 = 空, save 时映射 nil). 长度跟 sets 同步.
    @State private var perSetEnabled: Bool
    @State private var perSetReps: [Int]
    @State private var perSetWeights: [Double]
    /// A single request is queued before dismiss; the owning sheet's onDismiss presents the picker.
    /// onReplace 让 parent 弹 picker. 一次性 flag 防双击.
    @State private var replaceRequested: Bool = false
    @State private var progressionPresented = false
    @Environment(\.dismiss) private var dismiss

    init(
        exercise: Exercise,
        initialSets: Int,
        initialReps: Int?,
        initialWeight: Double?,
        initialDuration: Int?,
        initialSetReps: [Int?]? = nil,
        initialSetWeights: [Double?]? = nil,
        initialParameterStep: PlanStep? = nil,
        onConfirmParameters: ((Set<String>) -> Void)? = nil,
        onSave: @escaping (Int, Int?, Double?, Int?, [Int?]?, [Double?]?) -> Void,
        onReplace: (() -> Void)? = nil,
        syncsGlobally: Bool = false
    ) {
        self.exercise = exercise
        self.initialParameterStep = initialParameterStep
        self.onConfirmParameters = onConfirmParameters
        self.syncsGlobally = syncsGlobally
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

    private func input<T>(_ field: String, _ binding: Binding<T>) -> Binding<T> {
        Binding(get: { binding.wrappedValue }, set: { editedParameters.insert(field); binding.wrappedValue = $0 })
    }
    private var unsupportedCrossWeight: Bool {
        guard let suggestion = initialParameterStep?.parameterSuggestions?["weight"] else { return false }
        if suggestion.source == .personalHistory {
            return PersonalExerciseLoadReference.ruleID(reps: reps) == nil
                || suggestion.ruleID != PersonalExerciseLoadReference.ruleID(reps: reps)
        }
        return suggestion.source == .crossExercise && !(6...12).contains(reps)
    }
    private func suggested(_ field: String) -> Bool {
        if field == "weight", unsupportedCrossWeight { return false }
        return !editedParameters.contains(field) && initialParameterStep?.isSuggested(field) == true
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
        AppNavigationStack {
            ZStack {
                // 底色铺满整个 navigation 容器, 跟 Settings / MusclesPickerSheet 一致.
                // ignoresSafeArea 让 home indicator 区也是 MasoColor.background, 不露 sheet 默认浅灰底.
                MasoColor.background.ignoresSafeArea()
                Form {
                    // The entire native row requests replacement once, then returns to training after selection.
                    if onReplace != nil {
                        Section {
                            Button(action: {
                                guard !replaceRequested else { return }
                                replaceRequested = true
                                onReplace?()
                                Haptics.tap()
                                dismiss()
                            }) {
                                Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                        .listRowBackground(MasoColor.surface)
                    }

                    // Sets — 始终显示. 用 Stepper 风格 — label + 大字号 value, 自带 -/+
                    Section {
                        intStepperRow(field: "sets", label: "Sets", value: input("sets", $sets), range: 1...30)
                    }
                    .listRowBackground(MasoColor.surface)

                    if showsRepsWeight {
                        Section {
                            Toggle(isOn: $perSetEnabled.animation(.easeOut(duration: 0.2))) {
                                Text("Different per set")
                                    .foregroundStyle(MasoColor.text)
                            }
                            .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                        }
                        .listRowBackground(MasoColor.surface)

                        if perSetEnabled {
                            Section {
                                ForEach(perSetReps.indices, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Set \(i + 1)").font(.subheadline).foregroundStyle(.secondary)
                                        intStepperRow(field: "reps", label: "Reps", value: Binding(
                                            get: { perSetReps.indices.contains(i) ? perSetReps[i] : reps },
                                            set: { if perSetReps.indices.contains(i) { editedParameters.insert("reps"); perSetReps[i] = $0 } }
                                        ), range: 1...50)
                                        weightStepperRow(label: ExerciseWeightReference.perDumbbell(exercise) ? "Weight per dumbbell" : "Weight", value: Binding(
                                            get: { perSetWeights.indices.contains(i) ? perSetWeights[i] : weight },
                                            set: { if perSetWeights.indices.contains(i) { editedParameters.insert("weight"); perSetWeights[i] = $0 } }
                                        ))
                                    }
                                }
                            } header: {
                                Text("Reps × weight per set")
                            }
                            .listRowBackground(MasoColor.surface)
                        } else {
                            Section {
                                intStepperRow(field: "reps", label: "Reps", value: input("reps", $reps), range: 1...50)
                                weightStepperRow(label: ExerciseWeightReference.perDumbbell(exercise) ? "Weight per dumbbell" : "Weight", value: input("weight", $weight))
                            }
                            .listRowBackground(MasoColor.surface)
                        }
                    }

                    if showsDuration {
                        Section {
                            intStepperRow(field: "duration", label: "Duration", value: input("duration", $duration), range: 5...600, step: 5, suffix: "s")
                        }
                        .listRowBackground(MasoColor.surface)
                    }

                    if ExerciseWeightReference.expectsLoad(exercise) {
                        Section {
                            Button("Weight progression") { progressionPresented = true }
                                .accessibilityIdentifier("workout.progression.open")
                        }
                        .listRowBackground(MasoColor.surface)
                    }

                    // 提示: 文案随全局同步开关说真话 (同步开=改动写进所有计划; 关=仅本次, 永久保存去编辑计划)
                    Section {
                        Text(syncsGlobally
                             ? "Changes update this exercise across all your routines."
                             : "Changes apply to this session only. To save permanently, edit the plan.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .listRowBackground(MasoColor.surface)
                }
                // Form 自带 systemGroupedBackground 浅灰底 — 隐掉, 走我们 ZStack 的 MasoColor.background
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("workout.parameters.form")
                // sets 改变 → 同步逐组数组长度 (补/裁), 防 ForEach 越界 + 让新组继承上一组的值.
                .onChange(of: sets) { _, n in resizePerSet(to: max(1, n)) }
                .onChange(of: perSetEnabled) { _, _ in editedParameters.formUnion(["weight", "reps"]) }
            }
            .sheet(isPresented: $progressionPresented) {
                ExerciseLoadProgressionSheet(exercise: exercise, currentWeight: editedParameters.contains("weight") ? weight : initialWeight,
                    targetReps: reps, requiredSets: sets, allowsSuggestions: !perSetEnabled) { value in
                        weight = value; editedParameters.insert("weight")
                    }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            // 顶部 nav bar 同色, 否则会有一道 system tint 横条
            .tint(MasoColor.text)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("workout.parameters.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Untouched missing fields stay unknown; explicit zero load stays zero.
                        // Only edited fields become user-confirmed targets.
                        onConfirmParameters?(editedParameters)
                        let d: Int? = showsDuration ? (editedParameters.contains("duration") ? duration : initialDuration) : nil
                        if perSetEnabled && showsRepsWeight {
                            let n = max(1, sets)
                            let setR: [Int?] = (0..<n).map { i in
                                (i < perSetReps.count && perSetReps[i] > 0) ? perSetReps[i] : nil
                            }
                            let setW: [Double?] = (0..<n).map { i in
                                (i < perSetWeights.count) ? perSetWeights[i] : nil
                            }
                            // 统一值用第一组当 fallback (expandPlan 在数组缺项时回退到它).
                            let r0 = perSetReps.first.flatMap { $0 > 0 ? $0 : nil }
                            let w0 = perSetWeights.first
                            onSave(n,
                                   editedParameters.contains("reps") ? r0 : initialReps,
                                   editedParameters.contains("weight") ? w0 : initialWeight, d,
                                   editedParameters.contains("reps") ? setR : initialSetReps,
                                   editedParameters.contains("weight") ? setW : initialSetWeights)
                        } else {
                            let r: Int? = editedParameters.contains("reps") ? reps : initialReps
                            let w: Double? = !editedParameters.contains("weight") && initialWeight == nil ? nil : weight
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
    }

    /// 把逐组数组补/裁到 n 组 — 补的项继承末组(或统一)值, 多的截掉. sets 变化时调.
    private func resizePerSet(to n: Int) {
        while perSetReps.count < n { perSetReps.append(perSetReps.last ?? reps) }
        while perSetWeights.count < n { perSetWeights.append(perSetWeights.last ?? weight) }
        if perSetReps.count > n { perSetReps.removeLast(perSetReps.count - n) }
        if perSetWeights.count > n { perSetWeights.removeLast(perSetWeights.count - n) }
    }

    /// Shared native numeric fields; per-set and session-only persistence stays here.
    @ViewBuilder
    private func intStepperRow(field: String, label: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, suffix: String? = nil) -> some View {
        NativeIntegerParameterRow(title: label, value: value, range: range, step: step, suffix: suffix ?? "", isSuggested: suggested(field))
    }

    /// 重量字段行 — 按用户单位 (kg/lb) 展示+编辑, 存储 canonical kg.
    @ViewBuilder
    private func weightStepperRow(label: LocalizedStringKey, value: Binding<Double>) -> some View {
        NativeWeightParameterRow(title: label, kilograms: value, isSuggested: suggested("weight"), isUnknown: !editedParameters.contains("weight") && (initialWeight == nil || unsupportedCrossWeight) && !perSetEnabled, allowsCalibration: ExerciseWeightReference.expectsLoad(exercise))
        if suggested("weight"), !perSetEnabled {
            CrossExerciseSuggestionBasis(suggestion: initialParameterStep?.parameterSuggestions?["weight"])
        }
    }

}

// MARK: - 修正刚落库的一组 (P0#5-①)

/// 休息屏"刚才: 8 × 55 kg · 调整"点开的小 sheet — 双 stepper 调 reps/weight (无重量动作调
/// reps/时长), 保存写回刚落库的那条 SetRecord (DataStore.updateSetRecord, 按 id 定位).
/// 跟 EditCurrentStepSheet 的区别: 这里改的是"已经练完的事实", 不动 plan / segments /
/// 后续组的目标值 — 力竭没做满 8 次, 记录改回 6, 下一组目标仍是 8.
struct AdjustLastSetSheet: View {
    let record: SetRecord
    /// onSave(reps, weight, duration) — caller 写回 DataStore.
    let onSave: (Int?, Double?, Int?, Bool) -> Void
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    // 0 = 清空字段 (save 时映射回 nil), 跟 EditCurrentStepSheet 同约定.
    @State private var reps: Int
    @State private var weight: Double
    @State private var duration: Int
    @State private var confirmedSixRM: Bool

    init(record: SetRecord, onSave: @escaping (Int?, Double?, Int?, Bool) -> Void) {
        self.record = record
        self.onSave = onSave
        self._reps = State(initialValue: record.reps ?? 0)
        self._weight = State(initialValue: record.weight ?? 0)
        self._duration = State(initialValue: record.duration ?? 0)
        self._confirmedSixRM = State(initialValue: record.hasConfirmedSixRM)
    }

    /// 字段按记录本来有什么显示什么 — 力量组有 reps(+weight), 计时段只有 duration.
    /// "无重量动作只调 reps/时长": weight 字段只在记录带 weight (含 0 自重, 可补配重) 时出现.
    private var showsReps: Bool { record.reps != nil }
    private var showsWeight: Bool { record.weight != nil }
    private var showsDuration: Bool { record.duration != nil }

    var body: some View {
        AppNavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                Form {
                    Section {
                        if showsReps { NativeIntegerParameterRow(title: "Reps", value: $reps, range: 0...50) }
                        if showsWeight {
                            NativeWeightParameterRow(title: data.exById[record.exerciseId].map(ExerciseWeightReference.perDumbbell) == true ? "Weight per dumbbell" : "Weight", kilograms: $weight)
                        }
                        if showsDuration { NativeIntegerParameterRow(title: "Duration", value: $duration, range: 0...600, step: 5, suffix: "s") }
                    }

                    if record.exerciseId == CrossExerciseLoadReference.anchorID {
                        Section {
                            Toggle("Confirmed bench press 6RM", isOn: $confirmedSixRM)
                                .toggleStyle(.switch)
                                .tint(MasoColor.toggleAccent)
                                .disabled(reps != 6 || weight <= 0 || !weight.isFinite)
                                .accessibilityIdentifier("workout.record.confirm-six-rm")
                        } footer: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mark only an existing set: six full-range reps, no assistance or momentum, about 2 seconds up and down, with no seventh clean rep possible. You should already be familiar with the lift. No extra maximum test is needed.")
                                if reps != 6 || weight <= 0 {
                                    Text("Six completed reps and a positive weight are required.")
                                }
                                Text("Masso currently limits this estimate to men aged 18–30, a confirmed 30–70 kg reference from the last 30 days, and 6–12 target reps.")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Text("Correct this set and update related weight references.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .listRowBackground(MasoColor.surface)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: reps) { _, _ in confirmedSixRM = false }
                .onChange(of: weight) { _, _ in confirmedSixRM = false }
            }
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)


            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // 没显示的字段原样带回 (不误清); 显示的字段 0 → nil (清空语义),
                        // 例外: weight 保持 0 也是合法值 (自重组), 不映射 nil — 跟落库语义一致.
                        let r: Int? = showsReps ? (reps > 0 ? reps : nil) : record.reps
                        let w: Double? = showsWeight ? weight : record.weight
                        let d: Int? = showsDuration ? (duration > 0 ? duration : nil) : record.duration
                        onSave(r, w, d, confirmedSixRM)
                        Haptics.tap()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationBackground(MasoColor.background)
    }

}


private struct OpenWorkoutCompletionView: View {
    let durationMinutes: Int
    let setCount: Int
    let exerciseCount: Int
    let onDone: (String?) -> Void
    @State private var saveRoutine = true
    @State private var name = NSLocalizedString("Workout", comment: "") + " · " + Date().formatted(.dateTime.month().day())

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(MasoColor.accent)
                Text("Workout complete")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 52)

            HStack(spacing: 0) {
                completionStat(value: "\(exerciseCount)", label: "Exercises")
                statDivider
                completionStat(value: "\(setCount)", label: "Sets")
                statDivider
                completionStat(value: "\(durationMinutes)m", label: "Duration")
            }
            .padding(.vertical, 20)
            .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 32)

            if setCount > 0 {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Save as a routine", isOn: $saveRoutine)
                        .font(.system(size: 16, weight: .semibold))
                        .toggleStyle(.switch).tint(MasoColor.toggleAccent)

                    if saveRoutine {
                        TextField("Routine name", text: $name)
                            .font(.system(size: 16))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(MasoColor.surfaceHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(20)
                .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 16)
            }

            Spacer(minLength: 24)

            Button("Done") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                onDone(saveRoutine && setCount > 0 ? trimmed : nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(MasoColor.accent)
            .foregroundStyle(.black)
            .font(.system(size: 17, weight: .semibold))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(saveRoutine && setCount > 0 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MasoColor.background.ignoresSafeArea())
    }

    private var statDivider: some View {
        Rectangle()
            .fill(MasoColor.borderSoft)
            .frame(width: 1, height: 34)
    }

    private func completionStat(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(MasoColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}


private enum PlayerExerciseInfoMetrics {
    static let spacing: CGFloat = 16
    static let parameterHeight: CGFloat = 84
}

/// Fixed slots prevent optional history/status text and rest transitions from moving the rows.
private struct PlayerExerciseInfoLayout<Heading: View, Status: View, Parameters: View>: View {
    let compact: Bool
    @ViewBuilder let heading: () -> Heading
    @ViewBuilder let status: () -> Status
    @ViewBuilder let parameters: () -> Parameters
    @ScaledMetric(relativeTo: .title2) private var titleHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var statusHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : PlayerExerciseInfoMetrics.spacing) {
            heading().frame(height: titleHeight)
                .anchorPreference(key: PlayerLayoutBoundsKey.self, value: .bounds) { ["heading": $0] }
            if !compact {
                parameters().frame(height: PlayerExerciseInfoMetrics.parameterHeight)
                    .anchorPreference(key: PlayerLayoutBoundsKey.self, value: .bounds) { ["parameters": $0] }
            }
        }
        .overlay(alignment: .topLeading) {
            if !compact {
                status().frame(maxWidth: .infinity, alignment: .leading).frame(height: statusHeight)
                    .offset(y: -(statusHeight + 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MasoMetrics.cardPadding)
        .transaction { $0.animation = nil }
    }
}

/// Split balanced ASCII/full-width parentheses without changing the localized source name.
struct PlayerExerciseTitleParts {
    let title: String
    let subtitle: String?

    init(_ name: String) {
        let pattern = #"\((?:[^()]|\([^()]*\))*\)|（(?:[^（）]|（[^（）]*）)*）"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(name.startIndex..., in: name)
        let matches = regex.matches(in: name, range: range)
        let details = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: name) else { return nil }
            let text = name[range].dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let main = regex.stringByReplacingMatches(in: name, range: range, withTemplate: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Parenthetical-only custom names still need a meaningful primary label.
        title = main.isEmpty ? name : main
        subtitle = main.isEmpty || details.isEmpty ? nil : details.joined(separator: " · ")
    }
}

/// Presentation and its complete data are one state, so the first sheet frame
/// cannot capture an independently initialized empty array.
private struct PlayerVariantPickerSnapshot: Identifiable {
    let id = UUID()
    let rows: [Exercise]
    let selectedID: String
    let sameTarget: [Exercise]

    init(current: Exercise, base: Exercise, candidates: [Exercise], library: [Exercise]) {
        selectedID = current.id
        rows = ExerciseGrouping.variantMenuRows(defaultVersion: base, candidates: candidates, current: current)
        let shown = Set(rows.map(\.id))
        // Match the same specific primary target; broad section matches can imply
        // different training emphasis (for example upper vs lower chest).
        let targets = Set(current.primaryMuscles.filter { $0 != .fullBody })
        sameTarget = library.filter { item in
            !shown.contains(item.id) && !targets.isDisjoint(with: item.primaryMuscles)
        }
    }
}

/// Shared muscle, title/subtitle and variant control for current/rest-next scenes.
private struct PlayerExerciseHeading: View {
    @State private var variantPicker: PlayerVariantPickerSnapshot?
    @State private var pendingOtherExercise = false
    @State private var pendingVariant: Exercise?
    @State private var expandedTargetGroup: String?
    @Environment(DataStore.self) private var data
    let exercise: Exercise
    var compact = false
    let onDetail: () -> Void
    var onSelectVariant: ((Exercise) -> Void)? = nil
    var onRequestReplace: (() -> Void)? = nil

    private var versions: [Exercise] {
        ExerciseSelectionPolicy.shared.variants(for: exercise, in: data.userLibrary, settings: data.settings)
    }
    private var base: Exercise {
        ExerciseSelectionPolicy.shared.defaultVersion(for: exercise, in: data.userLibrary, settings: data.settings)
    }

    var body: some View {
        let parts = PlayerExerciseTitleParts(exercise.displayName)
        HStack(spacing: 12) {
            BodyHint(muscles: exercise.muscleGroups, height: compact ? 36 : 40,
                     region: detectBodyRegion(exercise.muscleGroups), panelSpacing: 2)
                .frame(width: 70, height: 44)
                .accessibilityIdentifier("workout.muscles")
            Button(action: onDetail) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parts.title)
                        .font(compact ? .headline : .title2.weight(.bold))
                        .lineLimit(1).truncationMode(.tail)
                        .accessibilityIdentifier("workout.exercise.title")
                    if let subtitle = parts.subtitle {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(MasoColor.textDim)
                            .lineLimit(1).truncationMode(.tail)
                            .accessibilityIdentifier("workout.exercise.subtitle")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(exercise.displayName))
            .accessibilityHint("Exercise details")
            .accessibilityIdentifier("workout.current.info")
            Button {
                variantPicker = PlayerVariantPickerSnapshot(current: exercise, base: base, candidates: versions, library: data.userLibrary)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .sheet(item: $variantPicker, onDismiss: {
                if pendingOtherExercise { pendingOtherExercise = false; onRequestReplace?() }
                if let variant = pendingVariant { pendingVariant = nil; onSelectVariant?(variant) }
            }) { snapshot in
                AppNavigationStack {
                    List {
                        if !snapshot.rows.isEmpty {
                            Section("Variants") {
                                ForEach(snapshot.rows) { variantButton($0, selectedID: snapshot.selectedID) }
                            }
                        }
                        if !snapshot.sameTarget.isEmpty {
                            Section("Same target muscles") {
                                ForEach(ExerciseGrouping.group(snapshot.sameTarget)) { group in
                                    targetGroupRow(group.canonical, group: group, isVariant: false, selectedID: snapshot.selectedID)
                                    if !group.isSingleton && expandedTargetGroup == group.id {
                                        groupedVariantSections(for: group, onCollapse: { expandedTargetGroup = nil }) { variant in
                                            targetGroupRow(variant, group: group, isVariant: true, selectedID: snapshot.selectedID)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Switch exercise").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { variantPicker = nil }
                                .labelStyle(.iconOnly).accessibilityIdentifier("workout.variant.done")
                        }
                        if onRequestReplace != nil {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Replace") { pendingOtherExercise = true; variantPicker = nil }
                                    .accessibilityIdentifier("workout.variant.replace-other")
                            }
                        }
                    }
                }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                    .accessibilityIdentifier("workout.variant.list")
            }
            .nativeGlassButtonStyle()
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .frame(minWidth: 44, minHeight: 44)
            .offset(x: 2)
            .accessibilityLabel("Variants")
            .accessibilityIdentifier("workout.variants")
        }
        .foregroundStyle(MasoColor.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetGroupRow(_ item: Exercise, group: ExerciseGroup, isVariant: Bool, selectedID: String) -> some View {
        GroupedExerciseRow(exercise: item, isVariant: isVariant, group: group,
                           isExpanded: expandedTargetGroup == group.id, showDisclosure: !group.isSingleton,
                           showVariantCategoryLabel: false, trailing: { EmptyView() },
                           onTap: { if item.id != selectedID { pendingVariant = item }; variantPicker = nil },
                           onToggleExpand: { withAnimation(.easeOut(duration: 0.2)) {
                               expandedTargetGroup = expandedTargetGroup == group.id ? nil : group.id
                           } })
    }

    private func variantButton(_ variant: Exercise, selectedID: String) -> some View {
        Button {
            if variant.id != selectedID { pendingVariant = variant }
            variantPicker = nil
        } label: {
            HStack(spacing: 12) {
                ExerciseImage(category: variant.category, exerciseID: variant.id,
                              imageFolder: variant.imageFolder, photoURL: variant.photoURL,
                              customImageData: variant.customImageData, cornerRadius: 8, size: 48, animated: false)
                    .accessibilityHidden(true)
                Text(variant.displayName).foregroundStyle(MasoColor.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if variant.id == selectedID {
                    Image(systemName: "checkmark").foregroundStyle(MasoColor.accent).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 2).contentShape(Rectangle())
        }
        .accessibilityLabel(Text(variant.displayName))
        .accessibilityAddTraits(variant.id == selectedID ? .isSelected : [])
        .accessibilityIdentifier("workout.variant.\(variant.id)")
    }


}

private struct PlayerParameterValue: View {
    let value: String
    let label: String
    var parameter: WorkoutParameter? = nil
    var onAdjust: ((WorkoutParameter, Int) -> Void)? = nil
    var isSuggested = false
    var needsCalibration = false
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 0) {
                if let parameter, let onAdjust { adjustmentButton(parameter, direction: -1, action: onAdjust) }
                MetricValueText(value: value,
                                numeratorColor: isSuggested && parameter != .sets ? MasoColor.parameterSuggestion : MasoColor.text,
                                denominatorColor: isSuggested && parameter == .sets ? MasoColor.parameterSuggestion : MasoColor.textDim,
                                numeratorWeight: .bold)
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity).allowsHitTesting(false)
                if let parameter, let onAdjust { adjustmentButton(parameter, direction: 1, action: onAdjust) }
            }
            Text(needsCalibration ? NSLocalizedString("First-use calibration", comment: "unknown weight") : (isSuggested ? label + " · " + NSLocalizedString("Suggested", comment: "parameter source") : label))
                .accessibilityIdentifier(needsCalibration ? "workout.weight.calibration" : isSuggested ? "workout.suggested.\(parameter?.rawValue ?? "value")" : "workout.explicit.\(parameter?.rawValue ?? "value")")
                .lineLimit(needsCalibration ? 2 : 1).minimumScaleFactor(0.6)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(MasoColor.text.opacity(0.6)).allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
        .frame(maxWidth: .infinity)

    }

    private func adjustmentButton(_ parameter: WorkoutParameter, direction: Int,
                                  action: @escaping (WorkoutParameter, Int) -> Void) -> some View {
        Button { action(parameter, direction) } label: {
            Image(systemName: direction > 0 ? "plus" : "minus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MasoColor.text.opacity(0.65))
                .frame(width: 32, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label) + Text(direction > 0 ? " +" : " −"))
        .accessibilityIdentifier("workout.parameter.\(parameter.rawValue).\(direction > 0 ? "increase" : "decrease")")
    }
}

private struct PlayerParameterDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.14)).frame(width: 0.5, height: 32)
            .allowsHitTesting(false)
    }
}

private struct PlayerParameterPanel<Content: View>: View {
    let title: LocalizedStringKey
    let onEdit: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .zIndex(1)
            .foregroundStyle(MasoColor.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background {
                Button(action: onEdit) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.06))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .zIndex(0)
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier("workout.current.edit")
            }
    }
}

private struct PlayerExerciseActionButton: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MasoColor.text)
                .frame(width: 32, height: 32)
                .glassCircleButtonBackground(fallback: MasoColor.background.opacity(0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(Text(title))
    }
}

private struct HeartIconBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct HeartPressInteraction: UIViewRepresentable {
    var onTap: () -> Void
    var onHold: () -> Void
    final class Coordinator: NSObject {
        var onTap: () -> Void = {}
        var onHold: () -> Void = {}
        @objc func tap(_ gesture: UITapGestureRecognizer) { if gesture.state == .recognized { onTap() } }
        @objc func hold(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { onHold() } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.55
        tap.require(toFail: hold)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onHold = onHold
    }
}

/// 心率卡片上的单圈波纹，只改画法。
/// 节拍时钟仍是 `时间 * bpm / 60 - 0.25`，与心形缩放对齐。
/// 不改 BPM、提醒阈值、`WorkoutHeartLiquid` 的颜色和最大半径。
/// 半径缓出；透明度是两端为 0 的单峰，所以循环相接时不跳，也不会叠出多圈。
/// 曲线系数是这一版的手感选择，不是约定指标。
private enum HeartRippleMotion {
    /// 波纹层刚出现时淡入的时长。只掩盖出现那一帧的跳变，不改变心跳周期。
    static let unveilDuration: TimeInterval = 0.20

    struct Sample {
        var spread: CGFloat
        var opacity: Double
        var lineWidth: CGFloat
        var blur: CGFloat
    }

    static func beatPhase(at date: Date, bpm: Int) -> Double {
        let cycle = date.timeIntervalSinceReferenceDate * Double(bpm) / 60 - 0.25
        return cycle - floor(cycle)
    }

    static func sample(phase: Double, unveil: Double) -> Sample {
        let t = min(1, max(0, phase))
        let eased = 1 - pow(1 - t, 1.6)
        let peakAt = 0.22
        let warped = t <= peakAt
            ? 0.5 * (t / peakAt)
            : 0.5 + 0.5 * ((t - peakAt) / (1 - peakAt))
        let envelope = pow(max(0, sin(.pi * warped)), 1.35)
        let u = min(1, max(0, unveil))
        let fade = u * u * (3 - 2 * u)
        return Sample(
            spread: CGFloat(eased),
            opacity: 0.46 * envelope * fade,
            lineWidth: CGFloat(2.4 * (1 - 0.38 * eased)),
            blur: CGFloat(0.15 + 0.9 * eased)
        )
    }
}

private struct HeartRippleRing<Ink: ShapeStyle>: View {
    var origin: CGRect
    var maxRadius: CGFloat
    var bpm: Int
    var color: Ink
    @State private var unveiledAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let motion = HeartRippleMotion.sample(
                phase: HeartRippleMotion.beatPhase(at: context.date, bpm: bpm),
                unveil: context.date.timeIntervalSince(unveiledAt) / HeartRippleMotion.unveilDuration
            )
            let diameter = max(CGFloat(0), maxRadius * motion.spread * 2)
            Circle()
                .stroke(color, lineWidth: motion.lineWidth)
                .frame(width: diameter, height: diameter)
                .blur(radius: motion.blur)
                .opacity(motion.opacity)
                .position(x: origin.midX, y: origin.midY)
                .transaction { $0.disablesAnimations = true }
        }
        .transaction { $0.disablesAnimations = true }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct WorkoutHeartRateButton: View {
    @Environment(TrainingSessionStore.self) private var store
    @Environment(DataStore.self) private var data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsPresented = false
    @State private var expanded = false
    @State private var expandedByWarning = false
    @State private var now = Date()

    private func toggleCard() {
        expanded.toggle()
        expandedByWarning = false
        data.settings.workoutHeartRateShowCard = expanded
        data.save()
        Haptics.tap()
    }

    private func heartContent(bpm: Int?) -> some View {
        Group {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { context in
                            let time = context.date.timeIntervalSinceReferenceDate
                            let beat = bpm.map { reduceMotion ? 1.0 : 1.0 + 0.16 * pow(max(0, sin(time * Double($0) * .pi / 30)), 8) } ?? 1
                            Image(systemName: "heart.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.red).scaleEffect(beat)
                                .anchorPreference(key: HeartIconBoundsKey.self, value: .bounds) { $0 }
                        }.fixedSize()
                        Text("Heart rate").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(bpm.map { $0.formatted(.number.locale(LanguageManager.currentLocale)) } ?? "—")
                            .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                        Text("bpm").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 3)
                .padding(16).contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                HStack(spacing: 5) {
                    Image(systemName: store.heartRate.warningPending ? "heart.fill" : "heart")
                        .foregroundStyle(bpm == nil ? MasoColor.textDim : .red)
                    Text(bpm.map { $0.formatted(.number.locale(LanguageManager.currentLocale)) } ?? "—").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold)).scaleEffect(0.8).padding(.horizontal, 12).frame(minHeight: 48)
            }
        }
    }

    @ViewBuilder private func heartBackground() -> some View {
        if expanded {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack {
                if #available(iOS 26.0, *) { shape.fill(.clear).glassEffect(.regular, in: shape) }
                else { shape.fill(.ultraThinMaterial).overlay(shape.fill(.black.opacity(0.25))) }

            }.clipShape(shape).allowsHitTesting(false)
        } else {
            Capsule().fill(.clear).glassCapsuleButtonBackground(fallback: MasoColor.background.opacity(0.6))
        }
    }

    private func heartControl(bpm: Int?) -> some View {
        let progress = WorkoutHeartLiquid.progress(bpm: bpm, limit: store.heartRate.reminderLimit)
        let value = (bpm.map { $0.formatted(.number.locale(LanguageManager.currentLocale)) } ?? "—") +
            (store.heartRate.warningPending ? ", " + NSLocalizedString("Above your reminder limit", comment: "") : "")
        return Button { settingsPresented = true } label: { heartContent(bpm: bpm) }
            .buttonStyle(.plain)
            .frame(width: expanded ? 176 : nil, height: expanded ? 102 : 48)
            .background { heartBackground() }
            .overlayPreferenceValue(HeartIconBoundsKey.self) { anchor in
                GeometryReader { geometry in
                    if expanded, scenePhase == .active, !settingsPresented, !reduceMotion,
                       let anchor, let bpm, let progress {
                        let origin = geometry[anchor]
                        let extent = max(origin.midX, geometry.size.width - origin.midX)
                        // 最大半径仍是 extent * (0.25 + 0.75 * progress)。显式转换只消掉 CGFloat/Double，不改映射。
                        let maxRadius = extent * CGFloat(0.25 + 0.75 * Double(progress))
                        HeartRippleRing(
                            origin: origin,
                            maxRadius: maxRadius,
                            bpm: bpm,
                            color: WorkoutHeartLiquid.color(progress: progress)
                        )
                    }
                }.allowsHitTesting(false)
            }
            .overlay {
                if !expanded && store.heartRate.warningPending {
                    Capsule().stroke(Color.red.opacity(0.9), lineWidth: 1.5).allowsHitTesting(false)
                }
            }
            .overlay { HeartPressInteraction(onTap: { settingsPresented = true }, onHold: toggleCard).accessibilityHidden(true) }
            .accessibilityAction(named: Text(LocalizedStringKey(expanded ? "Collapse heart rate card" : "Expand heart rate card"))) { toggleCard() }
            .accessibilityLabel("Heart rate")
            .accessibilityHint("Heart rate settings")
            .accessibilityValue(value)
            .accessibilityIdentifier(expanded ? "workout.heart.warning" : "workout.heart-rate")
    }

    var body: some View {
        heartControl(bpm: store.heartRate.freshBPM(at: now))
        .onAppear {
            expanded = data.settings.workoutHeartRateShowCard == true
            if store.heartRate.warningPending { expanded = true; expandedByWarning = true }
        }
        .onChange(of: data.settings.workoutHeartRateShowCard) { _, value in
            expanded = value == true
            expandedByWarning = false
        }
        .onChange(of: store.heartRate.warningPending) { _, pending in
            if pending && !expanded { expanded = true; expandedByWarning = true }
            else if !pending && expandedByWarning { expanded = data.settings.workoutHeartRateShowCard == true; expandedByWarning = false }
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(isPresented: $settingsPresented) { WorkoutHeartRateSettingsSheet() }
    }
}

struct WorkoutHeartRateSettingsSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var limitText = ""
    @State private var usesRecommendation = true
    @State private var showCard = false
    @State private var heartAssist = false
    @State private var errorText: String?
    @State private var connecting = false
    @State private var deleteHistory = false

    private var recommendation: WorkoutHeartRecommendation.Result {
        WorkoutHeartRecommendation.calculate(samples: WorkoutHeartLocalStore.shared.samples, age: data.settings.age, excluding: store.workoutSessionID)
    }

    private var recommendationExplanation: LocalizedStringKey {
        switch recommendation.basis {
        case .history: return "Based on your recent workout heart rates and age when available."
        case .age: return "Estimated from your age; it will adjust as workout data becomes available."
        case .fallback: return "Starting estimate until your age or workout heart-rate history is available."
        }
    }

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Toggle("Show heart rate card", isOn: $showCard)
                        .tint(MasoColor.toggleAccent)
                        .accessibilityIdentifier("workout.heart.show-card")
                    Toggle("Automatic heart rate control", isOn: $heartAssist)
                        .tint(MasoColor.toggleAccent)
                        .accessibilityIdentifier("workout.heart.assist")
                    Text("Experimental: heart rate changes can automatically log a set or skip rest. Readings may be delayed or incorrect; use Undo if needed.")
                        .font(.footnote).foregroundStyle(MasoColor.textDim)
                }
                Section {
                    Toggle("Read workout heart rate", isOn: Binding(get: { data.settings.workoutHeartRateEnabled == true }, set: { enabled in
                        if !enabled { data.settings.workoutHeartRateEnabled = false; store.heartRate.stop(); return }
                        connecting = true
                        Task {
                            do {
                                try await store.heartRate.requestAccess()
                                data.settings.workoutHeartRateEnabled = true
                                bindMonitor()
                                await store.heartRate.startWatchWorkoutIfNeeded()
                            }
                            catch { errorText = NSLocalizedString("Couldn't connect to Apple Health.", comment: "") }
                            connecting = false
                        }
                    })).toggleStyle(.switch).tint(MasoColor.toggleAccent).disabled(connecting)
                        .accessibilityIdentifier("workout.heart.enable")
                    if data.settings.workoutHeartRateEnabled == true {
                        Button("Open Masso on Apple Watch") {
                            Task {
                                do { try await store.heartRate.openWatchWorkout() }
                                catch { errorText = NSLocalizedString("Open Masso on your paired Apple Watch to read live heart rate.", comment: "") }
                            }
                        }
                    }
                } footer: {
                    Text("Live readings need a heart-rate sensor. No reading means no heart-rate warning.")
                    Text("If access was denied, update Masso's permissions in the Health app.")
                }
                Section {
                    HStack {
                        Text("Reminder limit")
                        Spacer()
                        TextField("bpm", text: Binding(get: { limitText }, set: { limitText = $0; usesRecommendation = false }))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110).accessibilityIdentifier("workout.heart.limit")
                    }
                    LabeledContent("Recommended", value: "\(recommendation.bpm.formatted(.number.locale(LanguageManager.currentLocale))) bpm")
                    if usesRecommendation {
                        Text("Using recommendation").font(.footnote).foregroundStyle(MasoColor.textDim)
                    } else {
                        Button("Reset to recommendation") {
                            usesRecommendation = true
                            limitText = recommendation.bpm.formatted(.number.locale(LanguageManager.currentLocale))
                            errorText = nil
                        }.accessibilityIdentifier("workout.heart.reset")
                    }
                    if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }
                } footer: {
                    Text(recommendationExplanation)
                    Text("Recommendations are estimates, not a medical safety limit. Medication and health conditions can affect heart rate.")
                    Text("Over your limit for 15 seconds: pause and rest. This is a personal reminder, not a medical alarm.")
                }
                Section {
                    if let latest = store.heartRate.latest {
                        LabeledContent("Source", value: latest.source)
                        LabeledContent("Last updated", value: latest.date.formatted(.dateTime.hour().minute().second().locale(LanguageManager.currentLocale)))
                    } else { Text("No heart-rate samples yet").foregroundStyle(MasoColor.textDim) }
                    Text("Heart-rate data stays on this device and is not sent to AI Coach.")
                        .font(.footnote).foregroundStyle(MasoColor.textDim)
                    Button("Delete heart-rate history", role: .destructive) { deleteHistory = true }
                }
            }
            .navigationTitle("Heart rate").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("workout.heart.save") }
            }
            .confirmationDialog("Delete heart-rate history?", isPresented: $deleteHistory, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if !WorkoutHeartLocalStore.shared.clear() { errorText = NSLocalizedString("Try again", comment: "") }
                }
            }
            .onAppear {
                showCard = data.settings.workoutHeartRateShowCard == true
                heartAssist = data.settings.workoutHeartRateAutomaticEnabled == true
                usesRecommendation = WorkoutHeartRecommendation.usesRecommendation(data.settings)
                let value = usesRecommendation ? recommendation.bpm : (data.settings.workoutHeartRateLimit ?? recommendation.bpm)
                limitText = value.formatted(.number.locale(LanguageManager.currentLocale))
            }
            .onChange(of: recommendation.bpm) { _, value in
                if usesRecommendation { limitText = value.formatted(.number.locale(LanguageManager.currentLocale)) }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func bindMonitor() {
        store.heartRateReadEnabled = data.settings.workoutHeartRateEnabled == true
        store.heartRate.bind(sessionID: store.session?.completed == false ? store.workoutSessionID : nil,
                             start: store.session?.startedAt, enabled: store.heartRateReadEnabled, limit: WorkoutHeartRecommendation.effective(settings: data.settings, samples: WorkoutHeartLocalStore.shared.samples, excluding: store.workoutSessionID))
        store.pushWatchState()
    }
    private func save() {
        if usesRecommendation {
            data.settings.workoutHeartRateUseRecommendation = true
            data.settings.workoutHeartRateLimit = nil
        } else {
            let formatter = NumberFormatter(); formatter.locale = LanguageManager.currentLocale; formatter.numberStyle = .decimal
            let trimmed = limitText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.allSatisfy({ $0.wholeNumberValue != nil }),
                  let value = formatter.number(from: trimmed)?.intValue, (40...240).contains(value) else {
                errorText = NSLocalizedString("Enter a limit from 40 to 240 bpm.", comment: ""); return
            }
            data.settings.workoutHeartRateLimit = value
            data.settings.workoutHeartRateUseRecommendation = false
        }
        data.settings.workoutHeartRateShowCard = showCard
        data.settings.workoutHeartRateAutomaticEnabled = heartAssist
        data.save()
        bindMonitor(); dismiss()
    }
}
