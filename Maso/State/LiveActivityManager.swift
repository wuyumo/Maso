import ActivityKit
import Foundation

// 训练 Live Activity 管理器 — 包装 ActivityKit, 让 TrainingSession 简单调 start/update/end.
//
// 不直接由 SwiftUI view 调用 — 由 TrainingSession state 变化时 hook 进来调.
// (避免业务 view 直接依赖 ActivityKit API)
//
// 行为:
//   - start(plan, state): 训练开始时调一次. 创建 ActivityKit.Activity, 锁屏顶部 + Dynamic Island 出现 banner.
//   - update(state): segment 切换 / play 暂停 时调. 更新 state, 不重新创建 activity.
//   - end(): 训练完成 / 用户主动结束时调. activity dismiss.
//
// iOS 限制:
//   - 用户在系统 Settings 关掉 Live Activities 时, start 失败. 我们静默 skip — 不影响主流程.
//   - 单个 app 同时只有一个 active activity. start 前先 end 旧的.
//   - app 不在前台时也能 update (走 ActivityKit framework, 不需要 push notif).

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var current: Activity<TrainingActivityAttributes>?

    private init() {}

    /// 训练开始 — 创建 activity.
    /// 失败原因: 用户禁 / 已超过同时 8 个 activity / iOS < 16.1 — 都静默忽略, 训练主流程不受影响.
    ///
    /// 之前 bug: `Task { await endAllActive() }` 是 fire-and-forget, 立即接 `Activity.request`
    /// 时旧 activity 可能没清完, 抢 quota → 新 activity 启不来. 现改成把"清旧 + 启新"放同
    /// 一 Task 顺序执行.
    func start(planName: String, initialState: TrainingActivityAttributes.ContentState) {
        let info = ActivityAuthorizationInfo()
        // 预检 — 不阻塞主线程, 立即返回. 真正请求走 Task.
        guard info.areActivitiesEnabled else {
            #if DEBUG
            print("[LiveActivity] disabled by user/system — skipping start")
            #endif
            return
        }
        Task { @MainActor in
            // 1. 先等清完旧的 — 否则新 request 跟旧的可能抢同一 activity slot.
            await endAllActive()
            // 2. 再启新的.
            let attrs = TrainingActivityAttributes(planName: planName)
            let content = ActivityContent(state: initialState, staleDate: nil)
            do {
                current = try Activity.request(
                    attributes: attrs,
                    content: content,
                    pushType: nil   // 不走远程 push, 全本地 ActivityKit update
                )
                #if DEBUG
                print("[LiveActivity] started: \(planName)")
                #endif
            } catch {
                // start 失败 — log 但不抛, 训练主流程继续
                #if DEBUG
                print("[LiveActivity] start failed: \(error)")
                #endif
            }
        }
    }

    /// 更新当前 activity state — segment 切换 / countdown 启停时调.
    func update(_ state: TrainingActivityAttributes.ContentState) {
        guard let activity = current else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    /// 训练完成 — 结束 activity. dismissImmediate 让锁屏 banner 立刻消失.
    /// 不调用 endAllActive() 是因为只 end 当前 instance, 其他 activity (理论上不该有) 不动.
    func end() {
        guard let activity = current else { return }
        let finalState = activity.content.state
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        current = nil
    }

    /// 清理残留 — start 前调 + app 启动时调 (从 crash / kill 留下的 zombie activity).
    private func endAllActive() async {
        for activity in Activity<TrainingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        current = nil
    }
}
