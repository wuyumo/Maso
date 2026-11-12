import Foundation
import HealthKit

// HealthKit 接入 — 把 Masso 训练数据写到 Apple Health → Apple Fitness 自动 pick up.
//
// 用户故事:
//   1. 用户在 Settings 打开 "Apple Fitness 同步"
//   2. 首次开启 → 弹 HealthKit 授权对话框 (用户必须明确允许)
//   3. 授权成功后, 历史 session 一次性补写 (retroactive)
//   4. 之后每完成一次训练, session.complete() 触发 writeWorkout
//   5. 用户关闭 toggle → 不再写新数据 (但已写入的不删, 那是用户在 Health/Fitness 自己管)
//
// 为什么 Apple Fitness ≠ 单独写 Fitness?
//   Apple Fitness app 本身没有公开 SDK, 但它从 HealthKit 读 workouts. 写 HKWorkout 到
//   HealthStore → Fitness 自动展示在 Activity / Workouts. 这是官方推荐做法.
//
// API 设计:
//   - 调用方 (SessionStore / Settings) 用 async / await
//   - HealthKitService 是 actor-isolated MainActor (@MainActor + @Observable),
//     方便从 view 直接 read authStatus
//
// 关键决策:
//   - 写入与读取分别授权：原训练同步只写；睡眠及外部训练在各自入口请求读取权限
//   - WorkoutActivityType: 默认 .functionalStrengthTraining (覆盖 90%+ Masso 用户场景)
//     若 session 是 cardio / yoga 主导, 用对应类型 (.running, .yoga, .flexibility)
//   - totalEnergyBurned: 用粗略估算 (MET × duration × weight), 不准但比 nil 有用

