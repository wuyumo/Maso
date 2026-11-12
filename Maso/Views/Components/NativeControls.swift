import SwiftUI
import WebKit

/// One selected/idle treatment for peer options, including onboarding categories.
struct NativeSelectionButton: View {
    let title: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            title.font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28)
        }
        .controlSize(.regular)
        .tint(isSelected ? MasoColor.accent : MasoColor.text)
        .applyIf(isSelected) { $0.nativeGlassProminentButtonStyle() }
        .applyIf(!isSelected) { $0.nativeGlassButtonStyle() }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One visual owner for exercise names, media and secondary metadata.
struct ExerciseRowContent: View {
    let exercise: Exercise
    var titleOverride: String? = nil
    var detailLine: String? = nil
    var onTapImage: (() -> Void)? = nil
    var showsChevron = false
    /// Historical variant: actual sets stay with their exercise, never plan targets.
    var recordedSets: [SetRecord]? = nil
    var parameterStep: PlanStep? = nil
    var body: some View {
        HStack(spacing: 14) {
            if let onTapImage {
                Button(action: onTapImage) { thumbnail }.buttonStyle(.plain)
                    .accessibilityLabel(Text(exercise.displayName))
            } else { thumbnail }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let titleOverride { Text(verbatim: titleOverride) }
                    else { ExerciseTitleLabel(exercise: exercise) }
                }.font(.body).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if let parameterStep { PlanParameterSummary(step: parameterStep, exercise: exercise) }
                else if let detailLine, !detailLine.isEmpty {
                    Text(detailLine).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
                ExerciseMetadata(exercise: exercise)
                if let recordedSets { RecordedExerciseParameters(records: recordedSets) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    private var thumbnail: some View {
        ExerciseImage(category: exercise.category, exerciseID: exercise.id, imageFolder: exercise.imageFolder,
                      photoURL: exercise.photoURL, customImageData: exercise.customImageData,
                      cornerRadius: 8, size: 56, animated: false)
    }
}
struct ExerciseMetadata: View {
    let exercise: Exercise
    var body: some View {
        let labels = [exercise.primaryMuscles.first?.displayName, exercise.equipmentDisplayName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !labels.isEmpty {
            Text(labels.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
struct ExerciseGridContent: View {
    let exercise: Exercise
    var detailLine: String? = nil
    var onTapImage: (() -> Void)? = nil
    var recordedSets: [SetRecord]? = nil
    var parameterStep: PlanStep? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let onTapImage { Button(action: onTapImage) { media }.buttonStyle(.plain) }
            else { media }
            ExerciseTitleLabel(exercise: exercise).font(.body).foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let parameterStep { PlanParameterSummary(step: parameterStep, exercise: exercise).lineLimit(1) }
            else if let detailLine {
                Text(detailLine).font(.footnote.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            ExerciseMetadata(exercise: exercise).lineLimit(1)
            if let recordedSets { RecordedExerciseParameters(records: recordedSets) }
        }.contentCardChrome(padding: 10)
    }
    private var media: some View {
        GeometryReader { geometry in
            ExerciseImage(category: exercise.category, exerciseID: exercise.id, imageFolder: exercise.imageFolder,
                          photoURL: exercise.photoURL, customImageData: exercise.customImageData,
                          cornerRadius: 8, size: geometry.size.width, animated: false)
        }.aspectRatio(1, contentMode: .fit)
    }
}

/// Shared read-only parameters for the recorded list and grid variants.
struct RecordedExerciseParameters: View {
    let records: [SetRecord]
    @Environment(DataStore.self) private var data
    @State private var editingRecord: SetRecord? = nil
    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: NSLocalizedString("Set %d", comment: ""),
                                    locale: LanguageManager.currentLocale, index + 1))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Text(recordedSetDetailLine(record)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }.accessibilityElement(children: .combine)
                    if record.exerciseId == CrossExerciseLoadReference.anchorID, record.reps == 6, (record.weight ?? 0) > 0 {
                        Button { editingRecord = record } label: {
                            if record.hasConfirmedSixRM { Label { Text(verbatim: "6RM") } icon: { Image(systemName: "checkmark") } }
                            else { Text(verbatim: "6RM") }
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        .tint(record.hasConfirmedSixRM ? MasoColor.accent : MasoColor.textDim)
                        .accessibilityLabel("Confirmed bench press 6RM")
                        .accessibilityIdentifier("workout.record.reference." + record.id)
                    }
                }
            }
        }.font(.footnote.monospacedDigit()).padding(.top, 4)
        .sheet(item: $editingRecord) { record in
            AdjustLastSetSheet(record: record) { reps, weight, duration, confirmed in
                data.updateSetRecord(id: record.id, reps: reps, weight: weight, duration: duration,
                                     sixRMConfirmed: confirmed)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

func recordedSetDetailLine(_ record: SetRecord) -> String {
    var values: [String] = []
    if let weight = record.weight, weight > 0 { values.append(weightLabel(weight)) }
    if let reps = record.reps {
        let count = String(format: NSLocalizedString("%d reps", comment: ""),
                           locale: LanguageManager.currentLocale, reps)
        if values.isEmpty { values.append(count) }
        else { values[0] += " × " + count }
    }
    if let duration = record.duration {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = LanguageManager.currentLocale
        formatter.calendar = calendar
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        if let text = formatter.string(from: TimeInterval(duration)) { values.append(text) }
    }
    return values.isEmpty ? "—" : values.joined(separator: " · ")
}
private struct ExerciseListHeights: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
/// Native rows inside a detail page's outer scroll view. No nested scrolling.
struct InlineExerciseList: View {
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void
    @State private var heights: [String: CGFloat] = [:]
    @ScaledMetric(relativeTo: .body) private var initialRowHeight: CGFloat = 96
    var body: some View {
        List(exercises) { exercise in
            Button { onSelect(exercise) } label: {
                ExerciseRowContent(exercise: exercise, showsChevron: true)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ExerciseListHeights.self,
                                               value: [exercise.id: geometry.size.height])
                    })
            }.buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain).scrollDisabled(true).scrollContentBackground(.hidden)
        .frame(height: exercises.reduce(CGFloat(0)) { $0 + (heights[$1.id] ?? initialRowHeight) })
        .onPreferenceChange(ExerciseListHeights.self) { heights.merge($0, uniquingKeysWith: { _, new in new }) }
    }
}
struct NativeIntegerParameterRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var suffix = ""
    var isSuggested = false
    private var bounded: Binding<Int> {
        Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) })
    }
    var body: some View {
        Stepper(value: bounded, in: range, step: step) {
            LabeledContent {
                HStack(spacing: 4) {
                    NumericValueField(value: bounded, range: range, textColor: isSuggested ? UIColor(MasoColor.parameterSuggestion) : .label)
                        .accessibilityLabel(Text(title))
                        .frame(minWidth: 48, idealWidth: 60, maxWidth: 80)
                    if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                    if isSuggested { Text("Suggested").font(.caption2).foregroundStyle(MasoColor.parameterSuggestion) }
                }
            }
        }.font(.body)
    }
}
struct NativeWeightParameterRow: View {
    var title: LocalizedStringKey = "Weight"
    @Binding var kilograms: Double
    var isSuggested = false
    var isUnknown = false
    var allowsCalibration = false
    var body: some View {
        let unit = WeightUnitProvider.current
        let displayed = $kilograms.inUnit(unit)
        let bounded = Binding<Double>(get: { displayed.wrappedValue }, set: {
            guard $0.isFinite else { return }
            displayed.wrappedValue = min(unit.weightMax, max(0, $0))
        })
        Stepper(value: bounded, in: 0...unit.weightMax, step: unit.weightStep) {
            LabeledContent {
                HStack(spacing: 4) {
                    NumericValueField(value: bounded, range: 0...unit.weightMax,
                                      textColor: isSuggested ? UIColor(MasoColor.parameterSuggestion) : .label, showsUnknown: isUnknown)
                        .accessibilityLabel(Text(title))
                        .frame(minWidth: 48, idealWidth: 64, maxWidth: 80)
                    Text(unit.label).foregroundStyle(.secondary)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if isUnknown && allowsCalibration {
                        Text("First-use calibration").font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("parameters.weight.calibration")
                    } else if isSuggested {
                        Text("Suggested").font(.caption2).foregroundStyle(MasoColor.parameterSuggestion)
                    }
                }
            }
        }.font(.body)
    }
}
struct NativeSelectionRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                content().foregroundStyle(.primary)
                Spacer(minLength: 12)
                if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.primary) }
            }.frame(minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct WorkoutSummaryContent: View {
    let plan: Plan
    var body: some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
            Text(plan.name.isEmpty ? NSLocalizedString("Shared workout", comment: "") : plan.name)
                .font(.headline).foregroundStyle(.primary).lineLimit(3)
            Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
struct PrimaryActionButton: View {
    let title: LocalizedStringKey
    var icon = "plus"
    var accent = MasoColor.accent
    var loading = false
    var size: TrainingCardActionLabel.Size = .regular
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            TrainingCardActionLabel(title: title, icon: icon, accent: accent,
                                    fillsWidth: true, loading: loading, size: size)
        }.buttonStyle(.plain)
    }
}
struct ExerciseMediaHero: View {
    let exercise: Exercise
    let width: CGFloat
    var allowsYouTubePlayback = true
    var showsTutorial = true
    var body: some View {
        FullBleedExerciseImage(exercise: exercise)
            .frame(width: width, height: Self.height(for: exercise, width: width))
            .clipped()
            .accessibilityIdentifier("exercise.media.hero")
            .detailHeroFade()
            .overlay(alignment: .bottomTrailing) {
                if showsTutorial, allowsYouTubePlayback, ExerciseMediaPolicy.youtubeID(exercise.videoURL) != nil, let url = exercise.videoURL {
                    ExerciseYouTubeLink(url: url, exercise: exercise)
                        .padding(16)
                    .accessibilityIdentifier("exercise.youtube")
                }
            }
    }

