import Foundation
import Observation
import SwiftUI

@MainActor final class AIExecutionTrace { var requests = 0 }
enum DeviceAIExecution { @TaskLocal static var trace: AIExecutionTrace? }

struct DeviceAIResultEnvelope: Codable {
    let payload: Data
    let summary: String
}

enum DeviceAIQuotaError: String, LocalizedError {
    case upgrade = "This AI task needs Pro. Your saved results remain available."
    case capacity = "Make room in My Plans before generating. Existing plans and training history are not deleted."
    case pending = "This AI task is already running. Please wait."
    case disclosure = "Review AI access on this device before continuing."
    case storage = "AI access could not be saved on this device. Nothing was charged."
    case automatic = "Today's automatic AI recommendation is already available."
    var errorDescription: String? { NSLocalizedString(rawValue, comment: "device AI policy") }
}

/// shortcut: local installation policy can reset on reinstall/device changes; no account or hidden fingerprint.
@MainActor @Observable final class DeviceAIQuota {
    private struct Metadata: Codable {
        var legacy: Bool
        var acknowledgedAt: Date?
        var noticePresentedAt: Date? = nil
        var recoverySnapshots: [DeviceRecoverySnapshot]? = nil
    }
    let ledger: CoachAccessLedger
    private let metadataURL: URL?
    private var metadata: Metadata
    private(set) var storageError = false
    var notice: String?
    var results: [CoachStoredResult] = []
    var lastSuccessful: CoachStoredResult?
    var monthlyTextUsed = 0
    var needsDisclosure: Bool { metadata.acknowledgedAt == nil }
    var legacy: Bool { metadata.legacy }
    var graceEnds: Date? {
        guard metadata.legacy, let date = metadata.noticePresentedAt ?? metadata.acknowledgedAt else { return nil }
        return date.addingTimeInterval(Double(ProAccessPolicy.current.legacyGraceDays * 86400))
    }

