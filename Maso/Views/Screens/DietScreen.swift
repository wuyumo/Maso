import SwiftUI
import Charts
import UIKit

struct DietScreen: View {
    var embeddedCarousel = false
    @Environment(DataStore.self) private var data
    @Environment(\.scenePhase) private var scenePhase
    @State private var mealToRecord: DietMeal?
    @State private var mealSeed: MealPhotoEstimate?
    @State private var pendingMealSeed: MealPhotoEstimate?
    @State private var lastMealPresented = false
    @State private var carouselHeight: CGFloat?
    @State private var nutritionInfoPresented = false
    @State private var preferencesPresented = false
    private var preferences: DietPreferences {
        data.settings.dietPreferences ?? DietPreferences()
    }
    private var profileKey: String { DailyDietPlan.profileKey(settings: data.settings, preferences: preferences) }
    var body: some View {
        Group {
            if embeddedCarousel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Diet").trainingSectionTitle()
                        Spacer()
                        Button { preferencesPresented = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .imageScale(.small)
                                .frame(width: 44, height: 44)
                        }
                        .tint(MasoColor.text)
                        .accessibilityLabel("Diet preferences")
                        .accessibilityIdentifier("diet.preferences")
                    }.frame(minHeight: 44)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        if let targets = data.dietGuidance()?.targets {
                            nutritionCard(targets)
                                .containerRelativeFrame(.horizontal) { length, _ in length - 56 }
                        }
                        ForEach(Array(data.wellnessMeals(on: Date()).enumerated()), id: \.element.id) { index, record in
                            RecordedMealCard(record: record, number: index + 1)
                                .containerRelativeFrame(.horizontal) { length, _ in length - 56 }
                        }
                        addMealButton
                            .frame(maxWidth: .infinity, minHeight: carouselHeight ?? 140)
                            .glassCardBackground()
                            .containerRelativeFrame(.horizontal) { length, _ in length - 56 }

                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .padding(.horizontal, -MasoMetrics.pagePaddingHorizontal)
                .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
                .onPreferenceChange(DietCarouselHeightKey.self) { height in
                    if height > 0, carouselHeight != height { carouselHeight = height }
                }
                }
            } else {
        ScrollView {
            VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
                if let guidance = data.dietGuidance() {
                    Text(LocalizedStringKey(guidance.subtitleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let targets = data.dietGuidance()?.targets {
                    nutritionCard(targets)
                }
                Button { nutritionInfoPresented = true } label: {
                    Label("Why these targets?", systemImage: "info.circle")
                        .font(.footnote)
                }.tint(MasoColor.textFaint)
                if data.settings.weight == nil {
                    NavigationLink { BodyProfileScreen() } label: {
                        TrainingCardActionLabel(title: "Add your weight for portion guidance", icon: "person.crop.circle", accent: MasoColor.dietAccent)
                    }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .center)
                }
                addMealButton.frame(maxWidth: .infinity, alignment: .center)
                RecordHistorySection(kind: .diet)

            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 4)
            .padding(.bottom, MasoMetrics.pagePaddingHorizontal)
        }
            }
        }
        .applyIf(!embeddedCarousel) { view in
            view.background(AppBackground())
        .navigationTitle("Diet")
        .navigationBarTitleDisplayMode(.large)
        .toolbarRole(.navigationStack)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { preferencesPresented = true } label: { Image(systemName: "slider.horizontal.3") }
                    .tint(MasoColor.text)
                        .accessibilityLabel("Diet preferences")
                        .accessibilityIdentifier("diet.preferences")
            }
        }
        }
        .sheet(item: $mealToRecord) { meal in
            MealEditorSheet(meal: meal, image: nil, initialEstimate: mealSeed)
        }
        .sheet(isPresented: $lastMealPresented, onDismiss: {
            if let pendingMealSeed {
                mealSeed = pendingMealSeed
                self.pendingMealSeed = nil
                mealToRecord = DietMeal(id: UUID().uuidString, title: "Meal", portions: [])
            }
        }) {
            LastMealSuggestionSheet { estimate in
                pendingMealSeed = estimate
                lastMealPresented = false
            }
        }
        .sheet(isPresented: $nutritionInfoPresented) { DietNutritionInfoSheet() }
        .tint(MasoColor.dietAccent)
        .task { data.captureWellnessGoal() }
        .onChange(of: data.dietGuidance()?.targets.carbohydrate) { _, _ in data.captureWellnessGoal(updateDiet: true) }
        .onChange(of: profileKey) { _, _ in data.captureWellnessGoal(updateDiet: true) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { data.captureWellnessGoal() } }
        .sheet(isPresented: $preferencesPresented) {
            DietPreferencesSheet(initial: preferences, settings: data.settings) { updated in
                data.settings.dietPreferences = updated
                data.save()
                data.captureWellnessGoal(updateDiet: true)
            }
        }
    }
    private var intake: MealNutrition { data.wellnessMeals(on: Date()).reduce(MealNutrition()) { $0 + $1.nutrition } }
    private var showsRemainingMealSuggestion: Bool {
        let records = data.wellnessMeals(on: Date())
        let goal = data.wellnessGoal(on: Date())
        return LastMealSuggestion.shouldOffer(score: DietIntakeProgress.calculate(goal: goal, meals: records)?.score,
            goal: goal.map { MealNutrition(protein: Double($0.protein), carbs: Double($0.carbsMinimum), fat: Double($0.fatMinimum)) }, consumed: intake)
    }
    private func nutritionCard(_ targets: DietNutritionTargets) -> some View {
        VStack(spacing: 0) {
            DietNutritionSummaryContent(
                targets: MealNutrition(protein: Double(targets.protein), carbs: Double(targets.carbohydrate), fat: Double(targets.fat)),
                actual: intake,
                progress: DietIntakeProgress.calculate(goal: data.wellnessGoal(on: Date()), meals: data.wellnessMeals(on: Date())),
                hasRecords: !data.wellnessMeals(on: Date()).isEmpty)
            if showsRemainingMealSuggestion {
                Divider()
                Button { lastMealPresented = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("What can I eat to meet my remaining targets?")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.padding(MasoMetrics.cardPadding)
                }.buttonStyle(.plain).tint(MasoColor.text)
            }

        }
        .modifier(DietCarouselSizing(height: embeddedCarousel ? carouselHeight : nil, measures: embeddedCarousel))
        .contentCardChrome(padding: 0)
        .accessibilityElement(children: .contain)
    }
    private var addMealButton: some View {
        Button {
            mealSeed = nil
            mealToRecord = DietMeal(id: UUID().uuidString, title: "Meal", portions: [])
        } label: {
            TrainingCardActionLabel(title: "Add meal", icon: "plus", accent: MasoColor.dietAccent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("diet.add-meal")
    }
}

/// Actual logged meals only; shares the same card material as the daily target.
/// Shared actual-first metric and target progress for Diet and Sleep.
struct ActualTargetProgress: View {
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = MasoMetrics.nutritionProteinValueSize
    let actualText: String
    let targetText: String?
    let actual: Double?
    let target: Double?
    let accent: Color
    var unit = ""
    var prominent = true
    var exportStyle = false
    var emphasizesDurationNumbers = false
    var valueFont: Font? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
            let actualLabel = styledActualLabel
            let targetLabel = Text(verbatim: targetText.map { " / " + $0 } ?? "")
                .font(prominent ? .title3 : .subheadline).foregroundColor(MasoColor.textDim)
            let unitLabel = Text(verbatim: unit.isEmpty ? "" : " " + unit)
                .font(prominent ? .title3 : .subheadline).foregroundColor(MasoColor.textDim)
            Text("\(actualLabel)\(unitLabel)\(targetLabel)")
                .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .lineLimit(emphasizesDurationNumbers ? 1 : nil)
                .minimumScaleFactor(emphasizesDurationNumbers ? 0.65 : 1)
            if let target, target.isFinite, target > 0 {
                Group {
                    if exportStyle {
                        ProgressView(value: min(max(0, actual ?? 0), target), total: target)
                            .progressViewStyle(ShareTargetProgressStyle(accent: accent))
                    } else {
                        ProgressView(value: min(max(0, actual ?? 0), target), total: target).tint(accent)
                    }
                }
                .accessibilityValue(Text(verbatim: actualText + (targetText.map { " / " + $0 } ?? "")))
            }
        }
    }

    private var styledActualLabel: Text {
        let numberFont: Font = valueFont ?? (prominent ? .system(size: valueSize, weight: .semibold, design: .rounded) : .title3.weight(.semibold))
        guard emphasizesDurationNumbers, actual != nil else {
            return Text(verbatim: actualText).font(numberFont)
                .foregroundColor(actual == nil ? MasoColor.textDim : MasoColor.text)
        }
        // Keep native spacing/order and Unicode digits; units stay smaller, like Health.
        var runs: [String] = []
        for character in actualText {
            if let last = runs.last, last.last?.isNumber == character.isNumber {
                runs[runs.count - 1].append(character)
            } else { runs.append(String(character)) }
        }
        return runs.reduce(Text(verbatim: "")) { result, run in
            let numeric = run.first?.isNumber == true
            return result + Text(verbatim: run)
                .font(numeric ? numberFont : (prominent ? .title3 : .subheadline))
                .foregroundColor(numeric ? MasoColor.text : MasoColor.textDim)
        }
    }
}

/// Static export uses SwiftUI drawing because native progress widgets cannot be rasterized.
private struct ShareTargetProgressStyle: ProgressViewStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MasoColor.borderSoft)
                Capsule().fill(accent).frame(width: geometry.size.width * min(1, max(0, configuration.fractionCompleted ?? 0)))
            }
        }.frame(height: 4)
    }
}

