import SwiftUI
import UIKit

enum WorkoutReportPresentation {
    /// The workout just finished. Exit ends the player once and returns home.
    case finish
    /// Opened from history. The surrounding stack owns Back.
    case history
}

/// One finished session, shown as a native sheet. Green is this session only.
struct WorkoutSessionReportScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.requestReview) private var requestReview
    let records: [SetRecord]
    var workoutName: String?
    var presentation: WorkoutReportPresentation = .history
    var sessionPhoto: UIImage? = nil
    var onSavePlan: (() -> Void)?
    var onExit: () -> Void = {}
    var onRepeat: (() -> Void)? = nil
    var onChangePhoto: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showsBack = false
    @State private var selectedNode: String?
    @State private var collapsed: Set<String> = []
    @State private var detailID: String?
    @State private var durationExpanded = false
    @State private var heartExpanded = false
    @State private var includeDetails = false
    @State private var includeHeart = false
    @State private var includePhoto = false
    @State private var exported = false
    @State private var exportName = ""
    @State private var confirmingDelete = false
    @State private var showSavePrompt = false
    @State private var planSaved = false
    @State private var showReminder = false
    @State private var activity: ShareImageBox?

    private var model: SessionMuscleReport {
        var samples: [String: [SessionMuscleReport.HeartPoint]] = [:]
        for record in records {
            samples[record.id] = WorkoutHeartLocalStore.shared.samples(for: record).map {
                SessionMuscleReport.HeartPoint(date: $0.date, bpm: $0.bpm)
            }
        }
        return SessionMuscleReport.make(
            records: records,
            exercises: data.exById,
            regions: (try? MuscleBodyRegion.loadBundled()) ?? [],
            samples: samples
        )
    }

    var body: some View {
        let report = model
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sessionHeading
                    bodyStage(report)
                    legend
                    SessionReportStats(report: report)
                    ForEach(report.muscles) { muscle in
                        muscleSection(muscle, proxy: proxy)
                    }
                    tables
                    shareScope
                    Text(verbatim: shareSelection(report).lines.joined(separator: "\n"))
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("workout.sessionReport.shareText")
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, MasoMetrics.rowPaddingV)
                .padding(.bottom, MasoMetrics.pageBottomInset)
            }
        }
        .background(MasoColor.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { floatingShare(identifier: "workout.sessionReport.share") { export(report) } }
        .overlay(alignment: .top) {
            if exported {
                Text(verbatim: exportName)
                    .accessibilityIdentifier("workout.sessionReport.shareExported")
                    .frame(width: 1, height: 1)
            }
        }
        .navigationTitle("Workout report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .finish {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: requestExit) {
                        Text("Exit")
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: true)
                    .accessibilityIdentifier("workout.sessionReport.exit")
                }
            }
            if onRepeat != nil || onChangePhoto != nil || onDelete != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let onRepeat {
                            Button("Repeat Workout", systemImage: "arrow.clockwise", action: onRepeat)
                        }
                        if let onChangePhoto {
                            Button("Photo", systemImage: "photo", action: onChangePhoto)
                        }
                        if onDelete != nil {
                            Button("Delete workout", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityIdentifier("workout.history.more")
                }
            }
        }
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) {
            setDetail(report.muscles.flatMap(\.exercises).first { $0.id == detailID })
        }
        .sheet(item: $activity) { payload in
            ActivityViewController(activityItems: [payload.image]) { _ in activity = nil }
        }
        .alert(NSLocalizedString("Save as plan?", comment: ""), isPresented: $showSavePrompt) {
            Button(NSLocalizedString("Save as plan", comment: "")) {
                onSavePlan?()
                planSaved = true
                finishExit()
            }
            Button(NSLocalizedString("Don't Save", comment: ""), role: .cancel) { finishExit() }
        } message: {
            Text(NSLocalizedString("Keep this workout as a reusable routine.", comment: ""))
        }
        .alert(NSLocalizedString("Want a nudge when you're recovered?", comment: ""), isPresented: $showReminder) {
            Button(NSLocalizedString("Turn on reminders", comment: "")) {
                Task { @MainActor in
                    let granted = await WorkoutReminderScheduler.shared.requestAuthorization()
                    data.settings.workoutRemindersEnabled = granted
                    if granted { data.rescheduleWorkoutReminders() }
                    onExit()
                }
            }
            Button(NSLocalizedString("Not now", comment: ""), role: .cancel) {
                data.settings.workoutRemindersEnabled = false
                data.rescheduleWorkoutReminders()
                onExit()
            }
        } message: {
            Text(NSLocalizedString("Masso can remind you to train once your muscles have recovered — all on your device. You can change this anytime in Settings.", comment: ""))
        }
        .alert("Delete workout?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sets and PRs from this workout will be removed. Your plans stay.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.sessionReport")
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var tables: some View {
        VStack(spacing: 0) {
            tableButton("Exercise duration", expanded: durationExpanded, identifier: "workout.sessionReport.duration") {
                durationExpanded.toggle()
            }
            if durationExpanded {
                WorkoutReportView(records: records, workoutName: workoutName, scope: .duration)
                    .padding(.bottom, MasoMetrics.rowPaddingV)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workout.sessionReport.durationTable")
            }
            tableButton("Exercises and heart rate", expanded: heartExpanded, identifier: "workout.sessionReport.heartTable") {
                heartExpanded.toggle()
            }
            if heartExpanded {
                WorkoutReportView(records: records, workoutName: workoutName, scope: .heart)
                    .padding(.bottom, MasoMetrics.rowPaddingV)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workout.sessionReport.heartTableBody")
            }
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        .accessibilityElement(children: .contain)
    }

    private func tableButton(_ title: LocalizedStringKey, expanded: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MasoMetrics.cardHeaderGap) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title).font(.body)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func floatingShare(identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Share").frame(maxWidth: .infinity)
        }
        .nativeGlassProminentButtonStyle()
        .controlSize(.large)
        .tint(MasoColor.accent)
        .foregroundStyle(.black)
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.bottom, MasoMetrics.rowPaddingV)
        .accessibilityIdentifier(identifier)
    }

    private func bodyStage(_ report: SessionMuscleReport) -> some View {
        MuscleBody3DView(
            fatigueMap: report.intensity,
            showsBack: showsBack,
            autoRotates: false,
            highlightedRegionNode: selectedNode,
            showsFatigueColors: true,
            accessibilityID: "workout.sessionReport.body",
            onMuscleTap: { region, _ in
                guard let row = report.muscles.first(where: { $0.nodes.contains(region.node) }) else { return }
                selectedNode = row.nodes.first
                collapsed.remove(row.id)
            }
        )
        .frame(height: 380)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                faceButton("Body front", back: false)
                faceButton("Body back", back: true)
            }
            .padding(8)
        }
        .accessibilityElement(children: .contain)
    }

    private func faceButton(_ title: LocalizedStringKey, back: Bool) -> some View {
        Button(title) { showsBack = back }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityAddTraits(showsBack == back ? .isSelected : [])
    }

    private var legend: some View {
        FlowLayout(spacing: MasoMetrics.rowPaddingH) {
            legendItem("Most volume", amount: 1)
            legendItem("Some volume", amount: 0.55)
            legendItem("Light volume", amount: 0.22)
            legendItem("Not trained", amount: 0)
        }
        .font(.caption)
        .foregroundStyle(MasoColor.textDim)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(_ title: LocalizedStringKey, amount: Double) -> some View {
        HStack(spacing: MasoMetrics.cardHeaderGap) {
            RoundedRectangle(cornerRadius: 2)
                .fill(MasoColor.recoverySurfaceColor(fatigue: amount))
                .frame(width: 10, height: 10)
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    private func muscleSection(_ muscle: SessionMuscleReport.MuscleRow, proxy: ScrollViewProxy) -> some View {
        let open = !collapsed.contains(muscle.id)
        return VStack(spacing: 0) {
            Button {
                if open { collapsed.insert(muscle.id) } else { collapsed.remove(muscle.id) }
                selectedNode = muscle.nodes.first
            } label: {
                HStack {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                        .flipsForRightToLeftLayoutDirection(true).accessibilityHidden(true)
                    Text(muscle.muscle.displayName).font(.headline)
                    Spacer()
                    Text(muscle.allocatedSets, format: .number.precision(.fractionLength(1)))
                        .font(.headline).monospacedDigit()
                    Text("Sets").font(.caption).foregroundStyle(MasoColor.textDim)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workout.sessionReport.muscle.\(muscle.muscle.rawValue)")
            if open {
                ForEach(muscle.exercises) { exercise in
                    Button { detailID = exercise.id } label: { exerciseRow(exercise, section: muscle.muscle) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("workout.sessionReport.exercise.\(exercise.id)")
                        .id(exercise.id)
                    if showsSixRM(exercise, in: muscle), let record = exercise.records.first(where: qualifiesForSixRM) {
                        ConfirmedBenchSixRMButton(record: record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        .id(muscle.id)
        .onChange(of: selectedNode) { _, node in
            guard let node, muscle.nodes.contains(node) else { return }
            proxy.scrollTo(muscle.id, anchor: .top)
        }
    }

    private func qualifiesForSixRM(_ record: SetRecord) -> Bool {
        record.exerciseId == CrossExerciseLoadReference.anchorID && record.reps == 6 && (record.weight ?? 0) > 0
    }

    /// Bench's primary tag is mid-chest, while the report section is the body region.
    /// Show the existing confirmation once, on the first section that lists the exercise.
    private func showsSixRM(_ exercise: SessionMuscleReport.ExerciseFacts, in muscle: SessionMuscleReport.MuscleRow) -> Bool {
        guard exercise.records.contains(where: qualifiesForSixRM) else { return false }
        return model.muscles.first { $0.exercises.contains { $0.id == exercise.id } }?.id == muscle.id
    }

    private func exerciseRow(_ exercise: SessionMuscleReport.ExerciseFacts, section: MuscleGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body.weight(.semibold))
                        .accessibilityIdentifier("workout.sessionReport.exerciseName.\(section.rawValue).\(exercise.id)")
                    if let variant = exercise.variant {
                        Text(variant).font(.caption).foregroundStyle(MasoColor.textDim)
                    }
                }
                Spacer(minLength: 8)
                if let volume = exercise.loadedVolumeKg {
                    Text(weightLabel(volume)).font(.body.weight(.semibold)).monospacedDigit()
                }
            }
            HStack(spacing: 6) {
                Text(loadLine(exercise)).font(.caption).foregroundStyle(MasoColor.textDim).monospacedDigit()
                if let work = exercise.workSeconds {
                    Text(reportClock(work)).font(.caption).foregroundStyle(MasoColor.textDim).monospacedDigit()
                }
                if exercise.timingIncomplete {
                    Text("Timing incomplete").font(.caption.weight(.semibold))
                }
            }
            ForEach(exercise.records) { record in
                if let line = SessionMuscleReport.setLine(record) {
                    Text(verbatim: line)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MasoColor.textDim)
                        .accessibilityIdentifier("workout.sessionReport.set.\(section.rawValue).\(record.id)")
                }
            }
            if exercise.heart.contains(where: \.drawsLine) {
                HeartSparkline(segments: exercise.heart)
                    .accessibilityIdentifier("workout.sessionReport.spark.\(exercise.id)")
            } else {
                Text("No heart rate").font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 28)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setDetail(_ exercise: SessionMuscleReport.ExerciseFacts?) -> some View {
        AppNavigationStack {
            List {
                if let exercise {
                    ForEach(exercise.records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            if let weight = record.weight, weight > 0, let reps = record.reps {
                                Text("\(weightLabel(weight)) × \(reps)")
                            } else if let reps = record.reps {
                                Text("\(reps)")
                            } else if let duration = record.duration {
                                Text(reportClock(Double(duration)))
                            }
                            if let work = record.activeSeconds {
                                Text(reportClock(work)).font(.caption).foregroundStyle(MasoColor.textDim)
                            } else {
                                Text("Timing incomplete").font(.caption.weight(.semibold))
                            }
                            if record.restBeforeSeconds != nil {
                                Text("Recorded rest").font(.caption).foregroundStyle(MasoColor.textDim)
                            }
                            let hearts = SessionMuscleReport.heartSegments(
                                for: record,
                                samples: WorkoutHeartLocalStore.shared.samples(for: record).map {
                                    SessionMuscleReport.HeartPoint(date: $0.date, bpm: $0.bpm)
                                }
                            )
                            if hearts.contains(where: \.drawsLine) {
                                Text("\(Int((hearts.flatMap(\.points).map(\.bpm).max() ?? 0).rounded()))").font(.caption)
                            } else {
                                Text("No heart rate").font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(exercise?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { detailID = nil } } }
        }
    }

    private var sessionHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let workoutName, !workoutName.isEmpty {
                Text(workoutName).font(.title2.bold()).foregroundStyle(MasoColor.text)
            }
            if let day = records.map(\.performedAt).min() {
                Text(verbatim: SessionMuscleReport.dayLabel(day))
                    .font(.subheadline)
                    .foregroundStyle(MasoColor.textDim)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.sessionReport.heading")
    }

    private var shareScope: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share").font(.headline)
            Toggle("Include exercise detail", isOn: $includeDetails)
                .accessibilityIdentifier("workout.sessionReport.shareDetailsToggle")
            Toggle("Include heart rate", isOn: $includeHeart)
                .accessibilityIdentifier("workout.sessionReport.shareHeartToggle")
            if sessionPhoto != nil {
                Toggle("Include photo", isOn: $includePhoto)
                    .accessibilityIdentifier("workout.sessionReport.sharePhotoToggle")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.sessionReport.shareScope")
    }

    private func shareSelection(_ report: SessionMuscleReport) -> SessionMuscleReport.ShareContent {
        SessionMuscleReport.shareContent(
            report: report,
            workoutName: workoutName,
            selection: .init(includeDetails: includeDetails, includeHeart: includeHeart, includePhoto: includePhoto && sessionPhoto != nil)
        )
    }

    #if DEBUG
    /// Distinct Documents names so the three boundary exports do not overwrite each other.
    static func exportFileName(_ selection: SessionMuscleReport.ShareContent) -> String {
        if selection.includesPhoto { return "session-report-heart-photo.png" }
        if selection.muscles.contains(where: { $0.heart != nil }) { return "session-report-heart.png" }
        if selection.muscles.contains(where: { !$0.exercises.isEmpty }) { return "session-report-detail.png" }
        return "session-report-default.png"
    }
    #endif

    private func export(_ report: SessionMuscleReport) {
        let selection = shareSelection(report)
        let card = ShareBitmap(report: report, content: selection, photo: selection.includesPhoto ? sessionPhoto : nil)
        guard let image = ShareImageRenderer.render(width: 390, { card }) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASO_SESSION_REPORT_EXPORT"] == "1",
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = image.pngData() {
            let name = Self.exportFileName(selection)
            let url = directory.appendingPathComponent(name)
            if (try? data.write(to: url, options: .atomic)) != nil {
                exportName = name
                exported = true
            }
            return
        }
        #endif
        activity = ShareImageBox(image: image)
    }

    private func loadLine(_ exercise: SessionMuscleReport.ExerciseFacts) -> String {
        switch exercise.load {
        case .loaded(_, let weight, let reps):
            return "\(exercise.setCount) × \(weightLabel(weight)) · \(reps.map(String.init).joined(separator: ", "))"
        case .mixed:
            return "\(exercise.setCount)"
        case .bodyweight(_, let reps):
            return "\(exercise.setCount) × \(reps.map(String.init).joined(separator: ", "))"
        case .timed(let seconds):
            return reportClock(Double(seconds))
        case .counted:
            return "\(exercise.setCount)"
        }
    }

    private func requestExit() {
        if onSavePlan != nil && !planSaved {
            showSavePrompt = true
            return
        }
        finishExit()
    }

    private func finishExit() {
        if data.shouldOfferReminderPrompt() {
            showReminder = true
            return
        }
        if data.shouldOfferReview() { requestReview() }
        onExit()
    }
}

private struct HeartSparkline: View {
    let segments: [SessionMuscleReport.HeartSegment]
    private var points: [SessionMuscleReport.HeartPoint] { segments.flatMap(\.points) }
    var body: some View {
        let lines = segments.filter(\.drawsLine)
        Canvas { context, size in
            guard let first = points.map(\.date).min(), let last = points.map(\.date).max(), last > first else { return }
            let low = (points.map(\.bpm).min() ?? 0) - 4
            let high = (points.map(\.bpm).max() ?? 1) + 4
            let span = last.timeIntervalSince(first)
            func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(first) / span) * size.width }
            func y(_ bpm: Double) -> CGFloat { (1 - CGFloat((bpm - low) / (high - low))) * size.height }
            for segment in lines {
                var path = Path()
                for (index, point) in segment.points.enumerated() {
                    let place = CGPoint(x: x(point.date), y: y(point.bpm))
                    if index == 0 { path.move(to: place) } else { path.addLine(to: place) }
                }
                context.stroke(path, with: .color(MasoColor.accent), lineWidth: 1.7)
            }
        }
        .frame(height: 32)
        .accessibilityLabel(Text("\(Int((points.map(\.bpm).max() ?? 0).rounded()))"))
    }
}

/// The same three labeled numbers on the report, the share preview, and the exported card.
private struct SessionReportStats: View {
    let report: SessionMuscleReport
    var identifier = "workout.sessionReport.stats"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            column(report.workSeconds.map(reportClock) ?? "—", "Work time", tag: report.timingIncomplete ? "Timing incomplete" : nil)
            column("\(report.setCount)", "Sets", tag: nil)
            column(report.loadedVolumeKg.map { weightLabel($0) } ?? "—", "Volume", tag: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func column(_ value: String, _ caption: LocalizedStringKey, tag: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text(caption)
                if let tag { Text(tag).fontWeight(.semibold).foregroundStyle(MasoColor.text) }
            }
            .font(.caption).foregroundStyle(MasoColor.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShareBitmap: View {
    let report: SessionMuscleReport
    let content: SessionMuscleReport.ShareContent
    var photo: UIImage? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name = content.name, !name.isEmpty { Text(name).font(.title2.bold()) }
            if let day = content.day {
                Text(verbatim: SessionMuscleReport.dayLabel(day)).font(.subheadline)
            }
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220)
            }
            ShareMuscleBody3D(muscleStyle: { muscle in
                guard let amount = report.intensity[muscle] else { return nil }
                return (MasoColor.accent, amount)
            })
            SessionReportStats(report: report, identifier: "workout.sessionReport.exportStats")
            ForEach(content.muscles.filter { !$0.exercises.isEmpty || $0.heart != nil }) { muscle in
                Text(muscle.name).font(.subheadline.weight(.semibold))
                ForEach(muscle.exercises) { exercise in
                    Text(exercise.name).font(.caption)
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.caption.monospacedDigit())
                    }
                }
                if let heart = muscle.heart {
                    Text(verbatim: heart).font(.caption.monospacedDigit())
                }
            }
        }
        .padding(MasoMetrics.pagePaddingHorizontal)
        .foregroundStyle(MasoColor.text)
        .preferredColorScheme(.dark)
    }
}

private struct ShareImageBox: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The presenting cover's Dynamic Type does not cross into a sheet.
private struct ReportSheetDynamicType: ViewModifier {
    @Environment(\.dynamicTypeSize) private var current
    func body(content: Content) -> some View {
        let size: DynamicTypeSize = ProcessInfo.processInfo.environment["MASO_TEST_LARGE_TYPE"] == "1" ? .accessibility3 : current
        content.environment(\.dynamicTypeSize, size)
    }
}

extension View {
    /// Large native sheet used by both the finished-workout and history report.
    func sessionReportSheetChrome() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(MasoColor.background)
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .modifier(ReportSheetDynamicType())
    }
}

private func reportClock(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds.rounded()))
    return "\(whole / 60):" + String(format: "%02d", whole % 60)
}
