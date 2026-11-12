import SwiftUI

// 嵌入式训练日历 — 顶在 HistoryScreen 顶部, 替代以前的"训练日历" sheet 入口.
//
// 两种状态:
//   - expanded: 整月 grid + 月底 stats (天数 / 连续 / 总组数). 第一眼看到.
//   - collapsed: 单行 7 天 strip (本周 only). 用户向上滑后, sticky 在顶部不挡内容.
//
// 状态切换由 caller (HistoryScreen) 根据 scrollOffset 决定 → 传 isCollapsed binding 进来.
// 内部用 `.animation(...)` 跑高度 / 内容 swap, 外部不需要管动画.
//
// Phase 4b — "expand info one level":
//   - 月底 stats 从 2 列扩到 3 列: 本月天数 / 当前连续 / 本月组数
//   - 每个 workout 日下方加一条 muscle dots (3 个大肌群最多), 给用户一眼看到"那天练了啥"
struct InlineWorkoutCalendar: View {
    @Environment(DataStore.self) private var data

    /// Caller 算好的 set: 用户有训练的日期 (startOfDay-normalized).
    let sessionDates: Set<Date>
    /// 每个 startOfDay → 当天命中的大肌群 (按出现顺序, 最多 3 个). 给日历下方 dot 用.
    /// 没有 = 当天没训练. 用 Color 而不是 enum, 这样 caller 可以走 MasoColor / MuscleColor 任意 mapping.
    let musclesPerDay: [Date: [Color]]

    @Binding var isCollapsed: Bool

    /// 当前展开显示的月份 (锚到月初). 由 caller (HistoryScreen) 持有 —— 顶部 metrics 严格按这个
    /// 月份口径算; 收起→重开时 caller 会把它重置回当前月 (重开默认回到本月, 不停在上次翻到的月).
    @Binding var monthAnchor: Date

    /// true = 嵌在外层卡片里 (跟 stats 合成一张卡) — 不自带 surface 底色 / 圆角, 只做 overflow 裁剪.
    var embedded: Bool = false

    /// 上一次月份切换方向 (-1 = 退到上个月, +1 = 进到下个月). 给 grid 的 transition
    /// 决定从哪边滑入 / 滑出 — 这样不管是 chevron 点击还是横向 swipe, 视觉方向都跟"动作"匹配.
    @State private var lastShiftDirection: Int = 1

    /// P3: 读 scenePhase 让回前台时 view 重算 today — 防跨午夜后 today 环 / 7 天 cutoff 卡在旧日.
    @Environment(\.scenePhase) private var scenePhase

    /// 走 DataStore.settings.weekStartDay 影响过的 calendar — 用户在 Settings 选了
    /// "周一" 还是 "周日" 这里就直接对齐.
    private var calendar: Calendar { data.settings.calendar }
    private var today: Date { calendar.startOfDay(for: Date()) }

