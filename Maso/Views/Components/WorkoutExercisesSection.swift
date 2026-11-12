import SwiftUI

/// Shared by editable workouts and completed workout details. Screen-specific
/// actions live in the entry closure; layout and presentation have one owner.
struct WorkoutExercisesSection<Item: Identifiable, Entry: View>: View {
    let items: [Item]
    @Binding var useCardLayout: Bool
    let emptyTitle: LocalizedStringKey
    var onMove: ((IndexSet, Int) -> Void)? = nil
    var onAddExercise: (() -> Void)? = nil
    @ViewBuilder var entry: (Item) -> Entry

    var body: some View {
        Section {
            HStack {
                Text("Exercises").font(.headline).foregroundStyle(MasoColor.text)
                Spacer()
                Picker("Layout", selection: $useCardLayout) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Grid", systemImage: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if items.isEmpty {
                Text(emptyTitle)
                    .font(.footnote).foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
            } else if useCardLayout {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(items) { item in entry(item) }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    entry(item)
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: onMove)
            }
            if let onAddExercise {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onAddExercise) {
                        TrainingCardActionLabel(title: "Add Exercise", icon: "plus", accent: MasoColor.text, prominent: false)
                            .glassCapsuleButtonBackground(fallback: MasoColor.surfaceHi)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout.addExercise")
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
    }
}

struct WorkoutExerciseRow: View {
    let detailLine: String
    let exercise: Exercise
    /// 点图片 → 弹动作详情. parent 传 closure, sheet 在 parent 挂.
    var onTapImage: (() -> Void)? = nil
    var showsChevron = false
    var recordedSets: [SetRecord]? = nil
    var parameterStep: PlanStep? = nil


    var body: some View {
        ExerciseRowContent(exercise: exercise, detailLine: detailLine,
                           onTapImage: onTapImage, showsChevron: showsChevron, recordedSets: recordedSets, parameterStep: parameterStep)
    }
}

// 单个 step 卡片 — 纵向布局 (图大 + 名字 + 详情). LazyVGrid 2 列时用.
// 视觉跟 Spotify / Apple Music 的 grid item 一致 — 图占大头, 文字"贴"图下面.
struct WorkoutExerciseGridCard: View {
    let detailLine: String
    let exercise: Exercise
    /// 点图片 → 弹动作详情. parent 传 closure, sheet 在 parent 挂.
    var onTapImage: (() -> Void)? = nil
    var recordedSets: [SetRecord]? = nil
    var parameterStep: PlanStep? = nil


    var body: some View {
        ExerciseGridContent(exercise: exercise, detailLine: detailLine, onTapImage: onTapImage,
                            recordedSets: recordedSets, parameterStep: parameterStep)
    }
}
