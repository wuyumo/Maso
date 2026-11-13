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
    var onSavePlan: (() -> Void)?
    var onExit: () -> Void = {}

    @State private var showsBack = false
    @State private var selectedNode: String?
    @State private var collapsed: Set<String> = []
    @State private var detailID: String?
    @State private var durationExpanded = false
    @State private var heartExpanded = false
    @State private var showShare = false
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
                    bodyStage(report)
                    legend
                    SessionReportStats(report: report)
                    ForEach(report.muscles) { muscle in
                        muscleSection(muscle, proxy: proxy)
                    }
                    tables
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, MasoMetrics.rowPaddingV)
                .padding(.bottom, MasoMetrics.pageBottomInset)
            }
        }
        .background(MasoColor.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { floatingShare(identifier: "workout.sessionReport.share") { showShare = true } }
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
        }
        .sheet(isPresented: Binding(get: { detailID != nil }, set: { if !$0 { detailID = nil } })) {
            setDetail(report.muscles.flatMap(\.exercises).first { $0.id == detailID })
        }
        .sheet(isPresented: $showShare) {
            AppNavigationStack {
                sharePreview(report)
                    .navigationTitle("Share")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { showShare = false }
                                .accessibilityIdentifier("workout.sessionReport.shareBack")
                        }
                    }
            }
            .sessionReportSheetChrome()
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.sessionReport")
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var tables: some View {
        VStack(spacing: 0) {
            DisclosureGroup(isExpanded: $durationExpanded) {
                if durationExpanded {
                    WorkoutReportView(records: records, workoutName: workoutName, scope: .duration)
                        .padding(.bottom, MasoMetrics.rowPaddingV)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("workout.sessionReport.durationTable")
                }
            } label: {
                Text("Exercise duration").font(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("workout.sessionReport.duration")
            }
            DisclosureGroup(isExpanded: $heartExpanded) {
                if heartExpanded {
                    WorkoutReportView(records: records, workoutName: workoutName, scope: .heart)
                        .padding(.bottom, MasoMetrics.rowPaddingV)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("workout.sessionReport.heartTableBody")
                }
            } label: {
                Text("Exercises and heart rate").font(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("workout.sessionReport.heartTable")
            }
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        .accessibilityElement(children: .contain)
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
        HStack(spacing: 12) {
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
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(MasoColor.recoverySurfaceColor(fatigue: amount))
                .frame(width: 10, height: 10)
            Text(title).lineLimit(1).minimumScaleFactor(0.7)
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

    private func sharePreview(_ report: SessionMuscleReport) -> some View {
        SharePreview(
            report: report,
            name: workoutName,
            onShare: { image in activity = ShareImageBox(image: image) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.sessionReport.sharePreview")
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

private struct SharePreview: View {
    let report: SessionMuscleReport
    let name: String?
    let onShare: (UIImage) -> Void
    @State private var includeDetails = false
    @State private var includeHeart = false
    @State private var showsBack = false
    @State private var exported = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MuscleBody3DView(
                        fatigueMap: report.intensity,
                        showsBack: showsBack,
                        autoRotates: false,
                        showsFatigueColors: true,
                        accessibilityID: "workout.sessionReport.shareBody"
                    )
                    .id("workout.sessionReport.shareTop")
                    .frame(height: 380)
                    .overlay(alignment: .bottomLeading) {
                        HStack {
                            Button("Body front") { showsBack = false }
                            Button("Body back") { showsBack = true }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(8)
                    }
                    SessionReportStats(report: report, identifier: "workout.sessionReport.shareStats")
                    ForEach(report.muscles) { muscle in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(muscle.muscle.displayName).font(.headline)
                                Spacer()
                                Text(muscle.allocatedSets, format: .number.precision(.fractionLength(1)))
                                    .monospacedDigit()
                                Text("Sets").font(.caption).foregroundStyle(MasoColor.textDim)
                            }
                            if includeDetails || includeHeart {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(muscle.exercises) { exercise in
                                        Text(exercise.name).font(.subheadline)
                                        if includeHeart {
                                            if exercise.heart.contains(where: \.drawsLine) {
                                                HeartSparkline(segments: exercise.heart)
                                                    .accessibilityIdentifier("workout.sessionReport.shareSpark.\(exercise.id)")
                                            } else {
                                                Text("No heart rate").font(.caption.weight(.semibold))
                                            }
                                        }
                                    }
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("workout.sessionReport.shareDetails.\(muscle.id)")
                            } else {
                                Text(muscle.exercises.map(\.name).joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(MasoColor.textDim)
                                    .accessibilityIdentifier("workout.sessionReport.shareSummary.\(muscle.id)")
                            }
                        }
                        .padding(MasoMetrics.rowPaddingH)
                        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                    }
                    Toggle("Include exercise detail", isOn: $includeDetails)
                        .accessibilityIdentifier("workout.sessionReport.shareDetailsToggle")
                    Toggle("Include heart rate", isOn: $includeHeart)
                        .accessibilityIdentifier("workout.sessionReport.shareHeartToggle")
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.bottom, MasoMetrics.pageBottomInset)
            }
            .onChange(of: includeHeart) { _, _ in scrollToShareTop(proxy) }
            .onChange(of: includeDetails) { _, _ in scrollToShareTop(proxy) }
            }
        }
        .background(MasoColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .overlay(alignment: .bottom) {
            Button(action: send) {
                Text("Share").frame(maxWidth: .infinity)
            }
            .nativeGlassProminentButtonStyle()
            .controlSize(.large)
            .tint(MasoColor.accent)
            .foregroundStyle(.black)
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.bottom, MasoMetrics.rowPaddingV)
            .accessibilityIdentifier("workout.sessionReport.shareSend")
        }
        .overlay(alignment: .top) {
            if exported {
                Text("session-report-share.png")
                    .accessibilityIdentifier("workout.sessionReport.shareExported")
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(false)
            }
        }
    }

    private func scrollToShareTop(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            proxy.scrollTo("workout.sessionReport.shareTop", anchor: .top)
        }
    }

    private func send() {
        let card = shareBitmap(report: report, name: name, details: includeDetails, heart: includeHeart)
        guard let image = ShareImageRenderer.render(width: 390, { card }) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASO_SESSION_REPORT_EXPORT"] == "1",
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = image.pngData() {
            try? data.write(to: directory.appendingPathComponent("session-report-share.png"))
            exported = true
            return
        }
        #endif
        onShare(image)
    }
}

private struct ShareBitmap: View {
    let report: SessionMuscleReport
    let name: String?
    let details: Bool
    let heart: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name, !name.isEmpty { Text(name).font(.title2.bold()) }
            ShareMuscleBody3D(muscleStyle: { muscle in
                guard let amount = report.intensity[muscle] else { return nil }
                return (MasoColor.accent, amount)
            })
            SessionReportStats(report: report, identifier: "workout.sessionReport.exportStats")
            ForEach(report.muscles) { muscle in
                HStack {
                    Text(muscle.muscle.displayName)
                    Spacer()
                    Text(muscle.allocatedSets, format: .number.precision(.fractionLength(1)))
                }
                .font(.subheadline)
                if details {
                    Text(muscle.exercises.map(\.name).joined(separator: " · "))
                        .font(.caption).foregroundStyle(MasoColor.textDim)
                }
                if heart {
                    if let peak = muscle.exercises.flatMap(\.heart).flatMap(\.points).map(\.bpm).max() {
                        Text("\(Int(peak.rounded()))").font(.caption).monospacedDigit()
                    } else {
                        Text("No heart rate").font(.caption)
                    }
                }
            }
        }
        .padding(MasoMetrics.pagePaddingHorizontal)
        .foregroundStyle(MasoColor.text)
        .preferredColorScheme(.dark)
    }
}

private func shareBitmap(report: SessionMuscleReport, name: String?, details: Bool, heart: Bool) -> ShareBitmap {
    ShareBitmap(report: report, name: name, details: details, heart: heart)
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
