import Observation
import Foundation

struct BodyHealthMeasurement: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let date: Date
    let value: Double // kg or cm
    let source: String
}
struct HealthActivityDay: Codable, Equatable, Identifiable, Sendable {
    var id: Date { day }
    let day: Date
    var steps: Double?
    var activeEnergy: Double?
    var restingEnergy: Double?
    var totalEnergy: Double? {
        guard let activeEnergy, let restingEnergy, activeEnergy.isFinite, restingEnergy.isFinite,
              activeEnergy >= 0, restingEnergy >= 0, (activeEnergy + restingEnergy).isFinite else { return nil }
        return activeEnergy + restingEnergy
    }
}
struct BodyActivityHealthSnapshot: Codable, Equatable, Sendable {
    let refreshedAt: Date
    let timeZone: String
    var weights: [BodyHealthMeasurement]
    var heights: [BodyHealthMeasurement]
    var activity: [HealthActivityDay]
    var incomplete: Bool = false
    var latestWeight: BodyHealthMeasurement? { weights.filter { $0.date <= refreshedAt && $0.value.isFinite && $0.value > 0 }.max { $0.date < $1.date } }
    var latestHeight: BodyHealthMeasurement? { heights.filter { $0.date <= refreshedAt && $0.value.isFinite && $0.value > 0 }.max { $0.date < $1.date } }
    func today(calendar: Calendar, now: Date = Date()) -> HealthActivityDay? {
        guard timeZone == calendar.timeZone.identifier,
              refreshedAt <= now.addingTimeInterval(300), calendar.isDate(refreshedAt, inSameDayAs: now) else { return nil }
        return activity.last { calendar.isDate($0.day, inSameDayAs: now) }
    }
}
struct BodyActivityHealthState: Codable, Equatable, Sendable {
    var enabled = false
    var useWeight: Bool? = nil
    var useHeight: Bool? = nil
    var appliedWeight: Double? = nil
    var appliedHeight: Double? = nil
    var previousManualWeight: Double? = nil
    var previousManualHeight: Double? = nil
    var snapshot: BodyActivityHealthSnapshot? = nil
}

extension UserSettings {
    /// Explicit manual edits stop following Health, even when the entered number matches it.
    mutating func setManualBodyMeasurement(_ value: Double, weight isWeight: Bool) {
        guard value.isFinite, (isWeight ? 20...500 : 50...260).contains(value) else { return }
        if isWeight {
            weight = value
            bodyActivityHealth?.useWeight = false
            bodyActivityHealth?.appliedWeight = nil
            bodyActivityHealth?.previousManualWeight = nil
        } else {
            heightCentimeters = value
            bodyActivityHealth?.useHeight = false
            bodyActivityHealth?.appliedHeight = nil
            bodyActivityHealth?.previousManualHeight = nil
        }
    }
    /// Health-derived data remains local, including when adopted as profile weight.
    var weightForAI: Double? {
        guard bodyActivityHealth?.appliedWeight != weight || bodyActivityHealth?.appliedWeight == nil else { return nil }
        return weight
    }
    mutating func reconcileHealthProfileOverrides() {
        guard var state = bodyActivityHealth else { return }
        var changed = false
        if let applied = state.appliedWeight, weight != applied { state.useWeight = false; state.appliedWeight = nil; changed = true }
        if let applied = state.appliedHeight, heightCentimeters != applied { state.useHeight = false; state.appliedHeight = nil; changed = true }
        if changed { bodyActivityHealth = state }
    }
    mutating func applyBodyActivityHealth(_ snapshot: BodyActivityHealthSnapshot) {
        reconcileHealthProfileOverrides()
        var state = bodyActivityHealth ?? .init()
        guard state.enabled else { return }
        if state.useWeight == nil, snapshot.latestWeight.map({ (20...500).contains($0.value) }) == true { state.useWeight = weight == nil }
        if state.useHeight == nil, snapshot.latestHeight.map({ (50...260).contains($0.value) }) == true { state.useHeight = heightCentimeters == nil }
        if state.useWeight == true, let sample = snapshot.latestWeight, (20...500).contains(sample.value) {
            if state.appliedWeight == nil { state.previousManualWeight = weight }
            weight = sample.value; state.appliedWeight = sample.value
        }
        if state.useHeight == true, let sample = snapshot.latestHeight, (50...260).contains(sample.value) {
            if state.appliedHeight == nil { state.previousManualHeight = heightCentimeters }
            heightCentimeters = sample.value; state.appliedHeight = sample.value
        }
        state.snapshot = snapshot
        bodyActivityHealth = state
    }
}