    init(directory: URL? = nil, legacy: Bool = false, acknowledged: Bool = true) {
        metadataURL = directory?.appendingPathComponent("notice.json")
        var m = Metadata(legacy: legacy, acknowledgedAt: acknowledged ? Date() : nil)
        var failed = false
        if let url = metadataURL, FileManager.default.fileExists(atPath: url.path) {
            do { m = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: url)) }
            catch { failed = true }
        }
        metadata = m
        do { ledger = try CoachAccessLedger(fileURL: directory?.appendingPathComponent("usage-results.json")) }
        catch { ledger = try! CoachAccessLedger(); failed = true }
        storageError = failed // Never silently replace corrupt production state with a fresh allowance.
    }

    static func installed(legacy: Bool) -> DeviceAIQuota {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MassoDeviceAI", isDirectory: true)
        let manager = DeviceAIQuota(directory: directory, legacy: legacy, acknowledged: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var value = directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true
            try value.setResourceValues(flags) // Not exported, iCloud-synced or restored as a shared quota.
        } catch { manager.storageError = true }
        return manager
    }

    func acknowledge(at now: Date = Date()) {
        if storageError { metadata.acknowledgedAt = now; notice = DeviceAIQuotaError.storage.localizedDescription; return }
        var value = metadata; value.acknowledgedAt = value.acknowledgedAt ?? now
        do {
            if let url = metadataURL {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            metadata = value
        } catch { storageError = true; notice = DeviceAIQuotaError.storage.localizedDescription }
    }

    func recordNoticePresentation(at now: Date = Date()) {
        guard metadata.legacy, metadata.noticePresentedAt == nil, metadata.acknowledgedAt == nil, !storageError else { return }
        var value = metadata; value.noticePresentedAt = now
        do {
            if let url = metadataURL {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            metadata = value
        } catch { storageError = true; notice = DeviceAIQuotaError.storage.localizedDescription }
    }

    static func period(_ now: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM"; return f.string(from: now)
    }

    func context(isPro: Bool, now: Date = Date()) -> CoachAccessContext {
        .init(now: now, period: Self.period(now), isPro: isPro, legacyNoticeAt: metadata.legacy ? (metadata.noticePresentedAt ?? metadata.acknowledgedAt ?? now) : nil)
    }

    func auxiliary<T>(_ operation: () async throws -> T) async rethrows -> T {
        if DeviceAIExecution.trace != nil { return try await operation() }
        return try await DeviceAIExecution.$trace.withValue(AIExecutionTrace(), operation: operation)
    }

    func perform<T: Codable>(kind: CoachTaskKind, isPro: Bool, operationID: String = UUID().uuidString,
                             goalID: String? = nil, parentID: String? = nil, image: Bool = false,
                             capacity: Bool = true, automatic: Bool = false,
                             now: Date = Date(), valid: (T) -> Bool,
                             summary: (T) -> String = { _ in NSLocalizedString("Saved AI result", comment: "") },
                             operation: () async throws -> T) async throws -> T {
        guard !storageError else { throw DeviceAIQuotaError.storage }
        var request = CoachTaskRequest(id: operationID, kind: kind, goalID: goalID ?? operationID)
        request.parentID = parentID; request.usesImage = image; request.canStoreResult = capacity
        if automatic { request.purpose = .automatic }
        let admission = try await ledger.reserve(request, context: context(isPro: isPro, now: now))
        if admission == .savedResult, let saved = await ledger.result(operationID) {
            let envelope = try JSONDecoder().decode(DeviceAIResultEnvelope.self, from: Data(saved.content.utf8))
            lastSuccessful = saved
            return try JSONDecoder().decode(T.self, from: envelope.payload)
        }
        guard admission.permitsGeneration else {
            let error: DeviceAIQuotaError = admission == .saveConflict ? .capacity : admission == .pending ? .pending : admission == .automaticBudgetExhausted ? .automatic : .upgrade
            if !automatic { notice = error.localizedDescription }; throw error
        }
        let trace = AIExecutionTrace()
        let started = Date()
        do {
            try Task.checkCancellation()
            let output = try await DeviceAIExecution.$trace.withValue(trace, operation: operation)
            try Task.checkCancellation()
            if valid(output) {
                let envelope = DeviceAIResultEnvelope(payload: try JSONEncoder().encode(output), summary: summary(output))
                let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
                lastSuccessful = try await ledger.succeed(operationID, validatedContent: text, at: now.addingTimeInterval(Date().timeIntervalSince(started)))
                await refresh()
            } else { try await ledger.release(operationID) }
            return output
        } catch {
            try? await ledger.release(operationID)
            throw error
        }
    }

    var recoverySnapshots: [DeviceRecoverySnapshot] { metadata.recoverySnapshots ?? [] }

    func recoverySnapshot(fatigue: [String: Double], hasEnoughData: Bool, isPro: Bool, now: Date = Date()) throws -> DeviceRecoverySnapshot {
        if !isPro, let acquired = recoverySnapshots.last { return acquired }
        guard !storageError else { throw DeviceAIQuotaError.storage }
        guard hasEnoughData, !fatigue.isEmpty, fatigue.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw DeviceAITextError(message:NSLocalizedString("A recovery snapshot needs at least 14 days of history, 6 recent sets and recent muscle data.", comment:"")) }
        let snapshot = DeviceRecoverySnapshot(id:UUID().uuidString, createdAt:now, fatigue:fatigue)
        var value = metadata; value.recoverySnapshots = recoverySnapshots + [snapshot]
        if let url = metadataURL {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(), withIntermediateDirectories:true)
            try JSONEncoder().encode(value).write(to:url, options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
        metadata = value
        return snapshot // Deterministic local preview; never spends an AI task or monthly text allowance.
    }

    func refresh() async {
        results = await ledger.results(); monthlyTextUsed = await ledger.monthlyUsed(Self.period(Date()))
    }

    func canClassifyImage(isPro: Bool) async -> Bool {
        if isPro { return true }
        if let end = graceEnds, Date() < end { return true }
        for kind in [CoachTaskKind.physiqueGoal, .routineImage, .nutritionImage, .equipmentImage, .recordsImage] {
            if !(await ledger.hasExperience(kind)) { return true }
        }
        notice = DeviceAIQuotaError.upgrade.localizedDescription
        return false
    }
}

struct DeviceAITextError: LocalizedError { let message: String; var errorDescription: String? { message } }


/// Benefit-change notice only; device-local policy lives in the existing details page.
struct DeviceAIChangeNotice: View {
    @Environment(DataStore.self) private var data
    @State private var details = false
    private var noticeMessage: String {
        let deadline = data.aiAccess.graceEnds ?? Date().addingTimeInterval(30 * 86400)
        let date = deadline.formatted(.dateTime.year().month(.abbreviated).day().locale(LanguageManager.currentLocale))
        return String(format:NSLocalizedString("AI access changed: 30-day transition. New limits start %@. Existing training stays available.",comment:""),date)
    }
    var body: some View {
        if data.aiAccess.legacy && data.aiAccess.needsDisclosure && !data.settings.isPro {
            VStack(alignment:.leading,spacing:8) {
                Text(noticeMessage)
                    .font(.footnote).fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("ai.policy.change-notice")
                HStack {
                    Button { details = true } label: {
                        Text("Details").frame(minWidth:44,minHeight:44).contentShape(Rectangle())
                    }.accessibilityIdentifier("ai.policy.notice.details")
                    Spacer()
                    Button { data.aiAccess.acknowledge() } label: {
                        Image(systemName:"xmark").frame(width:44,height:44).contentShape(Rectangle())
                    }.accessibilityLabel("Dismiss").accessibilityIdentifier("ai.policy.notice.dismiss")
                }.buttonStyle(.plain).foregroundStyle(.primary)
            }
            .padding(12).background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:12))
            .foregroundStyle(.primary).tint(.primary).padding(.horizontal,16)
            .onAppear { data.aiAccess.recordNoticePresentation() }
            .sheet(isPresented:$details) {
                AppNavigationStack {
                    DeviceAIUsageView()
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { details = false }.accessibilityIdentifier("ai.policy.details.close") } }
                }.tint(.primary)
            }
        }
    }
}