    @MainActor static func height(for exercise: Exercise, width: CGFloat) -> CGFloat {
        width * (ExerciseMediaPolicy.usesYouTubeThumbnail(for: exercise) ? 3.0 / 5.0 : 1)
    }
}

extension View {
    func detailHeroFade(height: CGFloat = 170) -> some View {
        overlay(alignment: .bottom) {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                .init(color: MasoColor.background.opacity(0.72), location: 0.55),
                .init(color: MasoColor.background, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: height).allowsHitTesting(false)
        }
    }
}

// Shared plan parameter summary, independent of browsing/import semantics.
/// Reused by routine, free-workout and live parameter editors.
struct CrossExerciseSuggestionBasis: View {
    let suggestion: ExerciseParameterSuggestion?
    @Environment(DataStore.self) private var data
    @State private var expanded = false
    var body: some View {
        if let suggestion, [.history, .userInput, .crossExercise, .personalHistory, .roughEstimate].contains(suggestion.source),
           let id = suggestion.exerciseID, let source = data.exById[id] {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if suggestion.source == .roughEstimate {
                        Text(String(format: NSLocalizedString("Rough starting weight from your completed set of %@ and reps, using a product ratio and a 70%% multiplier. Not a measured maximum or safety guarantee; adjust for your equipment and first set.", comment: "rough weight provenance"), source.displayName))
                    } else if suggestion.source == .personalHistory {
                        Text(String(format: NSLocalizedString("Estimated from your recorded working weights for %@ across multiple workouts at the same reps. Adjust after the first set.", comment: "personal exercise relationship"), source.displayName))
                        Text("Requires five consistent workout dates, including a separate validation workout, and a recent source record. This is a starting reference, not a strength measurement.")
                    } else if suggestion.source == .crossExercise {
                        Text(String(format: NSLocalizedString("Initial estimate from %@. A small study predicts six-rep maximums; Masso uses 75%% of that estimate, rounded down. Adjust after the first set.", comment: "cross exercise estimate explanation"), source.displayName))
                        Text("Masso currently limits this estimate to men aged 18–30, a confirmed 30–70 kg reference from the last 30 days, and 6–12 target reps.")
                        Link("Research source", destination: CrossExerciseLoadReference.studyURL)
                            .foregroundStyle(MasoColor.accent).tint(MasoColor.accent)
                    } else {
                        Text(String(format: NSLocalizedString("Based on your saved weight for %@. This is a starting reference; adjust after your first set.", comment: "weight reference provenance"), source.displayName))
                    }
                }.padding(.top, 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("parameters.weight.source-explanation")
            } label: {
                Text("Estimate basis")
                    .accessibilityIdentifier("parameters.cross-exercise.basis")
            }
            .font(.caption).foregroundStyle(.secondary)
            .onAppear {
                guard data.settings.hasSeenWeightEstimateExplanation != true else { return }
                expanded = true
                data.settings.hasSeenWeightEstimateExplanation = true
                data.save()
            }
            .onChange(of: suggestion) { _, _ in expanded = false }
        }
    }
}