    var body: some View {
        let _ = scenePhase  // 触发依赖: scenePhase 变 (后台→前台) → 重渲 → today 重算
        return VStack(alignment: .leading, spacing: 0) {
            if isCollapsed {
                collapsedRow
                    // 折叠态退场: 透明淡出 — 不再 .move(edge: .top) 那种"上滑消失",
                    // 视觉上是"折叠版淡出, 月版从顶部缓慢生长".
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity
                    ))
            } else {
                expandedView
                    // 展开态入场: 从顶部 anchor 缩放 + 淡入 — 看起来像"周条平滑长成月历",
                    // 而不是"月历突然从底下冒出来一闪".
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
        // 慢一点 + 弹一点 — "优雅、缓慢"地展开. spring duration ~0.45s.
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: isCollapsed)
        // 卡片样式: 独立时 surface 底色 + 圆角; embedded 时透明 + 直角 (圆角交给外层卡),
        // clipShape 仍负责动画期间的 overflow 裁剪.
        .background(embedded ? Color.clear : MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: embedded ? 0 : MasoMetrics.cornerRadiusMedium))
    }

    // MARK: - Collapsed: 单行本周 strip
    //
    // 整个 strip 都是 tap target — 点任何位置 (周一格 / 周三格 / 间距空白) 都展开整月.
    // 用 contentShape(Rectangle()) 让间距空白也响应 tap; chevron 是显式提示, 但不是唯一 hit zone.

    @ViewBuilder
    private var collapsedRow: some View {
        let week = currentWeekDays()
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { date in
                collapsedDay(date)
                    .frame(maxWidth: .infinity)
            }
            // 右侧 chevron — 提示可展开. 留出固定宽度别挤压 7 天 cell.
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(MasoColor.textFaint)
                .frame(width: 22)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) { isCollapsed = false }
            Haptics.tap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Workout calendar")
        .accessibilityHint("Double tap to expand month view")
    }

    @ViewBuilder
    private func collapsedDay(_ date: Date) -> some View {
        let isWorkout = sessionDates.contains(date)
        let isToday = date == today
        VStack(spacing: 4) {
            // DESIGN.md §2.2: 周缩写走 kicker 规格 10pt bold + tracking
            Text(weekdaySymbolForDate(date))
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(MasoColor.textFaint)
            ZStack {
                if isWorkout {
                    Circle().fill(MasoColor.accent)
                } else if isToday {
                    Circle().stroke(MasoColor.accent.opacity(0.5), lineWidth: 1)
                }
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: isWorkout ? .heavy : .semibold).monospacedDigit())
                    .foregroundStyle(
                        isWorkout ? .black
                        : (isToday ? MasoColor.accent : MasoColor.text)
                    )
            }
            .frame(width: 26, height: 26)
        }
    }

    // MARK: - Expanded: 月份切换 header + grid + stats

    @ViewBuilder
    private var expandedView: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)

            weekdayHeader
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            // .id(monthAnchor) → 月份变化时整个 grid 重建, 配合下面 transition 做滑入滑出动画.
            // 用 ZStack 容器锁定布局空间, 让进 / 出两份 grid 不会因为缺失而抖动高度.
            ZStack {
                monthGrid
                    .id(monthAnchor)
                    .transition(.asymmetric(
                        // lastShiftDirection > 0 (进下个月) → 新 grid 从右边滑入, 旧的从左边滑出
                        // lastShiftDirection < 0 (退上个月) → 反方向
                        insertion: .move(edge: lastShiftDirection >= 0 ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: lastShiftDirection >= 0 ? .leading : .trailing)
                            .combined(with: .opacity)
                    ))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .clipped()  // grid 滑出超出卡片边界时裁掉, 不要溢出到 stats / 列表上
        }
        // 整片 expanded 区域都接横滑手势 — 用户在任何位置 (header / weekday strip / 日期 grid)
        // 横扫都切月. simultaneousGesture 让父 ScrollView 仍能正常竖向滚动.
        .contentShape(Rectangle())
        .simultaneousGesture(monthSwipeGesture)
    }

    /// 横向 swipe 切月份 — iOS Calendar 同款: 向左划 = 下一个月, 向右划 = 上一个月.
    /// 阈值: 水平位移 > 50pt 且明显大于竖向位移 (避免误触竖向滚动). 末态触发, 不做 .onChanged
    /// 的实时跟随 — 跟随会跟 ScrollView 竖滚抢手势, 体验不稳.
    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // P3: 提高水平主导比 (1.5→2.5) — 对角滑动不再误触月份切换, 让竖向滚动优先.
                guard abs(dx) > 50, abs(dx) > abs(dy) * 2.5 else { return }
                if dx < 0 {
                    // 向左划 → 下一个月; 已经是当月 / 未来月不允许 (跟 chevron disabled 规则一致)
                    guard !isFutureMonth else { return }
                    shiftMonth(1)
                } else {
                    shiftMonth(-1)
                }
            }
    }

    @ViewBuilder
    private var monthHeader: some View {
        HStack(spacing: 8) {
            Button(action: { shiftMonth(-1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 32, height: 32)
                    .background(MasoColor.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthLabel)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(MasoColor.text)

            Spacer()

            Button(action: { shiftMonth(1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isFutureMonth ? MasoColor.textFaint : MasoColor.text)
                    .frame(width: 32, height: 32)
                    .background(MasoColor.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFutureMonth)
            .accessibilityLabel("Next month")

            // 收起回单行 strip — chevron.up 显式 affordance.
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) { isCollapsed = true }
                Haptics.tap()
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 32, height: 32)
                    .background(MasoColor.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse calendar")
        }
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = LanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: monthAnchor)
    }

    private var isFutureMonth: Bool {
        let comps = calendar.dateComponents([.year, .month], from: Date())
        let curMonth = calendar.date(from: comps) ?? Date()
        return monthAnchor >= curMonth
    }

    private func shiftMonth(_ delta: Int) {
        guard delta != 0,
              let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        let comps = calendar.dateComponents([.year, .month], from: next)
        let newAnchor = calendar.date(from: comps) ?? next
        // 先 set 方向 (transition 决定哪边滑入靠它), 再 withAnimation 改 anchor — 顺序反了
        // SwiftUI 会用旧 direction 跑动画.
        lastShiftDirection = delta >= 0 ? 1 : -1
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            monthAnchor = newAnchor
        }
        Haptics.tap()
    }

    @ViewBuilder
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdaySymbol(i))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(MasoColor.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekdaySymbol(_ i: Int) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.currentLocale
        let veryShort = f.veryShortStandaloneWeekdaySymbols ?? f.veryShortWeekdaySymbols ?? []
        let idx = (calendar.firstWeekday - 1 + i) % 7
        return idx < veryShort.count ? veryShort[idx] : ""
    }

    // DESIGN.md §2.2: expanded view 的周缩写 — kicker 规格 10pt bold + tracking

    private func weekdaySymbolForDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.currentLocale
        let veryShort = f.veryShortStandaloneWeekdaySymbols ?? f.veryShortWeekdaySymbols ?? []
        let weekday = calendar.component(.weekday, from: date)
        let idx = (weekday - 1) % 7
        return idx < veryShort.count ? veryShort[idx] : ""
    }

    @ViewBuilder
    private var monthGrid: some View {
        let cells = makeMonthCells()
        VStack(spacing: 4) {
            ForEach(0..<cells.count/7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let cell = cells[row*7 + col]
                        dayCell(cell)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCell) -> some View {
        switch cell {
        case .empty:
            Color.clear.frame(height: 40)
        case .day(let date, let inMonth):
            let isWorkout = sessionDates.contains(date)
            let isToday = date == today
            let dots = musclesPerDay[date] ?? []
            VStack(spacing: 3) {
                ZStack {
                    if isWorkout {
                        Circle().fill(MasoColor.accent)
                    } else if isToday {
                        Circle().stroke(MasoColor.accent.opacity(0.5), lineWidth: 0.5)
                    }
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: isWorkout ? .heavy : .semibold))
                        .foregroundStyle(
                            isWorkout ? .black
                            : (!inMonth ? MasoColor.textFaint
                               : (isToday ? MasoColor.accent : MasoColor.text))
                        )
                }
                .frame(width: 28, height: 28)
                // 肌群 dots — 最多 3 个, 每个 4pt 圆点. 没训练 → 空占位 (避免高度跳).
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < dots.count ? dots[i] : .clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
        }
    }

    private enum DayCell {
        case empty
        case day(Date, inMonth: Bool)
    }

    private func makeMonthCells() -> [DayCell] {
        let first = monthAnchor
        let weekdayOfFirst = calendar.component(.weekday, from: first)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let range = calendar.range(of: .day, in: .month, for: first) ?? 1..<2
        let dayCount = range.count
        var cells: [DayCell] = Array(repeating: .empty, count: leading)
        for d in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: d, to: first) {
                cells.append(.day(calendar.startOfDay(for: date), inMonth: true))
            }
        }
        while cells.count < 42 { cells.append(.empty) }
        if cells.count >= 42, cells[35..<42].allSatisfy({ if case .empty = $0 { return true } else { return false } }) {
            cells = Array(cells[0..<35])
        }
        if cells.count >= 35, cells[28..<35].allSatisfy({ if case .empty = $0 { return true } else { return false } }) {
            cells = Array(cells[0..<28])
        }
        return cells
    }

    // MARK: - 本周 7 天 (collapsed strip)
    // (stats 不在这里了 — 现在由 HistoryScreen 直接渲染在 calendar 之上)


    /// 返回包含 `today` 的那一周 7 天 (跟 calendar.firstWeekday 走, e.g. 周一开始).
    private func currentWeekDays() -> [Date] {
        let cal = calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        guard let weekStart = cal.date(from: comps) else { return [] }
        return (0..<7).compactMap { i in
            cal.date(byAdding: .day, value: i, to: weekStart).map { cal.startOfDay(for: $0) }
        }
    }
}

