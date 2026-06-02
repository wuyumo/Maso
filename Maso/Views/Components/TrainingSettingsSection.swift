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
                    ForEach(TrainingGoal.allCases, id: \.self) { g in
                        Button(action: {
                            data.settings.trainingGoal = g
                            // P2-4: 选目标时同步把组间歇设成该目标的推荐值, 让下面"Set rest"行
                            // 跟目标副文案 (~90s / 长歇) 一致, 不再各说各话. 用户之后可再手动微调.
                            data.settings.defaultRestSeconds = g.recommendedRestSeconds()
                            // 训练目标影响推荐计划的 reps → 重新生成, my plans 立刻跟着变.
                            data.markRecommendedPlansDirty()
                        }) {
                            HStack {
                                Text(g.displayName)
                                if g == data.settings.trainingGoal {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(data.settings.trainingGoal.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                }
                .buttonStyle(.plain)
            }
            // 副文案 — 解释当前目标的 rep range. 视觉上比 Row 弱一档.
            HStack(spacing: 0) {
                Text(data.settings.trainingGoal.subtitle)
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
            Text("These apply to recommended plans and exercises you add — your custom plans aren't changed.")
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        // 离开 Training Preferences (点 Done / 下拉关 sheet / 切走) 时, 若改过任何偏好就带 loading
        // 统一刷新 AI Plans —— 不再每动一下 stepper 就重算 (避免反复抖 + 让刷新成为一次明确动作).
        .onDisappear { data.commitRecommendedPlansIfDirty() }
    }

    /// "Muscles to focus" 行右侧文案 (跟 SettingsScreen 用同一份逻辑):
    ///   - 空 → "None"
    ///   - 1-2 个 major → "Chest" / "Chest, Back"
    ///   - 3+ → "Chest, Back +2"
    ///   - 有 sub 被选 → "Chest +3 details" (major + N 个细分)
    private var musclesSummaryText: String {
        let set = Set(data.settings.wantStrengthen)
        guard !set.isEmpty else { return NSLocalizedString("None", comment: "") }
        let (majors, extraSub) = MuscleSelector.summary(set)
        let shown = majors.prefix(2).map(\.displayName).joined(separator: ", ")
        let restMajor = max(0, majors.count - 2)
        var out = shown
        if restMajor > 0 { out += " +\(restMajor)" }
        if extraSub > 0 {
            out += " (\(extraSub) " + NSLocalizedString("details", comment: "muscle subdivisions") + ")"
        }
        return out
    }
}

// MARK: - TrainingSettingsSheet — 快捷设置 sheet, PlanRationaleCard pencil 入口
//
// 行为:
//   - presentationDetents([.medium, .large]) — 默认半屏, 可上拉满
//   - Done button 关闭
//   - 改任何项目立刻 write 回 data.settings, PlanRationaleCard / Plan 列表自动跟随
struct TrainingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 不再有 section 标题 — nav title "Training Preferences" 已经够清楚,
                    // 内部不重复 section header (用户反馈 Adjust 多余).
                    TrainingSettingsSection()
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 16)
            }
            .background(MasoColor.background.ignoresSafeArea())
            // Nav title 跟 Plans tab 卡片 kicker 对齐 — 用户点 "TRAINING PREFERENCES" 卡进来,
            // 看到 sheet 标题也是 "Training Preferences", 上下文连贯.
            .navigationTitle("Training Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
    }
}
