import SwiftUI

/// Only editable training fields are committed; unrelated settings and records survive.
struct TrainingPreferenceDraft: Equatable {
    var weeklyTrainingDays: Int
    var trainingSessionMinutes: Int?
    var exercisesPerSession: Int
    var defaultSetsPerExercise: Int
    var trainingGoalKind: TrainingGoalKind
    var defaultRestSeconds: Int
    var defaultBetweenExerciseRestSeconds: Int
    var maintainWeights: Bool
    var keepScreenAwakeDuringWorkout: Bool
    var coachMemory: String
    var wantStrengthen: [MuscleGroup]
    var equipment: TrainingEquipmentDraft

    init(settings: UserSettings) {
        weeklyTrainingDays = settings.weeklyTrainingDays
        trainingSessionMinutes = settings.trainingSessionMinutes
        exercisesPerSession = settings.exercisesPerSession
        defaultSetsPerExercise = settings.defaultSetsPerExercise
        trainingGoalKind = settings.trainingGoalKind
        defaultRestSeconds = settings.defaultRestSeconds
        defaultBetweenExerciseRestSeconds = settings.defaultBetweenExerciseRestSeconds
        maintainWeights = settings.loadProgression?.maintain ?? false
        keepScreenAwakeDuringWorkout = settings.keepScreenAwakeDuringWorkout
        coachMemory = settings.coachMemory
        wantStrengthen = settings.wantStrengthen.sorted { $0.rawValue < $1.rawValue }
        equipment = TrainingEquipmentDraft(settings: settings)
    }

    func apply(to settings: inout UserSettings) {
        settings.weeklyTrainingDays = weeklyTrainingDays
        settings.trainingSessionMinutes = trainingSessionMinutes
        settings.exercisesPerSession = exercisesPerSession
        settings.defaultSetsPerExercise = defaultSetsPerExercise
        settings.trainingGoalKind = trainingGoalKind
        settings.defaultRestSeconds = defaultRestSeconds
        settings.defaultBetweenExerciseRestSeconds = defaultBetweenExerciseRestSeconds
        var progression = settings.loadProgression ?? .init()
        progression.maintain = maintainWeights
        settings.loadProgression = progression
        settings.keepScreenAwakeDuringWorkout = keepScreenAwakeDuringWorkout
        settings.coachMemory = coachMemory
        settings.wantStrengthen = wantStrengthen
        equipment.apply(to: &settings)
    }

    func affectsRoutine(comparedTo original: Self) -> Bool {
        var comparison = self
        comparison.maintainWeights = original.maintainWeights
        comparison.keepScreenAwakeDuringWorkout = original.keepScreenAwakeDuringWorkout
        if comparison.equipment.displayedEnvironment != .home {
            comparison.equipment.homeEquipment = original.equipment.homeEquipment
        }
        if comparison.equipment.displayedEnvironment != .gym {
            comparison.equipment.gymEquipment = original.equipment.gymEquipment
        }
        return comparison != original
    }
}

// Shared native Form sections for training preferences.
struct TrainingSettingsSection: View {
    @Binding var settings: TrainingPreferenceDraft
    /// 选肌群 sheet 内部 own — 两处使用都能"点 → 弹 picker", caller 不需要管
    @State private var showMusclePicker = false
    @State private var moreTrainingSettingsExpanded = false
    @State private var heartRateSettingsPresented = false