/// The workout calendar uses the same rendering and full-history sheet as Diet/Sleep.
struct WorkoutMonthDotStrip: View {
    @Environment(DataStore.self) private var data
    let sessionDates: Set<Date>
    let calendar: Calendar
    var body: some View {
        PerformanceMonthDotStrip(snapshot: .workout(sessionDates, calendar: calendar), calendar: calendar, showRecovery: data.settings.showCalendarRecovery ?? false)
    }
}

struct LifestyleCalendarCard: View {
    @Environment(DataStore.self) private var data
    let kind: PerformanceCalendarSnapshot.Kind
    var body: some View {
        PerformanceMonthDotStrip(snapshot: .lifestyle(kind: kind, settings: data.settings, healthSleep: HealthKitService.shared.sleepMinutes), calendar: data.settings.calendar)
            .glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}

private extension PerformanceCalendarSnapshot.Kind {
    var accent: Color {
        switch self { case .workout: MasoColor.accent; case .diet: MasoColor.dietAccent; case .sleep: MasoColor.sleepAccent }
    }
    var title: LocalizedStringKey {
        switch self { case .workout: "Workout calendar"; case .diet: "Diet calendar"; case .sleep: "Sleep calendar" }
    }
}

struct PerformanceMonthDotStrip: View {
    let snapshot: PerformanceCalendarSnapshot
    let calendar: Calendar
    var showRecovery = false
    @State private var expanded = false
    private var months: [Date] {
        guard let current = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }
        let oldest = snapshot.earliestDay.flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? current
        let count = max(11, calendar.dateComponents([.month], from: oldest, to: current).month ?? 0)
        return (0...count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }
    var body: some View {
        GeometryReader { geometry in
            let gap = MasoMetrics.cardPadding
            let width = max(1, (geometry.size.width - 2 * MasoMetrics.cardPadding - 2 * gap) / 3)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: gap) {
                    ForEach(months, id: \.self) { month in
                        VStack(spacing: MasoMetrics.cardHeaderGap * 2) {
                            Text(month.formatted(calendar.isDate(month, equalTo: Date(), toGranularity: .year) ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).year()))
                                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            PerformanceMonthGrid(month: month, snapshot: snapshot, calendar: calendar, expanded: false, showRecovery: showRecovery)
                        }.frame(width: width)
                    }
                }.scrollTargetLayout().padding(MasoMetrics.cardPadding)
            }.scrollIndicators(.hidden).defaultScrollAnchor(.trailing).scrollTargetBehavior(.viewAligned)
        }
        .frame(height: 160)
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .accessibilityLabel(snapshot.kind.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("View all months")
        .accessibilityAction { expanded = true }
        .sheet(isPresented: $expanded) {
            PerformanceCalendarSheet(snapshot: snapshot, calendar: calendar, showRecovery: showRecovery)
        }
    }
}