@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private(set) var sleepMinutes: [Date: Double] = [:]
    private(set) var sleepStages: [Date: SleepStagesRecord] = [:]
    private(set) var sleepSamples: [SleepHealthSample] = []
    private(set) var sleepTimelines: [Date: [SleepStageInterval]] = [:]

    /// 设备 / 用户当前的 HealthKit 状态. View 层只读.
    enum AuthStatus {
        case unavailable     // 设备不支持 HealthKit (iPad / Simulator 之外的 macOS 等)
        case notDetermined   // 用户还没看过授权对话框
        case authorized      // 已授权写入
        case denied          // 用户拒绝过
    }
    private(set) var authStatus: AuthStatus = .notDetermined

    private init() {
        refreshAuthStatus()
    }

    /// 是否可在此设备使用 HealthKit (iPhone yes / Mac Catalyst 有限 / Simulator yes 但模拟)
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 刷新本地的 authStatus 缓存 — 从系统状态查回来.
    /// 注意: HealthKit 出于隐私不暴露 "用户授权写" 的真实结果, 只暴露 "用户已经做过决定吗".
    /// `sharingAuthorized` 表示用户做过明确允许; `sharingDenied` = 拒绝; `notDetermined` = 没问过.
    func refreshAuthStatus() {
        guard Self.isAvailable else { authStatus = .unavailable; return }
        let s = store.authorizationStatus(for: HKObjectType.workoutType())
        switch s {
        case .notDetermined: authStatus = .notDetermined
        case .sharingDenied: authStatus = .denied
        case .sharingAuthorized: authStatus = .authorized
        @unknown default: authStatus = .notDetermined
        }
    }

    /// 弹系统授权对话框. 用户点过 (不管允许 or 拒绝) 之后回到 app, status 不再是 notDetermined.
    /// - 新增数据类型可再次请求授权；已有读取权限由用户在健康 App 中管理。
    /// - throws 时表示系统级失败 (健康服务不可用), 不是用户拒绝.
    func requestAuthorization() async throws {
        guard Self.isAvailable else { return }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        // Apple 推荐: 读权限不要 (空 set 等于不要)
        try await store.requestAuthorization(toShare: toShare, read: [])
        refreshAuthStatus()
    }

    /// 写一条 workout. 返回 true = 成功; false = 用户拒绝 / API 失败.
    /// 写之前会 refresh authStatus, 确保权限还在 (用户可能去 Settings 里关了).
    @discardableResult
    func writeWorkout(
        activity: HKWorkoutActivityType,
        start: Date,
        end: Date,
        kcal: Double?,
        sourceTag: String?
    ) async -> Bool {
        refreshAuthStatus()
        guard authStatus == .authorized else { return false }
        guard end > start else { return false }

        // HKWorkoutBuilder (iOS 17+ 推荐) — 比 HKWorkout 老 init 更精细, 支持加 sample / event.
        // 我们目前不加 detail samples, 只 begin / end → finishWorkout.
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: config,
            device: .local()
        )

        do {
            try await builder.beginCollection(at: start)

            // 估算消耗 — 用 quantity sample 加进去 (Fitness 展示活动 kcal 时会读这个)
            if let kcal, kcal > 0 {
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let qty = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: qty,
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }

            // metadata — Health 详情里能看到, 跟 source app 名分离
            if let sourceTag {
                let md: [String: Any] = [
                    HKMetadataKeyWorkoutBrandName: "Masso",
                    HKMetadataKeyExternalUUID: sourceTag,
                    HKMetadataKeyIndoorWorkout: true,
                ]
                try await builder.addMetadata(md)
            }

            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Masso → HKWorkoutActivityType 映射

extension HKWorkoutActivityType {
    /// 根据 session 主体 ExerciseCategory 推断最贴近的 HK type.
    static func bestMatch(forCategories cats: [ExerciseCategory]) -> HKWorkoutActivityType {
        // 计数最多的 category 主导
        var counts: [ExerciseCategory: Int] = [:]
        for c in cats { counts[c, default: 0] += 1 }
        let top = counts.max(by: { $0.value < $1.value })?.key ?? .strength
        switch top {
        case .strength, .hypertrophyFocus, .calisthenics:
            return .functionalStrengthTraining
        case .cardio:
            return .other  // 太宽泛, Masso 没区分 running/cycling — 用 .other 让 Health 不强分类
        case .stretching, .flexibility, .mobility:
            return .flexibility
        case .plyometric:
            return .crossTraining
        }
    }
}


extension HealthKitService {
    func connectSleep() async throws {
        guard Self.isAvailable else { throw NSError(domain: "Health", code: 1) }
        try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
    }

    func refreshSleep(calendar: Calendar) async throws {
        guard Self.isAvailable else { return }
        let now = Date()
        let start = Date.distantPast
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: now), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results as? [HKCategorySample] ?? []) }
            }
            store.execute(query)
        }
        sleepSamples = samples.sorted { $0.startDate > $1.startDate }.map {
            SleepHealthSample(id: $0.uuid, start: $0.startDate, end: $0.endDate, value: $0.value, source: $0.sourceRevision.source.name)
        }
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        var intervals: [Date: [(Date, Date)]] = [:]
        var stages: [Date: [String: [(Int, Date, Date)]]] = [:]
        var watchSources: Set<String> = []
        for sample in samples {
            var cursor = max(sample.startDate, start)
            let end = min(sample.endDate, now)
            while cursor < end {
                let day = calendar.startOfDay(for: cursor)
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
                let wakeDay = cursor < noon ? day : calendar.date(byAdding: .day, value: 1, to: day)!
                let boundary = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: wakeDay)!
                let stop = min(end, boundary)
                if asleep.contains(sample.value) { intervals[wakeDay, default: []].append((cursor, stop)) }
                let source = sample.sourceRevision.source.bundleIdentifier + "|" + (sample.device?.localIdentifier ?? "")
                stages[wakeDay, default: [:]][source, default: []].append((sample.value, cursor, stop))
                if (sample.device?.model ?? "").localizedCaseInsensitiveContains("watch") { watchSources.insert(source) }
                cursor = stop
            }
        }
        var totals: [Date: Double] = [:]
        for (day, values) in intervals {
            totals[day] = SleepPreferences.mergedMinutes(values)
        }
        var stageTotals: [Date: SleepStagesRecord] = [:]
        var timelines: [Date: [SleepStageInterval]] = [:]
        for (day, sources) in stages {
            let sleepSources = sources.keys.filter { key in sources[key]!.contains { asleep.contains($0.0) } }
            let preferred = sleepSources.sorted().sorted { a, b in
                func hasStages(_ key: String) -> Bool {
                    sources[key]!.contains { [HKCategoryValueSleepAnalysis.asleepDeep, .asleepREM, .asleepCore].map(\.rawValue).contains($0.0) }
                }
                if hasStages(a) != hasStages(b) { return hasStages(a) }
                if watchSources.contains(a) != watchSources.contains(b) { return watchSources.contains(a) }
                return SleepPreferences.mergedMinutes(sources[a]!.filter { asleep.contains($0.0) }.map { ($0.1, $0.2) }) > SleepPreferences.mergedMinutes(sources[b]!.filter { asleep.contains($0.0) }.map { ($0.1, $0.2) })
            }
            guard let source = preferred.first, let values = sources[source] else { continue }
            func minutes(_ stage: HKCategoryValueSleepAnalysis) -> Double {
                SleepPreferences.mergedMinutes(values.filter { $0.0 == stage.rawValue }.map { ($0.1, $0.2) })
            }
            timelines[day] = values.filter { $0.0 != HKCategoryValueSleepAnalysis.inBed.rawValue }
                .map { SleepStageInterval(value: $0.0, start: $0.1, end: $0.2) }
            timelines[day] = SleepStageInterval.merged(timelines[day] ?? [])
            totals[day] = SleepPreferences.mergedMinutes(values.filter { asleep.contains($0.0) }.map { ($0.1, $0.2) })
            let detailed = values.contains { [HKCategoryValueSleepAnalysis.asleepDeep, .asleepREM, .asleepCore].map(\.rawValue).contains($0.0) }
            if detailed {
                func optionalMinutes(_ stage: HKCategoryValueSleepAnalysis) -> Double? {
                    values.contains { $0.0 == stage.rawValue } ? minutes(stage) : nil
                }
                stageTotals[day] = .init(deep: minutes(.asleepDeep), rem: minutes(.asleepREM), core: minutes(.asleepCore), awake: optionalMinutes(.awake), inBed: optionalMinutes(.inBed), unspecified: optionalMinutes(.asleepUnspecified))
            }

        }
        sleepMinutes = totals
        sleepStages = stageTotals
        sleepTimelines = timelines
    }
}

