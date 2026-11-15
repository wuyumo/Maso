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
    var onDelete: (() -> Void)? = nil

    @State private var planShareID = UUID().uuidString
    @State private var showingPreview = false
    @State private var photoRemoved = false
    @State private var pickedPhoto: UIImage?
    @State private var selectedNode: String?
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
        ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ReportPhotoPickerButton(photo: displayedPhoto, onChange: updatePhoto)
                    sessionHeading
                    bodyStage(report)
                    SessionReportStats(report: report)
                        .contentCardChrome()
                    ForEach(report.exercises) { exercise in
                        ReportExerciseSummary(exercise: exercise, intensity: exerciseIntensity(exercise), showsHeart: true)
                            .padding(MasoMetrics.cardPadding)
                            .contentCardChrome(padding: 0)
                            .accessibilityIdentifier("workout.sessionReport.exercise.\(exercise.id)")
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, MasoMetrics.rowPaddingV)
                .padding(.bottom, MasoMetrics.pageBottomInset)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                includePhoto = false
                showingPreview = true
            } label: {
                TrainingCardActionLabel(title: "Share", icon: "square.and.arrow.up", accent: MasoColor.accent, size: .large)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.bottom, MasoMetrics.rowPaddingV)
            .accessibilityIdentifier("workout.sessionReport.share")
        }
        .navigationTitle("Workout report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .finish {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: requestExit)
                        .accessibilityIdentifier("workout.sessionReport.exit")
                }
            }
            if onRepeat != nil || onDelete != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let onRepeat {
                            Button("Repeat Workout", systemImage: "arrow.clockwise", action: onRepeat)
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
        .sheet(isPresented: $showingPreview) { sharePreview(report) }
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

    private func bodyStage(_ report: SessionMuscleReport) -> some View {
        MuscleBody3DView(
            fatigueMap: report.intensity,
            autoRotates: false,
            highlightedRegionNode: selectedNode,
            showsFatigueColors: true,
            accessibilityID: "workout.sessionReport.body",
            onMuscleTap: { region, _ in
                guard let row = report.muscles.first(where: { $0.nodes.contains(region.node) }) else { return }
                selectedNode = row.nodes.first
            }
        )
        .frame(height: 380)
        .overlay(alignment: .bottomLeading) {
            legend.padding(8).allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private var sessionHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let workoutName, !workoutName.isEmpty {
                Text(workoutName).font(.title2.weight(.semibold)).foregroundStyle(MasoColor.text)
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

    private func shareSelection(_ report: SessionMuscleReport) -> SessionMuscleReport.ShareContent {
        SessionMuscleReport.shareContent(
            report: report,
            workoutName: workoutName,
            selection: .init(includeDetails: true, includeHeart: false, includePhoto: includePhoto && displayedPhoto != nil)
        )
    }

    #if DEBUG
    /// Distinct Documents names so the three boundary exports do not overwrite each other.
    static func exportFileName(_ selection: SessionMuscleReport.ShareContent) -> String {
        if selection.includesPhoto { return "session-report-photo.png" }
        if selection.muscles.contains(where: { $0.heart != nil }) { return "session-report-heart.png" }
        if selection.muscles.contains(where: { !$0.exercises.isEmpty }) { return "session-report-detail.png" }
        return "session-report-default.png"
    }
    #endif

    private func export(_ report: SessionMuscleReport) {
        let selection = shareSelection(report)
        let card = shareBitmap(report)
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

    private func updatePhoto(_ photo: UIImage?) {
        pickedPhoto = photo
        photoRemoved = photo == nil
        if photo == nil { includePhoto = false }
        guard let id = photoStorageID else { return }
        if let photo { data.setSessionPhoto(photo, forSessionId: id) }
        else { data.removeSessionPhoto(forSessionId: id) }
    }

    private var photoStorageID: String? {
        let ids = Set(records.map(\.id))
        guard !ids.isEmpty else { return nil }
        return data.recordedWorkoutSessions().first { Set(data.recordedSets(for: $0).map(\.id)) == ids }?.id
    }

    private var displayedPhoto: UIImage? {
        photoRemoved ? nil : (pickedPhoto ?? photoStorageID.flatMap { data.sessionPhoto(forSessionId: $0) } ?? sessionPhoto)
    }

    private func exerciseIntensity(_ exercise: SessionMuscleReport.ExerciseFacts) -> [MuscleGroup: Double] {
        MuscleStatusCompute.muscleFatigueMap(sets: exercise.records, exById: data.exById,
            now: records.map(\.performedAt).max() ?? Date())
    }

    private var planQRPayload: String? {
        SessionMuscleReport.planQRPayload(records: records, workoutName: workoutName, shareID: planShareID)
    }

    private func shareBitmap(_ report: SessionMuscleReport, preview: Bool = false) -> some View {
        ShareBitmap(report: report, content: shareSelection(report),
            photo: includePhoto ? displayedPhoto : nil, availablePhoto: displayedPhoto,
            photoSelection: preview ? $includePhoto : nil,
            onPhotoChange: preview ? { photo in updatePhoto(photo); includePhoto = photo != nil } : nil,
            qrPayload: planQRPayload, intensity: exerciseIntensity)
    }

    private func sharePreview(_ report: SessionMuscleReport) -> some View {
        AppNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    shareBitmap(report, preview: true)
                    if exported {
                        Text(verbatim: exportName).font(.caption)
                            .accessibilityIdentifier("workout.sessionReport.shareExported")
                    }
                }.padding(.vertical, 16)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingPreview = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { export(report) }
                        .accessibilityIdentifier("workout.sessionReport.previewShare")
                }
            }
            .sheet(item: $activity) { payload in
                ActivityViewController(activityItems: [payload.image]) { _ in activity = nil }
            }
        }
        .presentationBackground(MasoColor.background)
        .presentationDragIndicator(.visible)
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
        let ordered = segments.filter { !$0.points.isEmpty }.sorted { $0.points[0].date < $1.points[0].date }
        let lines = ordered.filter(\.drawsLine)
        Canvas { context, size in
            guard let first = points.map(\.date).min(), let last = points.map(\.date).max(), last > first else { return }
            let low = (points.map(\.bpm).min() ?? 0) - 4
            let high = (points.map(\.bpm).max() ?? 1) + 4
            let span = last.timeIntervalSince(first)
            func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(first) / span) * size.width }
            func y(_ bpm: Double) -> CGFloat { (1 - CGFloat((bpm - low) / (high - low))) * size.height }
            // Faint bridges describe missing intervals visually, without adding samples.
            for (previous, next) in zip(ordered, ordered.dropFirst()) {
                guard let end = previous.points.last, let start = next.points.first, start.date > end.date else { continue }
                var bridge = Path()
                bridge.move(to: CGPoint(x: x(end.date), y: y(end.bpm)))
                bridge.addLine(to: CGPoint(x: x(start.date), y: y(start.bpm)))
                context.stroke(bridge, with: .color(MasoColor.accent.opacity(0.22)), lineWidth: 1.2)
            }
            for segment in lines {
                var path = Path()
                for (index, point) in segment.points.enumerated() {
                    let place = CGPoint(x: x(point.date), y: y(point.bpm))
                    if index == 0 { path.move(to: place) } else { path.addLine(to: place) }
                }
                context.stroke(path, with: .color(MasoColor.accent), lineWidth: 1.7)
            }
        }
        .frame(width: 80, height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Int((points.map(\.bpm).max() ?? 0).rounded()))"))
    }
}