    var body: some View {
        Section {
            Stepper(value: $settings.weeklyTrainingDays, in: 1...7) {
                LabeledContent("Days per week", value: "\(settings.weeklyTrainingDays)")
            }
            Picker("Session length", selection: $settings.trainingSessionMinutes) {
                Text("No target").tag(Int?.none)
                ForEach(TrainingSessionLength.options(including: settings.trainingSessionMinutes), id: \.self) { minutes in
                    Text(onboardingMinutes(minutes)).tag(Optional(minutes))
                }
            }
            .onChange(of: settings.trainingSessionMinutes) { _, value in
                if let value { settings.exercisesPerSession = TrainingSessionLength.exerciseLimit(for: value) }
            }
            Button { showMusclePicker = true } label: {
                LabeledContent("Muscles to focus", value: musclesSummaryText)
            }
            .foregroundStyle(.primary)
            .sheet(isPresented: $showMusclePicker) {
                MusclesPickerSheet(selected: Binding(
                    get: { Set(settings.wantStrengthen) },
                    set: { settings.wantStrengthen = $0.sorted { $0.rawValue < $1.rawValue } }
                ))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            TrainingEnvironmentPicker(draft: $settings.equipment, allowsGymCustomization: true)
            Picker("Training goal", selection: $settings.trainingGoalKind) {
                ForEach(TrainingGoalKind.allCases, id: \.self) { goal in
                    Text(goal.displayName).tag(goal)
                }
            }
        }
        Section {
            Toggle("Maintain current weights", isOn: $settings.maintainWeights)
                .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                .accessibilityIdentifier("training.progression.maintain")
        } footer: {
            Text("Pause weight suggestions for all exercises. Your workout targets stay unchanged.")
        }
        Section {
            DisclosureGroup("More training settings", isExpanded: $moreTrainingSettingsExpanded) {
                Stepper(value: $settings.exercisesPerSession, in: 1...8) {
                    LabeledContent("Exercises per plan", value: "\(settings.exercisesPerSession)")
                }
                Stepper(value: $settings.defaultSetsPerExercise, in: 1...6) {
                    LabeledContent("Default sets", value: "\(settings.defaultSetsPerExercise)")
                }
                Stepper(value: $settings.defaultRestSeconds, in: 15...300, step: 15) {
                    LabeledContent("Set rest", value: "\(settings.defaultRestSeconds) s")
                }
                Stepper(value: $settings.defaultBetweenExerciseRestSeconds, in: 0...600, step: 15) {
                    LabeledContent("Exercise rest", value: "\(settings.defaultBetweenExerciseRestSeconds) s")
                }
                Toggle("Keep screen awake during workouts", isOn: $settings.keepScreenAwakeDuringWorkout)
                    .toggleStyle(.switch).tint(MasoColor.toggleAccent)
            }
        }
        Section {
            Button("Heart rate", systemImage: "heart") { heartRateSettingsPresented = true }
                .sheet(isPresented: $heartRateSettingsPresented) { WorkoutHeartRateSettingsSheet() }
        }
        Section("Notes for your AI coach") {
            TextField("Coach memory examples", text: $settings.coachMemory, axis: .vertical)
                .lineLimit(4...8)
            if !settings.coachMemory.isEmpty {
                Button("Clear", role: .destructive) { settings.coachMemory = "" }
            }
        }
    }

    /// "Muscles to focus" 行右侧文案 — 折叠到 6 大 section (跟 picker 粒度一致):
    ///   - 空 → "None"  ·  1-2 → "Chest" / "Chest, Back"  ·  3+ → "Chest, Back +2"
    private var musclesSummaryText: String {
        let sections = MuscleSelector.focusSummary(Set(settings.wantStrengthen))
        guard !sections.isEmpty else { return NSLocalizedString("None", comment: "") }
        let shown = sections.prefix(2).map(\.displayName).joined(separator: ", ")
        let rest = sections.count - 2
        return rest > 0 ? "\(shown) +\(rest)" : shown
    }
}

/// Same interaction in onboarding and the transactional preferences editor.
struct TrainingEnvironmentPicker: View {
    @Binding var draft: TrainingEquipmentDraft
    var allowsGymCustomization = false
    var identifierPrefix = "training"
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showGymEquipment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training environment").font(.headline)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { environmentButtons }
            } else {
                FlowLayout(spacing: 8) { environmentButtons }
            }
            if draft.displayedEnvironment == .home {
                Text("Home equipment").font(.subheadline.weight(.semibold))
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { homeEquipmentButtons }
                } else {
                    FlowLayout(spacing: 8) { homeEquipmentButtons }
                }
                if draft.homeEquipment.isEmpty {
                    Text("No equipment selected. Bodyweight only.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("\(identifierPrefix).home-equipment.empty")
                }
            } else if draft.displayedEnvironment == .gym, allowsGymCustomization {
                Button { showGymEquipment = true } label: {
                    LabeledContent("Gym equipment", value: gymEquipmentSummary)
                }
                .buttonStyle(.borderless).foregroundStyle(.primary)
            }
        }
        .sheet(isPresented: $showGymEquipment) {
            EquipmentPickerSheet(selected: $draft.gymEquipment)
                .presentationDragIndicator(.visible)
        }
    }

    private var environmentButtons: some View {
        ForEach(TrainingEnvironment.allCases) { environment in
            NativeSelectionButton(title: Text(verbatim: environment.title), isSelected: draft.displayedEnvironment == environment) {
                draft.select(environment)
                Haptics.selection()
            }
            .accessibilityIdentifier("\(identifierPrefix).equipment.\(environment.rawValue)")
        }
    }

    private var homeEquipmentButtons: some View {
        ForEach(HomeTrainingEquipment.allCases) { item in
            NativeSelectionButton(title: Text(verbatim: item.title), isSelected: draft.homeEquipment.contains(item)) {
                if draft.homeEquipment.contains(item) { draft.homeEquipment.remove(item) }
                else { draft.homeEquipment.insert(item) }
                Haptics.selection()
            }
            .accessibilityIdentifier("\(identifierPrefix).home-equipment.\(item.rawValue)")
        }
    }

    private var gymEquipmentSummary: String {
        guard !draft.gymEquipment.isEmpty else { return NSLocalizedString("All equipment", comment: "") }
        let names = EquipmentCategory.allCases.filter { draft.gymEquipment.contains($0.rawValue) }.map(\.displayName)
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }
}

// Legacy entry point delegates to the same transactional editor.
struct TrainingSettingsSheet: View {
    var onApply: () -> Void = {}
    var body: some View { TrainingPreferencesSheet(onConfirm: onApply) }
}

// MARK: - EquipmentPickerSheet (#1) — 多选健身房可用器械大类
//
// 空选 = 不限制 (全器械). 选了 → AI / 推荐计划只出这些器械 (+ 自重) 能做的动作.
struct EquipmentPickerSheet: View {
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    NativeSelectionRow(selected: selected.isEmpty, action: { selected.removeAll() }) {
                        Text("All")
                    }
                    ForEach(EquipmentCategory.allCases) { category in
                        NativeSelectionRow(selected: selected.contains(category.rawValue), action: {
                            if selected.contains(category.rawValue) { selected.remove(category.rawValue) }
                            else { selected.insert(category.rawValue) }
                            Haptics.tap()
                        }) { Text(LocalizedStringKey(category.displayName)) }
                    }
                }
            }
            .navigationTitle("Gym equipment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .tint(MasoColor.text)
        }
    }
}
