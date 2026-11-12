import SwiftUI
import Charts
import Combine

/// Full-page muscle status uses the same native model and fatigue mapping as Today.
struct MuscleMapDetailScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let fatigueMap: [MuscleGroup: Double]
    let gapMuscles: [MuscleGroup]
    let onStartGapWorkout: () -> Void
    var onUnlock: () -> Void = {}
    var onOpenMuscleInfo: (MuscleSelection) -> Void = { _ in }
    var onRecoveryCardVisibilityChange: (Bool) -> Void = { _ in }

    @State private var selectedMuscle: MuscleSelection?
    @State private var recoveryListPresented = false

    @State private var footerHeight: CGFloat = 60
    @State private var recoveryContentHeight: CGFloat = 340
    @State private var recoveryCardTop: CGFloat?

    var body: some View {
        let isPro = data.settings.isPro
        GeometryReader { geometry in
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let cardHeight = min(recoveryContentHeight, geometry.size.height * 0.64)
            let recoveryCardMargin: CGFloat = 20
            let availableHeight = max(1, geometry.size.height + geometry.safeAreaInsets.bottom - recoveryCardMargin - cardHeight - 24)
            // Keep the initial viewport entirely between the native title and bottom controls.
            // Selected-muscle framing still uses the full-screen SceneKit viewport.
            let defaultHeight = max(1, geometry.size.height - footerHeight - 32)
            let defaultScale = min(1, defaultHeight / max(1, fullHeight))
            let defaultShift = geometry.safeAreaInsets.top + 12 + defaultHeight / 2 - fullHeight / 2

            VStack(spacing: 16) {
                Spacer(minLength: 0)
                if let selection = selectedMuscle {
                    MuscleRecoveryOverlay(selection: selection,
                        onClose: { selectedMuscle = nil },
                        onOpenDetails: {
                            MuscleNavigationBridge.shared.prepare(from: .status, to: .exercises)
                            onOpenMuscleInfo(selection)
                        },
                        onContentHeightChange: { recoveryContentHeight = $0 })
                        .frame(maxWidth: 460)
                        .frame(height: cardHeight)
                        .glassCardBackground(cornerRadius: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .offset(y: geometry.safeAreaInsets.bottom - recoveryCardMargin)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { recoveryCardTop = $0 }
                        .transition(.opacity)
                } else {
                    MuscleRecoveryLegend(compact: true)
                        .blur(radius: isPro ? 0 : 4.5)
                        .accessibilityHidden(!isPro)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if selectedMuscle == nil {
                VStack(spacing: 12) {
                    if !isPro {
                        DeviceRecoveryPreviewButton()
                        Button("Unlock per-muscle recovery with Pro", systemImage: "lock.fill") {
                            dismiss(); onUnlock()
                        }
                        .buttonStyle(.bordered)
                    }
                    primaryCTA
                        .padding(.bottom, 16)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .top) {
                // Render independently of the safe-area content and floating card.
                // The SceneKit viewport reaches every screen edge, including the navigation bar.
                MuscleBody3DView(
                    fatigueMap: fatigueMap,
                    autoRotates: selectedMuscle == nil && !recoveryListPresented && !reduceMotion && scenePhase == .active,
                    highlightedRegionNode: selectedMuscle?.regionNode,
                    focusedRegionNode: selectedMuscle?.regionNode,
                    focusShowsBack: selectedMuscle?.showsBack ?? false,
                    focusVisibleFraction: selectedMuscle == nil ? 1 : availableHeight / max(1, fullHeight),
                    focusTopInsetFraction: geometry.safeAreaInsets.top / max(1, fullHeight),
                    showsFatigueColors: selectedMuscle == nil,
                    navigationRole: .status,
                    navigationOcclusionTop: selectedMuscle == nil ? nil : recoveryCardTop,
                    onTap: { selectedMuscle = nil },
                    onMuscleTap: { region, showsBack in
                        guard let muscle = region.muscles.first else { return }
                        Haptics.selection()
                        selectedMuscle = MuscleSelection(muscle: muscle, relatedMuscles: region.muscles,
                                                        regionNode: region.node, showsBack: showsBack)
                    }
                )
                .accessibilityIdentifier("detail.muscleBody3D")
                .frame(width: geometry.size.width, height: fullHeight)
                .scaleEffect(selectedMuscle == nil ? defaultScale : 1)
                .offset(y: -geometry.safeAreaInsets.top + (selectedMuscle == nil ? defaultShift : 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: selectedMuscle)
            }
        }
        .background(MasoColor.background.ignoresSafeArea())
        #if DEBUG
        .onAppear {
            guard ProcessInfo.processInfo.environment["MASO_MARKETING_SELECTED_MUSCLE"] == "shoulders",
                  let region = try? MuscleBodyRegion.loadBundled().first(where: { $0.node == "shoulders_left" }) else { return }
            selectedMuscle = MuscleSelection(muscle: .shoulders, relatedMuscles: region.muscles, regionNode: region.node, showsBack: true)
        }
        #endif
        .onChange(of: selectedMuscle != nil, initial: true) { _, visible in
            onRecoveryCardVisibilityChange(visible)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { recoveryListPresented = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Muscle recovery")
                    .accessibilityIdentifier("muscles.recoveryList")
            }
        }
        .navigationDestination(isPresented: $recoveryListPresented) {
            MuscleRecoveryListScreen(gapMuscles: gapMuscles, onStartGapWorkout: startGapWorkout) { selection in
                Haptics.selection()
                selectedMuscle = selection
                recoveryListPresented = false
            }
        }
    }

    /// 底部主 CTA — 规格照抄 PlansScreen.startWorkoutCTA ("Start workout" 那颗大胶囊),
    /// 全 app 主操作按钮共用这一套: 包住内容的胶囊 + accent 玻璃底 + 黑字.
    @ViewBuilder
    private var primaryCTA: some View {
        if gapMuscles.isEmpty {
            Label("All caught up", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            TrainGapsButton(hasGaps: true, action: startGapWorkout)
        }
    }

    private func startGapWorkout() {
        dismiss()
        onStartGapWorkout()
    }
}

/// The same action and primary button are used in both recovery presentations.
private struct TrainGapsButton: View {
    let hasGaps: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            TrainingCardActionLabel(title: "Train the gaps", icon: "play.fill", accent: MasoColor.accent)
        }
        .buttonStyle(.plain)
        .disabled(!hasGaps)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct MuscleRecoveryListScreen: View {
    @Environment(DataStore.self) private var data
    let gapMuscles: [MuscleGroup]
    let onStartGapWorkout: () -> Void
    let onSelect: (MuscleSelection) -> Void
    @State private var now = Date()

    private var entries: [MuscleStatusCompute.RecoverySummary] {
        MuscleStatusCompute.recoverySummaries(regions: (try? MuscleBodyRegion.loadBundled()) ?? [],
            sets: data.sets, exById: data.exById, now: now)
    }

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    Button {
                        let backMuscles: Set<MuscleGroup> = [.upperTraps, .lats, .lowerBack, .glutes, .hamstrings, .calves]
                        onSelect(MuscleSelection(muscle: entry.muscle, relatedMuscles: entry.region.muscles,
                            regionNode: entry.region.node, showsBack: backMuscles.contains(entry.muscle)))
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.muscle.displayName).font(.body).foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(status(for: entry.recovered)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Group {
                                if let recovery = entry.recovered {
                                    Text(recovery, format: .percent.precision(.fractionLength(0)))
                                } else { Text("—") }
                            }
                            .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("muscles.recovery.\(entry.muscle.rawValue)")
                }
            } header: { Text("Most recovered first") }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Muscle recovery")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TrainGapsButton(hasGaps: !gapMuscles.isEmpty, action: onStartGapWorkout)
                .padding(MasoMetrics.pagePaddingHorizontal)
        }
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func status(for recovery: Double?) -> LocalizedStringKey {
        guard let recovery else { return "No workouts yet" }
        switch MuscleStatusCompute.tierFor(fatigue: 1 - recovery) {
        case .fresh: return "Fresh"
        case .mostlyRecovered: return "Ready"
        case .recovering: return "Recovering"
        case .fatigued: return "Fatigued"
        }
    }
}

struct MuscleSelection: Hashable {
    let muscle: MuscleGroup
    let relatedMuscles: [MuscleGroup]
    let regionNode: String
    let showsBack: Bool
}

private extension MuscleGroup {
    var introductionKey: LocalizedStringKey {
        switch self {
        case .neck: return "Muscle intro · Neck"
        case .chest, .upperChest, .midChest, .lowerChest: return "Muscle intro · Chest"
        case .shoulders, .frontDelts, .sideDelts, .rearDelts, .rotatorCuff: return "Muscle intro · Shoulders"
        case .biceps, .bicepsLong, .bicepsShort, .brachialis: return "Muscle intro · Biceps"
        case .triceps, .tricepsLong, .tricepsLateral, .tricepsMedial: return "Muscle intro · Triceps"
        case .forearms, .forearmFlexors, .forearmExtensors, .brachioradialis: return "Muscle intro · Forearms"
        case .core, .abs, .upperAbs, .lowerAbs, .obliques, .serratus: return "Muscle intro · Core"
        case .glutes, .gluteusMaximus, .gluteusMedius: return "Muscle intro · Glutes"
        case .quads, .rectusFemoris, .vastusLateralis, .vastusMedialis: return "Muscle intro · Quads"
        case .hamstrings, .bicepsFemoris, .semitendinosus: return "Muscle intro · Hamstrings"
        case .calves, .gastrocnemius, .soleus, .tibialisAnterior: return "Muscle intro · Lower legs"
        case .adductors: return "Muscle intro · Adductors"
        case .back, .lats, .upperLats, .lowerLats, .upperTraps, .midTraps, .lowerTraps,
             .rhomboids, .teres, .lowerBack, .arms, .legs, .fullBody:
            return "Muscle intro · Back"
        }
    }

}

struct MuscleInfoScreen: View {
    @Environment(DataStore.self) private var data
    let muscle: MuscleGroup
    let relatedMuscles: [MuscleGroup]
    let regionNode: String
    let showsBack: Bool
    var onTrainMore: () -> Void = {}
    @State private var useGridLayout = false
    @State private var selectedExercise: Exercise?

    private var exercises: [Exercise] {
        let targets = Set(relatedMuscles)
        let matches = data.userLibrary.filter { exercise in
            exercise.primaryMuscles.contains(where: targets.contains)
        }
        return Array(data.sortByFavorites(matches).prefix(12))
    }


    var body: some View {
        GeometryReader { geometry in
        let heroHeight = min(640, max(500, geometry.size.height * 0.68)) * 0.6 + geometry.safeAreaInsets.top
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            MuscleBody3DView(
                fatigueMap: [:],
                showsBack: showsBack,
                highlightedRegionNode: regionNode,
                focusedRegionNode: regionNode,
                focusShowsBack: showsBack,
                focusVisibleFraction: 0.96,
                focusTopInsetFraction: 0.02,
                showsFatigueColors: false,
                navigationRole: .exercises
            )
            // Extend the render surface from the physical left edge; overscan to the
            // right preserves the previously approved right-biased muscle framing.
            .frame(width: geometry.size.width * 1.15, height: heroHeight)
            .frame(width: geometry.size.width, height: heroHeight, alignment: .leading)
            .overlay {
                LinearGradient(stops: [
                    .init(color: MasoColor.background.opacity(0), location: 0),
                    .init(color: MasoColor.background.opacity(0), location: 0.6),
                    .init(color: MasoColor.background, location: 1)
                ], startPoint: UnitPoint(x: 0, y: 0.5), endPoint: UnitPoint(x: 1, y: 0.5))
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [
                    .init(color: MasoColor.background.opacity(0), location: 0),
                    .init(color: MasoColor.background.opacity(0.08), location: 0.3),
                    .init(color: MasoColor.background.opacity(0.4), location: 0.6),
                    .init(color: MasoColor.background.opacity(0.8), location: 0.85),
                    .init(color: MasoColor.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 192).allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(Text(muscle.displayName))
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(muscle.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MasoColor.text)
                Text(muscle.introductionKey)
                    .font(.body)
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onTrainMore) {
                Label("Train this muscle more", systemImage: "message")
                    .font(.subheadline)
            }
                .nativeGlassButtonStyle().controlSize(.small).tint(MasoColor.text)
                .accessibilityIdentifier("muscle.trainMore")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Exercises for this muscle")
                        .font(.headline)
                        .foregroundStyle(MasoColor.text)
                    Spacer()
                    Picker("Layout", selection: $useGridLayout) {
                        Label("List", systemImage: "list.bullet").tag(false)
                        Label("Grid", systemImage: "square.grid.2x2").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                if exercises.isEmpty {
                    Text("No matching exercises yet")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else if useGridLayout {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(exercises) { exercise in
                            Button { selectedExercise = exercise } label: {
                                ExerciseGridContent(exercise: exercise)
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    InlineExerciseList(exercises: exercises) { selectedExercise = $0 }
                }
            }
        }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appUnobstructedMediaHeader()
        // Keep the system back item: hiding it disables native interactive pop.
        // Editor role keeps the compact chevron without repeating the parent title.
        .toolbarRole(.editor)
        .tint(MasoColor.text)
        .sheet(item: $selectedExercise) { exercise in
            ExerciseDetailSheet(exercise: exercise)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MuscleRecoveryOverlay: View {
    @Environment(DataStore.self) private var data
    let selection: MuscleSelection
    let onClose: () -> Void
    let onOpenDetails: () -> Void
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @State private var now = Date()
    @State private var explanationPresented = false
    // Measure text/padding independently from the chart to avoid a sizing feedback loop.
    @State private var contentHeight: CGFloat = 0
    private let preferredChartHeight: CGFloat = 180
    @State private var actionHeight: CGFloat = 0
    private var points: [MuscleStatusCompute.RecoveryPoint] {
        MuscleStatusCompute.recoveryTimeline(muscles: selection.relatedMuscles, sets: data.sets, exById: data.exById, now: now)
    }
    var body: some View {
        GeometryReader { geometry in
        let chartHeight = max(0, min(240, geometry.size.height - contentHeight - actionHeight))
        let contentSpacing: CGFloat = geometry.size.height < 480 ? 12 : MasoMetrics.cardPadding
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    Text(selection.muscle.displayName)
                        .font(.title2.weight(.bold)).foregroundStyle(MasoColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .nativeGlassButtonStyle().controlSize(.small).tint(MasoColor.text)
                        .accessibilityLabel("Close")
                }
                if let current = points.last {
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        HStack {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                TargetValueLabel(value: String(Int((current.recovered * 100).rounded())), unit: "%")
                                Button { explanationPresented = true } label: {
                                    Image(systemName: "info.circle").font(.caption)
                                }
                                .buttonStyle(.borderless).tint(.secondary)
                                .accessibilityLabel("Recovery estimate")
                                .popover(isPresented: $explanationPresented) {
                                    Text("Estimated from recorded workouts, not a measured recovery score.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                        .padding(16).frame(idealWidth: 260, maxWidth: 280)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .presentationCompactAdaptation(.popover)
                                }
                            }
                            Spacer(minLength: 12)
                            Text(tier(current.recovered)).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 140, alignment: .trailing)
                        }
                        Chart {
                            ForEach(points) { point in
                                AreaMark(x: .value("Date", point.date),
                                         yStart: .value("Baseline", 0),
                                         yEnd: .value("Recovery", point.recovered * 100))
                                    .foregroundStyle(LinearGradient(
                                        colors: [MasoColor.accent.opacity(0.28), MasoColor.accent.opacity(0)],
                                        startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.linear)
                                    .accessibilityHidden(true)
                            }
                            ForEach(points) { point in
                                LineMark(x: .value("Date", point.date), y: .value("Recovery", point.recovered * 100))
                                    .foregroundStyle(MasoColor.accent).interpolationMethod(.linear)
                            }
                            PointMark(x: .value("Date", current.date), y: .value("Recovery", current.recovered * 100))
                                .foregroundStyle(MasoColor.accent).symbolSize(85)
                                .annotation(position: .top, alignment: .trailing) { Text("Now").font(.caption).foregroundStyle(.secondary) }
                            RuleMark(x: .value("Date", now)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        }
                        .chartXScale(domain: (points.first?.date ?? now.addingTimeInterval(-86400))...now,
                                     range: .plotDimension(startPadding: 8, endPadding: 14))
                        .chartYScale(domain: 0...100, range: .plotDimension(startPadding: 12, endPadding: 12))
                        .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel { if let percent = value.as(Int.self) { Text("\(percent)%") } }
                        } }
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                        .frame(height: chartHeight)
                        .accessibilityLabel("Recovery estimate")
                        .accessibilityValue("\(Int((current.recovered * 100).rounded()))%")
                    }
                } else {
                    ContentUnavailableView("No workouts yet", systemImage: "chart.xyaxis.line")
                        .frame(height: chartHeight)
                }
            }.padding(MasoMetrics.pagePaddingHorizontal)
                .onGeometryChange(for: CGFloat.self) { ceil(max(0, $0.size.height - chartHeight)) } action: { height in
                    if height > 0 { contentHeight = height }
                }
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 8) {
                Button(action: onOpenDetails) {
                    HStack(spacing: 8) {
                        Text("Exercises")
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.font(.subheadline.weight(.semibold))
                }
            }
            .nativeGlassButtonStyle().controlSize(.regular).tint(MasoColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.bottom, MasoMetrics.pagePaddingHorizontal)
        .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { actionHeight = $0 }
        }
        .onChange(of: contentHeight + actionHeight) { _, height in
            if contentHeight > 0, actionHeight > 0 { onContentHeightChange(height + preferredChartHeight) }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        }
    }
    private func tier(_ recovery: Double) -> LocalizedStringKey {
        switch MuscleStatusCompute.tierFor(fatigue: 1 - recovery) {
        case .fresh: "Fresh · Ready to train"
        case .mostlyRecovered: "Rested · Ready to train"
        case .recovering: "Recovering · Keep it light"
        case .fatigued: "Fatigued · Rest recommended"
        }
    }
}