/// Both workout list and grid use the same per-field provenance styling.
struct PlanParameterSummary: View {
    let step: PlanStep
    var exercise: Exercise? = nil
    private func number(_ text: String, field: String) -> Text {
        Text(text).foregroundColor(step.isSuggested(field) ? MasoColor.parameterSuggestion : MasoColor.textDim)
    }
    private var summary: Text {
        let sets = number(pluralizedSets(step.sets), field: "sets")
        if let duration = step.duration { return sets + Text(" · ") + number("\(duration)s", field: "duration") }
        let reps = number(step.reps.map(String.init) ?? "?", field: "reps")
        if let weight = step.weight, weight > 0 {
            return sets + Text(" · ") + number(weightLabel(weight), field: "weight") + Text(" × ") + reps
        }
        return sets + Text(" × ") + reps
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            summary.font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            if ExerciseWeightReference.needsCalibration(step, exercise: exercise ?? ExerciseLibrary.byId[step.exerciseId]) {
                Text("First-use calibration").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("parameters.weight.calibration")
            }
            if ["sets", "reps", "weight", "duration"].contains(where: step.isSuggested) {
                Text("Suggested").font(.caption2).foregroundStyle(MasoColor.parameterSuggestion)
            }
        }
    }
}

func planStepDetailLine(_ step: PlanStep) -> String {
    if let d = step.duration {
        return "\(pluralizedSets(step.sets)) · \(d)s"
    }
    let reps = step.reps.map { "\($0)" } ?? "?"
    if let w = step.weight, w > 0 {
        return "\(pluralizedSets(step.sets)) · \(weightLabel(w)) × \(reps)"
    }
    return "\(pluralizedSets(step.sets)) × \(reps)"
}


