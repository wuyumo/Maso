import SwiftUI
import WatchKit
import HealthKit

@main
struct MasoWatchApp: App {
    @WKApplicationDelegateAdaptor(WorkoutLaunchDelegate.self) private var workoutLaunchDelegate
    /// 桥在 init 里就 activate WCSession — app 一启动立刻能收手机的最近状态.
    @State private var bridge = WatchBridge.shared
    /// HK 管理器进环境观察图 — vitals footer 的心率/卡路里随采集刷新.
    @State private var workout = WatchWorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(bridge)
        }
    }
}

final class WorkoutLaunchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            let mode = WatchBridge.shared.state.mode
            if mode == .exercise || mode == .rest { WatchWorkoutManager.shared.startIfNeeded() }
        }
    }
}