/// All authorized sleep-analysis samples, including overlapping sources and in-bed records.
struct SleepHealthSample: Identifiable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let value: Int
    let source: String
    var title: String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: "In bed"
        case .awake: "Awake"
        case .asleepCore: "Core sleep"
        case .asleepDeep: "Deep sleep"
        case .asleepREM: "REM sleep"
        default: "Sleep (unspecified)"
        }
    }
}

struct SleepStageInterval: Identifiable, Sendable {
    let value: Int
    let start: Date
    let end: Date
    var id: String { "\(value)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    var stage: String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake: "Awake"
        case .asleepREM: "REM sleep"
        case .asleepCore: "Core sleep"
        case .asleepDeep: "Deep sleep"
        default: "Sleep (unspecified)"
        }
    }
    static func transitions(_ intervals: [Self]) -> [(from: Self, to: Self)] {
        let sorted = intervals.sorted { $0.start < $1.start }
        return zip(sorted, sorted.dropFirst()).compactMap { from, to in
            guard from.value != to.value, abs(to.start.timeIntervalSince(from.end)) < 0.01 else { return nil }
            return (from, to)
        }
    }
    static func merged(_ intervals: [Self]) -> [Self] {
        Dictionary(grouping: intervals, by: \.value).flatMap { value, records -> [Self] in
            let sorted = records.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
            var result: [Self] = []
            for record in sorted {
                if let last = result.last, record.start <= last.end {
                    result[result.count - 1] = .init(value: value, start: last.start, end: max(last.end, record.end))
                } else { result.append(record) }
            }
            return result
        }.sorted { $0.start < $1.start }
    }
}


extension HealthKitService {
    func connectWorkouts() async throws {
        guard Self.isAvailable else { throw NSError(domain: "Health", code: 1) }
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
        try await store.requestAuthorization(toShare: [], read: read)
    }