/// Compact energy-first layout shared by today's and saved historical nutrition cards.
struct DietNutritionSummaryContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let targets: MealNutrition?
    let actual: MealNutrition
    let progress: DietIntakeProgress?
    let hasRecords: Bool
    var exportStyle = false
    private var validTargets: MealNutrition? {
        guard let targets, targets.valid, targets.protein > 0, targets.carbs > 0, targets.fat > 0 else { return nil }
        return targets
    }
    private var calorieFraction: Double? {
        guard hasRecords, let actualCalories = actual.estimatedCalories,
              let targetCalories = validTargets?.estimatedCalories, targetCalories > 0 else { return nil }
        return actualCalories / targetCalories
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
                Label("Calories", systemImage: "fork.knife")
                    .font(.headline).foregroundStyle(MasoColor.text)
                ActualTargetProgress(
                    actualText: hasRecords ? CalorieEstimateText.number(actual.estimatedCalories) : "—",
                    targetText: validTargets?.estimatedCalories.map { CalorieEstimateText.number($0) + " kcal" },
                    actual: hasRecords ? actual.estimatedCalories : nil,
                    target: validTargets?.estimatedCalories,
                    accent: DietProgressColor.color(for: calorieFraction),
                    unit: validTargets == nil && hasRecords ? "kcal" : "",
                    exportStyle: exportStyle, valueFont: .largeTitle.weight(.semibold))
                    .accessibilityIdentifier("diet.daily.calories")
                if validTargets == nil, hasRecords {
                    Text("Historical target unavailable").font(.footnote).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(MasoMetrics.cardPadding)
            Divider().overlay(MasoColor.borderSoft)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                nutrientCell("Protein", actual: actual.protein, target: validTargets?.protein, id: "protein")
                nutrientDivider
                nutrientCell("Carbs", actual: actual.carbs, target: validTargets?.carbs, id: "carbs")
                nutrientDivider
                nutrientCell("Fat", actual: actual.fat, target: validTargets?.fat, id: "fat")
            }.fixedSize(horizontal: false, vertical: true).padding(MasoMetrics.cardPadding)
        }
    }
    private var nutrientDivider: some View {
        Rectangle().fill(MasoColor.borderSoft)
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 1,
                   height: dynamicTypeSize.isAccessibilitySize ? 1 : nil)
            .accessibilityHidden(true)
    }
    private func nutrientCell(_ title: LocalizedStringKey, actual: Double, target: Double?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(MasoColor.textDim)
            VStack(alignment: .leading, spacing: 3) {
                ProgressFractionText(
                    numerator: hasRecords ? actual.formatted(.number.precision(.fractionLength(0...1)).locale(LanguageManager.currentLocale)) : "—",
                    denominator: nil, suffix: " g",
                    numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim)
                Text(verbatim: "/ " + (target.map { $0.formatted(.number.precision(.fractionLength(0)).locale(LanguageManager.currentLocale)) } ?? "—") + " g")
                    .fontWeight(.regular).foregroundStyle(MasoColor.textDim)
            }
            .font(.subheadline).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("diet.daily.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One estimate format across meal editing, records and target editing.
struct CalorieEstimateText: View {
    let nutrition: MealNutrition
    var body: some View {
        Text(verbatim: Self.number(nutrition.estimatedCalories, estimated: true) + " kcal")
            .monospacedDigit()
    }
    static func number(_ value: Double?, estimated: Bool = false) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return (estimated ? "≈ " : "") + value.formatted(.number.precision(.fractionLength(0)).locale(LanguageManager.currentLocale))
    }
}

struct RecordedMealCard: View {
    @Environment(DataStore.self) private var data
    @State private var confirmDeletion = false
    @State private var editing = false
    let record: MealCheckIn
    let number: Int
    var compact = false
    var allowsEditing = true
    var embedded = false
    var usesSavedTargetOnly = false
    var showsDate = true
    var body: some View {
        let savedGoal = usesSavedTargetOnly ? data.savedWellnessGoal(on: record.day) : data.wellnessGoal(on: record.day)
        let targets = savedGoal.map { MealNutrition(protein: Double($0.protein), carbs: Double($0.carbsMinimum), fat: Double($0.fatMinimum)) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(recordHeading)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 8) {
                    Text(record.mealTime, format: .dateTime.hour().minute())
                        .accessibilityIdentifier("meal.record.time")
                    CalorieEstimateText(nutrition: record.nutrition)
                        .accessibilityIdentifier("meal.record.calories")
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let image = MealEditorSheet.loadPhoto(record.photoFilename) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: compact ? 100 : 160)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(record.originalDescription ?? record.foods)
                .font(.subheadline)
                .foregroundStyle(MasoColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                macro("Protein", grams: record.nutrition.protein, target: targets?.protein)
                macro("Carbs", grams: record.nutrition.carbs, target: targets?.carbs)
                macro("Fat", grams: record.nutrition.fat, target: targets?.fat)
            }

        }.applyIf(!compact && !embedded) { $0.cardChrome() }
        .applyIf(compact) { $0.padding(.vertical, 12) }
        .contentShape(Rectangle())
        .onTapGesture { if allowsEditing { editing = true } }
        .sheet(isPresented: $editing) {
            MealEditorSheet(meal: DietMeal(id: record.mealID, title: record.title, portions: []),
                            image: MealEditorSheet.loadPhoto(record.photoFilename), existingRecord: record)
        }
        .contextMenu {
            if allowsEditing {
                Button(role: .destructive) { confirmDeletion = true } label: { Label("Delete meal", systemImage: "trash") }
            }
        }
        .alert("Delete meal?", isPresented: $confirmDeletion) {
            Button("Delete", role: .destructive) { data.deleteMeal(mealID: record.mealID, on: record.day) }
            Button("Cancel", role: .cancel) {}
        }
    }
    private var recordHeading: String {
        let date = record.day.formatted(.dateTime.month(.abbreviated).day().locale(LanguageManager.currentLocale))
        let mealNumber = String.localizedStringWithFormat(NSLocalizedString("Meal %d", comment: "logged meal number"), number)
        return showsDate ? "\(date) · \(mealNumber)" : mealNumber
    }

    private func macro(_ title: LocalizedStringKey, grams: Double, target: Double?) -> some View {
        NutritionRecordMacro(title: title, grams: grams, target: target)
    }

}