extension DataStore {
    @MainActor func refreshBodyActivityHealth() async {
        guard settings.bodyActivityHealth?.enabled == true, !refreshingBodyActivityHealth else { return }
#if DEBUG
        if ProcessInfo.processInfo.environment["MASO_HEALTH_BODY_FIXTURE"] == "1" { return }
#endif
        guard HealthKitService.isAvailable else { return }
        refreshingBodyActivityHealth = true
        defer { refreshingBodyActivityHealth = false }
        let snapshot = await HealthKitService.shared.readBodyActivity(calendar: settings.calendar)
        guard settings.bodyActivityHealth?.enabled == true else { return }
        let previousWeight = settings.weight
        settings.applyBodyActivityHealth(snapshot)
        if previousWeight != settings.weight { captureWellnessGoal(updateDiet: true) }
        save()
    }
}

extension UserSettings {
    /// Keep HealthKit samples and adopted measurements out of ordinary backups/exports.
    var excludingBodyHealthData: UserSettings {
        var copy = self
        if var state = copy.bodyActivityHealth {
            if let applied = state.appliedWeight, copy.weight == applied { copy.weight = state.previousManualWeight }
            if let applied = state.appliedHeight, copy.heightCentimeters == applied { copy.heightCentimeters = state.previousManualHeight }
            state.appliedWeight = nil; state.appliedHeight = nil
            state.previousManualWeight = nil; state.previousManualHeight = nil; state.snapshot = nil
            copy.bodyActivityHealth = state
        }
        return copy
    }
    mutating func restoreLocalBodyHealth(_ state: BodyActivityHealthState) {
        guard let preferences = bodyActivityHealth else { return }
        let useWeight = preferences.useWeight, useHeight = preferences.useHeight
        bodyActivityHealth = state
        bodyActivityHealth?.enabled = preferences.enabled
        if !preferences.enabled { bodyActivityHealth?.snapshot = nil }
        bodyActivityHealth?.useWeight = useWeight; bodyActivityHealth?.useHeight = useHeight
        if weight == state.previousManualWeight, let applied = state.appliedWeight { weight = applied }
        if heightCentimeters == state.previousManualHeight, let applied = state.appliedHeight { heightCentimeters = applied }
        reconcileHealthProfileOverrides()
    }
}

/// App-local HealthKit cache; never included in iCloud/device backups or user export bundles.
@MainActor
enum BodyHealthLocalStore {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalHealth", isDirectory: true).appendingPathComponent("body-activity.json")
    }
    private static var lastWritten: BodyActivityHealthState?
    static func read(from suppliedURL: URL? = nil) -> BodyActivityHealthState? {
        let url = suppliedURL ?? Self.url
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BodyActivityHealthState.self, from: bytes)
    }
    static func write(_ state: BodyActivityHealthState, to suppliedURL: URL? = nil) throws {
        let url = suppliedURL ?? Self.url
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtection])
        var file = url; try file.setResourceValues(values)
    }
    static func saveIfNeeded(_ settings: UserSettings) {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["MASO_HEALTH_BODY_FIXTURE"] != "1",
              ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1",
              let state = settings.bodyActivityHealth, state != lastWritten else { return }
        do { try write(state); lastWritten = state } catch { }
    }
}

struct WorkoutHeartSample: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let date: Date
    let bpm: Double
    let source: String
    var reminderLimit: Int? = nil
}

/// Count distinct sustained events from observed samples and their recorded limits.
struct WorkoutHeartExceedance: Identifiable {
    let id: String
    let start: Date
    var peak: Double
}

