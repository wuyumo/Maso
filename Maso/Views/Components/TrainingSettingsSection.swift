import SwiftUI

// MARK: - TrainingSettingsSection — 训练偏好的 6 行内容
//
// 单一来源 — Settings 页和 PlanRationaleCard 的"快捷设置 sheet"两处都渲染这一份.
// 改这里就同时改两处. 任何"训练偏好"的新增/删除/重排, 来这一份改即可.
//
// 不带 Section_ 外壳 / 不带 padding — 调用方决定:
//   - Settings: 包在 Section_(title: "Training") { ... } 里, 跟其他 Section 视觉一致
//   - 快捷 sheet: 也用 Section_ 包, 但外层 ScrollView 自己做 padding / nav
//
// 行项目跟 Settings → Training 完全平行:
//   1. Days per week
//   2. Muscles to focus
//   3. Set rest
//   4. Exercise rest
//   5. Quick-start from center tab
//   6. Show muscle subdivisions
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

            // ─── 3. Set rest ───
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

            // ─── 4. Exercise rest ───
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

            // ─── 5. Quick-start from center tab ───
            ToggleRow(
                title: "Quick-start from center tab",
                desc: "Tap the highlighted center tab again to jump straight into today's recommended workout",
                isOn: Binding(
                    get: { data.settings.quickStartOnActiveTab },
                    set: { data.settings.quickStartOnActiveTab = $0 }
                )
            )
            Divider().background(MasoColor.borderSoft)

            // ─── 6. Show muscle subdivisions ───
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
                    Section_(title: "Training") {
                        TrainingSettingsSection()
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 16)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Training")
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
