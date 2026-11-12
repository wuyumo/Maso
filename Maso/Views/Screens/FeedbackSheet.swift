import SwiftUI

// Bug report sheet — reports are queued locally then sent to the weekly central digest.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSuccess: () -> Void = {}
    var exercise: Exercise? = nil
    @State private var mediaIssue = ""

    @State private var text: String = ""
    @State private var feedbackStore = FeedbackStore.shared
    @FocusState private var focused: Bool
    /// 提交后给个轻量 inline 状态 — 网络结果回来再更新
    @State private var status: SubmitStatus = .idle

    private enum SubmitStatus {
        case idle, submitting, submitted, queued
    }

    var body: some View {

        AppNavigationStack {
            Form {
                if let exercise {
                    Section("Exercise") { Text(exercise.displayName) }
                    Section("What is wrong?") {
                        Picker("What is wrong?", selection: $mediaIssue) {
                            Text("Wrong exercise").tag("wrong_action")
                            Text("Wrong equipment").tag("wrong_equipment")
                            Text("Image or video problem").tag("media_problem")
                            Text("Other").tag("other")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .disabled(status != .idle)
                        .accessibilityIdentifier("exercise.media.report.issue")
                    }
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text).font(.body).frame(minHeight: 200)
                            .disabled(status != .idle)
                            .focused($focused)
                        if text.isEmpty {
                            Text("Type your feedback here…").foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text(exercise == nil ? "Tell us what's broken, missing, or worth changing." : "Add details (optional)")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressFractionText(numerator: String(text.count), denominator: String(max(0, 4000 - (reportBody.count - text.count))))
                        if exercise != nil { Text("The exercise and displayed media version are included with your report.") }
                        Text("Reports are reviewed together and emailed once a week. Your message, app version, iOS version, and language are included; no account or device ID is attached.")
                    }
                }
                if !feedbackStore.pending.isEmpty {
                    Section {
                        Label(String(format: NSLocalizedString(feedbackStore.pending.count == 1
                            ? "%d report waiting to upload" : "%d reports waiting to upload", comment: ""),
                            feedbackStore.pending.count), systemImage: "tray.full")
                            .foregroundStyle(.secondary)
                    }
                }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if status == .queued {
                        Label("Saved on this device. It has not reached the server yet.", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("feedback.queued")
                    }
                    PrimaryActionButton(title: LocalizedStringKey(buttonTitle), icon: "paperplane",
                                        loading: status == .submitting, action: submitOrRetry)
                        .disabled(!canSubmit)
                }.padding(MasoMetrics.pagePaddingHorizontal)
                .background(MasoColor.background)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle(exercise == nil ? "Report a Bug" : "Report exercise media").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: text) { _, value in
                if status == .submitted && !value.isEmpty { status = .idle }
            }
        }.tint(MasoColor.text)


    }

    private var canSubmit: Bool {
        guard status != .submitting && status != .submitted else { return false }
        if status == .queued { return !feedbackStore.pending.isEmpty }
        return (exercise == nil ? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !mediaIssue.isEmpty) && reportBody.count <= 4000
    }

    private var buttonTitle: String {
        switch status {
        case .idle: return "Submit report"
        case .submitting: return "Sending…"
        case .submitted: return "Report received"
        case .queued: return "Retry upload"
        }
    }

    private var reportBody: String {
        guard let exercise else { return text }
        let source: String
        if exercise.customImageData != nil { source = "personal_image" }
        else if let url = ExerciseDemoService.shared.files[exercise.id] {
            source = "downloaded_demo:" + url.deletingPathExtension().lastPathComponent
        } else if CoreExerciseDemos.thumbnail(exercise.id) != nil { source = "bundled_poster" }
        else if let folder = exercise.imageFolder, ExerciseMediaPolicy.ownsLegacy(exercise.id, folder: folder) { source = "legacy_frames" }
        else if ExerciseMediaPolicy.youtubeThumbnail(for: exercise) != nil { source = "youtube_thumbnail" }
        else if exercise.photoURL != nil { source = "project_photo" }
        else { source = "placeholder" }
        let catalogSHA = CoreExerciseDemos.assets[exercise.id]?.sha256 ?? "none"
        return "[exercise_media_report]\nexercise_id: \(exercise.id)\nmedia_source: \(source)\ncatalog_sha256: \(catalogSHA)\nissue: \(mediaIssue)\n\n\(text)"
    }

    private func submitOrRetry() {
        guard canSubmit else { return }
        if status == .queued {
            status = .submitting
            Task {
                let accepted = await feedbackStore.retryPending()
                status = accepted ? .submitted : .queued
                if accepted {
                    finishSuccessfully()
                }
            }
            return
        }

        let body = reportBody
        status = .submitting
        Task {
            let accepted = await feedbackStore.submit(body)
            status = accepted ? .submitted : .queued
            if accepted {
                finishSuccessfully()
            }
        }
    }

    private func finishSuccessfully() {
        dismiss()
        onSuccess()
    }
}

#Preview {
    FeedbackSheet()
        .preferredColorScheme(.dark)
}
