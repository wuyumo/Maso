import Foundation
import UserNotifications

/// 召回提醒 — 用户停训一段时间后, 在"恢复窗口"轻推一次"该练了".
///
/// 品牌原则一致 (跟 RestNotificationScheduler 同):
///   - **默认关 (opt-in)** — 用户在 Settings 主动打开才调度. 不默认打扰.
///   - **全本地** — 不收集 token, 不上服务器, 跟 "Data Not Collected" 一致.
///   - **以"最后一次训练"为基, 不以"最后一次开 app"** — 只浏览不训练不会重置计时.
///   - **每次训练完 / app 进后台都重排** — 用户持续训练 → 提醒日期不断后移, 永不真正弹出;
///     一旦停训 → 在 2 / 4 / 8 天处收到一组错峰的温和提醒, 然后归于安静.
@MainActor
final class WorkoutReminderScheduler {
    static let shared = WorkoutReminderScheduler()
    private init() {}

    /// 一组错峰召回 id — 重排时整组先清, 避免叠加.
    private static let ids = ["maso.comeback.1", "maso.comeback.2", "maso.comeback.3"]

    /// 请求通知权限 (用户在 Settings 打开开关时调). 已授权再调直接返回 true.
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 重排召回提醒.
    /// - enabled=false → 仅清除 (开关关掉 / 未开).
    /// - 以 lastWorkout (没有则 now) 为基, 在 +2 / +4 / +8 天错峰排三发; 已过去的跳过.
    /// - 若全部已过 (用户久未训练) → 退一步在 now+3 天补一发, 别让久未训练的用户完全收不到.
    func reschedule(enabled: Bool, lastWorkout: Date?, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.ids)
        guard enabled else { return }

        let now = Date()
        let base = lastWorkout ?? now
        // (id, 距 base 的天数, 标题 key)
        let plan: [(id: String, days: Double, title: String)] = [
            (Self.ids[0], 2, "Recovered and ready"),
            (Self.ids[1], 4, "Your muscles miss you"),
            (Self.ids[2], 8, "Let's get back to it"),
        ]
        var scheduledAny = false
        for item in plan {
            let fire = base.addingTimeInterval(item.days * 86_400)
            guard fire > now.addingTimeInterval(60) else { continue }   // 已过去的跳过
            schedule(id: item.id, title: item.title, body: body, fire: fire, center: center)
            scheduledAny = true
        }
        if !scheduledAny {
            // 全部已过 → 久未训练的用户也补一发 (now+3 天).
            schedule(id: Self.ids[2], title: "Let's get back to it", body: body,
                     fire: now.addingTimeInterval(3 * 86_400), center: center)
        }
    }

    private func schedule(id: String, title: String, body: String, fire: Date,
                          center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(title, comment: "comeback reminder title")
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// 关闭开关时清掉全部待发召回提醒.
    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.ids)
    }
}