private struct PerformanceMonthGrid: View {
    let month: Date
    let snapshot: PerformanceCalendarSnapshot
    let calendar: Calendar
    let expanded: Bool
    var showRecovery = false
    @State private var shareDay: Date?
    private var offset: Int { (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7 }
    private var days: Int { calendar.range(of: .day, in: .month, for: month)?.count ?? 0 }
    var body: some View {
        VStack(spacing: expanded ? 8 : 0) {
            if expanded {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(0..<42, id: \.self) { index in
                    let number = index - offset + 1
                    if number > 0 && number <= days,
                       let date = calendar.date(byAdding: .day, value: number - 1, to: month) {
                        dot(date, number: number)
                    } else { Color.clear.frame(height: expanded ? 44 : 7).accessibilityHidden(true) }
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareDay != nil }, set: { if !$0 { shareDay = nil } })) {
            if let day = shareDay { PerformanceShareSheet(snapshots: [snapshot], calendar: calendar, start: day, end: day) }
        }
    }
    private func dot(_ date: Date, number: Int) -> some View {
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        let progress = day <= today ? snapshot.progress[day] : nil
        let current = calendar.isDateInToday(date)
        let recovery = showRecovery ? snapshot.recoveryFraction(on: day, calendar: calendar) : nil
        let diameter: CGFloat = expanded ? (progress != nil || current ? 14 : 8) : (progress != nil || current ? 7 : 5)
        return VStack(spacing: expanded ? 5 : 0) {
            Circle()
                .fill(progress.map { snapshot.kind.accent.opacity(GoalCompletionAppearance.opacity($0)) } ?? (current ? Color.clear : Color.white.opacity(day > today ? 0.12 : 0.3)))
                .frame(width: diameter, height: diameter)
                .overlay { if current { Circle().strokeBorder(Color.white, lineWidth: 1.5) } }
                .overlay(alignment: .bottom) {
                    if let recovery {
                        Capsule().fill(MasoColor.accent)
                            .frame(width: (expanded ? 14 : 7) * recovery, height: expanded ? 3 : 2)
                            .offset(y: expanded ? 5 : 3)
                    }
                }
            if expanded { Text("\(number)").font(.caption2).foregroundStyle(day > today ? .tertiary : .secondary) }
        }
        .frame(height: expanded ? 44 : 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.month().day().year()))
        .accessibilityValue(recovery != nil ? Text("Recovery day") : value(progress))
        .contentShape(Rectangle())
        .onTapGesture { if expanded && day <= today { shareDay = day } }
        .accessibilityHint(expanded ? "Share day" : "")
        .accessibilityAction { if expanded && day <= today { shareDay = day } }
    }
    private func value(_ progress: Double?) -> Text {
        if snapshot.kind == .workout { return Text(progress != nil ? "Workout recorded" : "No workout") }
        if let progress { return Text("\(Int((progress * 100).rounded(.down)))%") }
        return Text("No data")
    }
}