    /// Full replacement also removes workouts deleted in Health. Never interpret an
    /// empty read result as proof of denied permission: HealthKit intentionally hides it.
    func readWorkouts(now: Date = Date()) async throws -> [ExternalWorkout] {
        guard Self.isAvailable else { throw NSError(domain: "Health", code: 1) }
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: nil, end: now, options: .strictEndDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            store.execute(query)
        }
        let records = workouts.compactMap { workout -> ExternalWorkout? in
            // Brand metadata catches our exports copied by another app as well.
            if (workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String)?.lowercased() == "masso" { return nil }
            let kind: ExternalWorkout.Kind
            switch workout.workoutActivityType {
            case .walking: kind = .walking
            case .cycling: kind = .cycling
            case .running: kind = .running
            case .swimming: kind = .swimming
            case .hiking: kind = .hiking
            case .yoga: kind = .yoga
            case .traditionalStrengthTraining, .functionalStrengthTraining: kind = .strength
            default: kind = .other
            }
            func positive(_ value: Double?) -> Double? {
                value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            }
            let distances = workout.allStatistics.compactMap { type, statistics -> Double? in
                guard type.identifier.hasPrefix("HKQuantityTypeIdentifierDistance") else { return nil }
                return positive(statistics.sumQuantity()?.doubleValue(for: .meter()))
            }
            let distance = distances.isEmpty ? nil : distances.reduce(0, +)
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return .init(id: workout.uuid.uuidString, activity: kind, startedAt: workout.startDate, endedAt: workout.endDate,
                         duration: workout.duration, distanceMeters: positive(distance), kilocalories: positive(energy),
                         sourceBundleID: workout.sourceRevision.source.bundleIdentifier, sourceName: workout.sourceRevision.source.name)
        }
        return ExternalWorkout.normalized(records, now: now)
    }
}

#if DEBUG
extension HealthKitService {
    func installMarketingSleepPreview(day: Date) {
        guard ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] == "1" else { return }
        let steps: [(HKCategoryValueSleepAnalysis, Int)] = [
            (.asleepCore, 35), (.asleepDeep, 34), (.asleepCore, 52), (.asleepREM, 22), (.awake, 6),
            (.asleepCore, 60), (.asleepDeep, 40), (.asleepCore, 42), (.asleepREM, 34), (.awake, 10),
            (.asleepCore, 40), (.asleepREM, 46), (.asleepCore, 49)
        ]
        var cursor = day.addingTimeInterval(-40 * 60)
        sleepTimelines[day] = steps.map { stage, minutes in
            let end = cursor.addingTimeInterval(Double(minutes) * 60)
            defer { cursor = end }
            return SleepStageInterval(value: stage.rawValue, start: cursor, end: end)
        }
        sleepMinutes[day] = 454
        sleepStages[day] = .init(deep: 74, rem: 102, core: 278, awake: 16)
    }
}
#endif

