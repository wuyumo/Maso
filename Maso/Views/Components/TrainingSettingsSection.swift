import SwiftUI

// MARK: - TrainingSettingsSection — 训练偏好的行内容
//
// 单一来源 — Settings 页和 PlanRationaleCard 的"快捷设置 sheet"两处都渲染这一份.
// 改这里就同时改两处. 任何"训练偏好"的新增/删除/重排, 来这一份改即可.
//
// 不带 Section_ 外壳 / 不带 padding — 调用方决定:
//   - Settings: 包在 Section_(title: "Training") { ... } 里, 跟其他 Section 视觉一致
//   - 快捷 sheet: 也用 Section_ 包, 但外层 ScrollView 自己做 padding / nav
//
// 当前行 (按顺序):
//   1. Days per week
//   2. Muscles to focus
//   3. Exercises per session
//   4. Default sets
//   5. Training goal (+ rep-range 副文案)
//   6. Set rest
//   7. Exercise rest
//   8. Quick-start from center tab
//   9. Show muscle subdivisions
//   + 作用域说明脚注
struct TrainingSettingsSection: View {
    @Environment(DataStore.self) private var data
    /// 选肌群 sheet 内部 own — 两处使用都能"点 → 弹 picker", caller 不需要管
    @State private var showMusclePicker = false
    /// 选器械 sheet (#1).
    @State private var showEquipmentPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // ─── 1. Days per week ───
            // 改这个只 mark dirty (1-3 全身 / 4-5 分化 / 6+ PPL); 真正 regen 推迟到离开页面 (Done)
            // 统一带 loading 刷新 —— 不再每动一下就重算, 避免反复抖, 也让刷新成为明确动作.
            Row(label: "Days per week") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.weeklyTrainingDays },
                        set: { newVal in
                            data.settings.weeklyTrainingDays = newVal
                            data.markRecommendedPlansDirty()
                        }
                    ),
                    range: 1...7
                )
            }
            Divider().background(MasoColor.borderSoft)

            // ─── 2. Muscles to focus ───
            // 展示策略: 不再只显示数字, 而是显示具体选了哪些 — 让用户一眼看到偏好,
            // 不用点进去才知道. 多于 2 个用 "Chest, Back +2" 简写.
            Button(action: { showMusclePicker = true }) {
                Row(label: "Muscles to focus") {
                    HStack(spacing: 6) {
                        Text(musclesSummaryText)
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                }
            }
            .buttonStyle(.plain)
            Divider().background(MasoColor.borderSoft)

            // ─── 2b. Gym equipment (#1) ───
            // 用户勾选健身房有的器械 → AI / 推荐计划只出这些器械能做的动作. 空 = 不限制.
            Button(action: { showEquipmentPicker = true }) {
                Row(label: "Gym equipment") {
                    HStack(spacing: 6) {
                        Text(equipmentSummaryText)
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                }
            }
            .buttonStyle(.plain)
            Divider().background(MasoColor.borderSoft)

            // ─── 3. Exercises per plan ───
            // 推荐 plan 每张多少动作. 1-8. 离开页面统一 regen → 每张推荐计划严格补/裁到这个动作数:
            //   - 模板/社区计划动作多 → prefix(cap) 裁到 cap
            //   - 社区计划某 session 动作少 (如只有 5) → padStepsToTarget 按已练肌群补配件到 cap
            // 所以用户设 7 就一定是 7, 不会被计划自身的动作数卡住 (修复"设了 7 却显示 5").
            Row(label: "Exercises per plan") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.exercisesPerSession },
                        set: { newVal in
                            data.settings.exercisesPerSession = newVal
                            data.markRecommendedPlansDirty()
                        }
                    ),
                    range: 1...8
                )
            }
            Divider().background(MasoColor.borderSoft)

            // ─── 4. Default sets per exercise ───
            // 每个动作几组. 1-6 — 单组 (1) 服务 powerlifting test set; 6 组是 high-volume 上限.
            Row(label: "Default sets") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.defaultSetsPerExercise },
                        set: { newVal in
                            data.settings.defaultSetsPerExercise = newVal
                            data.markRecommendedPlansDirty()
                        }
                    ),
                    range: 1...6
                )
            }
            Divider().background(MasoColor.borderSoft)

            // ─── 5. Training goal (reps + rest 范围) ───
            // strength: 1-5 reps × 长歇 (3-5 min)
            // hypertrophy (默认): 6-12 reps × ~90s
            // endurance: 12-20 reps × ~45s
            // 选了之后, 新加动作 (训练中 + Add exercise) 用对应 reps 默认.
            // 模板里手调的 reps 不动 (e.g. squat 模板就是 6 reps, 比 hyp 默认 8 更贴具体动作).
            Row(label: "Training goal") {
                Menu {
                    ForEach(TrainingGoalKind.allCases, id: \.self) { g in
                        Button(action: {
                            // 写 trainingGoalKind —— didSet 级联设 trainingGoal + defaultRestSeconds
                            // (沿用旧"选目标也设组间歇"行为, 只是上移到 5 档这一层).
                            data.settings.trainingGoalKind = g
                            // 训练目标影响推荐计划的动作选择 + reps → 重新生成, my plans 立刻跟着变.
                            data.markRecommendedPlansDirty()
                        }) {
                            HStack {
                                Text(g.displayName)
                                if g == data.settings.trainingGoalKind {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(data.settings.trainingGoalKind.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                }
                .buttonStyle(.plain)
            }
            // 副文案 — 解释当前目标. 视觉上比 Row 弱一档.
            HStack(spacing: 0) {
                Text(data.settings.trainingGoalKind.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
                Spacer()
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.bottom, 8)
            Divider().background(MasoColor.borderSoft)

            // ─── 6. Set rest ───
            Row(label: "Set rest") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.defaultRestSeconds },
                        set: { data.settings.defaultRestSeconds = $0 }
                    ),
                    range: 15...300,
                    step: 15,
                    suffix: "s"
                )
            }
            Divider().background(MasoColor.borderSoft)

            // ─── 7. Exercise rest ───
            Row(label: "Exercise rest") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.defaultBetweenExerciseRestSeconds },
                        set: { data.settings.defaultBetweenExerciseRestSeconds = $0 }
                    ),
                    range: 0...600,
                    step: 15,
                    suffix: "s"
                )
            }
            Divider().background(MasoColor.borderSoft)

            // ─── 8. Prefer community plans ───
            // 开 → 推荐计划改从 Community 挑成熟方案 materialize, 而不是模板自动生成.
            // 改了立刻 regen, 让用户马上看到 AI Plans 换成社区计划 (或换回模板).
            ToggleRow(
                title: "Prefer community plans",
                desc: "Build your AI Plans from a proven community program that matches your days per week and goal, instead of auto-generating them.",
                isOn: Binding(
                    get: { data.settings.preferCommunityPlans },
                    set: { newVal in
                        data.settings.preferCommunityPlans = newVal
                        data.markRecommendedPlansDirty()
                    }
                )
            )
            // (移除: "Quick-start from center tab" — 入口已不在; 该行为仍按 settings 默认值生效.)
            // (移除: "Show muscle subdivisions" — 不再让用户切换, 始终按默认显示细分肌群.)

            // P2-4 / P2-11: 说明这些偏好的作用域 — 否则用户改了"默认组数"看自建 plan 没变会以为坏了.
            Text("These apply to recommended routines and exercises you add — your custom routines aren't changed.")
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(MasoColor.borderSoft)

            // ─── Coaching memory ───
            // 用户可读 / 可改 / 可清的"记忆文件" — AI 每次生成 routine 都读它 (DataStore.buildAIPayload
            // → AIPayload.coachMemory → prompt). 来源: AI 对话框发送时自动 append, 这里直接编辑也行.
            // live 写 settings.coachMemory (跟本 section 其它偏好同套路); 改它不 mark dirty / 不重生成,
            // 只喂下一次生成. 落盘走 section .onDisappear / app 进后台 flushSave (跟其它 live 偏好一致).
            coachMemorySection
        }
        // 关掉选肌群 sheet 只 mark dirty, 不立即 regen — 跟其它偏好一样, 等离开页面统一刷新.
        .sheet(isPresented: $showMusclePicker, onDismiss: { data.markRecommendedPlansDirty() }) {
            MusclesPickerSheet(
                selected: Binding(
                    get: { Set(data.settings.wantStrengthen) },
                    set: { data.settings.wantStrengthen = Array($0) }
                )
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // 选器械 sheet (#1) — 同样关闭只 mark dirty, 离开页面统一 regen.
        .sheet(isPresented: $showEquipmentPicker, onDismiss: { data.markRecommendedPlansDirty() }) {
            EquipmentPickerSheet(
                selected: Binding(
                    get: { Set(data.settings.availableEquipment) },
                    set: { data.settings.availableEquipment = Array($0) }
                )
            )
            .presentationDragIndicator(.visible)
        }
        // 离开 Training Preferences (点 Done / 下拉关 sheet / 切走) 时, 若改过任何偏好就带 loading
        // 统一刷新 AI Plans —— 不再每动一下 stepper 就重算 (避免反复抖 + 让刷新成为一次明确动作).
        .onDisappear { data.commitRecommendedPlansIfDirty() }
    }

    // MARK: - Coaching memory

    /// 教练记忆 — accent label + 多行 TextEditor (live 绑 settings.coachMemory) + 帮助文案 + Clear.
    /// 视觉跟本 section 一致: surface 行底上叠一块 surfaceHi 的可编辑框, accent kicker.
    @ViewBuilder
    private var coachMemorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .heavy))
                Text("Coaching memory")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                Spacer()
                // 清空 — 仅有内容时出现.
                if !data.settings.coachMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        data.settings.coachMemory = ""
                        data.save()
                        Haptics.tap()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(MasoColor.accent)

            // 多行编辑器 — live 写 settings.coachMemory. 叠在 surfaceHi 上跟周围 surface 行区分开.
            TextEditor(text: Binding(
                get: { data.settings.coachMemory },
                set: { data.settings.coachMemory = $0 }
            ))
            .font(.system(size: 14))
            .foregroundStyle(MasoColor.text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 96)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MasoColor.surfaceHi)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MasoColor.borderSoft, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Notes the AI uses every time it builds your routines — edit or clear anytime.")
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Gym equipment" 行右侧文案 — 空 = "All equipment"; 否则列大类名 (>2 用 "+N").
    private var equipmentSummaryText: String {
        let sel = data.settings.availableEquipment
        guard !sel.isEmpty else { return NSLocalizedString("All equipment", comment: "") }
        let names = EquipmentCategory.allCases.filter { sel.contains($0.rawValue) }.map(\.displayName)
        let shown = names.prefix(2).joined(separator: ", ")
        let rest = names.count - 2
        return rest > 0 ? "\(shown) +\(rest)" : shown
    }

    /// "Muscles to focus" 行右侧文案 — 折叠到 6 大 section (跟 picker 粒度一致):
    ///   - 空 → "None"  ·  1-2 → "Chest" / "Chest, Back"  ·  3+ → "Chest, Back +2"
    private var musclesSummaryText: String {
        let sections = MuscleSelector.focusSummary(Set(data.settings.wantStrengthen))
        guard !sections.isEmpty else { return NSLocalizedString("None", comment: "") }
        let shown = sections.prefix(2).map(\.displayName).joined(separator: ", ")
        let rest = sections.count - 2
        return rest > 0 ? "\(shown) +\(rest)" : shown
    }
}