private struct PerformanceCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: PerformanceCalendarSnapshot
    let calendar: Calendar
    var showRecovery = false
    @State private var visibleMonths = 12
    @State private var explanationPresented = false
    private var months: [Date] {
        guard let current = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }
        return (0..<visibleMonths).compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }
    var body: some View {
        AppNavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
                    legend
                    Text("Tap a day to share").font(.caption).foregroundStyle(.secondary)
                    ForEach(months, id: \.self) { month in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                                Spacer()
                                PerformanceShareButton(snapshots: [snapshot], calendar: calendar, month: month)
                            }
                            PerformanceMonthGrid(month: month, snapshot: snapshot, calendar: calendar, expanded: true, showRecovery: showRecovery)
                        }
                        .cardChrome()
                        .onAppear { if month == months.last { visibleMonths += 12 } }
                    }
                }
                .padding(MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background)
            .navigationTitle(snapshot.kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CombinedPerformanceShareButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(MasoColor.text) }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
        .sheet(isPresented: $explanationPresented) {
            AppNavigationStack {
                Form {
                    Section {
                        Text(snapshot.kind == .workout ? "Green marks workout days." : (snapshot.kind == .diet ? "Color strength shows your three-macro target progress." : "Color strength shows your sleep-duration progress."))
                        if snapshot.kind != .workout {
                            Text("Grey means no record or no target. Saved daily targets are used when available; otherwise your current target is used.")
                        }
                    }
                }
                .navigationTitle("Calendar colors")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { explanationPresented = false }.tint(MasoColor.text)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            legendRow(snapshot.kind == .workout ? "Workout recorded" : "Goal met", color: snapshot.kind.accent)
            if snapshot.kind != .workout {
                legendRow("In progress", color: snapshot.kind.accent.opacity(0.45))
            }
            if snapshot.kind == .workout && showRecovery { legendRow("Recovery day", color: snapshot.kind.accent.opacity(0.6)) }
            legendRow(snapshot.kind == .workout ? "No workout" : "No data", color: .white.opacity(0.3))
            HStack(spacing: 8) {
                Circle().strokeBorder(.white, lineWidth: 1.5).frame(width: 9, height: 9)
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Button { explanationPresented = true } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .tint(MasoColor.textDim)
                .accessibilityLabel("Calendar colors")
            }
        }
    }

    private func legendRow(_ title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct MonthlyWorkoutShareButton: View {
    let month: Date
    let sessionDates: Set<Date>
    let calendar: Calendar
    var body: some View {
        PerformanceShareButton(snapshots: [.workout(sessionDates, calendar: calendar)], calendar: calendar, month: month)
    }
}

struct PerformanceShareButton: View {
    let snapshots: [PerformanceCalendarSnapshot]
    let calendar: Calendar
    let month: Date
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { ShareIcon() }
            .nativeGlassButtonStyle().controlSize(.small)
            .tint(MasoColor.text).accessibilityLabel("Share month")
            .sheet(isPresented: $presented) {
                let interval = calendar.dateInterval(of: .month, for: month)!
                PerformanceShareSheet(snapshots: snapshots, calendar: calendar, start: interval.start,
                                      end: min(Date(), interval.end.addingTimeInterval(-1)))
            }
    }
}

