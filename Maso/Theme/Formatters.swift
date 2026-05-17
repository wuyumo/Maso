import Foundation

// 格式化函数 — 整个 app 共用. UI 文案 English-first.

/// 倒计时 / 时长格式化
/// < 60s: 直接秒数 "45"
/// >= 60s: "M:SS" "2:30"
func formatRemaining(_ seconds: Int) -> String {
    if seconds < 60 { return String(seconds) }
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

/// "N exercises" — localized via Localizable.strings (中文不区分单复数)
func pluralizedExercises(_ count: Int) -> String {
    String(format: NSLocalizedString("%d exercises", comment: ""), count)
}

/// "N sets" — localized
func pluralizedSets(_ count: Int) -> String {
    String(format: NSLocalizedString("%d sets", comment: ""), count)
}

/// 重量格式化: 整数显示 "45", 0.5 倍数显示 "47.5"
func formatWeight(_ w: Double) -> String {
    if w.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(w))" }
    return String(format: "%.1f", w)
}

/// 相对日期: "Today" / "Yesterday" / "N days ago" / "May 8" — localized
func relativeDay(_ date: Date, now: Date = Date()) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return NSLocalizedString("Today", comment: "") }
    if cal.isDateInYesterday(date) { return NSLocalizedString("Yesterday", comment: "") }
    let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                     to: cal.startOfDay(for: now)).day ?? 0
    if daysAgo > 0 && daysAgo < 7 {
        let key = daysAgo == 1 ? "%d day ago" : "%d days ago"
        return String(format: NSLocalizedString(key, comment: ""), daysAgo)
    }
    let fmt = DateFormatter()
    fmt.locale = Locale.current  // 跟系统语言走 — 中文环境会显示 "5月8日"
    fmt.setLocalizedDateFormatFromTemplate("MMMd")
    return fmt.string(from: date)
}
