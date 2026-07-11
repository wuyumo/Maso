import SwiftUI

// 周训练频率分享卡 — 给 WorkoutCalendarScreen 的"分享这周训练频率" 用.
//
// 信息层级:
//   - "This Week" 标题 + 日期范围
//   - 7 天 mini 日历 (一行 7 个圆, 训练日 accent 实心, 没训练 灰圆)
//   - 关键数据: 训练天数 / 总组数 / 连续训练天数
//   - Footer
struct WeeklyFrequencyShareCard: View {
    /// 本周训练过的日期 set (key = startOfDay)
    let sessionDates: Set<Date>
    let totalSets: Int
    let streakDays: Int  // 连续训练天数 (相对今天)
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // 一周 7 天: 今天 - 6 ... 今天
        return (0..<7).reversed().map { offset in
            cal.date(byAdding: .day, value: -offset, to: today)!
        }
    }

    private var rangeLabel: String {
        let cal = Calendar.current
        let start = weekDates.first ?? Date()
        let end = weekDates.last ?? Date()
        let df = DateFormatter()
        df.dateFormat = cal.isDate(start, equalTo: end, toGranularity: .month) ? "MMM d" : "MMM d"
        let s = df.string(from: start)
        df.dateFormat = "MMM d"
        let e = df.string(from: end)
        return "\(s) – \(e)"
    }

    private var workoutCount: Int {
        weekDates.filter { sessionDates.contains($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            SharePhotoBanner(photo: userPhoto, onTapToAdd: onTapAddPhoto)
            VStack(spacing: 18) {
                Spacer(minLength: userPhoto == nil ? 28 : 16)

                // 标题
                VStack(spacing: 4) {
                    Text(rangeLabel.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(MasoColor.accent)
                    Text("This Week")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                }

                // 7 天 mini 日历
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        DayDot(date: date, trained: sessionDates.contains(date))
                    }
                }
                .padding(.top, 4)

                // 关键数据 — 标签走本地化 (跟 UnifiedShareCard 同一套键)
                HStack(spacing: 18) {
                    ShareStat(value: "\(workoutCount)/7", label: NSLocalizedString("Days", comment: "share stat — trained days out of 7"))
                    ShareStat(value: "\(totalSets)", label: NSLocalizedString("Total Sets", comment: "share stat — weekly total sets"))
                    if streakDays > 0 {
                        ShareStat(value: "🔥\(streakDays)", label: NSLocalizedString("Streak", comment: "share stat — week streak"))
                    }
                }
                .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)

            ShareCardFooter(qrPayload: MasoLinks.appStore)
        }
        .background(MasoColor.background)
    }
}

/// 单天的圆点 — 训练日 accent 实心, 未训练 灰圆描边
private struct DayDot: View {
    let date: Date
    let trained: Bool

    private static let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "E"  // M/T/W/T/F/S/S
        return df
    }()
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "d"
        return df
    }()

    var body: some View {
        VStack(spacing: 6) {
            Text(Self.weekdayFormatter.string(from: date).prefix(1))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MasoColor.textDim)
            ZStack {
                Circle()
                    .fill(trained ? MasoColor.accent : Color.clear)
                    .overlay(
                        Circle().stroke(trained ? Color.clear : MasoColor.borderSoft, lineWidth: 1)
                    )
                    .frame(width: 32, height: 32)
                Text(Self.dayFormatter.string(from: date))
                    .font(.system(size: 12, weight: .heavy).monospacedDigit())
                    .foregroundStyle(trained ? .black : MasoColor.text)
            }
        }
    }
}