/// Shared period chooser available inside the calendar, leaving Workout's main toolbar uncluttered.
struct CombinedPerformanceShareButton: View {
    @Environment(DataStore.self) private var data
    @State private var presented = false
    private var snapshots: [PerformanceCalendarSnapshot] {
        [.workout(data.recordedWorkoutDates(), calendar: data.settings.calendar),
         .lifestyle(kind: .diet, settings: data.settings),
         .lifestyle(kind: .sleep, settings: data.settings, healthSleep: HealthKitService.shared.sleepMinutes)]
    }
    var body: some View {
        Button { presented = true } label: { Label("Share overview", systemImage: "square.and.arrow.up") }
            .tint(MasoColor.text)
            .sheet(isPresented: $presented) {
                PerformanceShareSheet(snapshots: snapshots, calendar: data.settings.calendar,
                                      start: data.settings.calendar.date(byAdding: .day, value: -6, to: Date())!, end: Date(), allowsRange: true)
            }
    }
}

struct PerformanceShareSheet: View {
    let snapshots: [PerformanceCalendarSnapshot]
    let calendar: Calendar
    @State var start: Date
    @State var end: Date
    var allowsRange = false
    var completeDailyRecords = false
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var data
    @Environment(TrainingSessionStore.self) private var training
    @State private var sharedImage: FullPageExport?
    @State private var failed = false
    @State private var range = 7
    @State private var cardSelection = ShareCardSelection()
    @ViewBuilder private var card: some View {
        if completeDailyRecords && calendar.isDate(start, inSameDayAs: end) {
            DailyRecordShareCard(day: start).environment(data).environment(training)
        } else {
            PerformancePeriodShareCard(snapshots: snapshots, calendar: calendar, start: start, end: end,
                settings: data.settings, sets: data.sets, healthSleep: HealthKitService.shared.sleepMinutes)
        }
    }
    var body: some View {
        AppNavigationStack {
            ScrollView {
                if allowsRange {
                    Picker("Period", selection: $range) {
                        Text("Last 7 days").tag(7)
                        Text("Last 30 days").tag(30)
                        Text("This month").tag(0)
                        Text("Custom").tag(-1)
                    }.pickerStyle(.menu).tint(MasoColor.text)
                        .onChange(of: range) { _, value in
                            if value >= 0 {
                                end = Date()
                                start = value == 0 ? calendar.dateInterval(of: .month, for: end)!.start : calendar.date(byAdding: .day, value: 1-value, to: end)!
                            }
                        }
                    if range == -1 {
                        DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                        DatePicker("To", selection: $end, in: start...Date(), displayedComponents: .date)
                    }
                }
                card.shareSelection(cardSelection, editing: true).padding(.vertical, 16)
            }.padding(.horizontal, allowsRange ? 16 : 0)
                .background(MasoColor.background)
                .navigationTitle("Share").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Share") {
                            if let image = ShareImageRenderer.render({ card.shareSelection(cardSelection, editing: false) }) {
                                sharedImage = FullPageExport(items: [image])
                            } else { failed = true }
                        }.disabled(!cardSelection.canShare)
                    }
                }.tint(MasoColor.text)
                .sheet(item: $sharedImage) { result in
                    ActivityViewController(activityItems: result.items) { done in
                        if done { Analytics.shared.track("workout_share", ["surface": .string("performance_period")]) }
                    }
                }
                .alert("Couldn’t prepare share", isPresented: $failed) { Button("OK", role: .cancel) {} }
        }.presentationDetents([.large])
    }
}