enum WorkoutHeartExceedanceDetector {
    static func events(in samples: [WorkoutHeartSample]) -> [WorkoutHeartExceedance] {
        var events: [WorkoutHeartExceedance] = []
        var start: Date? = nil, previous: Date? = nil, threshold: Int? = nil, firstID: String? = nil
        var count = 0
        var eventIndex: Int? = nil
        var peak = 0.0
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            guard sample.bpm.isFinite, let limit = sample.reminderLimit, (40...240).contains(limit) else {
                start = nil; previous = nil; threshold = nil; firstID = nil; count = 0; eventIndex = nil; peak = 0
                continue
            }
            if let previous, sample.date <= previous { continue }
            if threshold != limit || previous.map({ sample.date.timeIntervalSince($0) > 15 }) == true {
                start = nil; firstID = nil; count = 0; eventIndex = nil; peak = 0
            }
            previous = sample.date; threshold = limit
            guard sample.bpm > Double(limit) else {
                start = nil; firstID = nil; count = 0; eventIndex = nil; peak = 0
                continue
            }
            if start == nil { start = sample.date; firstID = sample.id }
            count += 1; peak = max(peak, sample.bpm)
            if let index = eventIndex { events[index].peak = peak }
            else if count >= 3, let start, let firstID, sample.date.timeIntervalSince(start) >= 15 {
                events.append(.init(id: firstID, start: start, peak: peak))
                eventIndex = events.count - 1
            }
        }
        return events
    }
}

/// Return to the compact control only after continuous, fresh recovery readings.
struct WorkoutHeartWarningRecovery {
    private var since: Date?
    private var last: Date?
    private var count = 0
    mutating func observe(bpm: Double, date: Date, limit: Int?, now: Date) -> Bool {
        guard let limit, limit > 0, now.timeIntervalSince(date) <= 20,
              date.timeIntervalSince(now) <= 5, last.map({ date > $0 }) ?? true else { return false }
        if let last, date.timeIntervalSince(last) > 15 { since = nil; count = 0 }
        last = date
        guard bpm < Double(limit) * 0.7 else { since = nil; count = 0; return false }
        if since == nil { since = date }
        count += 1
        return count >= 3 && date.timeIntervalSince(since!) >= 15
    }
}

/// Escalates only sustained readings substantially above the personal reminder.
/// This controls visual emphasis, not a medical risk classification.
struct WorkoutHeartVisualEscalation {
    private(set) var isEscalated = false
    private var last: Date?
    private var since: Date?
    private var count = 0
    private var previousLimit: Int?

    mutating func observe(bpm: Double, date: Date, limit: Int?, now: Date) {
        if previousLimit != limit { self = Self(); previousLimit = limit }
        guard let limit, (40...240).contains(limit), bpm.isFinite, (20...300).contains(bpm),
              now.timeIntervalSince(date) <= 20, date.timeIntervalSince(now) <= 5,
              last.map({ date > $0 }) ?? true else { return }
        if let last, date.timeIntervalSince(last) > 15 {
            isEscalated = false; since = nil; count = 0
        }
        last = date
        let boundary = isEscalated ? Double(limit) * 1.08 : Double(limit) + max(20, Double(limit) * 0.15)
        let qualifies = isEscalated ? bpm < boundary : bpm >= boundary
        guard qualifies else { since = nil; count = 0; return }
        if since == nil { since = date }
        count += 1
        if count >= 3, let since, date.timeIntervalSince(since) >= 15 {
            isEscalated.toggle(); self.since = nil; count = 0
        }
    }
}

/// A training reminder estimate, not an individual's medical maximum or safe limit.
enum WorkoutHeartRecommendation {
    enum Basis { case history, age, fallback }
    struct Result { let bpm: Int; let basis: Basis }