extension HealthKitService {
    static var bodyActivityReadTypes: Set<HKObjectType> {
        Set([HKQuantityTypeIdentifier.bodyMass, .height, .stepCount, .activeEnergyBurned, .basalEnergyBurned].map { HKQuantityType($0) })
    }
    func connectBodyActivity() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.bodyActivityReadTypes)
    }

    /// Read all accessible measurement history and all available daily activity totals.
    /// HealthKit statistics aggregate overlapping sources; do not sum raw device samples or add workout kcal again.
    func readBodyActivity(calendar: Calendar, now: Date = Date()) async -> BodyActivityHealthSnapshot {
        async let weights = try? readBodyMeasurements(.bodyMass, unit: .gramUnit(with: .kilo), range: Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude, now: now)
        async let heights = try? readBodyMeasurements(.height, unit: .meterUnit(with: .centi), range: Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude, now: now)
        async let steps = try? readDailyHealth(.stepCount, unit: .count(), calendar: calendar, now: now)
        async let active = try? readDailyHealth(.activeEnergyBurned, unit: .kilocalorie(), calendar: calendar, now: now)
        async let resting = try? readDailyHealth(.basalEnergyBurned, unit: .kilocalorie(), calendar: calendar, now: now)
        let (w, h, s, a, r) = await (weights, heights, steps, active, resting)
        let days = Set((s ?? [:]).keys).union((a ?? [:]).keys).union((r ?? [:]).keys).sorted()
        return .init(refreshedAt: now, timeZone: calendar.timeZone.identifier,
            weights: w ?? [], heights: h ?? [],
            activity: days.map { .init(day: $0, steps: s?[$0], activeEnergy: a?[$0], restingEnergy: r?[$0]) },
            incomplete: w == nil || h == nil || s == nil || a == nil || r == nil)
    }
    private func readBodyMeasurements(_ id: HKQuantityTypeIdentifier, unit: HKUnit, range: ClosedRange<Double>, now: Date) async throws -> [BodyHealthMeasurement] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: nil, end: now, options: .strictEndDate), limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (results as? [HKQuantitySample] ?? []).compactMap { sample -> BodyHealthMeasurement? in
                    let value = sample.quantity.doubleValue(for: unit)
                    guard value.isFinite, range.contains(value), sample.endDate <= now else { return nil }
                    return .init(id: sample.uuid.uuidString, date: sample.endDate, value: value, source: sample.sourceRevision.source.name)
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
    private func readDailyHealth(_ id: HKQuantityTypeIdentifier, unit: HKUnit, calendar: Calendar, now: Date) async throws -> [Date: Double] {
        let type = HKQuantityType(id)
        let first: Date? = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: nil, end: now, options: .strictEndDate), limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, values, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: values?.first?.startDate) }
            }
            store.execute(query)
        }
        guard let first, first <= now else { return [:] }
        let start = calendar.startOfDay(for: first)
        return try await withCheckedThrowingContinuation { continuation in
            var interval = DateComponents(); interval.day = 1; interval.calendar = calendar; interval.timeZone = calendar.timeZone
            let query = HKStatisticsCollectionQuery(quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate), options: .cumulativeSum,
                anchorDate: calendar.startOfDay(for: now), intervalComponents: interval)
            let healthStore = store
            query.initialResultsHandler = { query, collection, error in
                defer { healthStore.stop(query) }
                if let error { continuation.resume(throwing: error); return }
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: now) { statistics, _ in
                    guard statistics.startDate <= now, let quantity = statistics.sumQuantity() else { return }
                    let value = quantity.doubleValue(for: unit)
                    if value.isFinite, value >= 0 { result[calendar.startOfDay(for: statistics.startDate)] = value }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}

/// Watch messages provide timely data; HealthKit supplies timestamped store updates.
/// Neither transport guarantees continuous delivery, so stale samples never alert.
@MainActor @Observable
final class WorkoutHeartRateMonitor {
    private let health = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var sessionID: String?
    private var sessionStart: Date?
    private var limit: Int?
    var reminderLimit: Int? { limit }
    private var policy = WorkoutHeartAlertPolicy()
    private var warningRecovery = WorkoutHeartWarningRecovery()
    private var visualEscalation = WorkoutHeartVisualEscalation()
    var hasEscalatedWarning: Bool { visualEscalation.isEscalated }
    private var requestedWatchSessionID: String?
    private(set) var latest: WorkoutHeartSample?
    var warningPending = false