struct DeviceAIRulesText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI allowances are stored only on this device installation. Changing devices or reinstalling may reset them; they are not shared across devices.").accessibilityIdentifier("ai.policy.device-scope")
            Text("Each supported AI task has one successful free experience on this installation. Free also includes 2 shared text tasks per calendar month (UTC). Repeat images and ongoing reviews need Pro.")
            Text("A task includes 2 same-goal adjustments within 24 hours. Failed requests, clarification, local tools and reopening saved results do not use the allowance.")
            Text("Existing purchases keep their rights. AI needs internet access and your data-sharing permission.")
            Text("Automatic recommendations have a separate budget of one successful result per day; they do not spend your active AI allowance.")
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct DeviceAIUsageView: View {
    @Environment(DataStore.self) private var data
    @State private var paywall = false
    var body: some View {
        List {
            Section("AI access on this device") {
                DeviceAIRulesText()
                Text(String(format: NSLocalizedString("Monthly text tasks used: %d of 2", comment: ""), data.aiAccess.monthlyTextUsed))
                if data.aiAccess.legacy {
                    Text("Existing users have 30 days from this notice before the new AI limits apply. Previous use is not counted retroactively.")
                        .fixedSize(horizontal:false,vertical:true)
                }
                if let end = data.aiAccess.graceEnds {
                    Text(end, format: .dateTime.year().month().day()).accessibilityIdentifier("ai.policy.grace-end")
                }
                if let notice = data.aiAccess.notice { Text(notice).foregroundStyle(.secondary) }
            }
            Section("Recovery snapshot") { DeviceRecoveryPreviewButton() }
            if data.summaryMinDataMet {
                Button("AI Coach Summary") {
                    Task { _ = await data.generateSummary(); await data.aiAccess.refresh() }
                }.frame(minHeight: 44)
            }
            Section("Saved AI results") {
                if data.aiAccess.results.isEmpty { Text("No saved AI results yet.") }
                ForEach(data.aiAccess.results, id: \.jobID) { result in
                    NavigationLink {
                        DeviceAIResultView(result: result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text((try? JSONDecoder().decode(DeviceAIResultEnvelope.self, from: Data(result.content.utf8)))?.summary ?? NSLocalizedString("Saved AI result", comment: ""))
                            Text(result.completedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !data.settings.isPro { Button("Masso Pro") { paywall = true }.frame(minHeight: 44) }
            Section("Supported workout sources") {
                Text("Paste text or attach a workout photo. Direct links can read public article text or subtitle files from the listed sites when readable text is available.")
                    .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("ai.sources.intro")
                Text(verbatim:WorkoutSourceReader.hosts.filter { !$0.hasPrefix("www.") }.sorted().joined(separator:"\n"))
                    .font(.footnote).fixedSize(horizontal:false,vertical:true).textSelection(.enabled).accessibilityIdentifier("ai.sources.hosts")
                Text("Video pages, including YouTube and Bilibili, are not watched or transcribed. Login-only or restricted pages are unsupported. Paste text, a transcript or screenshots instead; an unsuccessful extraction uses no successful experience.")
                    .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("ai.sources.video-limit")
                Text("Direct-link limits: HTTPS, 2 MB, 120–60,000 readable characters. Some pages on these sites may still be unreadable.")
                    .font(.footnote).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("ai.sources.limits")
            }
        }
        .tint(.primary)
        .navigationTitle("AI access and saved results")
        .task { await data.aiAccess.refresh() }
        .sheet(isPresented: $paywall) { PaywallScreen(source: "device_ai_access") }
    }
}

private struct DeviceAIResultView: View {
    let result: CoachStoredResult
    @Environment(DataStore.self) private var data
    private var envelope: DeviceAIResultEnvelope? { try? JSONDecoder().decode(DeviceAIResultEnvelope.self, from: Data(result.content.utf8)) }
    private var plans: [Plan] {
        guard let bytes = envelope?.payload else { return [] }
        if let p = try? JSONDecoder().decode(Plan.self, from: bytes) { return [p] }
        if let p = try? JSONDecoder().decode([Plan].self, from: bytes) { return p }
        if let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
           let array = object["plans"], let encoded = try? JSONSerialization.data(withJSONObject: array),
           let p = try? JSONDecoder().decode([Plan].self, from: encoded) { return p }
        return []
    }
    private var meal: MealPhotoEstimate? {
        guard let bytes = envelope?.payload else { return nil }
        if let direct = try? JSONDecoder().decode(MealPhotoEstimate.self, from: bytes) { return direct }
        if let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
           let value = object["meal"], !(value is NSNull),
           let nested = try? JSONSerialization.data(withJSONObject: value) {
            return try? JSONDecoder().decode(MealPhotoEstimate.self, from: nested)
        }
        return nil
    }
    private var review: AISummary? {
        envelope.flatMap { try? JSONDecoder().decode(AISummary.self, from: $0.payload) }
    }
    private var pickedExercises: [String] {
        guard let bytes = envelope?.payload else { return [] }
        return (try? JSONDecoder().decode([String].self, from: bytes)) ?? []
    }
    var body: some View {
        List {
            Text(envelope?.summary ?? "").textSelection(.enabled)
            DisclosureGroup("Details") {
                if let bytes = envelope?.payload, let object = try? JSONSerialization.jsonObject(with:bytes, options:.fragmentsAllowed),
                   let pretty = try? JSONSerialization.data(withJSONObject:object, options:[.prettyPrinted,.sortedKeys,.fragmentsAllowed]),
                   let text = String(data:pretty, encoding:.utf8) {
                    Text(text).accessibilityIdentifier("ai.result.full-payload").font(.body.monospaced()).textSelection(.enabled).fixedSize(horizontal:false, vertical:true)
                }
            }.accessibilityIdentifier("ai.result.details") // Full acquired typed result, including source defaults; no request or entitlement check.

            if let meal {
                Text(meal.foods).textSelection(.enabled)
                LabeledContent("Protein", value: meal.nutrition.protein.formatted() + " g")
                LabeledContent("Carbs", value: meal.nutrition.carbs.formatted() + " g")
                LabeledContent("Fat", value: meal.nutrition.fat.formatted() + " g")
            }
            if let review {
                ForEach(review.recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.title).font(.headline)
                        Text(recommendation.detail).textSelection(.enabled)
                    }
                }
            }
            ForEach(Array(pickedExercises.enumerated()), id: \.offset) { _, id in
                Text(data.exById[id]?.displayName ?? id)
            }
            ForEach(plans) { plan in
                Section(plan.name) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(data.exById[step.exerciseId]?.displayName ?? step.exerciseId)
                            Text(planStepDetailLine(step)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button("Save to My Plans") {
                        if !data.saveCoachPlan(plan) { data.aiAccess.notice = DeviceAIQuotaError.capacity.localizedDescription }
                    }.frame(minHeight: 44)
                }
            }
            Text("Existing plans, exercises and acquired results remain usable after Pro expires.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Saved AI result")
    }
}

#if DEBUG
struct DeviceAIQuotaUITestView: View {
    @Environment(DataStore.self) private var data
    @State private var count = 0
    @State private var status = ""
    var body: some View {
        AppNavigationStack {
            VStack(spacing: 16) {
                Text(String(count)).accessibilityIdentifier("quota.fixture.calls")
                Text(status).accessibilityIdentifier("quota.fixture.status")
                Button("Generate fixture task") {
                    Task {
                        do {
                            let _: String = try await data.aiAccess.perform(kind: .nutritionImage, isPro: false,
                                image: true, valid: { !$0.isEmpty }) { count += 1; return "Native fixture result — no AI network request" }
                            status = "saved"
                        } catch { status = error.localizedDescription }
                    }
                }.accessibilityIdentifier("quota.fixture.run")
                NavigationLink("AI access and saved results") { DeviceAIUsageView() }
            }
        }
    }
}
#endif


struct DeviceRecoverySnapshot: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let fatigue: [String: Double]
}

struct DeviceRecoveryPreviewButton: View {
    @Environment(DataStore.self) private var data
    @State private var snapshot: DeviceRecoverySnapshot?
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading, spacing:8) {
            Button(LocalizedStringKey(data.aiAccess.recoverySnapshots.isEmpty ? "Preview recovery snapshot" : "View saved recovery snapshot")) {
                do {
                    let map = MuscleStatusCompute.muscleFatigueMap(sets:data.sets, exById:data.exById)
                    snapshot = try data.aiAccess.recoverySnapshot(fatigue:Dictionary(uniqueKeysWithValues:map.map { ($0.key.rawValue,$0.value) }), hasEnoughData:data.summaryMinDataMet, isPro:data.settings.isPro)
                    error = nil
                } catch { self.error = error.localizedDescription }
            }.frame(minHeight:44).accessibilityIdentifier("recovery.snapshot.preview")
            if let error { Text(error).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
        }
        .sheet(item:$snapshot) { saved in
            AppNavigationStack {
                List {
                    Text("A saved training-based estimate, not a live or medical measurement.").fixedSize(horizontal:false,vertical:true)
                    Text(saved.createdAt, format:.dateTime.year().month().day().hour().minute()).accessibilityIdentifier("recovery.snapshot.timestamp")
                    ForEach(saved.fatigue.keys.sorted(),id:\.self) { raw in
                        let tier = MuscleStatusCompute.tierFor(fatigue:saved.fatigue[raw] ?? 0)
                        let label = switch tier { case .fresh: "Fresh"; case .mostlyRecovered: "Mostly recovered"; case .recovering: "Recovering"; case .fatigued: "Fatigued" }
                        LabeledContent(MuscleGroup(rawValue:raw)?.displayName ?? raw, value:NSLocalizedString(label,comment:""))
                    }
                }.navigationTitle("Recovery snapshot")
            }
        }
    }
}