    static func calculate(samples: [WorkoutHeartSample], age: Int?, excluding sessionID: String?, now: Date = Date()) -> Result {
        let validAge = age.flatMap { (18...100).contains($0) ? $0 : nil }
        let baseline = validAge.map { Int((Double(220 - $0) * 0.85).rounded()) } ?? 150
        let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60)
        let prior = samples.filter { $0.sessionID != sessionID && $0.date >= cutoff && $0.date <= now && $0.bpm.isFinite && (40...240).contains($0.bpm) }
        let sessions = Dictionary(grouping: prior, by: \.sessionID).values.compactMap { readings -> Double? in
            guard readings.count >= 10 else { return nil }
            guard let first = readings.map(\.date).min(), let last = readings.map(\.date).max(), last.timeIntervalSince(first) >= 60 else { return nil }
            let values = readings.map(\.bpm).sorted()
            return values[Int((Double(values.count - 1) * 0.9).rounded(.down))]
        }.sorted()
        if sessions.count >= 3 {
            let median = sessions[sessions.count / 2]
            return Result(bpm: min(baseline, max(100, Int(median.rounded()))), basis: .history)
        }
        return Result(bpm: baseline, basis: validAge == nil ? .fallback : .age)
    }

    static func usesRecommendation(_ settings: UserSettings) -> Bool {
        settings.workoutHeartRateUseRecommendation ?? (settings.workoutHeartRateLimit == nil)
    }

    static func effective(settings: UserSettings, samples: [WorkoutHeartSample], excluding sessionID: String?) -> Int {
        if !usesRecommendation(settings), let limit = settings.workoutHeartRateLimit { return limit }
        return calculate(samples: samples, age: settings.age, excluding: sessionID).bpm
    }
}

/// Personal reminder policy, not a diagnosis or age-based medical threshold.
struct WorkoutHeartAlertPolicy {
    private var highSince: Date?
    private var lastSample: Date?
    private var lastAlert: Date?
    private var previousLimit: Int?
    private var highSamples = 0
    mutating func observe(bpm: Double, date: Date, limit: Int?, now: Date) -> Bool {
        if previousLimit != limit { highSince = nil; lastSample = nil; highSamples = 0; previousLimit = limit }
        guard let limit, (40...240).contains(limit), bpm.isFinite, (20...300).contains(bpm),
              now.timeIntervalSince(date) <= 20, date.timeIntervalSince(now) <= 5,
              lastSample.map({ date > $0 }) ?? true else { return false }
        if let lastSample, date.timeIntervalSince(lastSample) > 15 { highSince = nil; highSamples = 0 }
        lastSample = date
        guard bpm > Double(limit) else { highSince = nil; highSamples = 0; return false }
        highSamples += 1
        if highSince == nil { highSince = date }
        guard let highSince, highSamples >= 3, date.timeIntervalSince(highSince) >= 15,
              lastAlert.map({ now.timeIntervalSince($0) >= 120 }) ?? true else { return false }
        lastAlert = now
        return true
    }
}

/// Preliminary heart-rate trend heuristic; it does not establish whether exercise occurred.
struct WorkoutHeartAutomaticDetector {
    enum Phase { case exercise, rest }
    private var samples: [WorkoutHeartSample] = []
    private var armed = false
    private var peak: WorkoutHeartSample?
    private var declineSamples = 0
    private var fired = false

    mutating func observe(_ sample: WorkoutHeartSample, phase: Phase, now: Date) -> Bool {
        guard !fired, sample.bpm.isFinite, (20...300).contains(sample.bpm),
              now.timeIntervalSince(sample.date) <= 20, sample.date.timeIntervalSince(now) <= 5,
              samples.last.map({ sample.date > $0.date }) ?? true else { return false }
        if let last = samples.last, sample.date.timeIntervalSince(last.date) > 20 {
            samples.removeAll(); armed = false; peak = nil; declineSamples = 0
        }
        if let peak, sample.date.timeIntervalSince(peak.date) > 45 {
            samples.removeAll(); armed = false; self.peak = nil; declineSamples = 0
        }
        samples.append(sample)
        samples.removeAll { sample.date.timeIntervalSince($0.date) > 45 }
        guard samples.count >= 3, let first = samples.first,
              sample.date.timeIntervalSince(first.date) >= 15 else { return false }
        if phase == .rest {
            if sample.bpm - first.bpm >= 12 { fired = true; return true }
            return false
        }
        if !armed {
            guard sample.bpm - first.bpm >= 8 else { return false }
            armed = true; peak = sample; declineSamples = 1
            return false
        }
        guard let currentPeak = peak else { return false }
        if sample.bpm > currentPeak.bpm { peak = sample; declineSamples = 1; return false }
        declineSamples += 1
        if declineSamples >= 3, sample.date.timeIntervalSince(currentPeak.date) >= 15,
           currentPeak.bpm - sample.bpm >= 12 {
            fired = true
            return true
        }
        return false
    }
}

