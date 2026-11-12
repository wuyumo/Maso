import Foundation

/// Device-install policy. Local state intentionally is not a cross-device identity or anti-reinstall service.
struct ProAccessPolicy: Codable, Sendable {
    let schemaVersion: Int
    let productionAIEnforcementEnabled: Bool
    let requiresVerifiedSharedAuthority: Bool
    let freeSavedPlans: Int
    let freeCustomExercises: Int
    let freeMonthlyTextTasks: Int
    let includedRevisions: Int
    let revisionWindowHours: Int
    let legacyGraceDays: Int
    let reservationMinutes: Int
    let proActiveTaskLimit: Int?
    let proImageTaskLimit: Int?

    static let current: Self = {
        guard let url = Bundle.main.url(forResource: "pro-access-policy", withExtension: "json"),
              let data = try? Data(contentsOf: url), let policy = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(schemaVersion: 1, productionAIEnforcementEnabled: false,
                requiresVerifiedSharedAuthority: true, freeSavedPlans: 5, freeCustomExercises: 3,
                freeMonthlyTextTasks: 2, includedRevisions: 2, revisionWindowHours: 24,
                legacyGraceDays: 30, reservationMinutes: 10, proActiveTaskLimit: nil, proImageTaskLimit: nil)
        }
        return policy
    }()
}

enum CoachTaskKind: String, Codable, CaseIterable, Sendable {
    case sourceImport, focus, time, equipment, returnToTraining, physiqueGoal
    case weeklyPlan, singleWorkout, routineImage, nutritionText, nutritionImage, trainingReview, recoverySnapshot, equipmentImage, recordsImage
    var allowsMonthlyText: Bool {
        switch self {
        case .sourceImport, .focus, .time, .equipment, .returnToTraining, .weeklyPlan, .singleWorkout, .nutritionText: true
        default: false
        }
    }
}

struct CoachTaskRequest: Codable, Equatable, Sendable {
    enum Purpose: String, Codable, Sendable { case active, automatic, localTool, clarification }
    let id: String
    let kind: CoachTaskKind
    /// Opaque stable goal identity, not user text. Entry points share the same operation ID.
    let goalID: String
    var parentID: String? = nil
    var purpose: Purpose = .active
    var usesImage = false
    var canStoreResult = true
    var hasEnoughData = true
}

struct CoachAccessContext: Sendable {
    let now: Date
    /// UTC month from the device clock; local reset/clock manipulation is not server-enforced.
    let period: String
    var isPro = false
    var legacyNoticeAt: Date? = nil
}

enum CoachAdmission: String, Codable, Sendable {
    case firstExperience, monthlyText, revision, existingSubscriber, transition
    case automaticRecommendation, automaticBudgetExhausted
    case noCharge, automaticBudgetRequired, savedResult, pending, upgrade, saveConflict, insufficientData
    var permitsGeneration: Bool {
        [.firstExperience, .monthlyText, .revision, .existingSubscriber, .transition, .automaticRecommendation].contains(self)
    }
}

struct CoachStoredResult: Codable, Equatable, Sendable {
    let jobID: String
    let kind: CoachTaskKind
    /// Persist a validated derived result, never images, health samples, credentials or raw prompts.
    let content: String
    let completedAt: Date
    var goalID: String? = nil
    var parentID: String? = nil
}

enum CoachLedgerError: Error { case operationConflict, missingReservation, invalidResult, invalidPeriod }