struct NutritionRecordMacro: View {
    let title: LocalizedStringKey
    let grams: Double
    let target: Double?
    var body: some View {
        let fraction = target.flatMap { value -> Double? in
            guard value.isFinite, value > 0, grams.isFinite, grams >= 0 else { return nil }
            let ratio = grams / value
            return ratio.isFinite ? ratio : nil
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Group {
                if let target {
                    ProgressFractionText(numerator: grams.formatted(.number.precision(.fractionLength(0...1))),
                                         denominator: target.formatted(.number.precision(.fractionLength(0...1))), suffix: " g",
                                         numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim)
                } else { Text("\(Int(grams.rounded())) g") }
            }.font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DietPreferencesSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @State private var original: DietPreferences
    @State private var originalMacros: [Double]
    @State private var draft: DietPreferences
    @State private var proteinValue: Double
    @State private var carbohydrateValue: Double
    @State private var fatValue: Double
    @State private var selectedPreset: DietTargetPreset
    @State private var calculationPresented = false
    let save: (DietPreferences) -> Void

    init(initial: DietPreferences, settings: UserSettings, save: @escaping (DietPreferences) -> Void) {
        _original = State(initialValue: initial)
        _draft = State(initialValue: initial)
        let derived = DietNutritionTargets.build(settings: settings)
        _proteinValue = State(initialValue: Double(initial.proteinTarget ?? derived?.protein ?? 120))
        _carbohydrateValue = State(initialValue: Double(initial.carbohydrateTarget ?? derived?.carbohydrate ?? 240))
        _fatValue = State(initialValue: Double(initial.fatTarget ?? derived?.fat ?? 60))
        _selectedPreset = State(initialValue: initial.proteinTarget == nil && initial.carbohydrateTarget == nil && initial.fatTarget == nil ? .profileGoal : .custom)
        _originalMacros = State(initialValue: [Double(initial.proteinTarget ?? derived?.protein ?? 120), Double(initial.carbohydrateTarget ?? derived?.carbohydrate ?? 240), Double(initial.fatTarget ?? derived?.fat ?? 60)])
        self.save = save
    }

    private var hasChanges: Bool {
        draft != original || [proteinValue, carbohydrateValue, fatValue] != originalMacros
    }
    private var weightKg: Double? { data.settings.weight }
    private var targetSettings: UserSettings { data.settings }
    private var proteinRange: ClosedRange<Double> { gramRange(0.8...2.4, current: proteinValue) }
    private var carbohydrateRange: ClosedRange<Double> { gramRange(1.5...6.0, floor: 130, current: carbohydrateValue) }
    private var fatRange: ClosedRange<Double> { gramRange(0.5...1.5, current: fatValue) }
    private func gramRange(_ factors: ClosedRange<Double>, floor: Int = 5, current: Double) -> ClosedRange<Double> {
        let weight = weightKg ?? 75
        let derivedLower = max(floor, Int((weight * factors.lowerBound / 5).rounded(.up)) * 5)
        let lower = min(derivedLower, roundedTarget(current))
        let upper = max(derivedLower + 5, max(Int((weight * factors.upperBound / 5).rounded(.down)) * 5, roundedTarget(current)))
        return Double(lower)...Double(upper)
    }
    private func apply(_ preset: DietTargetPreset) {
        guard preset != .custom, let values = DietNutritionTargets.preset(preset, settings: targetSettings) else { return }
        proteinValue = Double(values.protein)
        carbohydrateValue = Double(values.carbohydrate)
        fatValue = Double(values.fat)
    }
    private func roundedTarget(_ value: Double) -> Int { max(5, Int((value / 5).rounded()) * 5) }

    var body: some View {
        AppNavigationStack {
            Form {
                if data.settings.weight == nil {
                    Section {
                        NavigationLink("Body measurements") { BodyProfileScreen() }
                    }
                }
                Section {
                    Picker("Starting point", selection: Binding(get: { selectedPreset }, set: { selectedPreset = $0; apply($0) })) {
                        ForEach(DietTargetPreset.allCases) { preset in Text(LocalizedStringKey(preset.title)).tag(preset) }
                    }
                    LabeledContent("Calories") {
                        CalorieEstimateText(nutrition: MealNutrition(protein: Double(roundedTarget(proteinValue)),
                            carbs: Double(roundedTarget(carbohydrateValue)), fat: Double(roundedTarget(fatValue))))
                            .accessibilityIdentifier("diet.target.calories")
                    }
                    macroSlider("Protein", value: $proteinValue, range: proteinRange, id: "protein")
                    macroSlider("Carbohydrates", value: $carbohydrateValue, range: carbohydrateRange, id: "carbs")
                    macroSlider("Fat", value: $fatValue, range: fatRange, id: "fat")
                    Text("Adjust your daily targets; saved amounts stay fixed.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { calculationPresented = true } label: {
                        Label("How are these targets calculated?", systemImage: "info.circle")
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .font(.footnote).tint(MasoColor.textFaint)
                    .disabled(weightKg == nil)
                } header: { Text("Daily nutrition targets") }
                Section {
                    Picker("Meals per day", selection: Binding(get: { draft.mealCount }, set: { draft.mealsPerDay = $0 })) {
                        ForEach(2...5, id: \.self) { count in Text("\(count) meals").tag(count) }
                    }
                    Picker("Eating window", selection: Binding(get: { draft.windowHours }, set: { draft.eatingWindowHours = $0 })) {
                        Text("Flexible").tag(nil as Int?)
                        Text("12:12 · 12-hour window").tag(Optional(12))
                        Text("14:10 · 10-hour window").tag(Optional(10))
                        Text("16:8 · 8-hour window").tag(Optional(8))
                    }
                    if draft.windowHours != nil {
                        DatePicker("Starts at", selection: Binding(get: { dietClockTime(draft.startMinutes) }, set: { date in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                            draft.windowStartMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                        }), displayedComponents: .hourAndMinute)
                        if let end = draft.endMinutes {
                            LabeledContent("Ends at") {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(dietClockTime(end), format: .dateTime.hour().minute())
                                    if end <= draft.startMinutes { Text("Next day").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                } header: { Text("Meal schedule") } footer: {
                    Text("Meal timing divides your daily amounts; it does not change the daily totals.")
                }
            }
            .navigationTitle("Diet preferences").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(MasoColor.text) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.proteinTarget = roundedTarget(proteinValue)
                        draft.carbohydrateTarget = roundedTarget(carbohydrateValue)
                        draft.fatTarget = roundedTarget(fatValue)
                        save(draft); dismiss()
                    }.tint(MasoColor.text).disabled(weightKg == nil)
                    .accessibilityIdentifier("diet.preferences.save")
                }
            }
            .sheet(isPresented: $calculationPresented) { DietTargetCalculationSheet(settings: targetSettings) }
            .onChange(of: data.settings.weight) { oldValue, newValue in
                if oldValue == nil, newValue != nil, draft.proteinTarget == nil,
                   let values = DietNutritionTargets.preset(.profileGoal, settings: targetSettings) {
                    proteinValue = Double(values.protein)
                    carbohydrateValue = Double(values.carbohydrate)
                    fatValue = Double(values.fat)
                }
            }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .confirmPreferenceDismissal(hasChanges: hasChanges)
    }

    private func macroSlider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(roundedTarget(value.wrappedValue)) g").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; selectedPreset = .custom }), in: range, step: 5)
                .disabled(weightKg == nil)
                .accessibilityLabel(title)
                .accessibilityValue("\(roundedTarget(value.wrappedValue)) grams")
                .accessibilityIdentifier("diet.target.slider.\(id)")
        }
    }
}

private struct DietTargetCalculationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let settings: UserSettings
    private var currentTargets: DietNutritionTargets? { DietNutritionTargets.build(settings: settings) }
    var body: some View {
        AppNavigationStack {
            List {
                Section("Your starting point") {
                    Text("We use your body weight and training goal to set protein and carbohydrate targets. Weekly training days also shape your starting carbs; fat starts at about 0.8 g per kg of body weight.")
                    if let weight = settings.weight {
                        LabeledContent("Body weight", value: "\(Int(weight.rounded())) \(settings.weightUnit.label)")
                    }
                    LabeledContent("Training days", value: "\(settings.weeklyTrainingDays) / week")
                    if let targets = currentTargets {
                        LabeledContent("Profile-based starting point", value: "P \(targets.protein) · C \(targets.carbohydrate) · F \(targets.fat) g")
                    }
                }
                Section("Make it yours") {
                    Text("Choose a starting point, then adjust each slider. Your saved gram amounts become your daily targets. Changing the number of meals only splits those totals across the day.")
                    Text("Automatic carb adjustments apply only before you set a daily carbohydrate target.")
                }
                Section("A practical guide") {
                    Text("The presets are simple starting estimates based on body weight and common sports-nutrition guidance. They are not measurements of your calorie needs or medical advice. Choose amounts that fit your appetite, training and guidance from your clinician or dietitian.")
                    Link("ISSN · Protein and exercise", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/")!)
                    Link("ACSM · Nutrition and athletic performance", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/26891166/")!)
                }
            }
            .navigationTitle("About your targets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) } }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

private struct DietNutritionInfoSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AppNavigationStack {
            List {
                Section("Calories") {
                    Text("Estimated from protein, carbs and fat.")
                    Link("USDA · Food energy", destination: URL(string: "https://www.nal.usda.gov/programs/fnic")!)
                    if let progress = DietIntakeProgress.calculate(goal: data.wellnessGoal(on: Date()), meals: data.wellnessMeals(on: Date())) {
                        LabeledContent("Diet score", value: (Double(progress.percent) / 100).formatted(.percent.precision(.fractionLength(0)).locale(LanguageManager.currentLocale)))
                    }
                }
                Section("Personal daily targets") {
                    Text("Your fixed gram targets use the weight, training goal and weekly training frequency saved in Masso. If you are 65 or older, the protein factor is raised modestly. Meal count only divides the daily targets; it does not change them.")
                    Text("Carbohydrate uses your goal and planned training days, with a 130 g adult reference floor. Fat uses a simple 0.8 g/kg planning value. These are practical estimates, not measured calorie needs or medical prescriptions.")
                    Text("Targets use weight and training preferences. Health activity is a reference, not an extra food allowance.")
                    Link("ISSN · Protein and exercise (2017)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/")!)
                    Link("National Academies · Dietary Reference Intakes", destination: URL(string: "https://nap.nationalacademies.org/catalog/10490/dietary-reference-intakes-for-energy-carbohydrate-fiber-fat-fatty-acids-cholesterol-protein-and-amino-acids")!)
                }
                Section("Daily adjustments") {
                    if let guidance = data.dietGuidance() {
                        Text(LocalizedStringKey(guidance.subtitleKey))
                        LabeledContent("Carb adjustment", value: "\(guidance.carbohydrateAdjustment > 0 ? "+" : "")\(guidance.carbohydrateAdjustment) g")
                    }
                    Text("Carbs follow logged workouts and working sets. Training/rest offsets use 0.5 g/kg around your weekly average; high-volume days add 0.3 g/kg. The change is limited to 50 g either way, with a 130 g floor. These are Masso planning rules, not exact doses from a study.")
                    Text("Protein and fat remain steady. Sleep under 7 hours changes the recovery advice, not your macro targets: sleep studies do not establish a gram adjustment for missed sleep.")
                    Text("Each meal shows its share of the full daily targets. Today's targets update with your workout records; earlier days retain their saved targets.")
                    Link("Carbs and resistance training · Review (2022)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8878406/")!)
                    Link("Carb feeding · Meta-analysis (2022)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC9584980/")!)
                    Link("Sleep and dietary intake · Review (2020)", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/33001515/")!)
                }
                Section("Protein across the day") {
                    Text("Protein is split evenly across your selected 2–5 meals. Changing meal count or eating window keeps the daily target unchanged.")
                    Text("Daily protein and consistent training matter most. Small trials support balanced meals for muscle protein synthesis; long-term muscle-growth results are mixed.")
                    Link("ISSN · Protein and exercise (2017)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/")!)
                    Link("Mamerow · Protein distribution (2014)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4018950/")!)
                    Link("Protein distribution review (2020)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC7285146/")!)
                }
                Section("Carbs and dinner") {
                    Text("Two meals split carbs 45% / 55%. With three meals, the split is 25% / 35% / 40%. Four meals reserve 15% for a snack; five reserve 10% for each of two snacks. The remaining carbs follow the three-meal split.")
                    Text("These percentages are an app planning default, not a proven optimal ratio. A small trial found faster sleep onset with a high-GI meal four hours before bed; other trials found no benefit. More dinner carbs do not guarantee better sleep or justify cutting dinner protein.")
                    Link("Afaghi · Carbs and sleep (2007)", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/17284739/")!)
                    Link("Athletes' evening meals trial (2019)", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/30994759/")!)
                }
                Section("Eating window") {
                    Text("Flexible timing is the default. 12:12, 14:10 and 16:8 describe fasting hours and eating hours. A shorter window does not lower your daily nutrition targets or guarantee better muscle growth.")
                    Link("NIDDK · Time-restricted eating", destination: URL(string: "https://www.niddk.nih.gov/health-information/professionals/diabetes-discoveries-practice/patients-intermittent-fasting")!)
                }
                Section("Portion guide") {
                    Text("Approximate cooked weights; oats are dry, yogurt/tofu are packaged weights, fruit is edible weight. Swaps match protein or carbs, not all nutrients. Cooking fats are not included in these portions.")
                }
            }
            .navigationTitle("Meal balance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) } }
        }.tint(MasoColor.dietAccent).presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

private struct DietCarouselHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DietCarouselSizing: ViewModifier {
    let height: CGFloat?
    let measures: Bool
    func body(content: Content) -> some View {
        if measures {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DietCarouselHeightKey.self, value: geometry.size.height)
                    }
                }
                .frame(height: height, alignment: .top)
        } else {
            content
        }
    }
}

struct SleepHomeSection: View {
    var detail = false
    @Environment(DataStore.self) private var data
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing = false
    @State private var infoPresented = false
    @State private var recordsPresented = false
    @State private var lastNightDetailsExpanded = false
    @State private var connecting = false
    @State private var errorMessage: String?
    private var preferences: SleepPreferences { data.settings.sleepPreferences ?? SleepPreferences() }
    private var key: String { SleepPreferences.dayKey(Date(), calendar: data.settings.calendar) }
    private var minutes: Double? {
        HealthKitService.shared.sleepMinutes[data.settings.calendar.startOfDay(for: Date())] ?? data.settings.sleepRecords?[key]
    }
    private var stages: SleepStagesRecord? {
        HealthKitService.shared.sleepStages[data.settings.calendar.startOfDay(for: Date())] ?? data.settings.sleepStageRecords?[key]
    }
    private var nightGoal: Int? { data.savedSleepTarget(on: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
            combinedCard
            Button { infoPresented = true } label: {
                Label("Why this sleep target?", systemImage: "info.circle").font(.footnote)
            }.tint(MasoColor.textFaint)
        }
        .navigationTitle("Sleep").navigationBarTitleDisplayMode(.large).toolbarRole(.navigationStack)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                    .tint(MasoColor.text).accessibilityLabel("Sleep preferences")
            }
        }
        .sheet(isPresented: $editing) {
            SleepScheduleSheet(initial: preferences) { updated in data.settings.applySleepPreferences(updated); data.save() }
        }
        .sheet(isPresented: $infoPresented) { SleepInfoSheet() }
        .sheet(isPresented: $recordsPresented) { SleepHealthRecordsSheet() }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
        .alert("Couldn't read sleep data", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    private var combinedCard: some View {
        let day = data.settings.calendar.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: 16) {
            SleepTargetSummaryContent(targetMinutes: minutes == nil ? preferences.targetMinutes : nightGoal,
                                      actualMinutes: minutes, actualTargetMinutes: minutes == nil ? nil : nightGoal)
            Divider()
            SleepNightChart(day: day, intervals: HealthKitService.shared.sleepTimelines[day] ?? [],
                            minutes: minutes, heading: "Last night", detailsExpanded: $lastNightDetailsExpanded,
                            connectAction: preferences.healthConnected ? nil : connectSleep, connecting: connecting,
                            embedded: true, usesSavedTargetOnly: true, showsStandaloneSummary: false)
        }.contentCardChrome()
    }

    private func connectSleep() {
        connecting = true
        Task {
            do {
                try await HealthKitService.shared.connectSleep()
                var updated = preferences; updated.healthConnected = true
                data.settings.sleepPreferences = updated; data.save(); await refresh()
            } catch { errorMessage = error.localizedDescription }
            connecting = false
        }
    }

    private func duration(_ minutes: Double) -> Text {
        Text(Duration.seconds(minutes * 60), format: .time(pattern: .hourMinute)).monospacedDigit()
    }
    private func stageRow(_ title: LocalizedStringKey, minutes: Double?) -> some View {
        HStack { Text(title); Spacer(); if let minutes { duration(minutes) } else { Text("—") } }.font(.subheadline)
    }
    private func refresh() async {
        do { try await data.refreshSleepSummary() } catch { errorMessage = error.localizedDescription }
    }
}

func sleepScorePercent(_ minutes: Double, target: Int) -> Int {
    guard minutes.isFinite, minutes >= 0, target > 0 else { return 0 }
    return Int((min(minutes, Double(target)) / Double(target) * 100).rounded())
}

/// Shared expandable stage details for every recorded night.
private struct SleepDetailsContent: View {
    @Environment(DataStore.self) private var data
    @State private var recordsPresented = false
    let day: Date
    private var stages: SleepStagesRecord? {
        data.recordedSleepStages[data.settings.calendar.startOfDay(for: day)]
    }
    var body: some View {
        VStack(spacing: 12) {
            Divider()
            row("Deep sleep", minutes: stages?.deep)
            row("REM sleep", minutes: stages?.rem)
            row("Core sleep", minutes: stages?.core)
            if let awake = stages?.awake { row("Awake", minutes: awake) }
            if let inBed = stages?.inBed { row("In bed", minutes: inBed) }
            if let unspecified = stages?.unspecified { row("Sleep (unspecified)", minutes: unspecified) }
            if stages == nil {
                Text("Your device hasn't provided sleep stages.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Personal reference").font(.subheadline).foregroundStyle(.secondary)
            referenceRow("Deep sleep", deep: true)
            referenceRow("REM sleep", deep: false)
            if data.settings.sleepPreferences?.healthConnected == true {
                Button("View Apple Health records") { recordsPresented = true }
                    .font(.caption).tint(MasoColor.sleepAccent).buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $recordsPresented) { SleepHealthRecordsSheet() }
    }
    private func referenceRow(_ title: LocalizedStringKey, deep: Bool) -> some View {
        let values = SleepStagesRecord.priorValues(on: day, calendar: data.settings.calendar,
                                                   records: data.recordedSleepStages, stage: deep ? \.deep : \.rem)
        return HStack {
            Text(title).font(.subheadline)
            Spacer()
            if let range = SleepStagesRecord.reference(values) {
                Text(verbatim: compactSleepDuration(range.lowerBound) + " – " + compactSleepDuration(range.upperBound))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else { Text("Building your baseline").font(.subheadline).foregroundStyle(.secondary) }
        }
    }
    private func row(_ title: LocalizedStringKey, minutes: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(minutes.map { compactSleepDuration($0) } ?? "—").monospacedDigit()
        }.font(.subheadline).foregroundStyle(MasoColor.text)
    }
}

struct SleepTargetSummaryContent: View {
    @Environment(DataStore.self) private var data
    let targetMinutes: Int?
    let actualMinutes: Double?
    var actualTargetMinutes: Int? = nil
    var actualLabel: LocalizedStringKey = "Last night"
    var exportStyle = false
    var day: Date? = nil
    @State private var deepInfoPresented = false
    private var stageRecords: [Date: SleepStagesRecord] {
        data.recordedSleepStages
    }
    private var validTarget: Int? {
        (actualTargetMinutes ?? targetMinutes).flatMap { $0 > 0 ? $0 : nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
            HStack(alignment: .top) {
                Label { Text(actualLabel).foregroundStyle(MasoColor.text) } icon: {
                    Image(systemName: "moon").foregroundStyle(MasoColor.sleepAccent)
                }.font(.headline)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Sleep score").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: actualMinutes.flatMap { minutes in
                        validTarget.map { (Double(sleepScorePercent(minutes, target: $0)) / 100).formatted(.percent.precision(.fractionLength(0)).locale(LanguageManager.currentLocale)) }
                    } ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                }
            }
            ActualTargetProgress(actualText: actualMinutes.map(compactSleepDuration) ?? "—",
                                 targetText: validTarget.map { compactSleepDuration(Double($0)) },
                                 actual: actualMinutes, target: validTarget.map(Double.init), accent: MasoColor.sleepAccent,
                                 exportStyle: exportStyle, emphasizesDurationNumbers: true)
            let night = data.settings.calendar.startOfDay(for: day ?? Date())
            let deep = stageRecords[night]?.deep
            let reference = SleepStagesRecord.deepReference(on: night, calendar: data.settings.calendar, records: stageRecords)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Deep sleep").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    ProgressFractionText(numerator: deep.map(compactSleepDuration) ?? "—",
                                         denominator: reference.map(compactSleepDuration) ?? "—")
                        .font(.subheadline).monospacedDigit()
                    Text(verbatim: deep.flatMap { actual in reference.map {
                        (actual / $0).formatted(.percent.precision(.fractionLength(0)).locale(LanguageManager.currentLocale))
                    }} ?? "—").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if !exportStyle {
                    SleepPersonalReferenceInfo(isPresented: $deepInfoPresented)
                }
            }
            if validTarget == nil, actualMinutes != nil {
                Text("Historical target unavailable").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Keep the native popover sized to its explanation, rather than the short trigger label.
struct SleepPersonalReferenceInfo: View {
    @Binding var isPresented: Bool
    var body: some View {
        Button { isPresented = true } label: {
            Label("Personal reference", systemImage: "info.circle").font(.caption)
                .foregroundStyle(MasoColor.textFaint)
        }.buttonStyle(.plain).tint(MasoColor.textFaint)
        .popover(isPresented: $isPresented) {
            ViewThatFits(in: .vertical) {
                explanation
                ScrollView { explanation }.scrollBounceBehavior(.basedOnSize)
            }
            .frame(idealWidth: 280, maxWidth: 280, alignment: .leading)
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
    }
    private var explanation: some View {
        Text("Deep sleep is compared with the median of your previous 14 days, using at least 3 recorded nights. It is a personal reference, not a medical target, and does not affect Sleep score. Missing sleep stages or insufficient history show —.")
            .font(.body).lineLimit(nil).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SleepNightChart: View {
    @Environment(DataStore.self) private var data
    let day: Date
    let intervals: [SleepStageInterval]
    let minutes: Double?
    var heading: LocalizedStringKey? = nil
    var detailsExpanded: Binding<Bool>? = nil
    var connectAction: (() -> Void)? = nil
    var connecting = false
    var embedded = false
    var usesSavedTargetOnly = false
    var showsStandaloneSummary = true
    var showsDetailsControl = true
    @State private var localDetailsExpanded = false
    private var expansion: Binding<Bool> { detailsExpanded ?? $localDetailsExpanded }
    private var rows: [String] {
        let standard = ["Awake", "REM sleep", "Core sleep", "Deep sleep"]
        return intervals.contains { $0.stage == "Sleep (unspecified)" } ? standard + ["Sleep (unspecified)"] : standard
    }
    private var timeBounds: ClosedRange<Date> {
        let start = intervals.map(\.start).min() ?? day
        let end = intervals.map(\.end).max() ?? start.addingTimeInterval(3600)
        return start...max(end, start.addingTimeInterval(60))
    }
    private var timeEndpoints: [Date] {
        guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max(), end > start else { return [] }
        return [start, end]
    }
    private var nightlyTarget: Int? {
        if usesSavedTargetOnly { return data.savedSleepTarget(on: day) }
        let key = SleepPreferences.dayKey(day, calendar: data.settings.calendar)
        return data.settings.sleepPreferences?.recordedGoals[key]
            ?? data.wellnessGoal(on: day)?.sleepMinutes
            ?? (data.settings.sleepPreferences ?? SleepPreferences()).targetMinutes
    }
    private func stageLabel(_ stage: String) -> String {
        switch stage {
        case "REM sleep": "REM"
        case "Core sleep": "Core"
        case "Deep sleep": "Deep"
        case "Awake": "Awake"
        default: NSLocalizedString("Sleep (unspecified)", comment: "sleep chart missing stages")
        }
    }
    private func color(_ stage: String) -> Color {
        switch stage {
        case "Awake": Color(red: 1, green: 0.43, blue: 0.33)
        case "REM sleep": Color(red: 0.38, green: 0.79, blue: 0.96)
        case "Core sleep": Color(red: 0.20, green: 0.54, blue: 0.97)
        case "Deep sleep": Color(red: 0.23, green: 0.20, blue: 0.62)
        default: .gray
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsStandaloneSummary {
            HStack {
                if let heading { Text(heading).font(.headline) }
                else { Text(day, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated)).font(.headline) }
                Spacer()
            }
            if minutes == nil { Text("No sleep data yet").font(.subheadline).foregroundStyle(.secondary) }
            }
            if !intervals.isEmpty {
            Chart(intervals) { interval in
                RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("End", interval.end), y: .value("Stage", interval.stage), height: .ratio(0.62))
                    .foregroundStyle(Color.clear)
                    .accessibilityLabel(Text(LocalizedStringKey(interval.stage)))
                    .accessibilityValue(Text("\(interval.start.formatted(date: .omitted, time: .shortened)) – \(interval.end.formatted(date: .omitted, time: .shortened))"))
            }
            .chartBackground { proxy in transitionBackground(proxy) }
            .chartXScale(domain: timeBounds, range: .plotDimension(startPadding: 8, endPadding: 8))
            .chartYScale(domain: rows)
            .chartYAxis {
                AxisMarks(position: .leading, values: rows) { value in
                    AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                    AxisValueLabel {
                        if let stage = value.as(String.self) {
                            Text(verbatim: stageLabel(stage)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(MasoColor.borderSoft)
                }
            }
            .frame(height: rows.count == 5 ? 315 : 265)
            if timeEndpoints.count == 2 {
                HStack(spacing: 8) {
                    Text(timeEndpoints[0], format: .dateTime.hour().minute().locale(LanguageManager.currentLocale))
                        .accessibilityIdentifier("sleep.chart.start")
                    Spacer(minLength: 8)
                    Text(timeEndpoints[1], format: .dateTime.hour().minute().locale(LanguageManager.currentLocale))
                        .accessibilityIdentifier("sleep.chart.end")
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }
            }
            if showsDetailsControl {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expansion.wrappedValue.toggle() }
            } label: {
            HStack {
                Text(showsStandaloneSummary ? LocalizedStringKey("Total sleep") : LocalizedStringKey("Sleep details")).font(.subheadline)
                Spacer()
                if showsStandaloneSummary {
                if let minutes {
                    Text(verbatim: compactSleepDuration(minutes))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Group {
                    if let deep = HealthKitService.shared.sleepStages[day]?.deep
                        ?? data.settings.sleepStageRecords?[SleepPreferences.dayKey(day, calendar: data.settings.calendar)]?.deep {
                        Text(verbatim: compactSleepDuration(deep))
                    } else {
                        Text("—")
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                .accessibilityLabel(Text("Deep sleep"))
                }
                Image(systemName: expansion.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(MasoColor.text)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sleep details")
            if expansion.wrappedValue { SleepDetailsContent(day: day) }
            }
            if showsStandaloneSummary, let minutes, let nightlyTarget {
                Divider()
                HStack {
                    Text("Sleep score").font(.subheadline)
                    Spacer()
                    Text("\(sleepScorePercent(minutes, target: nightlyTarget))%")
                        .font(.headline).monospacedDigit()
                }
            }
            if let connectAction {
                PrimaryActionButton(title: "Connect Apple Health", icon: "heart", accent: MasoColor.sleepAccent,
                                    loading: connecting, action: connectAction).disabled(connecting)
            }
        }.applyIf(!embedded) { $0.cardChrome() }
    }
    private func transitionBackground(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame {
                let plot = geometry[plotFrame]
                Canvas { context, _ in
                    context.clip(to: Path(plot))
                    let centers = rows.compactMap { proxy.position(forY: $0) }.sorted()
                    let rowHeight = zip(centers, centers.dropFirst()).map { abs($1 - $0) }.min() ?? plot.height
                    let blockHeight = rowHeight * 0.62
                    let padding: CGFloat = 2.5
                    let cornerRadius: CGFloat = 7
                    var blocks: [(rect: CGRect, stage: String)] = []
                    var silhouette: CGPath?
                    func unite(_ rect: CGRect) {
                        let component = CGPath(rect: rect, transform: nil)
                        if let existing = silhouette {
                            silhouette = existing.union(component)
                        } else { silhouette = component }
                    }
                    for interval in intervals {
                        guard let start = proxy.position(forX: interval.start),
                              let end = proxy.position(forX: interval.end),
                              let y = proxy.position(forY: interval.stage) else { continue }
                        let block = CGRect(x: plot.minX + start, y: plot.minY + y - blockHeight / 2, width: max(1, end - start), height: blockHeight)
                        blocks.append((block, interval.stage))
                        unite(block.insetBy(dx: -padding, dy: -padding))
                    }
                    for transition in SleepStageInterval.transitions(intervals) {
                        guard let xPosition = proxy.position(forX: transition.from.end),
                              let fromY = proxy.position(forY: transition.from.stage),
                              let toY = proxy.position(forY: transition.to.stage) else { continue }
                        let rect = CGRect(x: plot.minX + xPosition - padding, y: plot.minY + min(fromY, toY) - blockHeight / 2 - padding, width: padding * 2, height: abs(toY - fromY) + blockHeight + padding * 2)
                        unite(rect)
                    }
                    let stops = rows.compactMap { stage -> Gradient.Stop? in
                        guard let y = proxy.position(forY: stage) else { return nil }
                        return .init(color: color(stage).opacity(0.38), location: min(1, max(0, y / plot.height)))
                    }.sorted { $0.location < $1.location }
                    if let silhouette {
                        let outline = roundedSleepOutline(silhouette, radius: cornerRadius + padding)
                        context.drawLayer { layer in
                            layer.addFilter(.blur(radius: 0.2))
                            layer.fill(outline, with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)))
                        }
                    }
                    for block in blocks {
                        let radius = min(cornerRadius, block.rect.width / 2, block.rect.height / 2)
                        let path = Path(roundedRect: block.rect, cornerRadius: radius)
                        context.fill(path, with: .color(color(block.stage)))
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

}

// Round the boundary after unioning, including inward corners at each junction.
// Rounding components before their union creates small caps at the seams.
private func roundedSleepOutline(_ outline: CGPath, radius: CGFloat) -> Path {
    var polygons: [[CGPoint]] = []
    var points: [CGPoint] = []
    outline.applyWithBlock { element in
        switch element.pointee.type {
        case .moveToPoint:
            if !points.isEmpty { polygons.append(points) }
            points = [element.pointee.points[0]]
        case .addLineToPoint: points.append(element.pointee.points[0])
        case .closeSubpath:
            if !points.isEmpty { polygons.append(points); points = [] }
        default: break
        }
    }
    if !points.isEmpty { polygons.append(points) }
    var result = Path()
    for var polygon in polygons {
        if polygon.first == polygon.last { polygon.removeLast() }
        guard polygon.count > 2 else { continue }
        let corners = polygon.indices.map { index -> (entry: CGPoint, exit: CGPoint, vertex: CGPoint) in
            let vertex = polygon[index]
            let previous = polygon[(index + polygon.count - 1) % polygon.count]
            let next = polygon[(index + 1) % polygon.count]
            let before = hypot(previous.x - vertex.x, previous.y - vertex.y)
            let after = hypot(next.x - vertex.x, next.y - vertex.y)
            let distance = min(radius, before / 2, after / 2)
            func toward(_ point: CGPoint, length: CGFloat) -> CGPoint {
                guard length > 0 else { return vertex }
                return CGPoint(x: vertex.x + (point.x - vertex.x) * distance / length, y: vertex.y + (point.y - vertex.y) * distance / length)
            }
            return (toward(previous, length: before), toward(next, length: after), vertex)
        }
        result.move(to: corners[0].exit)
        for index in 1...corners.count {
            let corner = corners[index % corners.count]
            result.addLine(to: corner.entry)
            result.addQuadCurve(to: corner.exit, control: corner.vertex)
        }
        result.closeSubpath()
    }
    return result
}

private struct SleepInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AppNavigationStack {
            List {
                Section("Why 8 hours?") {
                    Text("Adults generally need 7–9 hours a night. Eight hours is a starting point, not a precise calculation from your workout or body weight. Adjust for how rested you feel.")
                    Link("NIH · Recommended sleep duration", destination: URL(string: "https://www.nhlbi.nih.gov/health/sleep/how-much-sleep")!)
                    Link("AASM / SRS · Adult sleep consensus (2015)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4442216/")!)
                }
                Section("Sleep and recovery") {
                    Text("Sleep supports recovery and performance. A small experiment found lower muscle protein synthesis after one sleepless night. It does not prove that every extra hour produces more muscle, or that everyone needs the same duration.")
                    Link("Lamon · Sleep loss and muscle protein synthesis (2021)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC7785053/")!)
                }
                Section("Deep sleep and REM") {
                    Text("Stage durations vary with age, night and device. Your ranges summarize the previous 14 days once at least 7 nights are available; they are personal references, not recommended targets. Apple Watch stages are estimates.")
                    Link("Apple · Sleep tracking", destination: URL(string: "https://support.apple.com/en-ie/108906")!)
                }
                Section("Apple Health records") {
                    Text("Masso reads all authorized sleep-analysis history: core, deep, REM, unspecified sleep, awake and in-bed samples, with times and sources. Missing stages stay blank. Overlapping sources are not added together; detailed stage data is preferred for nightly totals. These totals may differ from Apple's source priorities. In-bed time is not sleep time.")
                    Text("Allow Sleep access in Apple Health. Data appears after your device syncs. HealthKit does not reveal whether read access was denied, so no records can mean no data or no permission.")
                    Link("Apple · Sleep-analysis data", destination: URL(string: "https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis")!)
                }
            }.navigationTitle("About sleep").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) } }
        }.tint(MasoColor.sleepAccent).presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

private struct SleepHealthRecordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AppNavigationStack {
            List {
                let samples = HealthKitService.shared.sleepSamples
                if samples.isEmpty {
                    Text("No sleep data yet").foregroundStyle(.secondary)
                }
                ForEach(samples) { sample in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(LocalizedStringKey(sample.title)).font(.headline)
                            Spacer()
                            Text(Duration.seconds(sample.end.timeIntervalSince(sample.start)), format: .time(pattern: .hourMinute)).monospacedDigit()
                        }
                        Text("\(sample.start.formatted(date: .abbreviated, time: .shortened)) – \(sample.end.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text(sample.source).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Apple Health sleep records").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct SleepScheduleSheet: View {
    @Environment(DataStore.self) private var data
    @State private var original: SleepPreferences
    @State private var permissionDenied = false
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @State var draft: SleepPreferences
    let save: (SleepPreferences) -> Void
    init(initial: SleepPreferences, save: @escaping (SleepPreferences) -> Void) { _original = State(initialValue: initial); _draft = State(initialValue: initial); self.save = save }
    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(get: { draft.targetMinutes }, set: { draft.durationTargetMinutes = $0 }), in: 240...720, step: 30) {
                        LabeledContent("Sleep target") {
                            Text(Duration.seconds(Double(draft.targetMinutes) * 60), format: .time(pattern: .hourMinute)).monospacedDigit()
                        }
                    }
                }
                Section {
                    Toggle("Bedtime reminder", isOn: Binding(get: { draft.bedtimeReminderEnabled ?? false }, set: { enabled in
                        draft.bedtimeReminderEnabled = enabled
                    })).toggleStyle(.switch)
                    if draft.bedtimeReminderEnabled == true {
                        DatePicker("Reminder time", selection: timeBinding($draft.bedtimeMinutes), displayedComponents: .hourAndMinute)
                    }
                    Text("Sleep recorded by Apple Watch or compatible devices appears through Apple Health.")
                }
            }
            .navigationTitle("Sleep preferences").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(MasoColor.text).disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveDraft() }.tint(MasoColor.text).disabled(draft.targetMinutes == 0 || saving) }
            }
        }.tint(MasoColor.sleepAccent).presentationDetents([.large]).presentationDragIndicator(.visible)
        .confirmPreferenceDismissal(hasChanges: draft != original)
        .alert("Notifications are off", isPresented: $permissionDenied) {
            Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Allow Masso notifications in Settings to receive bedtime reminders.") }
    }
    private func saveDraft() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            if draft.bedtimeReminderEnabled == true {
                let granted = await WorkoutReminderScheduler.shared.requestAuthorization()
                guard granted else { permissionDenied = true; saving = false; return }
            }
            var updated = data.settings.sleepPreferences ?? original
            updated.durationTargetMinutes = draft.durationTargetMinutes
            updated.bedtimeMinutes = draft.bedtimeMinutes
            updated.bedtimeReminderEnabled = draft.bedtimeReminderEnabled
            save(updated)
            saving = false
            dismiss()
        }
    }
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date())! }, set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
}

struct MealEditorSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let meal: DietMeal
    let existingRecord: MealCheckIn?
    @State private var image: UIImage?
    @State private var pickedImage: UIImage?
    @State private var photoLoadingFailed = false
    @State private var replacementSource: PhotoPickerSource?
    @State private var photoActionsPresented = false
    @State private var previousMealsPresented = false
    @State private var copiedMealID: String?
    @State private var analysisRequestID = UUID()
    @State private var description = ""
    @State private var consumedAt = Date()
    @State private var analyzedDescription: String?
    @State private var foods = ""
    @State private var nutrition = MealNutrition()
    @State private var nutrientAnalysis: MealNutritionAnalysis?
    @State private var analyzing = false
    @State private var error: String?
    @State private var analysisTask: Task<Void, Never>?
    @State private var aiUpgradePrompt = UpgradePrompt()
    @FocusState private var descriptionFocused: Bool
    init(meal: DietMeal, image: UIImage?, existingRecord: MealCheckIn? = nil, initialEstimate: MealPhotoEstimate? = nil, initialDescription: String? = nil) {
        self.meal = meal
        self.existingRecord = existingRecord
        _consumedAt = State(initialValue: existingRecord?.mealTime ?? Date())
        _image = State(initialValue: image)
        _description = State(initialValue: existingRecord?.originalDescription ?? existingRecord?.foods ?? initialDescription ?? initialEstimate?.foods ?? "")
        _analyzedDescription = State(initialValue: existingRecord.map { $0.originalDescription ?? $0.foods } ?? initialEstimate?.foods)
        _foods = State(initialValue: existingRecord?.foods ?? initialEstimate?.foods ?? "")
        _nutrition = State(initialValue: existingRecord?.nutrition ?? initialEstimate?.nutrition ?? MealNutrition())
        _nutrientAnalysis = State(initialValue: existingRecord?.analysis ?? initialEstimate?.analysis)
    }
    var body: some View {
        AppNavigationStack {
            Form {
                if existingRecord == nil && !previousMeals.isEmpty {
                    Section {
                        Button {
                            descriptionFocused = false
                            previousMealsPresented = true
                        } label: {
                            Label("Choose a previous meal", systemImage: "clock.arrow.circlepath")
                        }
                        .disabled(analyzing)
                        .accessibilityIdentifier("meal.previous.open")
                    }
                }
                Section {
                    DatePicker("Meal time", selection: $consumedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .environment(\.calendar, data.settings.calendar)
                        .accessibilityIdentifier("meal.time")
                }

                Section {
                    if let image {
                        Button { descriptionFocused = false; photoActionsPresented = true } label: {
                            GeometryReader { geometry in
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            }
                            .frame(height: 220)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Replace photo")
                    } else {
                        Button {
                            descriptionFocused = false
                            photoActionsPresented = true
                        } label: {
                            AddPhotoPlaceholder()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                        .listRowBackground(Color.clear)
                    }
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $description)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .focused($descriptionFocused)
                            .disabled(analyzing)
                        if description.isEmpty {
                            Text("e.g. Two eggs, a bowl of rice and a glass of milk")
                                .font(.body).foregroundStyle(.tertiary)
                                .padding(.horizontal, 5).padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 200)
                    .accessibilityLabel("Foods and portions")
                }
                if nutrition.valid, nutrition.protein + nutrition.carbs + nutrition.fat > 0,
                   description.trimmingCharacters(in: .whitespacesAndNewlines) == analyzedDescription?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Section {
                        LabeledContent("Calories") {
                            CalorieEstimateText(nutrition: nutrition)
                                .accessibilityIdentifier("meal.estimate.calories")
                        }
                        if let breakdown = nutrientAnalysis {
                        DisclosureGroup("Nutrition estimate") {
                            ForEach(breakdown.items) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    LabeledContent {
                                        HStack(spacing: 4) {
                                            NumericValueField(value: Binding(
                                                get: { nutrientAnalysis?.items.first(where: { $0.id == item.id })?.grams ?? item.grams },
                                                set: { updateAmount(id: item.id, grams: $0) }
                                            ), range: 0...3000)
                                                .accessibilityLabel(item.name).frame(width: 72)
                                            Text("g").foregroundStyle(.secondary)
                                        }
                                    } label: { Text(item.name).font(.subheadline) }
                                    switch item.source {
                                    case .database:
                                        if let id = item.fdcID, let url = URL(string: "https://fdc.nal.usda.gov/food-search/?query=\(id)") {
                                            Link("Food data: USDA", destination: url).font(.caption).tint(MasoColor.dietAccent)
                                        }
                                    case .label: Text("Nutrition label").font(.caption).foregroundStyle(.secondary)
                                    case .model: Text("AI estimate").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                        }
                        HStack {
                            previewMacro("Protein", grams: nutrition.protein)
                            Spacer()
                            previewMacro("Carbs", grams: nutrition.carbs)
                            Spacer()
                            previewMacro("Fat", grams: nutrition.fat)
                        }
                    } footer: {
                        if nutrientAnalysis?.hasEstimatedPortions == true { Text("Estimated portions. Adjust grams if needed.") }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(LocalizedStringKey(existingRecord == nil ? "Add meal" : "Edit meal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { analysisTask?.cancel(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if analyzing {
                        HStack { ProgressView(); Text("Analyzing meal…").font(.subheadline) }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Button { generateMeal() } label: {
                        TrainingCardActionLabel(
                            title: LocalizedStringKey(existingRecord == nil ? "Add meal" : "Save changes"),
                            icon: existingRecord == nil ? "plus" : "checkmark",
                            accent: MasoColor.dietAccent
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(analyzing || consumedAt > Date() || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("meal.save")
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
            .confirmationDialog("Photo", isPresented: $photoActionsPresented) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { replacementSource = .camera }
                }
                Button("Choose from Library") { replacementSource = .photoLibrary }
                if image != nil { Button("Remove photo", role: .destructive) { image = nil } }
            }
            .sheet(isPresented: $previousMealsPresented) {
                previousMealsPicker
            }
            .sheet(item: pickerSource(.photoLibrary), onDismiss: finishPickingPhoto) { source in
                // Stage the result; updating the Form and starting AI while the
                // camera is still transitioning caused a keyboard-layout crash.
                PhotoPicker(image: $pickedImage, source: source,
                            onLoadFailure: { photoLoadingFailed = true }).ignoresSafeArea()
            }
            .fullScreenCover(item: pickerSource(.camera), onDismiss: finishPickingPhoto) { source in
                // Camera owns the full screen, rather than a nested draggable
                // sheet that reparents its keyboard layout guide during closing.
                PhotoPicker(image: $pickedImage, source: source,
                            onLoadFailure: { photoLoadingFailed = true }).ignoresSafeArea()
            }
            .onChange(of: image) { _, newImage in
                analysisTask?.cancel()
                analysisRequestID = UUID()
                analyzing = false; error = nil
                if newImage != nil {
                    description = ""; analyzedDescription = nil; foods = ""; nutrition = MealNutrition(); nutrientAnalysis = nil
                    descriptionFocused = false
                    aiUpgradePrompt.requestAI(isPro: data.settings.isPro, source: "meal_photo") {
                        analysisTask = Task { await analyzePhoto() }
                    }
                }
            }
            .onChange(of: description) { _, _ in error = nil }
            .onDisappear { analysisTask?.cancel() }
        }
        .tint(MasoColor.text)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .aiUpgradeReminder(aiUpgradePrompt)
    }

    private var previousMeals: [MealCheckIn] {
        let now = Date()
        let records = (data.settings.mealCheckIns ?? []).filter {
            $0.mealTime <= now && $0.confirmedAt <= now &&
            !($0.originalDescription ?? $0.foods).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Dictionary(grouping: records) { data.settings.calendar.startOfDay(for: $0.day) }
            .values.flatMap(DataStore.latestMealRecords)
            .sorted { $0.mealTime > $1.mealTime }
    }

    private var previousMealsPicker: some View {
        AppNavigationStack {
            List(previousMeals) { record in
                Button {
                    applyPreviousMeal(record)
                    previousMealsPresented = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: record.originalDescription ?? record.foods)
                            .font(.body.weight(.medium)).foregroundStyle(MasoColor.text)
                            .lineLimit(2)
                        HStack {
                            Text(verbatim: record.mealTime.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(LanguageManager.currentLocale)))
                            Spacer(minLength: 4)
                            Text(verbatim: CalorieEstimateText.number(record.nutrition.estimatedCalories) + " kcal")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("meal.previous.item.\(record.mealID)")
            }
            .navigationTitle("Choose a previous meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { previousMealsPresented = false } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private func applyPreviousMeal(_ record: MealCheckIn) {
        analysisTask?.cancel()
        analysisRequestID = UUID()
        analyzing = false
        error = nil
        image = nil
        let copiedDescription = record.originalDescription ?? record.foods
        description = copiedDescription
        analyzedDescription = copiedDescription
        foods = record.foods
        nutrition = record.nutrition
        nutrientAnalysis = record.analysis
        copiedMealID = UUID().uuidString
    }

    private func pickerSource(_ source: PhotoPickerSource) -> Binding<PhotoPickerSource?> {
        Binding(
            get: { replacementSource == source ? source : nil },
            set: { value in
                if let value { replacementSource = value }
                else if replacementSource == source { replacementSource = nil }
            }
        )
    }

    private func finishPickingPhoto() {
        let selected = pickedImage
        pickedImage = nil
        if photoLoadingFailed {
            photoLoadingFailed = false
            error = NSLocalizedString("Couldn't load that image. Try another.", comment: "")
            return
        }
        guard let selected else { return } // Cancel preserves the current meal draft.
        guard let preview = MealPhotoPreparation.preview(selected) else {
            error = NSLocalizedString("Couldn't process that image. Try another.", comment: "")
            return
        }
        image = preview
    }

    private func generateMeal() {
        guard !analyzing, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        descriptionFocused = false
        if description.trimmingCharacters(in: .whitespacesAndNewlines) == analyzedDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           nutrition.valid, nutrition.protein + nutrition.carbs + nutrition.fat > 0 {
            confirm()
        } else {
            aiUpgradePrompt.requestAI(isPro: data.settings.isPro, source: "meal_text") {
                analyzing = true
                analysisTask = Task { await analyzeDescriptionAndSave() }
            }
        }
    }

    private func analyzePhoto() async {
        guard let bytes = jpeg() else {
            error = NSLocalizedString("Couldn't process that image. Try another.", comment: "")
            return
        }
        let requestID = UUID(); analysisRequestID = requestID
        analyzing = true; error = nil
        defer { if analysisRequestID == requestID { analyzing = false } }
        do {
            let result = try await data.aiAccess.perform(kind: .nutritionImage, isPro: data.settings.isPro,
                operationID: requestID.uuidString, image: true,
                valid: { $0.isFood && $0.nutrition.valid && $0.nutrition.protein + $0.nutrition.carbs + $0.nutrition.fat > 0 }, summary: { $0.foods }) {
                    try await AIWorkoutService.shared.analyzeMealPhoto(bytes, language: data.settings.language)
                }
            guard !Task.isCancelled, analysisRequestID == requestID else { return }
            description = result.foods; analyzedDescription = result.foods
            foods = result.foods; nutrition = result.nutrition; nutrientAnalysis = result.analysis
        } catch {
            if !Task.isCancelled, analysisRequestID == requestID { self.error = error.localizedDescription }
        }
    }

    /// Submitted text is the final source of truth, including any corrections to the photo estimate.
    private func analyzeDescriptionAndSave() async {
        let requestID = UUID(); analysisRequestID = requestID
        error = nil
        defer { if analysisRequestID == requestID { analyzing = false } }
        do {
            let result = try await data.aiAccess.perform(kind: .nutritionText, isPro: data.settings.isPro,
                operationID: requestID.uuidString,
                valid: { $0.isFood && $0.nutrition.valid && $0.nutrition.protein + $0.nutrition.carbs + $0.nutrition.fat > 0 }, summary: { $0.foods }) {
                    try await AIWorkoutService.shared.analyzeMealText(description, language: data.settings.language)
                }
            guard !Task.isCancelled, analysisRequestID == requestID else { return }
            guard result.nutrition.valid, result.nutrition.protein + result.nutrition.carbs + result.nutrition.fat > 0 else {
                throw NSError(domain: "Meal", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Could not estimate this meal. Add foods and portions, then try again.", comment: "meal estimate error")])
            }
            foods = result.foods; nutrition = result.nutrition; nutrientAnalysis = result.analysis
            confirm()
        } catch {
            if !Task.isCancelled, analysisRequestID == requestID { self.error = error.localizedDescription }
        }
    }
    private func previewMacro(_ title: LocalizedStringKey, grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g").font(.subheadline).monospacedDigit()
        }
    }
    private func updateAmount(id: Int, grams: Double) {
        guard grams.isFinite, grams > 0, grams <= 3000, var updated = nutrientAnalysis,
              let index = updated.items.firstIndex(where: { $0.id == id }) else { return }
        let item = updated.items[index]
        let ratio = grams / item.grams
        let value = MealNutrition(protein: item.nutrition.protein * ratio,
                                  carbs: item.nutrition.carbs * ratio, fat: item.nutrition.fat * ratio)
        let total = updated.items.enumerated().reduce(MealNutrition()) { sum, entry in
            sum + (entry.offset == index ? value : entry.element.nutrition)
        }
        guard value.valid, total.valid, updated.items.reduce(0, { $0 + ($1.id == id ? grams : $1.grams) }) <= 6000 else { return }
        updated.items[index].grams = grams; updated.items[index].nutrition = value
        nutrientAnalysis = updated; nutrition = total
        foods = updated.items.map { "\($0.name) \($0.grams.formatted(.number.precision(.fractionLength(0...1)))) g" }.joined(separator: ", ")
        description = foods; analyzedDescription = foods
    }

    private func jpeg() -> Data? {
        guard let image else { return nil }
        let scale = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.8)
    }
    static var photoDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DietPhotos", isDirectory: true)
    }
    static func loadPhoto(_ name: String) -> UIImage? {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        return UIImage(contentsOfFile: photoDirectory.appendingPathComponent(name).path)
    }
    private func confirm() {
        do {
            var filename = ""
            if image != nil {
                guard let bytes = jpeg() else {
                    error = NSLocalizedString("Couldn't process that image. Try another.", comment: "")
                    return
                }
                try FileManager.default.createDirectory(at: Self.photoDirectory, withIntermediateDirectories: true)
                filename = UUID().uuidString + ".jpg"
                try bytes.write(to: Self.photoDirectory.appendingPathComponent(filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            let day = data.settings.calendar.startOfDay(for: consumedAt)
            let record = MealCheckIn(day: day, mealID: copiedMealID ?? meal.id, title: meal.title, photoFilename: filename,
                                    foods: foods, nutrition: nutrition, confirmedAt: Date(),
                                    originalDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                    analysis: nutrientAnalysis, consumedAt: consumedAt)
            let old = data.saveMealRecord(record, replacing: existingRecord)
            let referenced = Set((data.settings.mealCheckIns ?? []).map(\.photoFilename))
            for previous in old where !previous.photoFilename.isEmpty && !referenced.contains(previous.photoFilename) {
                try? FileManager.default.removeItem(at: Self.photoDirectory.appendingPathComponent(previous.photoFilename))
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}


struct SleepScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
                SleepHomeSection(detail: true)
                RecordHistorySection(kind: .sleep, excludingDay: Date())
            }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.vertical, 16)
        }.background(AppBackground())
    }
}

extension DataStore {
    @MainActor func refreshSleepSummary() async throws {
        guard settings.sleepEnabled ?? true, settings.sleepPreferences?.healthConnected == true else { return }
        try await HealthKitService.shared.refreshSleep(calendar: settings.calendar)
        applySleepSummary(minutes: HealthKitService.shared.sleepMinutes, stages: HealthKitService.shared.sleepStages)
    }

    /// HealthKit cannot distinguish denied read access from an empty result.
    /// Keep the last saved history if no sleep is returned, instead of erasing it.
    @MainActor func applySleepSummary(minutes: [Date: Double], stages: [Date: SleepStagesRecord]) {
        let validMinutes = minutes.filter { $0.value.isFinite && $0.value >= 0 }
        guard !validMinutes.isEmpty else { return }
        var preferences = settings.sleepPreferences ?? SleepPreferences()
        var records: [String: Double] = [:]
        for (day, minutes) in validMinutes {
            let key = SleepPreferences.dayKey(day, calendar: settings.calendar)
            records[key] = minutes
            if preferences.recordedGoals[key] == nil, settings.calendar.isDateInToday(day) { preferences.recordedGoals[key] = preferences.targetMinutes }
        }
        settings.sleepRecords = records
        var savedStages: [String: SleepStagesRecord] = [:]
        for (day, record) in stages where validMinutes[day] != nil {
            savedStages[SleepPreferences.dayKey(day, calendar: settings.calendar)] = record
        }
        settings.sleepStageRecords = savedStages
        settings.sleepPreferences = preferences
        save()
    }
}

func compactSleepDuration(_ minutes: Double) -> String {
    MassoDurationFormatter.sleep(minutes, locale: LanguageManager.currentLocale)
}

private func dietClockTime(_ minute: Int) -> Date {
    Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
}

/// Shared number/unit hierarchy for all three goal cards.
struct TargetValueLabel: View {
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = MasoMetrics.nutritionProteinValueSize
    let value: String
    let unit: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MasoMetrics.cardHeaderGap) {
            MetricValueText(value: value, numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim,
                            numeratorFont: .system(size: valueSize, weight: .semibold, design: .rounded),
                            denominatorFont: .system(size: valueSize, weight: .regular, design: .rounded))
                .font(.system(size: valueSize, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.title3).foregroundStyle(MasoColor.textDim)
        }
    }
}

/// Identical week layout; workout marks recorded days, nutrition/sleep encode target attainment.
struct GoalCompletionRulesSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let kind: PerformanceCalendarSnapshot.Kind
    private var accent: Color {
        switch kind { case .workout: MasoColor.accent; case .diet: MasoColor.dietAccent; case .sleep: MasoColor.sleepAccent }
    }
    private var currentSleepTarget: Int { (data.settings.sleepPreferences ?? SleepPreferences()).targetMinutes }
    private var sleepTarget: Int {
        let key = SleepPreferences.dayKey(Date(), calendar: data.settings.calendar)
        return data.settings.sleepPreferences?.recordedGoals[key] ?? data.wellnessGoal(on: Date())?.sleepMinutes ?? currentSleepTarget
    }
    var body: some View {
        AppNavigationStack {
            Form {
                if kind == .workout {
                    workoutRules
                } else {
                Section("Target used today") {
                    if kind == .sleep {
                        LabeledContent("Sleep target", value: compactSleepDuration(Double(sleepTarget)))
                        if currentSleepTarget != sleepTarget {
                            LabeledContent("Current sleep target", value: compactSleepDuration(Double(currentSleepTarget)))
                        }
                        Text("Solid blue means actual sleep reaches your saved nightly target. Awake and time in bed are excluded. Deep and REM are references, not scoring targets.")
                            .font(.subheadline)
                    } else if let targets = data.dietGuidance()?.targets {
                        let goal = data.wellnessGoal(on: Date())
                        LabeledContent("Protein", value: "\(goal?.protein ?? targets.protein) g")
                        LabeledContent("Carbs", value: "\(goal?.carbsMinimum ?? targets.carbohydrate) g")
                        LabeledContent("Fat", value: "\(goal?.fatMinimum ?? targets.fat) g")
                        Text("Solid yellow means all three fixed daily targets are met. Going above a target does not add extra credit.")
                            .font(.subheadline)
                    } else {
                        Text("Add your weight for nutrition targets")
                    }
                }
                Section("What the colors mean") {
                    GoalColorStates(kind: kind, sleepTarget: kind == .sleep ? sleepTarget : nil)
                }
                Section("How it is calculated") {
                    if kind == .sleep {
                        Text("Completion = actual sleep minutes ÷ that night's target. Values above the target earn no extra credit. Stage estimates do not determine the color.")
                    } else {
                        Text("Diet score shows weighted intake relative to daily protein, carbs and fat targets (20/10/5), rounded to a whole percentage. It can exceed 100%; this means above target, not healthier. Meal percentages show their contribution to the daily targets.")
                        Text("Only saved meal records count. AI nutrition estimates can be inaccurate; colors measure recorded target adherence, not diet quality or health.")
                    }
                    Text("Saved historical targets take priority. If a day has no saved target, the current target is used; changing today's goal does not overwrite saved goals.")
                }
                Section("Research & guidance") {
                    if kind == .sleep {
                        Text("Adults generally need 7–9 hours; ages 13–18 need 8–10 hours and ages 6–12 need 9–12 hours. Eight hours is an adult starting point. A blue dot only confirms your chosen goal, not that your sleep is healthy.")
                        Link("NIH · Recommended sleep duration", destination: URL(string: "https://www.nhlbi.nih.gov/health/sleep/how-much-sleep")!)
                        Link("AASM / SRS · Adult sleep consensus (2015)", destination: URL(string: "https://www.aasm.org/resources/pdf/adultsleepdurationconsensus.pdf")!)
                        Link("Apple · Sleep tracking", destination: URL(string: "https://support.apple.com/en-ie/108906")!)
                    } else {
                        Text("Nutrition targets are estimates based on weight and training preferences. Health activity does not automatically change them.")
                        Link("ISSN · Protein and exercise (2017)", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/")!)
                        Link("ACSM · Nutrition and athletic performance (2016)", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/26891166/")!)
                    }
                }
                }
            }
            .navigationTitle("Goal & color rules").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) } }
        }.tint(accent).presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    @ViewBuilder private var workoutRules: some View {
        Section("Workout target") {
            LabeledContent("Weekly target", value: String.localizedStringWithFormat(
                NSLocalizedString("%d days / week", comment: "Workout frequency target"),
                max(1, min(7, data.settings.weeklyTrainingDays))))
            Text("Your goal is weekly. Rest days do not count as failed daily goals.")
        }
        Section("What the colors mean") {
            GoalColorStates(kind: .workout)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.12)).frame(width: 16, height: 16)
                Text("Today")
            }
            Text("Your goal is weekly. Rest days do not count as failed daily goals.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("How it is calculated") {
            Text("Each day with a Masso workout or imported Apple Health workout counts once. Imported workouts do not advance your workout plan or count toward muscle progress.")
            Text("Muscle recovery shades are shown in My Muscle Status.")
        }
    }
 }

/// One source for point-state explanations in the combined calendar and individual goal sheets.
struct GoalColorStates: View {
    let kind: PerformanceCalendarSnapshot.Kind
    var sleepTarget: Int? = nil
    private var accent: Color {
        switch kind { case .workout: MasoColor.accent; case .diet: MasoColor.dietAccent; case .sleep: MasoColor.sleepAccent }
    }
    var body: some View {
        if kind == .workout {
            row("Workout recorded", fraction: 1, detail: NSLocalizedString("Green means at least one recorded training set that day.", comment: ""))
            row("No workout", fraction: nil, detail: NSLocalizedString("No workout recorded on this day.", comment: ""))
        } else {
            row("No data", fraction: nil, detail: NSLocalizedString("No recorded intake/sleep or no usable target.", comment: ""))
            row("Light color", fraction: 0.25, detail: threshold(0, 0.5))
            row("Medium color", fraction: 0.5, detail: threshold(0.5, 0.8))
            row("Deep color", fraction: 0.8, detail: threshold(0.8, 1))
            row("Goal met", fraction: 1, detail: sleepTarget.map { "≥ " + compactSleepDuration(Double($0)) } ?? "≥ 100%")
        }
    }
    private func threshold(_ lower: Double, _ upper: Double) -> String {
        if let sleepTarget {
            return compactSleepDuration(ceil(Double(sleepTarget) * lower)) + " – < " + compactSleepDuration(ceil(Double(sleepTarget) * upper))
        }
        let low = lower.formatted(.percent.precision(.fractionLength(0)))
        let high = upper.formatted(.percent.precision(.fractionLength(0)))
        return lower == 0 ? "< " + high : low + " – < " + high
    }
    private func row(_ title: LocalizedStringKey, fraction: Double?, detail: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(fraction.map { accent.opacity(GoalCompletionAppearance.opacity($0)) }
                          ?? Color.secondary.opacity(0.2)).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 2)
    }
}


private struct LastMealSuggestionSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onUse: (MealPhotoEstimate) -> Void
    @State private var proteinID = "chicken_breast_cooked"
    @State private var starchID = "white_rice_cooked"
    @State private var vegetableID = "broccoli_boiled"
    @State private var appliedProteinID = "chicken_breast_cooked"
    @State private var appliedStarchID = "white_rice_cooked"
    @State private var appliedVegetableID = "broccoli_boiled"
    private var needsRefresh: Bool { proteinID != appliedProteinID || starchID != appliedStarchID || vegetableID != appliedVegetableID }
    private func refreshSuggestion() {
        appliedProteinID = proteinID; appliedStarchID = starchID; appliedVegetableID = vegetableID
    }
    private var records: [MealCheckIn] { data.wellnessMeals(on: Date()) }
    private var suggestion: LastMealSuggestion? {
        guard !records.isEmpty, proteins.contains(where: { $0.id == appliedProteinID }), starches.contains(where: { $0.id == appliedStarchID }),
              let goal = data.wellnessGoal(on: Date()) else { return nil }
        let preferences = data.settings.dietPreferences ?? DietPreferences()
        return LastMealSuggestion.build(goal: .init(protein: Double(goal.protein), carbs: Double(goal.carbsMinimum), fat: Double(goal.fatMinimum)),
            consumed: records.reduce(MealNutrition()) { $0 + $1.nutrition }, proteinID: appliedProteinID, starchID: appliedStarchID,
            includeVegetables: appliedVegetableID != "none",
            allowNuts: !preferences.excludedFoods.contains("almonds") && preferences.allergens.isDisjoint(with: ["Nuts", "Tree nuts", "Peanuts"]),
            vegetableID: appliedVegetableID == "none" ? "broccoli_boiled" : appliedVegetableID)
    }
    private var proteins: [(id: String, title: String)] {
        let preferences = data.settings.dietPreferences ?? DietPreferences()
        let options = [("chicken_breast_cooked", "Chicken breast", "chicken"),
                       ("tofu_firm", "Firm tofu", "tofu"), ("salmon_cooked", "Salmon", "fish"),
                       ("beef_ground_cooked", "Lean beef", "beef")]
        return options.filter { id, _, legacyID in
            if preferences.plantBased && id != "tofu_firm" { return false }
            if preferences.excludedFoods.contains(legacyID) { return false }
            if id == "salmon_cooked" && preferences.allergens.contains("Fish") { return false }
            if id == "tofu_firm" && preferences.allergens.contains("Soy") { return false }
            return true
        }.map { ($0.0, $0.1) }
    }
    private var starches: [(id: String, title: String)] {
        let exclusions = (data.settings.dietPreferences ?? DietPreferences()).excludedFoods
        return [("white_rice_cooked", "Rice", "rice"), ("potato_boiled", "Potatoes", "potato")]
            .filter { !exclusions.contains($0.2) }.map { ($0.0, $0.1) }
    }
    private var vegetables: [(id: String, title: String)] {
        let exclusions = (data.settings.dietPreferences ?? DietPreferences()).excludedFoods
        let choices = [("broccoli_boiled", "Broccoli", "broccoli"), ("spinach_boiled", "Spinach", "spinach")]
        return choices.filter { !exclusions.contains($0.2) }.map { ($0.0, $0.1) } + [("none", "None")]
    }
    var body: some View {
        AppNavigationStack {
            Form {
                if let suggestion {
                    Section("Remaining today") {
                        macroSummary(suggestion.remaining)
                    }
                    if suggestion.portions.isEmpty {
                        Section { Text(LocalizedStringKey(suggestion.remaining.protein + suggestion.remaining.carbs + suggestion.remaining.fat <= 1 ? "Daily targets met" : "No extra meal suggested")).foregroundStyle(.secondary) }
                    } else {
                        Section {
                            ForEach(suggestion.portions) { portion in
                                LabeledContent(LocalizedStringKey(portion.title), value: "\(Int(portion.grams)) g")
                            }
                            macroSummary(suggestion.nutrition)
                        } header: { Text("Suggested meal") } footer: {
                            Text("Based on logged meals · Cooked / ready-to-eat weights")
                        }
                        Section {
                            DisclosureGroup("Adjust meal") {
                                Picker("Protein", selection: $proteinID) {
                                    ForEach(proteins, id: \.id) { Text(LocalizedStringKey($0.title)).tag($0.id) }
                                }
                                Picker("Vegetables", selection: $vegetableID) {
                                    ForEach(vegetables, id: \.id) { Text(LocalizedStringKey($0.title)).tag($0.id) }
                                }
                                Picker("Carbs", selection: $starchID) {
                                    ForEach(starches, id: \.id) { Text(LocalizedStringKey($0.title)).tag($0.id) }
                                }
                                Button("Refresh suggestion", systemImage: "arrow.clockwise") { refreshSuggestion() }
                                    .nativeGlassButtonStyle().controlSize(.small).disabled(!needsRefresh)
                            }
                        }
                    }
                } else {
                    Section { Text(LocalizedStringKey(records.isEmpty ? "Log a meal first" : proteins.isEmpty || starches.isEmpty ? "No suitable foods" : "Add your weight for nutrition targets")).foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden).background(AppBackground()).tint(MasoColor.text)
            .navigationTitle("Meal suggestion").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if let suggestion, !suggestion.portions.isEmpty {
                    PrimaryActionButton(title: "Log this meal", icon: "plus", accent: MasoColor.dietAccent) { onUse(suggestion.estimate()) }
                        .disabled(needsRefresh)
                        .padding(MasoMetrics.pagePaddingHorizontal)
                        .frame(maxWidth: .infinity)
                        .background(AppBackground())
                }
            }
            .onAppear {
                if !proteins.contains(where: { $0.id == proteinID }), let first = proteins.first { proteinID = first.id }
                if !starches.contains(where: { $0.id == starchID }), let first = starches.first { starchID = first.id }
                if !vegetables.contains(where: { $0.id == vegetableID }), let first = vegetables.first { vegetableID = first.id }
                refreshSuggestion()
            }
        }.presentationDetents([.large])
    }
    private func macroSummary(_ nutrition: MealNutrition) -> some View {
        HStack(spacing: 12) {
            macroAmount("Protein", nutrition.protein)
            macroAmount("Carbs", nutrition.carbs)
            macroAmount("Fat", nutrition.fat)
        }.padding(.vertical, 4)
    }
    private func macroAmount(_ title: LocalizedStringKey, _ grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(grams.rounded())) g").font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