// MARK: - TrainingSettingsSheet — 快捷设置 sheet, PlanRationaleCard pencil 入口
//
// 行为:
//   - presentationDetents([.medium, .large]) — 默认半屏, 可上拉满
//   - Done button 关闭
//   - 改任何项目立刻 write 回 data.settings, PlanRationaleCard / Plan 列表自动跟随
struct TrainingSettingsSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 点 "Generate routines" → 应用偏好后回调 (PlansScreen 拿来跑生成动画 + 出 routines).
    var onApply: () -> Void = {}

    /// 进入半页时对训练偏好拍快照 — 用来判断"改没改"(CTA 可点态) + Discard 时回滚.
    @State private var original: UserSettings? = nil
    @State private var showDiscardAlert = false
    /// Request #3 — 改了组间歇/动作间歇/默认组数时, 关页前问一次"要不要也更新我已存的计划".
    @State private var showApplyParamsAlert = false

    /// 页内任一训练偏好相对快照有改动 → CTA 激活. (UserSettings 非 Equatable, 逐字段比.)
    private var changed: Bool {
        guard let o = original else { return false }
        let s = data.settings
        return o.weeklyTrainingDays != s.weeklyTrainingDays
            || o.exercisesPerSession != s.exercisesPerSession
            || o.defaultSetsPerExercise != s.defaultSetsPerExercise
            || o.trainingGoalKind != s.trainingGoalKind
            || o.trainingGoal != s.trainingGoal
            || o.defaultRestSeconds != s.defaultRestSeconds
            || o.defaultBetweenExerciseRestSeconds != s.defaultBetweenExerciseRestSeconds
            || o.preferCommunityPlans != s.preferCommunityPlans
            || Set(o.wantStrengthen) != Set(s.wantStrengthen)
            || Set(o.availableEquipment) != Set(s.availableEquipment)
    }

    /// Request #3 — 哪些 per-step 参数变了 (rest / between-rest / sets), 可"应用到既有 routine"
    /// (非破坏式传播, 不重建选择). 跟 changed (regenerate 类) 分开判断.
    private var perStepParamsChanged: Bool {
        guard let o = original else { return false }
        let s = data.settings
        return o.defaultRestSeconds != s.defaultRestSeconds
            || o.defaultBetweenExerciseRestSeconds != s.defaultBetweenExerciseRestSeconds
            || o.defaultSetsPerExercise != s.defaultSetsPerExercise
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 不重复 section header — nav title "Training Preferences" 已够清楚.
                    TrainingSettingsSection()
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Training Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { attemptClose() }
                }
            }
            .tint(MasoColor.text)
            // CTA 钉在半页最底部 — 初始置灰, 改了内容才激活, 点了才 Apply + 生成.
            .safeAreaInset(edge: .bottom) {
                generateButton
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(MasoColor.background.opacity(0.92))
            }
        }
        .onAppear { if original == nil { original = data.settings } }
        // 有改动时禁用下滑关闭 — 逼用户走 Close → Discard alert, 不会误丢改动.
        .interactiveDismissDisabled(changed)
        .alert("Apply changes?", isPresented: $showDiscardAlert) {
            Button("Apply") { applyAndClose() }
            Button("Discard", role: .destructive) { discardAndClose() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("You changed your training preferences. Apply them and regenerate your routines?")
        }
        // Request #3 — 改了 rest / 默认组数时, opt-in 地把新值套到既有计划 (不静默覆盖, 不重建选择).
        .alert("Update your saved routines?", isPresented: $showApplyParamsAlert) {
            Button("Update them") { applyParamsThenClose(updateExisting: true) }
            Button("Keep as is") { applyParamsThenClose(updateExisting: false) }
        } message: {
            Text("You changed your default rest or sets. Apply these to the exercises in all your saved routines too?")
        }
    }

    private var generateButton: some View {
        Button { applyAndClose() } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 14, weight: .heavy))
                Text("Generate routines").font(.system(size: 15, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(changed ? .black : MasoColor.textDim)
            .background(changed ? MasoColor.accent : MasoColor.surfaceHi)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!changed)
        .animation(.easeOut(duration: 0.2), value: changed)
    }

    private func attemptClose() {
        if changed { showDiscardAlert = true } else { dismiss() }
    }

    /// 应用偏好 (已 live 写进 data.settings) → 存盘 → 关页 → 触发生成.
    /// Request #3: 若改了 per-step 参数 (rest / sets), 先弹"要不要也套到既有计划", 由用户选完再走完整流程.
    private func applyAndClose() {
        data.save()
        if perStepParamsChanged {
            showApplyParamsAlert = true   // 走 alert → applyParamsThenClose
        } else {
            finishApply()
        }
    }

    /// Request #3 alert 的两个分支 —— 选"更新"则把改过的 rest/sets 非破坏式套到既有计划, 然后照常关页生成.
    private func applyParamsThenClose(updateExisting: Bool) {
        if updateExisting, let o = original {
            let s = data.settings
            data.applyDefaultParamsToAllRoutines(
                setRest: o.defaultRestSeconds != s.defaultRestSeconds ? s.defaultRestSeconds : nil,
                betweenRest: o.defaultBetweenExerciseRestSeconds != s.defaultBetweenExerciseRestSeconds ? s.defaultBetweenExerciseRestSeconds : nil,
                setsFloor: o.defaultSetsPerExercise != s.defaultSetsPerExercise ? s.defaultSetsPerExercise : nil
            )
        }
        finishApply()
    }

    /// 收尾: 关页 + 触发 (regenerate 类偏好的) 重新生成.
    private func finishApply() {
        let apply = onApply
        dismiss()
        DispatchQueue.main.async { apply() }
    }

    /// 丢弃改动 → 回滚到进入时的快照 → 存盘 → 关页 (不生成).
    private func discardAndClose() {
        if let o = original { data.settings = o; data.save() }
        dismiss()
    }
}

