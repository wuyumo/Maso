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

/// canonical kg → "<数值> <单位>" (按用户单位设置换算 + 带标签). 全 app 显示训练重量统一走它,
/// 避免硬编码 "kg" 让 lb 设置失效.
func weightLabel(_ kg: Double, _ unit: WeightUnit) -> String {
    "\(formatWeight(unit.fromKg(kg))) \(unit.label)"
}

/// 同上, 用全局当前单位 (WeightUnitProvider.current) — 显示点不必自己拿 settings.
func weightLabel(_ kg: Double) -> String {
    weightLabel(kg, WeightUnitProvider.current)
}

/// session 真实训练时长 (分钟) — 首末 SetRecord.performedAt 差, 下限 5 分钟兜底
/// (单组 session 首末同一时刻, "0m" 无意义). 跟完成屏 (PlanPlayerScreen.completedDurationSeconds)
/// 同一路"取真实时间戳"; History 卡片 / 详情 / 分享卡统一走它, 不再用"组数×2 分钟"的编造值 (P1#17).
func sessionDurationMinutes(first: Date, last: Date) -> Int {
    max(5, Int((last.timeIntervalSince(first) / 60).rounded()))
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
    // P2-2: 跟 in-app 选的语言走 (LanguageManager), 不是 Locale.current —
    // 否则用户在 app 内切语言后, History 日历月份跟新语言、session 卡日期却停在旧语言.
    fmt.locale = LanguageManager.currentLocale
    fmt.setLocalizedDateFormatFromTemplate("MMMd")
    return fmt.string(from: date)
}
