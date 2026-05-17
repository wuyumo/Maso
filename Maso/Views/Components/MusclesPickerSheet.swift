import SwiftUI

// 多选肌群 sheet — Settings → "Muscles to focus" 入口.
//
// 行为:
//   - 复用 MuscleSelector 组件 (跟 Onboarding / QuickWorkout 创建训练同款 chip 选择 UI).
//   - 大肌群 chip + 解剖学子分区 chip, 两层都独立 toggle.
//   - 尊重 Settings.muscleDetailEnabled — 关时只显示 12 个 major.
//   - "编辑 → Save 提交"模式: sheet 内 local state, 点 Save 才写回 parent binding.
//     X 关闭则放弃改动 (跟 iOS Notes / Reminders 编辑 sheet 一致).
//   - onAppear 调 sanitize 清掉 wantStrengthen 里"不在 picker 暴露层级"的孤儿值
//     (修了原来"全部取消还显示 count = 1"的 bug, 源头是 DataStore 默认 .lats 这种 sub
//      被存进去但 picker 看不到).
struct MusclesPickerSheet: View {
    @Environment(DataStore.self) private var data
    @Binding var selected: Set<MuscleGroup>
    @Environment(\.dismiss) private var dismiss

    /// Local working state — 用户改 chip 改的是这个 set, 点 Save 才写回 binding.
    @State private var draft: Set<MuscleGroup> = []
    /// 初始 sanitize 后的 baseline — 用来比较 draft 跟 baseline 是否一致, 决定 Save 是否启用.
    @State private var baseline: Set<MuscleGroup> = []

    private var detailEnabled: Bool { data.settings.muscleDetailEnabled }
    private var isDirty: Bool { draft != baseline }

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pick the muscle groups you want to prioritize. Today's recommendations and AI plans will favor these.")
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .padding(.top, 8)

                        // 主选择区 — 共享组件
                        MuscleSelector(
                            selected: $draft,
                            detailEnabled: detailEnabled
                        )

                        // 帮助文案: 不强制选满 / 可清空
                        if !detailEnabled {
                            Text("Enable \"Show muscle subdivisions\" in Settings to pick details like upper chest or rear delts.")
                                .font(.system(size: 11))
                                .foregroundStyle(MasoColor.textFaint)
                                .padding(.top, 4)
                        }

                        // Clear all — 给 power user 一个一键清空入口, 比"逐个反点"快
                        if !draft.isEmpty {
                            Button(action: {
                                draft.removeAll()
                                Haptics.tap()
                            }) {
                                Text("Clear all")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MasoColor.textDim)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Muscles to focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(isDirty ? MasoColor.accent : MasoColor.textFaint)
                    }
                    .disabled(!isDirty)
                }
            }
            .onAppear { initializeDraft() }
        }
        .presentationBackground(MasoColor.background)
    }

    /// 进入时把 parent 传进来的 selected 洗一遍 (清孤儿 + 按 detailEnabled 折叠),
    /// 写入 draft 跟 baseline. baseline 用于"用户改了没"判断, draft 是用户编辑的目标.
    private func initializeDraft() {
        let cleaned = MuscleSelector.sanitize(selected, detailEnabled: detailEnabled)
        draft = cleaned
        baseline = cleaned
        // 如果 sanitize 改动了数据 (清了孤儿值), 也立即同步回 parent. 不等用户 Save,
        // 因为这是修脏数据, 用户没改动也应该写回.
        if cleaned != selected {
            selected = cleaned
        }
    }

    private func save() {
        selected = draft
        Haptics.tap()
        dismiss()
    }
}