/// A complete day, using the same readonly cards as the calendar detail page.
struct DailyRecordShareCard: View {
    let day: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
            Text(day.formatted(.dateTime.month(.wide).day().year().locale(LanguageManager.currentLocale)))
                .font(.title2.bold()).foregroundStyle(MasoColor.text)
            DailyRecordCards(day: day, sharing: true)
            }.padding(ShareLayout.contentInset)
            ShareCardFooter(qrPayload: MasoLinks.appStore, qrSize: 64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MasoColor.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, LanguageManager.currentLocale)
    }
}

private struct PerformancePeriodShareCard: View {
    let snapshots: [PerformanceCalendarSnapshot]
    let calendar: Calendar
    let start: Date
    let end: Date
    let settings: UserSettings
    let sets: [SetRecord]
    let healthSleep: [Date: Double]
    private var first: Date { calendar.startOfDay(for: start) }
    private var last: Date { calendar.startOfDay(for: min(end, Date())) }
    private var days: Int { max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0)+1) }
    private var isMonth: Bool { first == calendar.dateInterval(of: .month, for: first)?.start && calendar.isDate(first, equalTo: last, toGranularity: .month) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
            if calendar.isDate(first, inSameDayAs: last) {
                Text(first, format: .dateTime.month(.wide).day().year()).font(.title2.bold())
            } else if isMonth {
                Text(first, format: .dateTime.month(.wide).year()).font(.title2.bold())
            } else {
                Text(first.formatted(.dateTime.year().month(.abbreviated).day().locale(LanguageManager.currentLocale)) + " – " + last.formatted(.dateTime.year().month(.abbreviated).day().locale(LanguageManager.currentLocale))).font(.headline)
            }
            ForEach(snapshots.indices, id: \.self) { index in
                ShareSelectableCard(id: "period-\(snapshots[index].kind)", title: NSLocalizedString(snapshots[index].kind == .workout ? "Workout" : snapshots[index].kind == .diet ? "Diet" : "Sleep", comment: "")) {
                    summary(snapshots[index])
                }
            }
            }.padding(ShareLayout.contentInset)
            ShareCardFooter(qrPayload: MasoLinks.appStore, qrSize: 64)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(MasoColor.background).environment(\.colorScheme, .dark)
            .environment(\.locale, LanguageManager.currentLocale)
            .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight)
    }
    @ViewBuilder private func summary(_ snapshot: PerformanceCalendarSnapshot) -> some View {
        let entries = PerformanceShareSummary.entries(snapshot, start: start, end: end, calendar: calendar)
        let total: Double = entries.values.reduce(0.0) { $0 + $1 }
        let average: Int = entries.isEmpty ? 0 : Int((total / Double(entries.count) * 100.0).rounded())
        let numberSize: CGFloat = snapshots.count > 1 ? 36 : 48
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey(snapshot.kind == .workout ? "Workout" : snapshot.kind == .diet ? "Diet" : "Sleep")).font(.headline)
                    if snapshot.kind == .workout {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(entries.count)").font(.system(size: snapshots.count > 1 ? 36 : 56, weight: .bold, design: .rounded)).foregroundStyle(snapshot.kind.accent)
                            Text("Days trained").foregroundStyle(.secondary)
                        }
                    } else if entries.isEmpty {
                        Text("No data").font(.title2).foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(average)%").font(.system(size: numberSize, weight: .bold, design: .rounded)).foregroundStyle(snapshot.kind.accent)
                            Text(LocalizedStringKey(days == 1 ? "Target progress" : "Average target progress")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(String(format: NSLocalizedString("%lld of %lld days recorded", comment: ""), entries.count, days)).font(.caption).foregroundStyle(.secondary)
                    }
                    if days == 1 { dailyDetails(snapshot.kind) } else { periodDetails(snapshot.kind) }
                    if isMonth {
                        PerformanceMonthGrid(month: first, snapshot: snapshot, calendar: calendar, expanded: snapshots.count == 1).allowsHitTesting(false)
                    } else if days > 1 {
                        // No missing record is presented as success: unknown days remain grey.
                        periodDots(snapshot)
                    }
                }
    }
    private func periodDots(_ snapshot: PerformanceCalendarSnapshot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
            ForEach(0..<days, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: first)!
                Circle().fill(dotColor(snapshot, day: day)).frame(width: 14, height: 14)
            }
        }
    }
    private func dotColor(_ snapshot: PerformanceCalendarSnapshot, day: Date) -> Color {
        guard let value = snapshot.progress[day] else { return Color.white.opacity(0.2) }
        return snapshot.kind.accent.opacity(GoalCompletionAppearance.opacity(value))
    }
    @ViewBuilder private func dailyDetails(_ kind: PerformanceCalendarSnapshot.Kind) -> some View {
        switch kind {
        case .workout:
            let records = sets.filter { calendar.isDate($0.performedAt, inSameDayAs: first) && $0.performedAt <= Date() }
            HStack {
                Text("Sets"); Spacer(); Text("\(records.count)").monospacedDigit()
            }.foregroundStyle(.secondary)
        case .diet:
            let meals = (settings.mealCheckIns ?? []).filter { calendar.isDate($0.day, inSameDayAs: first) && $0.confirmedAt <= Date() && $0.mealTime <= Date() }
            HStack(spacing: 16) {
                dailyMacro("Protein", meals.reduce(0) { $0 + $1.nutrition.protein })
                dailyMacro("Carbs", meals.reduce(0) { $0 + $1.nutrition.carbs })
                dailyMacro("Fat", meals.reduce(0) { $0 + $1.nutrition.fat })
            }
        case .sleep:
            let key = SleepPreferences.dayKey(first, calendar: calendar)
            if let minutes = healthSleep[first] ?? settings.sleepRecords?[key], minutes.isFinite, minutes >= 0 {
                HStack { Text("Total sleep"); Spacer(); Text("\(Int(minutes)/60)h\(Int(minutes)%60)m").monospacedDigit() }.foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func periodDetails(_ kind: PerformanceCalendarSnapshot.Kind) -> some View {
        switch kind {
        case .workout:
            let records = sets.filter { $0.performedAt >= first && $0.performedAt < calendar.date(byAdding: .day, value: 1, to: last)! && $0.performedAt <= Date() }
            HStack { Text("Sets"); Spacer(); Text("\(records.count)").monospacedDigit() }.foregroundStyle(.secondary)
        case .diet:
            let meals = (settings.mealCheckIns ?? []).filter { $0.day >= first && $0.day < calendar.date(byAdding: .day, value: 1, to: last)! && $0.confirmedAt <= Date() && $0.mealTime <= Date() }
            let count = Set(meals.map { calendar.startOfDay(for: $0.day) }).count
            if count > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average per recorded day").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        dailyMacro("Protein", meals.reduce(0.0) { $0 + $1.nutrition.protein } / Double(count))
                        dailyMacro("Carbs", meals.reduce(0.0) { $0 + $1.nutrition.carbs } / Double(count))
                        dailyMacro("Fat", meals.reduce(0.0) { $0 + $1.nutrition.fat } / Double(count))
                    }
                }
            }
        case .sleep:
            let values = sleepValues
            if !values.isEmpty {
                let minutes = Int((values.reduce(0.0,+) / Double(values.count)).rounded())
                HStack { Text("Average per recorded day"); Spacer(); Text("\(minutes/60)h\(minutes%60)m").monospacedDigit() }.font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var sleepValues: [Double] {
        var records: [Date: Double] = [:]
        for (key, minutes) in settings.sleepRecords ?? [:] {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) { records[day] = minutes }
        }
        for (day, minutes) in healthSleep { records[calendar.startOfDay(for: day)] = minutes }
        return records.filter { $0.key >= first && $0.key <= last && $0.value.isFinite && $0.value >= 0 }.map(\.value)
    }
    private func dailyMacro(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(value.rounded())) g").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

}


struct PerformanceDayShareButton: View {
    @Environment(DataStore.self) private var data
    let kind: PerformanceCalendarSnapshot.Kind
    let day: Date
    var usesSavedTargetOnly = false
    @State private var presented = false
    private var snapshot: PerformanceCalendarSnapshot {
        data.dailyRecordSnapshots(usesSavedTargetOnly: usesSavedTargetOnly).first { $0.kind == kind }
            ?? .init(kind: kind, progress: [:])
    }
    var body: some View {
        Button { presented = true } label: { ShareIcon() }
            .nativeGlassButtonStyle().controlSize(.small).tint(MasoColor.text)
            .accessibilityLabel("Share day")
            .sheet(isPresented: $presented) {
                PerformanceShareSheet(snapshots: [snapshot], calendar: data.settings.calendar, start: day, end: day)
            }
    }
}