/// The same three labeled numbers on the report, the share preview, and the exported card.
private struct SessionReportStats: View {
    let report: SessionMuscleReport
    var identifier = "workout.sessionReport.stats"

    var body: some View {
        HStack(alignment: .top) {
            ReportStat(value: report.workSeconds.map(reportClock) ?? "—", label: NSLocalizedString("Work time", comment: ""))
                .frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.6)
            ReportStat(value: "\(report.setCount)", label: NSLocalizedString("Sets", comment: ""))
                .frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.6)
            ReportStat(value: report.loadedVolumeKg.map { weightLabel($0) } ?? "—", label: NSLocalizedString("Volume", comment: ""))
                .frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct ReportStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(MasoColor.textDim)
        }
    }
}

private struct ReportPhotoPickerButton: View {
    var compactReplacement = false
    let photo: UIImage?
    let onChange: (UIImage?) -> Void
    @State private var options = false
    @State private var picker: PhotoPickerSource?
    @State private var selected: UIImage?

    @ViewBuilder private var control: some View {
        if compactReplacement {
            Button { options = true } label: {
                Text("Replace").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassCapsuleButtonBackground(fallback: MasoColor.surfaceHi)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replace photo")
            .accessibilityIdentifier("share.photo.upload")
        } else {
            SharePhotoBanner(photo: photo, compact: true) { options = true }
        }
    }

    var body: some View {
        control
            .confirmationDialog("Photo", isPresented: $options, titleVisibility: .visible) {
                Button("Choose from Library") { picker = .photoLibrary }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { picker = .camera }
                }
                if photo != nil { Button("Remove Photo", role: .destructive) { onChange(nil) } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $picker) { source in PhotoPicker(image: $selected, source: source) }
            .onChange(of: selected) { _, image in
                if let image { onChange(image); selected = nil }
            }
    }
}

/// One shared row for the live report and optional exported exercise summaries.
private struct ReportExerciseSummary: View {
    let exercise: SessionMuscleReport.ExerciseFacts
    let intensity: [MuscleGroup: Double]
    var showsHeart: Bool
    var forSharing = false

