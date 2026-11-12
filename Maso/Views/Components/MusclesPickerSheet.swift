import SwiftUI

// Native multi-select form. Draft changes commit on Save; existing selections
// normalize to the six major muscle sections exposed by this preference.
struct MusclesPickerSheet: View {
    @Environment(DataStore.self) private var data
    @Binding var selected: Set<MuscleGroup>
    @Environment(\.dismiss) private var dismiss

    /// Local working state — 用户更改选项时编辑这个 set, 点 Save 才写回 binding.
    @State private var draft: Set<MuscleGroup> = []
    /// 初始 sanitize 后的 baseline — 用来比较 draft 跟 baseline 是否一致, 决定 Save 是否启用.
    @State private var baseline: Set<MuscleGroup> = []

    private var isDirty: Bool { draft != baseline }

    var body: some View {
        let sections: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]
        AppNavigationStack {
            Form {
                Section {
                    NativeSelectionRow(selected: draft == Set(sections), action: { draft = Set(sections) }) { Text("All") }
                    ForEach(sections, id: \.self) { muscle in
                        NativeSelectionRow(selected: draft.contains(muscle), action: {
                            if draft.contains(muscle) { draft.remove(muscle) } else { draft.insert(muscle) }
                            Haptics.tap()
                        }) { Text(muscle.displayName) }
                    }
                    if !draft.isEmpty { Button("Clear all") { draft.removeAll() }.tint(MasoColor.textDim) }
                }
            }
            .navigationTitle("Muscles to focus").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isDirty) }
            }.onAppear { initializeDraft() }
        }.tint(MasoColor.text)
    }

    /// 进入时把 parent 传进来的 selected 洗一遍 (清孤儿 + 按 detailEnabled 折叠),
    /// 写入 draft 跟 baseline. baseline 用于"用户改了没"判断, draft 是用户编辑的目标.
    private func initializeDraft() {
        // 折叠到 6 大 section (旧数据里 .quads / .upperChest 这种折成 .legs / .chest), 跟 sectionsOnly UI 对齐.
        let cleaned = Set(selected.compactMap { $0.section })
        draft = cleaned
        baseline = cleaned
        // Do not write into the parent draft on presentation. Saving is the
        // only operation that commits this normalized selection.
    }

    private func save() {
        selected = draft
        Haptics.tap()
        dismiss()
    }
}