/// Health-only local file; excluded from normal DataStore saves, export and AI context.
@MainActor @Observable
final class WorkoutHeartLocalStore {
    static let shared = WorkoutHeartLocalStore()
    private(set) var samples: [WorkoutHeartSample] = []
    private let fileURL: URL
    private let persists: Bool
    private var lastWrite = Date.distantPast
    private var needsReconcile = false
    private var deletedSessions = Set<String>()
    private var deletedSamples = Set<String>()
    init(url: URL? = nil) {
        fileURL = url ?? BodyHealthLocalStore.url.deletingLastPathComponent().appendingPathComponent("workout-heart.json")
        persists = url != nil || (NSClassFromString("XCTestCase") == nil && ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1")
        if persists, FileManager.default.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([WorkoutHeartSample].self, from: data) { samples = saved }
            else { needsReconcile = true }
        }
    }
    func append(_ sample: WorkoutHeartSample, now: Date = Date()) {
        guard sample.bpm.isFinite, (20...300).contains(sample.bpm), !samples.contains(where: { $0.id == sample.id }) else { return }
        if let index = samples.firstIndex(where: { $0.sessionID == sample.sessionID && abs($0.date.timeIntervalSince(sample.date)) < 1 && abs($0.bpm - sample.bpm) < 0.5 }) {
            // Replace the timely Watch transport copy with its authoritative HealthKit
            // UUID so future Health deletions remove the corresponding local sample.
            if samples[index].id.hasPrefix("watch|"), !sample.id.hasPrefix("watch|") {
                var authoritative = sample
                authoritative.reminderLimit = samples[index].reminderLimit
                samples[index] = authoritative
            }
            return
        }
        samples.append(sample)
        if now.timeIntervalSince(lastWrite) >= 30 { flush(now: now) }
    }
    func removeSessions(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deletedSessions.formUnion(ids)
        samples.removeAll { ids.contains($0.sessionID) }; flush()
    }
    func remove(ids: Set<String>) { deletedSamples.formUnion(ids); samples.removeAll { ids.contains($0.id) }; flush() }
    @discardableResult func clear() -> Bool {
        let previous = samples, reconcile = needsReconcile
        samples = []; needsReconcile = false
        guard flush() else { samples = previous; needsReconcile = reconcile; return false }
        return true
    }
    @discardableResult func flush(now: Date = Date()) -> Bool {
        guard persists else { return true }
        if needsReconcile {
            // Never overwrite an existing protected/unreadable file with an empty
            // launch cache. Reconcile after unlock, retaining deletion tombstones.
            guard let bytes = try? Data(contentsOf: fileURL), let previous = try? JSONDecoder().decode([WorkoutHeartSample].self, from: bytes) else { return false }
            var seen = Set<String>()
            samples = (previous + samples).filter { !deletedSessions.contains($0.sessionID) && !deletedSamples.contains($0.id) && seen.insert($0.id).inserted }
            needsReconcile = false
        }
        do {
            var directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(samples).write(to: fileURL, options: [.atomic, .completeFileProtection])
            var file = fileURL; try file.setResourceValues(values)
            lastWrite = now
            deletedSessions = []; deletedSamples = []
            return true
        } catch { return false /* Locked files remain intact; keep the live samples in memory. */ }
    }
    func samples(for record: SetRecord) -> [WorkoutHeartSample] {
        guard let sessionID = record.workoutSessionID, let intervals = record.activeIntervals else { return [] }
        return samples.filter { sample in
            sample.sessionID == sessionID && intervals.contains { sample.date >= $0.start && sample.date < $0.end }
        }.sorted { $0.date < $1.date }
    }
}