// MARK: - EquipmentPickerSheet (#1) — 多选健身房可用器械大类
//
// 空选 = 不限制 (全器械). 选了 → AI / 推荐计划只出这些器械 (+ 自重) 能做的动作.
struct EquipmentPickerSheet: View {
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        Text("Pick the equipment your gym has — AI and recommended routines will only use moves you can actually do. Leave empty for no restriction (bodyweight is always available).")
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 4)

                        ForEach(EquipmentCategory.allCases) { cat in
                            let on = selected.contains(cat.rawValue)
                            Button {
                                if on { selected.remove(cat.rawValue) } else { selected.insert(cat.rawValue) }
                                Haptics.tap()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(on ? .black : MasoColor.accent)
                                        .frame(width: 34, height: 34)
                                        .background(on ? MasoColor.accent : MasoColor.accent.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    Text(LocalizedStringKey(cat.displayName))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(MasoColor.text)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(on ? MasoColor.accent : MasoColor.textFaint)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(MasoColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }

                        if !selected.isEmpty {
                            Button {
                                selected.removeAll(); Haptics.tap()
                            } label: {
                                Text("Clear — use all equipment")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(MasoColor.textDim)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                    .padding(MasoMetrics.pagePaddingHorizontal)
                }
            }
            .navigationTitle("Gym equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold)
                }
            }
            .tint(MasoColor.text)
        }
        .presentationBackground(MasoColor.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
