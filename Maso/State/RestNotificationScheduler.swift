import Foundation
import UserNotifications

/// 休息倒计时通知 — 用户在休息段把手机锁屏 / 切到别的 app, 倒计时结束时弹通知提醒.
///
/// 设计原则 (符合 plan 理念 "不打扰用户"):
///   - **仅在休息段 + app 不在前台时调度**. 前台时 app 自己有声音 + 震动, 不需要通知.
///   - **app 回前台立刻取消**. 不让用户回 app 后又收一遍重复提醒.
///   - **训练结束 / 用户主动 advance** 也取消.
///   - **不收集 token, 不上服务器, 全是本地通知**. 跟 "Data Not Collected" 品牌一致.
///   - **可选** — 用户在 Settings 关闭通知权限 → 静默 fail, app 仍正常工作.
///
/// 通知触发时机:
///   - `seg.endsAt` (休息倒计时归零的绝对时刻) 是 timer fire 的目标
///   - schedule 时计算 `endsAt - now()` 作为 delay
@MainActor
final class RestNotificationScheduler {
    static let shared = RestNotificationScheduler()

    private static let notificationId = "maso.rest.ending"
    private var permissionAsked: Bool = false

    private init() {}

    /// 调度 rest 结束通知. 重复调用会先 cancel 再 schedule (覆盖上一次).
    /// 参数: 倒计时结束的绝对时间, 通常是 `session.endsAt`.
    /// 是否切换动作影响通知文案: 切换 → "Time to switch exercise", 否则 → "Time for next set"
    func schedule(endsAt: Date, isCrossExercise: Bool, nextExerciseName: String?) {
        // 取消上一次
        cancel()

        let delay = endsAt.timeIntervalSinceNow
        // < 2s 直接 skip — 用户可能在前台 advance, 没必要发了又秒收
        guard delay > 2 else { return }

        Task { @MainActor in
            // 没问过权限 → 先静默问一次. 用户拒绝 → 后续都跳过.
            if !permissionAsked {
                permissionAsked = true
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            }

            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = isCrossExercise
                ? NSLocalizedString("Time to switch exercise", comment: "")
                : NSLocalizedString("Rest's up — next set", comment: "")
            if let name = nextExerciseName {
                content.body = name
            }
            content.sound = .default
            content.categoryIdentifier = "MASO_REST"
            // 触发器: 用绝对时间触发, time-interval 精度更可控
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: delay,
                repeats: false
            )
            let req = UNNotificationRequest(
                identifier: Self.notificationId,
                content: content,
                trigger: trigger
            )
            try? await center.add(req)
        }
    }

    /// 取消 pending rest 通知. app 回前台 / 用户 advance / 训练结束都该调.
    func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        // 已经 deliver 到通知中心的也清掉 — 用户回 app 没必要再看一次
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }
}