/// All preference editors use the same native attempted-dismiss confirmation.
struct PreferenceDismissalModifier: ViewModifier {
    let hasChanges: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDiscard = false
    func body(content: Content) -> some View {
        content
            .background(PreferenceDismissalObserver(hasChanges: hasChanges) { confirmingDiscard = true })
            .alert("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
    }
}

extension View {
    func confirmPreferenceDismissal(hasChanges: Bool) -> some View {
        modifier(PreferenceDismissalModifier(hasChanges: hasChanges))
    }
}

struct PreferenceDismissalObserver: UIViewControllerRepresentable {
    let hasChanges: Bool
    let onAttempt: () -> Void
    func makeUIViewController(context: Context) -> ObserverController { ObserverController() }
    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.guardDelegate.hasChanges = hasChanges
        controller.guardDelegate.onAttempt = onAttempt
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }
    final class ObserverController: UIViewController {
        let guardDelegate = DismissalDelegate()
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); install() }
        func install() {
            var ancestor: UIViewController? = self
            var presentedRoot: UIViewController?
            while let controller = ancestor {
                if controller.presentingViewController != nil { presentedRoot = controller }
                ancestor = controller.parent
            }
            guard let presentation = presentedRoot?.presentationController else { return }
            if presentation.delegate !== guardDelegate {
                guardDelegate.forwardingDelegate = presentation.delegate
                presentation.delegate = guardDelegate
            }
        }
    }
    /// Preserve SwiftUI's dismissal bookkeeping while intercepting only dirty exits.
    final class DismissalDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
        var hasChanges = false
        var onAttempt: () -> Void = {}
        weak var forwardingDelegate: UIAdaptivePresentationControllerDelegate?
        func presentationControllerShouldDismiss(_ controller: UIPresentationController) -> Bool {
            !hasChanges && (forwardingDelegate?.presentationControllerShouldDismiss?(controller) ?? true)
        }
        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            if hasChanges { onAttempt() }
            else { forwardingDelegate?.presentationControllerDidAttemptToDismiss?(controller) }
        }
        func presentationControllerWillDismiss(_ controller: UIPresentationController) {
            forwardingDelegate?.presentationControllerWillDismiss?(controller)
        }
        func presentationControllerDidDismiss(_ controller: UIPresentationController) {
            forwardingDelegate?.presentationControllerDidDismiss?(controller)
        }
    }
}

/// Shared direct demonstration link used in the exercise hero and active player.
struct ExerciseYouTubeLink: View {
    let url: URL
    var exercise: Exercise? = nil
    var iconOnly = false
    var iconSize: CGFloat = 18
    var compact = false
    @Environment(\.openURL) private var openURL
    @State private var resolving = false
    @State private var requestTask: Task<Void, Never>?
    @ViewBuilder
    var body: some View {
        if compact {
            tutorialButton.nativeGlassButtonStyle().controlSize(.mini)
        } else {
            tutorialButton
        }
    }

