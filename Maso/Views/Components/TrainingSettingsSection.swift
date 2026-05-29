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
            // 改这个就 auto-regenerate 推荐计划 (1-3 全身 / 4-5 分化 / 6+ PPL).
            // PlanRationaleCard 直接看 weeklyTrainingDays + plans, 自动跟随刷新.
            Row(label: "Days per week") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.weeklyTrainingDays },
                        set: { newVal in
                            data.settings.weeklyTrainingDays = newVal
                            data.regenerateRecommendedPlans()
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

            // ─── 3. Exercises per session ───
            // 推荐 plan 每张多少动作. 1-6 上限 — 模板最多就 6 step. 用户改后重新 regen.
            Row(label: "Exercises per session") {
                IntStepperContent(
                    value: Binding(
                        get: { data.settings.exercisesPerSession },
                        set: { newVal in
                            data.settings.exercisesPerSession = newVal
                            data.regenerateRecommendedPlans()
                        }
                    ),
                    range: 1...6
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
                            data.regenerateRecommendedPlans()
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

            // ─── 8. Quick-start from center tab ───
            ToggleRow(
                title: "Quick-start from center tab",
                desc: "Tap the highlighted center tab again to jump straight into today's recommended workout",
                isOn: Binding(
                    get: { data.settings.quickStartOnActiveTab },
                    set: { data.settings.quickStartOnActiveTab = $0 }
                )
            )
            Divider().background(MasoColor.borderSoft)

            // ─── 9. Show muscle subdivisions ───
            // 默认开 (跟解剖学一致暴露 sub muscle).
            // 关掉之后 UI 只暴露大肌群入口, 给追求"简洁"的用户用.
            ToggleRow(
                title: "Show muscle subdivisions",
                desc: "Off: pick the whole muscle (chest, back) — no upper/mid/lower split. On: full anatomical detail.",
                isOn: Binding(
                    get: { data.settings.muscleDetailEnabled },
                    set: { data.settings.muscleDetailEnabled = $0 }
                )
            )

            // P2-4 / P2-11: 说明这些偏好的作用域 — 否则用户改了"默认组数"看自建 plan 没变会以为坏了.
            Text("These apply to recommended plans and exercises you add — your custom plans aren't changed.")
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .padding(.horizontal, MasoMetrics.cardPadding)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showMusclePicker) {
            MusclesPickerSheet(
                selected: Binding(
                    get: { Set(data.settings.wantStrengthen) },
                    set: { data.settings.wantStrengthen = Array($0) }
                )
            )
            .presentationDetents([.medium, .large])
        }
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
