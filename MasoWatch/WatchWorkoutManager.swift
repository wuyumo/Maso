import Foundation
import HealthKit
import Observation

/// 手表端 HKWorkoutSession — 训练期间跑实时心率 + 卡路里采集, 结束时保存到 Health
/// (Activity 圆环积分). 开了 session 立即通过 WatchBridge 通知手机 (.hkActive),
/// 手机端这次训练就不再写自己那份 HKWorkout, 防止 Health 双计.
///
/// 生命周期由 WatchRootView 驱动: mode 进入 exercise/rest → startIfNeeded();
/// mode 回到 done/idle → end(). 训练 app 跑着 session 时 watchOS 会保持 app 常驻前台.
@Observable
final class WatchWorkoutManager: NSObject, @unchecked Sendable {
    static let shared = WatchWorkoutManager()

    var heartRate: Int = 0
    var activeCalories: Int = 0
    private(set) var running = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func startIfNeeded() {
        guard !running, HKHealthStore.isHealthDataAvailable() else { return }
        running = true
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        Task {
            do {
                let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
                let read: Set<HKObjectType> = [
                    HKQuantityType(.heartRate),
                    HKQuantityType(.activeEnergyBurned),
                ]
                try await store.requestAuthorization(toShare: share, read: read)
                let session = try HKWorkoutSession(healthStore: store, configuration: config)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
                builder.delegate = self
                self.session = session
                self.builder = builder
                let start = Date()
                session.startActivity(with: start)
                try await builder.beginCollection(at: start)
                WatchBridge.shared.send(.hkActive)
            } catch {
                // 授权被拒 / session 创建失败 — 镜像功能照常, 只是没有心率和圆环
                self.running = false
                self.session = nil
                self.builder = nil
            }
        }
    }

    func end() {
        guard running else { return }
        running = false
        guard let session, let builder else { return }
        session.end()
        Task {
            _ = try? await builder.endCollection(at: Date())
            _ = try? await builder.finishWorkout()
            self.session = nil
            self.builder = nil
            await MainActor.run {
                self.heartRate = 0
                self.activeCalories = 0
            }
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let qt = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: qt) else { continue }
            let hr: Int? = qt == HKQuantityType(.heartRate)
                ? stats.mostRecentQuantity().map { Int($0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded()) }
                : nil
            let kcal: Int? = qt == HKQuantityType(.activeEnergyBurned)
                ? stats.sumQuantity().map { Int($0.doubleValue(for: .kilocalorie()).rounded()) }
                : nil
            Task { @MainActor in
                if let hr { self.heartRate = hr }
                if let kcal { self.activeCalories = kcal }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