    private var tutorialButton: some View {
        Button {
            guard !resolving else { return }
            resolving = true
            requestTask = Task { @MainActor in
                let destination = if let exercise { await ExerciseTutorialService.shared.resolve(exercise).url } else { url }
                guard !Task.isCancelled else { return }
                resolving = false
                openURL(destination)
            }
        } label: {
            Group {
                if iconOnly {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: iconSize, weight: .semibold))
                        .frame(width: 44, height: 44)
                } else if compact {
                    Label("Watch tutorial", systemImage: "play.rectangle.fill")
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Label("Watch tutorial", systemImage: "play.rectangle.fill")
                        .font(Font.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .glassCapsuleButtonBackground(tint: .white.opacity(0.12), fallback: MasoColor.surfaceHi)
                }
            }
        }
        .foregroundStyle(MasoColor.text)
        .disabled(resolving)
        .overlay { if resolving { ProgressView().allowsHitTesting(false) } }
        .accessibilityLabel("Watch tutorial")
        .onDisappear { requestTask?.cancel(); requestTask = nil; resolving = false }
    }
}

/// Pin and title share one source across the library, selectors and workout lists.
struct ExerciseTitleLabel: View {
    @Environment(DataStore.self) private var data
    let exercise: Exercise
    var pinColor: Color = .secondary
    var body: some View {
        HStack(spacing: 5) {
            if data.isFavorite(exercise.id) {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(pinColor)
                    .accessibilityLabel("Pinned")
            }
            Text(exercise.displayName)
        }
    }
}

// MARK: - Official inline YouTube playback

struct PlayerInlineYouTubeView: View {
    let videoID: String
    let sourceURL: URL
    let playback: WorkoutYouTubePlayback
    private var status: YouTubePlaybackStatus { playback.status }
    private var destinationURL: URL { playback.destination?.url ?? sourceURL }
    private var destinationLabel: String { playback.destination?.label ?? "Watch on YouTube" }