    private var loadDetails: [String] {
        SessionMuscleReport.groupedLoads(exercise.records).map {
            "\(weightLabel($0.weight)) × \($0.reps) × \($0.sets)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ShareMuscleMap2D(muscleStyle: { muscle in
                guard let value = intensity[muscle] else { return nil }
                return (MasoColor.recoverySurfaceColor(fatigue: value), 1)
            }, height: forSharing ? 72 : 104)
            .frame(width: forSharing ? 60 : 90)
            .accessibilityLabel(Text("Estimated muscle stimulus"))
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name).font(.headline)
                if let variant = exercise.variant {
                    Text(variant).font(.caption).foregroundStyle(MasoColor.textDim)
                }
                if forSharing {
                    Text(verbatim: loadDetails.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(MasoColor.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(exercise.loadedVolumeKg.map { weightLabel($0) } ?? "—")
                        .font(.body.weight(.semibold)).monospacedDigit()
                    ForEach(Array(loadDetails.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.caption2).foregroundStyle(MasoColor.textDim)
                    }
                }
                if showsHeart { ReportHeartSummary(exercise: exercise) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ReportHeartSummary: View {
    let exercise: SessionMuscleReport.ExerciseFacts
    @ScaledMetric(relativeTo: .caption2) private var heartIconSize = 9
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
                    let points = exercise.heart.flatMap(\.points)
                    if let low = points.map(\.bpm).min(), let high = points.map(\.bpm).max() {
                        HStack(spacing: 4) {
                            Image(systemName: "heart").font(.system(size: heartIconSize)).foregroundStyle(.white.opacity(0.55))
                                .accessibilityHidden(true)
                            Text(verbatim: "\(Int(low.rounded()).formatted(.number.locale(LanguageManager.currentLocale)))–\(Int(high.rounded()).formatted(.number.locale(LanguageManager.currentLocale))) \(NSLocalizedString("bpm", comment: ""))")
                        }
                            .font(.caption).monospacedDigit()
                            .accessibilityElement(children: .combine)
                        if points.count > 1 {
                            Spacer(minLength: 0)
                            HeartSparkline(segments: exercise.heart)
                                .accessibilityIdentifier("workout.sessionReport.spark.\(exercise.id)")
                        }
                    }
        }
    }
}

private struct ShareBitmap: View {
    let report: SessionMuscleReport
    let content: SessionMuscleReport.ShareContent
    var photo: UIImage? = nil
    var availablePhoto: UIImage? = nil
    var photoSelection: Binding<Bool>? = nil
    var onPhotoChange: ((UIImage?) -> Void)? = nil
    let qrPayload: String?
    let intensity: (SessionMuscleReport.ExerciseFacts) -> [MuscleGroup: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                if availablePhoto != nil, let photoSelection {
                    HStack {
                        Text("Photo").font(.subheadline.weight(.semibold))
                        Spacer()
                        InlineSectionToggle(isOn: photoSelection)
                            .accessibilityLabel("Include photo")
                            .accessibilityIdentifier("workout.sessionReport.sharePhotoToggle")
                    }
                }
                if let photo {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GeometryReader { geometry in
                                Image(uiImage: photo).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("workout.sessionReport.sharePhoto")
                        .overlay(alignment: .bottomTrailing) {
                            if let onPhotoChange {
                                ReportPhotoPickerButton(compactReplacement: true, photo: photo, onChange: onPhotoChange)
                                    .padding(12)
                            }
                        }
                } else if let onPhotoChange {
                    ReportPhotoPickerButton(photo: availablePhoto, onChange: onPhotoChange)
                }
                if let name = content.name, !name.isEmpty { Text(name).font(.title2.weight(.semibold)) }
                if let day = content.day {
                    Text(verbatim: SessionMuscleReport.dayLabel(day)).font(.subheadline).foregroundStyle(MasoColor.textDim)
                }
                ShareMuscleMap2D(muscleStyle: { muscle in
                    guard let amount = report.intensity[muscle] else { return nil }
                    return (MasoColor.recoverySurfaceColor(fatigue: amount), 1)
                })
                .frame(maxWidth: .infinity)
                SessionReportStats(report: report, identifier: "workout.sessionReport.exportStats")
                    .padding(MasoMetrics.cardPadding)
                    .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                ForEach(report.exercises) { exercise in
                    ReportExerciseSummary(exercise: exercise, intensity: intensity(exercise), showsHeart: false, forSharing: true)
                        .accessibilityIdentifier("workout.sessionReport.sharedExercise.\(exercise.id)")
                }
            }.padding(.horizontal, ShareLayout.contentInset)
            ReportShareFooter(qrPayload: qrPayload)
        }
        .padding(.vertical, ShareLayout.contentInset)
        .foregroundStyle(MasoColor.text)
        .background(MasoColor.background)
        .preferredColorScheme(.dark)
    }
}

private struct ReportShareFooter: View {
    @Environment(\.layoutDirection) private var contentDirection
    let qrPayload: String?
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if ShareQR.image(for: qrPayload ?? MasoLinks.appStore) != nil {
                    HStack(spacing: 4) {
                        Text(qrPayload == nil ? LocalizedStringKey("Scan to download Masso") : LocalizedStringKey("Scan to get this routine"))
                            .font(.caption2).foregroundStyle(MasoColor.textDim)
                            .environment(\.layoutDirection, contentDirection)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(MasoColor.textDim)
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        MasoMarkIcon(color: MasoColor.accent).frame(width: 24, height: 24)
                        Text(verbatim: "MASSO").font(.system(size: 13, weight: .heavy)).tracking(2)
                    }
                    Text(MasoBrand.slogan).font(.system(size: 10)).foregroundStyle(MasoColor.textDim)
                        .environment(\.layoutDirection, contentDirection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if let qr = ShareQR.image(for: qrPayload ?? MasoLinks.appStore) {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 104, height: 104)
                    .padding(3).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("QR code")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.layoutDirection, .leftToRight)
        .padding(MasoMetrics.cardPadding)
        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        .padding(.horizontal, ShareLayout.contentInset)
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
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .modifier(ReportSheetDynamicType())
    }
}

private func reportClock(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds.rounded()))
    return "\(whole / 60):" + String(format: "%02d", whole % 60)
}
