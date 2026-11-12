import Foundation
import UserNotifications

/// Notification text is resolved when scheduled, using the same effective language
/// as the interface. Never use stale persisted settings or launch-time localization.
enum AppNotificationText {
    static func string(_ key: String, language: String = LanguageManager.currentLanguageCode) -> String {
        let code = SupportedLanguage(rawValue: language)?.rawValue ?? LanguageManager.currentLanguageCode
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

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
            let targetDay = base.addingTimeInterval(item.days * 86_400)
            let fire = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: targetDay) ?? targetDay
            guard fire > now.addingTimeInterval(60) else { continue }   // 已过去的跳过
            schedule(id: item.id, title: item.title, body: body, fire: fire, center: center)
            scheduledAny = true
        }
        if !scheduledAny {
            // 全部已过 → 久未训练的用户也补一发 (now+3 天).
            schedule(id: Self.ids[2], title: "Let's get back to it", body: body,
                     fire: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: now.addingTimeInterval(3 * 86_400)) ?? now.addingTimeInterval(3 * 86_400), center: center)
        }
    }

    private func schedule(id: String, title: String, body: String, fire: Date,
                          center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = AppNotificationText.string(title)
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


/// Local bedtime reminders; only schedule after explicit permission and opt-in.
@MainActor
final class SleepReminderScheduler {
    static let shared = SleepReminderScheduler()
    private static let identifier = "masso.sleep.bedtime"
    func reschedule(settings: UserSettings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard settings.sleepEnabled ?? true,
              let preferences = settings.sleepPreferences,
              preferences.bedtimeReminderEnabled == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Masso"
        content.body = AppNotificationText.string("Your muscles are off duty. Put your phone down and sleep well.")
        content.sound = .default
        var time = DateComponents()
        time.hour = preferences.bedtimeMinutes / 60
        time.minute = preferences.bedtimeMinutes % 60
        center.add(UNNotificationRequest(identifier: Self.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)))
    }
}


/// Shared local meal schedule for home guidance and opt-in notifications.
enum DailyReminderContext {
    static func mealMinutes(settings: UserSettings) -> [Int] {
        let preferences = settings.dietPreferences ?? DietPreferences()
        if preferences.windowHours != nil {
            return (0..<preferences.mealCount).compactMap { preferences.scheduledMinute(at: $0) }
        }
        switch preferences.mealCount {
        case 2: return [12 * 60, 18 * 60]
        case 4: return [8 * 60, 12 * 60, 16 * 60, 18 * 60]
        case 5: return [8 * 60, 11 * 60, 14 * 60, 17 * 60, 18 * 60]
        default: return [8 * 60, 12 * 60, 18 * 60]
        }
    }

    /// A record satisfies only its nearest meal slot on the recorded day.
    static func hasLoggedMeal(settings: UserSettings, near date: Date) -> Bool {
        let calendar = Calendar.current
        let slots = mealMinutes(settings: settings).compactMap {
            calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: date)
        }
        guard let requested = slots.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }) else { return false }
        return (settings.mealCheckIns ?? []).contains { meal in
            guard calendar.isDate(meal.day, inSameDayAs: date),
                  abs(meal.mealTime.timeIntervalSince(requested)) <= 2 * 3600 else { return false }
            return slots.min(by: { abs($0.timeIntervalSince(meal.mealTime)) < abs($1.timeIntervalSince(meal.mealTime)) }) == requested
        }
    }

    static func heading(settings: UserSettings, now: Date) -> (title: String, subtitle: String)? {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let bedtime = (settings.sleepPreferences ?? SleepPreferences()).bedtimeMinutes
        let sinceBedtime = (minutes - bedtime + 1440) % 1440
        let untilBedtime = (bedtime - minutes + 1440) % 1440
        if settings.sleepEnabled ?? true,
           untilBedtime <= 60 || sinceBedtime <= 120 || minutes < 5 * 60 {
            return (NSLocalizedString("Time to wind down", comment: "home bedtime action"),
                    NSLocalizedString("Sleep helps your muscles recover", comment: "home bedtime context"))
        }
        if settings.dietEnabled ?? true,
           mealMinutes(settings: settings).contains(where: { minute in
               let distance = abs(minutes - minute)
               return min(distance, 1440 - distance) <= 45
           }) {
            return (NSLocalizedString("Time to eat", comment: "home meal action"),
                    NSLocalizedString("Fuel your muscles with a balanced meal", comment: "home meal context"))
        }
        return nil
    }
}

@MainActor
final class MealReminderScheduler {
    static let shared = MealReminderScheduler()
    private static let ids = (0..<5).map { "masso.meal.\($0)" }

    func reschedule(settings: UserSettings) {
        let center = UNUserNotificationCenter.current()
        let datedIDs = (0..<7).flatMap { day in (0..<5).map { "masso.meal.\(day).\($0)" } }
        center.removePendingNotificationRequests(withIdentifiers: Self.ids + datedIDs)
        guard settings.dietEnabled ?? true, settings.mealRemindersEnabled == true else { return }
        let calendar = Calendar.current
        let now = Date()
        // Rolling week, max 35 requests, refreshed on saving and foreground entry.
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for (index, minutes) in DailyReminderContext.mealMinutes(settings: settings).enumerated() {
                guard let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day), date > now,
                      !DailyReminderContext.hasLoggedMeal(settings: settings, near: date) else { continue }
                let content = UNMutableNotificationContent()
                content.title = AppNotificationText.string("Time to eat")
                content.body = AppNotificationText.string("Fuel your muscles with a balanced meal")
                content.sound = .default
                let time = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                center.add(UNNotificationRequest(identifier: "masso.meal.\(offset).\(index)", content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: false)))
            }
        }
    }
}
