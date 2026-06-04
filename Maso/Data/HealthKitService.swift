import Foundation
import HealthKit

// HealthKit 接入 — 把 Maso 训练数据写到 Apple Health → Apple Fitness 自动 pick up.
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
//   - 不读 read permission — 我们只 write, 不需要读用户其他健康数据 (减少授权摩擦)
//   - WorkoutActivityType: 默认 .functionalStrengthTraining (覆盖 90%+ Maso 用户场景)
//     若 session 是 cardio / yoga 主导, 用对应类型 (.running, .yoga, .flexibility)
//   - totalEnergyBurned: 用粗略估算 (MET × duration × weight), 不准但比 nil 有用

@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

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
    /// - 不能再次拉起对话框 (HealthKit API 限制) — 用户要改决定必须自己去 Settings.app.
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

// MARK: - Maso → HKWorkoutActivityType 映射

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
            return .other  // 太宽泛, Maso 没区分 running/cycling — 用 .other 让 Health 不强分类
        case .stretching, .flexibility, .mobility:
            return .flexibility
        case .plyometric:
            return .crossTraining
        }
    }
}
