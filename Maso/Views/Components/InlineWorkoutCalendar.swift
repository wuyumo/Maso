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

    @State private var monthAnchor: Date = startOfCurrentMonth()
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
        // 卡片样式: surface 底色 + 圆角. clipShape 顺便完成动画期间的 overflow 裁剪 (不再单独 .clipped()).
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
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

// MARK: - 私有 helper

/// 顶层 helper — 给 @State 默认值用 (不能调 self.func, 也不能用 private extension 的 method).
private func startOfCurrentMonth() -> Date {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: Date())
    return cal.date(from: comps) ?? Date()
}