    func openWatchWorkout() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        try await health.startWatchApp(toHandle: configuration)
    }

    /// Called after the current, explicitly opted-in phone session has been synced.
    /// A settings/limit refresh must not repeatedly launch the Watch app.
    func startWatchWorkoutIfNeeded(launch: (() async throws -> Void)? = nil) async {
        guard let sessionID, requestedWatchSessionID != sessionID,
              !WatchSyncManager.shared.watchHealthSessionActive else { return }
        requestedWatchSessionID = sessionID
        do {
            if let launch { try await launch() }
            else { try await openWatchWorkout() }
        } catch {
            // The existing explicit Watch launch button remains the retry entry.
        }
    }

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw NSError(domain: "Health", code: 1) }
        try await health.requestAuthorization(toShare: [], read: [HKQuantityType(.heartRate)])
    }

    func bind(sessionID: String?, start: Date?, enabled: Bool, limit: Int?) {
        if self.limit != limit { warningPending = false; policy = WorkoutHeartAlertPolicy(); warningRecovery = WorkoutHeartWarningRecovery(); visualEscalation = WorkoutHeartVisualEscalation() }
        self.limit = limit
        guard enabled, let sessionID, let start else { stop(); return }
        guard self.sessionID != sessionID else { return }
        stop()
        self.limit = limit; self.sessionID = sessionID; sessionStart = start
        WatchSyncManager.shared.onHeartRate = { [weak self] key, bpm, date in
            self?.receive(.init(id: "watch|\(key)|\(date.timeIntervalSince1970)", sessionID: key, date: date, bpm: bpm, source: "Apple Watch"))
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, values, deleted, _, _ in
            let samples = (values as? [HKQuantitySample] ?? []).map {
                WorkoutHeartSample(id: $0.uuid.uuidString, sessionID: sessionID, date: $0.endDate,
                    bpm: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())), source: $0.sourceRevision.source.name)
            }
            let deletedIDs = Set((deleted ?? []).map { $0.uuid.uuidString })
            Task { @MainActor in
                guard let self, self.sessionID == sessionID else { return }
                if !deletedIDs.isEmpty { WorkoutHeartLocalStore.shared.remove(ids: deletedIDs) }
                for sample in samples.sorted(by: { $0.date < $1.date }) { self.receive(sample) }
            }
        }
        let query = HKAnchoredObjectQuery(type: HKQuantityType(.heartRate), predicate: predicate,
                                        anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        self.query = query
        health.execute(query)
    }

    func receive(_ sample: WorkoutHeartSample, now: Date = Date()) {
        guard sample.sessionID == sessionID, let sessionStart, sample.date >= sessionStart,
              sample.date.timeIntervalSince(now) <= 5, sample.bpm.isFinite, (20...300).contains(sample.bpm) else { return }
        var sample = sample
        sample.reminderLimit = now.timeIntervalSince(sample.date) <= 20 ? limit : nil
        WorkoutHeartLocalStore.shared.append(sample, now: now)
        if latest.map({ sample.date > $0.date }) ?? true { latest = sample }
        visualEscalation.observe(bpm: sample.bpm, date: sample.date, limit: limit, now: now)
        if warningPending && warningRecovery.observe(bpm: sample.bpm, date: sample.date, limit: limit, now: now) {
            warningPending = false
            warningRecovery = WorkoutHeartWarningRecovery()
        }
        if policy.observe(bpm: sample.bpm, date: sample.date, limit: limit, now: now) {
            warningPending = true
            warningRecovery = WorkoutHeartWarningRecovery()
            Haptics.tap()
        }
    }

    func freshBPM(at date: Date) -> Int? {
        guard let latest, date.timeIntervalSince(latest.date) <= 20 else { return nil }
        return Int(latest.bpm.rounded())
    }

    func stop() {
        if let query { health.stop(query) }
        query = nil; sessionID = nil; sessionStart = nil; latest = nil
        requestedWatchSessionID = nil
        warningPending = false; policy = WorkoutHeartAlertPolicy(); warningRecovery = WorkoutHeartWarningRecovery(); visualEscalation = WorkoutHeartVisualEscalation()
        WatchSyncManager.shared.onHeartRate = nil
        WorkoutHeartLocalStore.shared.flush()
    }
}

extension HealthKitService {
    /// Reports may open after Watch-to-phone HealthKit delivery has caught up.
    /// A denied/empty read remains unknown; it is never reported as zero heart rate.
    func backfillWorkoutHeart(records: [SetRecord], enabled: Bool) async {
        guard enabled, Self.isAvailable else { return }
        let grouped = Dictionary(grouping: records.filter { $0.workoutSessionID != nil }, by: { $0.workoutSessionID! })
        for (sessionID, records) in grouped {
            let intervals = records.flatMap { $0.activeIntervals ?? [] }
            guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max(), end > start else { continue }
            let values: [HKQuantitySample] = (try? await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: HKQuantityType(.heartRate),
                    predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                    limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
                }
                store.execute(query)
            }) ?? []
            for value in values where value.endDate >= start && value.endDate < end {
                WorkoutHeartLocalStore.shared.append(.init(id: value.uuid.uuidString, sessionID: sessionID, date: value.endDate,
                    bpm: value.quantity.doubleValue(for: .count().unitDivided(by: .minute())), source: value.sourceRevision.source.name))
            }
        }
        WorkoutHeartLocalStore.shared.flush()
    }
}