/// Installed-device ledger, also exercised by native policy/UX tests.
/// shortcut: actor serialization is process-local; replace this adapter before cross-device enforcement.
actor CoachAccessLedger {
    private struct Job: Codable {
        let request: CoachTaskRequest
        let admission: CoachAdmission
        let period: String
        let reservedAt: Date
        var result: CoachStoredResult? = nil
        var successfulRevisions = 0
    }
    private struct State: Codable {
        var schemaVersion = 1
        var experienced: Set<CoachTaskKind> = []
        var automatic: [String: Int]? = nil
        var monthly: [String: Int] = [:]
        var jobs: [String: Job] = [:]
    }
    private var state: State
    private let policy: ProAccessPolicy
    private let fileURL: URL?

    init(policy: ProAccessPolicy = .current, fileURL: URL? = nil) throws {
        self.policy = policy
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            // Corrupt state must fail, not silently reset consumed experience or lose saved results.
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
        } else { state = State() }
    }

    private func persist(_ next: State) throws {
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
        }
        state = next
    }

    func reserve(_ request: CoachTaskRequest, context: CoachAccessContext) throws -> CoachAdmission {
        guard context.period.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil else {
            throw CoachLedgerError.invalidPeriod
        }
        var next = state
        next.jobs = next.jobs.filter { _, job in
            job.result != nil || context.now.timeIntervalSince(job.reservedAt) < Double(policy.reservationMinutes * 60)
        }
        if let existing = next.jobs[request.id] {
            guard existing.request.id == request.id, existing.request.kind == request.kind,
                  existing.request.goalID == request.goalID, existing.request.parentID == request.parentID,
                  existing.request.purpose == request.purpose, existing.request.usesImage == request.usesImage else { throw CoachLedgerError.operationConflict }
            try persist(next)
            return existing.result == nil ? .pending : .savedResult
        }
        if request.purpose == .localTool || request.purpose == .clarification { return .noCharge }
        if request.purpose == .automatic {
            let day = Self.day(context.now)
            let pending = next.jobs.values.filter { $0.result == nil && $0.admission == .automaticRecommendation && Self.day($0.reservedAt) == day }.count
            guard (next.automatic?[day] ?? 0) + pending < 1 else { return .automaticBudgetExhausted }
            next.jobs[request.id] = Job(request: request, admission: .automaticRecommendation, period: context.period, reservedAt: context.now)
            try persist(next)
            return .automaticRecommendation
        }
        guard request.canStoreResult else { return .saveConflict }
        guard request.hasEnoughData else { return .insufficientData }
        let admission: CoachAdmission
        if let parentID = request.parentID {
            guard let parent = next.jobs[parentID], let result = parent.result,
                  parent.request.parentID == nil,
                  parent.request.goalID == request.goalID, parent.request.kind == request.kind else {
                throw CoachLedgerError.operationConflict
            }
            let pending = next.jobs.values.filter { $0.result == nil && $0.request.parentID == parentID }.count
            if context.now >= result.completedAt,
               context.now.timeIntervalSince(result.completedAt) <= Double(policy.revisionWindowHours * 3600),
               parent.successfulRevisions + pending < policy.includedRevisions {
                admission = .revision
            } else if context.isPro { admission = .existingSubscriber }
            else { return .upgrade }
        } else if context.isPro {
            // Existing subscriptions/lifetime rights are not reduced to an experimental 30/10 cap.
            admission = .existingSubscriber
        } else if let notice = context.legacyNoticeAt, context.now >= notice,
                  context.now.timeIntervalSince(notice) < Double(policy.legacyGraceDays * 86400) {
            admission = .transition
        } else if !next.experienced.contains(request.kind) {
            if next.jobs.values.contains(where: { $0.result == nil && $0.admission == .firstExperience && $0.request.kind == request.kind }) {
                return .pending
            }
            admission = .firstExperience
        } else if request.kind.allowsMonthlyText && !request.usesImage {
            let pending = next.jobs.values.filter { $0.result == nil && $0.admission == .monthlyText && $0.period == context.period }.count
            guard next.monthly[context.period, default: 0] + pending < policy.freeMonthlyTextTasks else { return .upgrade }
            admission = .monthlyText
        } else { return .upgrade }
        next.jobs[request.id] = Job(request: request, admission: admission, period: context.period, reservedAt: context.now)
        try persist(next)
        return admission
    }

    /// Only a trusted result validator may call success. HTTP200 or a local fallback is not success.
    func succeed(_ id: String, validatedContent: String, at: Date) throws -> CoachStoredResult {
        guard var job = state.jobs[id] else { throw CoachLedgerError.missingReservation }
        if let result = job.result { return result }
        guard !validatedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              at >= job.reservedAt,
              at.timeIntervalSince(job.reservedAt) < Double(policy.reservationMinutes * 60) else {
            throw CoachLedgerError.invalidResult
        }
        var next = state
        let result = CoachStoredResult(jobID: id, kind: job.request.kind, content: validatedContent, completedAt: at, goalID: job.request.goalID, parentID: job.request.parentID)
        job.result = result
        next.jobs[id] = job
        switch job.admission {
        case .firstExperience: next.experienced.insert(job.request.kind)
        case .monthlyText: next.monthly[job.period, default: 0] += 1
        case .automaticRecommendation:
            var values = next.automatic ?? [:]; values[Self.day(job.reservedAt), default: 0] += 1; next.automatic = values
        case .revision:
            if let parent = job.request.parentID { next.jobs[parent]?.successfulRevisions += 1 }
        default: break
        }
        try persist(next)
        return result
    }

    /// Failure, unchanged revision, cancellation without a result, and clarification all release reservation.
    func release(_ id: String) throws {
        guard let job = state.jobs[id], job.result == nil else { return }
        var next = state
        next.jobs.removeValue(forKey: id)
        try persist(next)
    }

    /// Readback never depends on subscription or a network connection and never consumes quota.
    func result(_ id: String) -> CoachStoredResult? { state.jobs[id]?.result }
    func monthlyUsed(_ period: String) -> Int { state.monthly[period, default: 0] }
    private static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    func hasExperience(_ kind: CoachTaskKind) -> Bool { state.experienced.contains(kind) }
    func results() -> [CoachStoredResult] { state.jobs.values.compactMap(\.result).sorted { $0.completedAt > $1.completedAt } }

}