    var body: some View {
        GeometryReader { geometry in
            let fits = geometry.size.width >= 200 && geometry.size.height >= 200
            VStack(spacing: 8) {
                if fits && status != .failed {
                    ZStack {
                        if let selectedID = playback.videoID {
                            InlineYouTubeWebView(videoID: selectedID, playback: playback)
                                .id(playback.loadID)
                        }
                        if status == .loading {
                            ProgressView().allowsHitTesting(false)
                                .accessibilityLabel("Watch tutorial")
                        }
                    }
                    .frame(height: min(geometry.size.height, max(200, geometry.size.width * 9 / 16)))
                    .background(.black)
                    .overlay(alignment: .bottomTrailing) {
                        if case .bilibili = playback.destination {
                            Link(destination: destinationURL) {
                                Image(systemName: "arrow.up.right.square").padding(10)
                            }
                            .accessibilityLabel(Text(NSLocalizedString("Watch on bilibili", comment: "")))
                            .accessibilityIdentifier("workout.tutorial.bilibili.external")
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "play.slash").font(.title2)
                        Text("Video unavailable").font(.subheadline)
                        if fits {
                            Button("Retry") { playback.retry() }
                                .nativeGlassButtonStyle()
                                .accessibilityIdentifier("workout.youtube.retry")
                        }
                        Link(destination: destinationURL) {
                            Label { Text(NSLocalizedString(destinationLabel, comment: "")) } icon: { Image(systemName: "arrow.up.right") }
                                .font(.caption)
                                .frame(minHeight: 36)
                        }
                        .foregroundStyle(MasoColor.textDim)
                        .accessibilityIdentifier("workout.youtube.external")
                    }
                    .foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.youtube.player")
        .accessibilityValue(Text(statusLabel))
        .task(id: playback.loadID) {
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled, status == .loading else { return }
            playback.failed()
        }
    }
    private var statusLabel: LocalizedStringKey {
        switch status {
        case .loading: return "Loading video"
        case .ready: return "Ready"
        case .playing: return "Video playing"
        case .failed: return "Video unavailable"
        }
    }

}

enum YouTubePlaybackStatus { case loading, ready, playing, failed }

/// Session-owned official player. Only an already-entered native PiP presentation
/// survives minimization; ordinary inline playback still stops when its sheet closes.
@MainActor @Observable
final class WorkoutYouTubePlayback {
    private(set) var exerciseID: String?
    private(set) var videoID: String?
    var status = YouTubePlaybackStatus.loading
    private(set) var isPictureInPicture = false
    private(set) var loadID = UUID()
    private(set) var destination: ExerciseTutorialDestination?
    @ObservationIgnored private var selectedExercise: Exercise?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var fallingBack = false
    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var coordinator: InlineYouTubeWebView.Coordinator?
    @ObservationIgnored private weak var retentionHost: UIView?
    @ObservationIgnored private var inlineAttached = false

    func select(exerciseID: String, videoID: String) {
        stop()
        self.exerciseID = exerciseID
        self.videoID = videoID
        destination = .youtube(videoID)
        loadID = UUID()
    }

    func select(exercise: Exercise, forceProbe: Bool = false) {
        stop()
        selectedExercise = exercise
        exerciseID = exercise.id
        loadID = UUID()
        routeTask = Task { [weak self] in
            let destination = await ExerciseTutorialService.shared.resolve(exercise, forceProbe: forceProbe)
            guard !Task.isCancelled, let self, self.exerciseID == exercise.id else { return }
            self.apply(destination)
        }
    }

    private func apply(_ destination: ExerciseTutorialDestination) {
        releaseWebView()
        self.destination = destination
        videoID = destination.playerID
        status = destination.playerID == nil ? .failed : .loading
        loadID = UUID()
    }

    func failed() {
        guard case .youtube = destination, let exercise = selectedExercise, !fallingBack else {
            if !fallingBack { status = .failed }
            return
        }
        fallingBack = true
        releaseWebView()
        status = .loading
        routeTask = Task { [weak self] in
            let destination = await ExerciseTutorialService.shared.bilibili(for: exercise)
            guard !Task.isCancelled, let self, self.exerciseID == exercise.id else { return }
            self.fallingBack = false
            self.apply(destination)
        }
    }

    func player(videoID: String) -> WKWebView {
        if let webView, self.videoID == videoID { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let coordinator = InlineYouTubeWebView.Coordinator(playback: self)
        configuration.userContentController.add(coordinator, name: "massoYouTube")
        // Observe public HTML video presentation events in the player frame. This
        // reads presentation state only; it never extracts media or forces PiP.
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.presentationObserver, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = coordinator
        web.accessibilityIdentifier = "workout.youtube.webview"
        self.coordinator = coordinator
        self.webView = web
        self.videoID = videoID
        web.loadHTMLString(InlineYouTubeWebView.html(videoID: videoID), baseURL: InlineYouTubeWebView.origin)
        return web
    }

    func attachInline(to container: UIView, videoID: String) {
        inlineAttached = true
        let web = player(videoID: videoID)
        web.removeFromSuperview()
        web.frame = container.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(web)
        if isPictureInPicture {
            // Same document/player and time; close native presentation into its
            // newly attached inline viewport instead of loading another video.
            web.closeAllMediaPresentations(completionHandler: {})
        }
    }

    func detachInline(from container: UIView) {
        guard webView?.superview === container else { return }
        inlineAttached = false
        if status == .failed { releaseWebView() }
        else { minimize() }
    }

    func minimize() {
        inlineAttached = false
        guard isPictureInPicture else { stop(); return }
        parkIfNeeded()
    }

    func registerRetentionHost(_ host: UIView) {
        retentionHost = host
        if !inlineAttached && isPictureInPicture { parkIfNeeded() }
    }

    private func parkIfNeeded() {
        guard let webView, let retentionHost else { return }
        // Keep the existing viewport/document attached to the App window while
        // its video is visible in the system PiP presentation.
        webView.removeFromSuperview()
        webView.autoresizingMask = []
        retentionHost.addSubview(webView)
    }

    func presentationChanged(isPictureInPicture: Bool) {
        self.isPictureInPicture = isPictureInPicture
        if !isPictureInPicture && !inlineAttached { stop() }
    }

    func enteredBackground() {
        if !isPictureInPicture { stop() }
    }

    func retry() {
        if let exercise = selectedExercise { select(exercise: exercise, forceProbe: true); return }
        guard let exerciseID, let videoID else { return }
        select(exerciseID: exerciseID, videoID: videoID)
    }

    private func releaseWebView() {
        let oldWeb = webView
        webView = nil
        isPictureInPicture = false
        oldWeb?.configuration.userContentController.removeScriptMessageHandler(forName: "massoYouTube")
        oldWeb?.navigationDelegate = nil
        oldWeb?.closeAllMediaPresentations(completionHandler: {})
        oldWeb?.pauseAllMediaPlayback(completionHandler: {})
        oldWeb?.stopLoading()
        oldWeb?.loadHTMLString("", baseURL: nil)
        oldWeb?.removeFromSuperview()
        coordinator = nil
        AppAudioSession.endTutorialPlayback()
    }

    func stop() {
        routeTask?.cancel(); routeTask = nil
        selectedExercise = nil; destination = nil; fallingBack = false
        releaseWebView()
        exerciseID = nil; videoID = nil
        isPictureInPicture = false
        inlineAttached = false
        status = .loading
    }

    static let presentationObserver = """
    (() => {
      document.addEventListener('playing', () => window.webkit.messageHandlers.massoYouTube.postMessage('playing'), true);
      const watched = new WeakSet();
      function bind() {
        document.querySelectorAll('video').forEach(video => {
          if (watched.has(video)) return;
          watched.add(video);
          video.addEventListener('playing', () => window.webkit.messageHandlers.massoYouTube.postMessage('playing'));
          const report = () => {
            const active = document.pictureInPictureElement === video || video.webkitPresentationMode === 'picture-in-picture';
            window.webkit.messageHandlers.massoYouTube.postMessage(active ? 'pip-entered' : 'pip-exited');
          };
          video.addEventListener('enterpictureinpicture', report);
          video.addEventListener('leavepictureinpicture', report);
          video.addEventListener('webkitpresentationmodechanged', report);
        });
      }
      new MutationObserver(bind).observe(document, {childList: true, subtree: true});
      bind();
    })();
    """
}

/// Park only an already-floating video behind Root, keeping the exact WebKit
/// document alive across fullScreenCover destruction. This is not an App mini-player.
struct WorkoutYouTubeRetentionHost: UIViewRepresentable {
    let playback: WorkoutYouTubePlayback
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.clipsToBounds = true
        host.isUserInteractionEnabled = false
        playback.registerRetentionHost(host)
        return host
    }
    func updateUIView(_ host: UIView, context: Context) { playback.registerRetentionHost(host) }
}

/// The bundle ID identifies the app as required by YouTube's WebView embedding contract.
/// No media URL extraction, downloads, custom playback controls or clipped branding.
struct InlineYouTubeWebView: UIViewRepresentable {
    let videoID: String
    let playback: WorkoutYouTubePlayback

    static var origin: URL {
        URL(string: "https://" + (Bundle.main.bundleIdentifier ?? "com.yumowu.maso").lowercased())!
    }

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        playback.attachInline(to: container, videoID: videoID)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {}

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        coordinator.playback?.detachInline(from: container)
    }

    static func html(videoID: String) -> String {
        if videoID.hasPrefix("bili:"), ExerciseTutorialService.validBVID(String(videoID.dropFirst(5))) {
            let bvid = String(videoID.dropFirst(5))
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body,iframe{margin:0;width:100%;height:100%;border:0;background:black;overflow:hidden}</style></head><body><iframe src="https://player.bilibili.com/player.html?bvid=\(bvid)&autoplay=1&danmaku=0&muted=0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen onload="window.webkit.messageHandlers.massoYouTube.postMessage('ready')" onerror="window.webkit.messageHandlers.massoYouTube.postMessage('failed')"></iframe></body></html>
            """
        }
        // IDs originate from ExerciseMediaPolicy; validate again before interpolating HTML.
        guard videoID.count == 11,
              videoID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return "" }
        let language = LanguageManager.currentLanguageCode
        let safeLanguage = language.filter { $0.isASCII && ($0.isLetter || $0 == "-") }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body,#player{margin:0;width:100%;height:100%;background:#000;overflow:hidden}</style></head><body><div id="player"></div><script>
        function report(s){window.webkit.messageHandlers.massoYouTube.postMessage(s)}
        function onYouTubeIframeAPIReady(){new YT.Player('player',{width:'100%',height:'100%',videoId:'\(videoID)',playerVars:{playsinline:1,autoplay:1,controls:1,rel:0,origin:'\(origin.absoluteString)',hl:'\(safeLanguage)'},events:{onReady:function(e){report('ready');e.target.playVideo()},onStateChange:function(e){if(e.data===1)report('playing')},onError:function(){report('failed')}}})}
        var s=document.createElement('script');s.src='https://www.youtube.com/iframe_api';s.onerror=function(){report('failed')};document.head.appendChild(s);
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var playback: WorkoutYouTubePlayback?
        init(playback: WorkoutYouTubePlayback) { self.playback = playback }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let playback, message.webView === playback.webView,
                  let value = message.body as? String else { return }
            let host = message.frameInfo.securityOrigin.host.lowercased()
            // loadHTMLString can give our own main document an opaque security
            // origin. Its script is App-owned; embedded presentation events must
            // still come from the official YouTube frame, never arbitrary frames.
            guard message.frameInfo.isMainFrame || host == InlineYouTubeWebView.origin.host || host == "youtube.com" || host.hasSuffix(".youtube.com")
                    || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
                    || (playback.videoID?.hasPrefix("bili:") == true &&
                        (host == "bilibili.com" || host.hasSuffix(".bilibili.com"))) else { return }
            switch value {
            case "ready": playback.status = .ready
            case "playing":
                AppAudioSession.beginTutorialPlayback()
                playback.status = .playing
            case "failed": playback.failed()
            case "pip-entered": playback.presentationChanged(isPictureInPicture: true)
            case "pip-exited": playback.presentationChanged(isPictureInPicture: false)
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === playback?.webView { playback?.failed() } }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === playback?.webView { playback?.failed() } }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === playback?.webView { playback?.failed() } }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false,
               let url = action.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

/// One explicit, native place for load suggestions and per-exercise preferences.
struct ExerciseLoadProgressionSheet: View {
    let exercise: Exercise
    var currentWeight: Double? = nil
    var targetReps: Int? = nil
    var requiredSets = 2
    var allowsSuggestions = true
    var onApplyWeight: ((Double) -> Void)? = nil
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var training
    @Environment(\.dismiss) private var dismiss
    @State private var maintain = false
    @State private var limitEnabled = false
    @State private var limitKg = 0.0
    @State private var candidate: ProgressionEngine.Suggestion?
    @State private var loaded = false

    private var validLimit: Bool { !limitEnabled || (limitKg.isFinite && limitKg > 0 && limitKg <= 500) }
    private var visibleCandidate: ProgressionEngine.Suggestion? {
        guard !maintain, data.settings.loadProgression?.maintain != true, validLimit,
              let candidate, !limitEnabled || candidate.weightKg <= limitKg else { return nil }
        return candidate
    }

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Toggle("Maintain current weights", isOn: $maintain)
                        .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                        .accessibilityIdentifier("progression.maintain")
                    Toggle("Stage weight limit", isOn: $limitEnabled)
                        .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                        .accessibilityIdentifier("progression.limit.enabled")
                    if limitEnabled {
                        NativeWeightParameterRow(title: "Stage weight limit", kilograms: $limitKg)
                            .accessibilityIdentifier("progression.limit.value")
                    }
                } footer: {
                    Text("These preferences only limit progression suggestions. They do not change saved weights or define a safe maximum.")
                }
                Section {
                    if data.settings.loadProgression?.maintain == true {
                        Text("Global maintenance mode is on.")
                    } else if let suggestion = visibleCandidate {
                        LabeledContent("Optional next weight", value: weightLabel(suggestion.weightKg))
                            .accessibilityIdentifier("progression.suggestion")
                        Text("Repeated workouts reached the rep range. Only consider an increase if your form stayed steady and you had reps left.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let onApplyWeight {
                            Button("Use suggested weight") {
                                savePolicy(); onApplyWeight(suggestion.weightKg); dismiss()
                            }
                            .accessibilityIdentifier("progression.apply")
                        }
                        Button("Not now") {
                            var prefs = data.settings.loadProgression ?? .init()
                            prefs.notices[exercise.id]?.declined = true
                            data.settings.loadProgression = prefs; data.save(); candidate = nil
                        }
                        .accessibilityIdentifier("progression.decline")
                    } else {
                        Text("No weight increase suggested.")
                            .accessibilityIdentifier("progression.quiet")
                    }
                } header: {
                    Text("Weight progression")
                } footer: {
                    Text("Suggestions depend on your goal and repeated workouts. Keeping the same weight is also an option.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(MasoColor.background)
            .navigationTitle("Weight progression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePolicy(); dismiss() }
                        .disabled(!validLimit).accessibilityIdentifier("progression.save")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            let prefs = data.settings.loadProgression ?? .init()
            let policy = prefs.exercises[exercise.id] ?? .init()
            maintain = policy.maintain; limitEnabled = policy.limitKg != nil; limitKg = policy.limitKg ?? 0
            let browsing = currentWeight == nil && targetReps == nil
            candidate = allowsSuggestions ? ProgressionEngine.suggestion(exerciseId: exercise.id,
                targetReps: targetReps ?? data.lastSet(forExerciseId: exercise.id)?.reps,
                sets: data.sets, exercise: exercise, goal: data.settings.trainingGoalKind,
                currentWeight: browsing ? data.lastSet(forExerciseId: exercise.id)?.weight : currentWeight,
                requiredSets: requiredSets, preferences: prefs,
                activeSessionID: training.session?.completed == false ? training.workoutSessionID : nil) : nil
            if let candidate {
                var updated = prefs
                updated.notices[exercise.id] = .init(evidence: candidate.evidence, shownAt: Date())
                data.settings.loadProgression = updated; data.save()
            }
        }
    }
    private func savePolicy() {
        guard validLimit else { return }
        var prefs = data.settings.loadProgression ?? .init()
        prefs.exercises[exercise.id] = .init(maintain: maintain, limitKg: limitEnabled ? limitKg : nil)
        data.settings.loadProgression = prefs; data.save()
    }
}
