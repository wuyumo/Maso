import SwiftUI
import StoreKit

// 训练状态页 — 显示 7 天活跃肌群 + 训练记录卡片
//
// 卡片设计: 按 "训练计划 (plan)" 维度展示, 而不是按动作组拆分.
// 一张卡片 = 一次完整的训练 session (同一 planId + 同一 calendar 日).
// 没有 planId 的记录 (自由训练) 单独成卡, kicker 显示训练日期, 标题 "Free workout".
//
// 点卡片 → 打开 session 详情 sheet, 可查看每个动作的组数 + 再次训练.
struct HistoryScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subs
    /// 点 "再次训练" 时回调到 RootView, 用统一的 startTraining 入口启动
    let onReplay: (Plan) -> Void
    /// 右上角齿轮 → 弹 Settings sheet (RootView 持有 sheet state)
    let onOpenSettings: () -> Void

    @State private var selectedSession: SessionSummary?
    /// 7 天前的训练记录默认收折, 用户点 "Show older" 才展开.
    /// 7 天最近的训练对用户更相关 (回顾、规划), 更早的 long tail 不需要默认展开.
    @State private var showOlderSessions: Bool = false
    /// 长按 → contextMenu Delete → 二次确认 alert. 存待删 session (planId + day) 区分.
    @State private var pendingDeleteSession: SessionSummary? = nil
    /// 训练日历的展开 / 收起态.
    /// 默认 true (收起单行 strip) — 让用户进 tab 第一眼看到的是训练记录, 而不是日历占满一屏.
    /// 用户点 strip 主动展开; scroll 也会强制 collapse. 收起后不再自动展开 — 完全用户主导.
    @State private var calendarCollapsed: Bool = true
    /// 日历展开后当前显示的月份 (月初). 顶部 metrics 在展开态严格按这个月份算 —— 翻到上个月,
    /// metrics 就是上个月的. 收起时重置回当前月 → 重开默认回到本月, 不停在上次翻到的月份.
    @State private var calendarMonthAnchor: Date = historyCurrentMonthStart()
    /// 顶部 ProBanner tap → 弹 paywall. 从 Today tab 挪过来 — History 用户回顾训练时
    /// 自然产生"想看更多数据/解锁高级功能"的动机, banner 放这比放在 Today 干扰训练流程更顺.
    @State private var paywallPresented: Bool = false


    /// ProBanner kicker 的"起步价/月" — 取 yearly product 月均价 (年价 ÷ 12), locale-aware.
    /// product 还没 load 出来时返回 nil → banner 只显示 "MASO PRO", 不写死假价格.
    private var proFromPrice: String? {
        guard let yearly = subs.product(for: .yearly) else { return nil }
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    var body: some View {
        // 单一 ScrollView, 跟 PlansScreen 同款行为:
        //   - stats + calendar 是 scroll content 的一部分, 跟 session 列表一起滚动
        //   - 用户向上滑 → 标题从 large 收成 inline, headbar 出系统 material blur
        //   - ScrollView 到顶后向下拖 (overscroll) → calendar 从 strip 展开成月
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Pro 展示位 — Pro 用户隐藏. 从 Today tab 搬过来 (Today 是训练入口, 不放营销卡;
                // History 是用户主动来"看数据回顾"时, 看到 Pro 升级提示更自然).
                if !data.settings.isPro {
                    ProBanner(fromPrice: proFromPrice) { paywallPresented = true }
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                        .padding(.top, 4)
                }

                // 顶端 3 metrics + 训练日历 — 合成同一张卡, 中间用分割线隔开.
                VStack(spacing: 0) {
                    // 3 metrics (跟着 calendar 状态切本周 / 本月口径)
                    statsRow
                        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: calendarCollapsed)

                    // 分割线 — 隔开 metrics 与日历, 左右内缩跟 iOS 列表分割线一致.
                    Rectangle()
                        .fill(MasoColor.borderSoft)
                        .frame(height: 0.5)
                        .padding(.horizontal, 12)

                    // 训练日历 — 默认 7 天 strip, 点 strip / chevron 展开整月. embedded → 不自带卡片底.
                    InlineWorkoutCalendar(
                        sessionDates: workoutDateSet(),
                        musclesPerDay: musclesPerDayMap(),
                        isCollapsed: $calendarCollapsed,
                        monthAnchor: $calendarMonthAnchor,
                        embedded: true
                    )
                }
                .background(MasoColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                // 训练记录列表
                let allSessions = groupedSessions()
                if allSessions.isEmpty {
                    Text("No workouts yet")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.vertical, 56)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    let cutoff = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
                    let recent = allSessions.filter { $0.day >= cutoff }
                    let older = allSessions.filter { $0.day < cutoff }

                    VStack(spacing: 12) {
                        ForEach(recent) { session in
                            sessionCardRow(session)
                        }
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    if !older.isEmpty {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) { showOlderSessions.toggle() }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: showOlderSessions ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .heavy))
                                Text(showOlderSessions
                                     ? NSLocalizedString("Hide older workouts", comment: "")
                                     : String(format: NSLocalizedString("Show %d older workout(s)", comment: ""), older.count))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(MasoColor.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(MasoColor.surface.opacity(0.5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                        if showOlderSessions {
                            VStack(spacing: 12) {
                                ForEach(older) { session in
                                    sessionCardRow(session)
                                }
                            }
                            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
        }
        // (撤销 scroll-based 展开/收起 — 现在完全交给用户主动点击 strip / chevron 控制)
        // 页面底色 #121212 — 跟 Plans / Today 一致, 不再透出 NavigationStack 默认纯黑底.
        // ignoresSafeArea 让底色延伸到 home indicator 区. NavigationStack 的 large title /
        // material blur 仍正常叠在这个底色之上 (跟 Plans 同视觉).
        .background(MasoColor.background.ignoresSafeArea())
        // B2: 收起→重新展开时把日历重置回当前月 (不停在上次翻到的月份). 在展开瞬间重置 —
        // expandedView 是全新插入, 直接渲染当前月, 没有 grid 滑动残影.
        .onChange(of: calendarCollapsed) { _, collapsed in
            if !collapsed { calendarMonthAnchor = historyCurrentMonthStart() }
        }
        .screenHeader("History") {
            // 分享训练总览 — 直接进 customize 预览 (跟训练详情 / 日历页同一套分享模式):
            // 所有有数据的 section 默认全开 (最近一次训练 + 本周肌肉状态 + 本周日历),
            // 用户在卡内关掉不想要的, 点 Share 才弹系统分享. 没数据的 section 整节不出现.
            historyShareButton
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
            }
            .accessibilityLabel("Settings")
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(
                session: session,
                exerciseStats: exerciseStats(for: session),
                replayPlan: replayPlan(for: session),
                onReplay: { plan in
                    selectedSession = nil
                    DispatchQueue.main.async { onReplay(plan) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
            .presentationDragIndicator(.visible)
        }
        // 删除 session 的二次确认 — 长按 SessionCard → contextMenu Delete 触发.
        // 删除是 destructive (清掉这场训练的所有 SetRecord, 包括 PR), 必须 confirm.
        .alert("Delete workout?", isPresented: Binding(
            get: { pendingDeleteSession != nil },
            set: { if !$0 { pendingDeleteSession = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let s = pendingDeleteSession {
                    data.deleteSession(planId: s.planId, day: s.day)
                }
                pendingDeleteSession = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSession = nil }
        } message: {
            Text("All sets and PRs from this workout will be removed. Your plans stay.")
        }
    }

    /// 单个 SessionCard + tap handler — 给 recent / older 两个 list 共享.
    /// 长按 → contextMenu Delete → alert 二次确认. (HistoryScreen 顶部有 muscle status hero card,
    /// 没改成 List, 所以用 contextMenu 替代右滑 — 删除能力一致.)
    @ViewBuilder
    private func sessionCardRow(_ session: SessionSummary) -> some View {
        SessionCard(
            session: session,
            photo: data.sessionPhoto(forSessionId: session.id),
            onReplay: replayPlan(for: session).map { plan in
                { onReplay(plan) }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedSession = session }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteSession = session
            } label: {
                Label {
                    Text("Delete workout")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - 顶部 3 metrics 卡 (跟 calendar 状态切换本周 / 本月)

    /// 顶部 stats row — 跟着 calendar 是 strip 还是月展示不同口径:
    ///   - 7 天 strip (collapsed): "Days this week / Current streak / Sets this week"
    ///   - 月 grid (expanded):   "Days this month / Current streak / Sets this month"
    /// Streak 跟两种状态都用一样 (是绝对的"连续天数"概念, 跟周/月无关).
    @ViewBuilder
    private var statsRow: some View {
        if calendarCollapsed {
            weeklyStatsCard
        } else {
            monthlyStatsCard
        }
    }

    /// 本周 stats — Days this week / Streak / Sets this week
    @ViewBuilder
    private var weeklyStatsCard: some View {
        let cal = data.settings.calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let weekStart = cal.date(from: comps) ?? Date()
        let weekDays: Set<Date> = Set((0..<7).compactMap {
            cal.date(byAdding: .day, value: $0, to: weekStart).map { cal.startOfDay(for: $0) }
        })
        let daysThisWeek = workoutDateSet().intersection(weekDays).count
        statsCard(
            value1: "\(daysThisWeek)", label1: "Days this week",
            value2: "\(currentStreakDays())", label2: "Current streak",
            value3: "\(setsThisWeekCount())", label3: "Sets this week"
        )
    }

    /// 本月 stats — Days this month / Streak / Sets this month.
    /// 严格按日历当前显示的月份 (calendarMonthAnchor) 算 — 翻到上个月, Days/Sets 就是上个月的.
    /// Streak 仍是"从今天往回数"的绝对连续天数 (标签写明 Current), 跟显示月份无关.
    @ViewBuilder
    private var monthlyStatsCard: some View {
        let cal = data.settings.calendar
        let monthDays: Set<Date> = workoutDateSet().filter {
            cal.isDate($0, equalTo: calendarMonthAnchor, toGranularity: .month)
        }
        statsCard(
            value1: "\(monthDays.count)", label1: "Days this month",
            value2: "\(currentStreakDays())", label2: "Current streak",
            value3: "\(setsThisMonthCount())", label3: "Sets this month"
        )
    }

    /// 共享 stats 卡渲染 — 三列, 浅 surface 底色, 圆角.
    private func statsCard(
        value1: String, label1: String,
        value2: String, label2: String,
        value3: String, label3: String
    ) -> some View {
        HStack(spacing: 14) {
            statColumn(value: value1, label: label1)
            statDivider
            statColumn(value: value2, label: label2)
            statDivider
            statColumn(value: value3, label: label3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        // 卡片底色/圆角交给外层合成卡 (stats + 日历 同一张卡).
    }

    private var statDivider: some View {
        Rectangle().fill(MasoColor.borderSoft).frame(width: 0.5, height: 28)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(MasoColor.accent)
            Text(LocalizedStringKey(label))
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 训练日历 helpers (InlineWorkoutCalendar 喂数据用)

    /// 用户有训练的日历日集合 (供 InlineWorkoutCalendar 高亮)
    private func workoutDateSet() -> Set<Date> {
        let cal = Calendar.current
        var out: Set<Date> = []
        for s in data.sets {
            out.insert(cal.startOfDay(for: s.performedAt))
        }
        return out
    }

    /// startOfDay → 当天命中的大肌群对应颜色 (最多 3 个).
    /// 不同肌群分到不同 accent 衍生色, 让用户一眼看到"这天练了 chest+arms+core".
    private func musclesPerDayMap() -> [Date: [Color]] {
        let cal = Calendar.current
        var bucket: [Date: [MuscleGroup]] = [:]
        var seenPerDay: [Date: Set<MuscleGroup>] = [:]
        for s in data.sets {
            let day = cal.startOfDay(for: s.performedAt)
            guard let ex = data.exById[s.exerciseId] else { continue }
            for m in ex.muscleGroups {
                // 折叠到大肌群 (e.g. upperChest → chest), 跟 picker / share 视觉一致
                let major = MuscleSelector.majorOf(m)
                var seen = seenPerDay[day] ?? []
                if seen.insert(major).inserted {
                    seenPerDay[day] = seen
                    bucket[day, default: []].append(major)
                }
            }
        }
        // 按 mapping 转 Color. 取前 3 (再多 dot 太挤).
        return bucket.mapValues { groups in
            groups.prefix(3).map { Self.muscleDotColor(for: $0) }
        }
    }

    /// 大肌群 → 日历 dot 颜色. 6 个主要 group 各分一个颜色, 其它 fallback accent.
    /// 选色: spotify 暗色背景下高对比 + 跟 accent 绿区分.
    private static func muscleDotColor(for m: MuscleGroup) -> Color {
        switch m {
        case .chest:     return Color(red: 1.0, green: 0.42, blue: 0.42)   // 暖红
        case .back:      return Color(red: 0.42, green: 0.78, blue: 1.0)   // 蓝
        case .shoulders: return Color(red: 1.0, green: 0.75, blue: 0.20)   // 黄橙
        case .biceps, .triceps, .forearms, .arms:
            return Color(red: 0.78, green: 0.55, blue: 1.0)                // 紫
        case .quads, .hamstrings, .glutes, .calves, .adductors, .legs:
            return Color(red: 0.20, green: 0.82, blue: 0.62)               // 绿松
        case .core:      return Color(red: 1.0, green: 0.55, blue: 0.85)   // 粉
        default:         return MasoColor.accent.opacity(0.7)
        }
    }

    /// 显示月份的组数 — 严格按 calendarMonthAnchor 所在月算 (展开态 metrics 用).
    private func setsThisMonthCount() -> Int {
        let cal = data.settings.calendar
        return data.sets.filter {
            cal.isDate($0.performedAt, equalTo: calendarMonthAnchor, toGranularity: .month)
        }.count
    }

    /// 本周组数 — collapsed strip 下面的 stats 用. 走 ISO 周 (yearForWeekOfYear)
    /// 跟 InlineWorkoutCalendar.currentWeekDays() 同样口径, 确保 days 跟 sets 同源.
    private func setsThisWeekCount() -> Int {
        // 走 settings.calendar — 跟 weekStartDay 偏好对齐 (周日 vs 周一)
        let cal = data.settings.calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let weekStart = cal.date(from: comps) else { return 0 }
        return data.sets.filter { $0.performedAt >= weekStart }.count
    }

    /// 当前连续训练天数 (从今天往回数, 直到遇到没训练的日子)
    private func currentStreakDays() -> Int {
        let cal = Calendar.current
        let days = workoutDateSet()
        let today = cal.startOfDay(for: Date())
        // P2-3: 今天还没练不该让连胜归零. 今天练了 → 从今天数; 今天没练但昨天练了 → 从昨天数
        // (连胜仍存活); 昨天也没练 → 真的断了 (0).
        var cursor = today
        if !days.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = cal.startOfDay(for: y)
            if !days.contains(cursor) { return 0 }
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = cal.startOfDay(for: prev)
        }
        return streak
    }

    /// 把 SetRecord 按 (planId, 日历日) 聚合成 session 卡; 按时间倒序返回
    // MARK: - 训练总览分享 (#history-share)

    /// 右上角分享 — UnifiedShareCard, 全 section 默认开 (照片占位 / 最近训练 / 肌肉状态 / 日历).
    private var historyShareButton: some View {
        let workoutData = historyWorkoutSection()
        let muscleData = historyMuscleSection()
        let calendarData = historyCalendarSection()
        return ShareImageButton(
            previewTitle: NSLocalizedString("My Training", comment: ""),
            defaultSections: ShareSections(todayStatus: true, workout: true, muscleStatus: true, calendar: true),
            shareContent: { photo, onTapAdd, mode in
                switch mode {
                case .editing(let binding):
                    UnifiedShareCard(
                        userPhoto: photo,
                        onTapAddPhoto: onTapAdd,
                        workoutSection: workoutData,
                        muscleStatusSection: muscleData,
                        calendarSection: calendarData,
                        editToggles: binding
                    )
                case .rendering(let visible):
                    UnifiedShareCard(
                        userPhoto: photo,
                        onTapAddPhoto: onTapAdd,
                        workoutSection: workoutData,
                        muscleStatusSection: muscleData,
                        calendarSection: calendarData,
                        visibleSections: visible
                    )
                }
            },
            label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .regular))
            }
        )
        .accessibilityLabel("Share")
    }

    /// 最近一次训练 — 没有任何记录时返回 nil, 该 section 整节不出现.
    private func historyWorkoutSection() -> WorkoutSectionData? {
        guard let s = groupedSessions().first else { return nil }
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return WorkoutSectionData(
            dateLabel: df.string(from: s.day),
            planName: s.planName ?? NSLocalizedString("Free workout", comment: ""),
            durationLabel: "~\(max(5, s.setCount * 2))m",
            setCount: s.setCount,
            exerciseCount: s.exerciseCount,
            prCount: s.prCount,
            muscles: s.muscles,
            exerciseNames: exerciseStats(for: s).prefix(4).map { $0.exercise.displayName }
        )
    }

    /// 本周肌肉状态 — 跟 SessionDetailSheet 的同名构造同一套 MuscleStatusCompute.
    private func historyMuscleSection() -> MuscleStatusSectionData {
        let fatigueMap = MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById)
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let weekSets = data.sets.filter { $0.performedAt >= cutoff }
        let days = Set(weekSets.map { cal.startOfDay(for: $0.performedAt) }).count
        var sections = Set<MuscleGroup>()
        for set in weekSets {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let sec = m.section { sections.insert(sec) }
            }
        }
        return MuscleStatusSectionData(
            muscleOpacity: { m in MuscleStatusCompute.opacityFor(muscle: m, fatigueMap: fatigueMap) },
            coarseOnly: !data.settings.muscleDetailEnabled,
            workoutsThisWeek: days,
            totalSetsThisWeek: weekSets.count,
            muscleSectionsHit: sections.count
        )
    }

    /// 本周训练日历 + 连胜.
    private func historyCalendarSection() -> CalendarSectionData {
        let cal = Calendar.current
        var dates: Set<Date> = []
        for s in data.sets { dates.insert(cal.startOfDay(for: s.performedAt)) }
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let weekSetCount = data.sets.filter { $0.performedAt >= cutoff }.count
        // 连胜 — 今天没练但昨天练了仍存活 (跟 stats strip 同语义)
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        if !dates.contains(cursor) {
            cursor = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: cursor)!)
        }
        while dates.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = cal.startOfDay(for: prev)
        }
        return CalendarSectionData(
            sessionDates: dates,
            totalSets: weekSetCount,
            streakDays: streak
        )
    }

    private func groupedSessions() -> [SessionSummary] {
        let cal = Calendar.current
        struct Key: Hashable { let planId: String; let day: Date }
        var bucket: [Key: [SetRecord]] = [:]
        var order: [Key] = []
        for rec in data.sets {
            let day = cal.startOfDay(for: rec.performedAt)
            let key = Key(planId: rec.planId ?? "free", day: day)
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(rec)
        }
        let summaries: [SessionSummary] = order.map { key in
            let recs = bucket[key] ?? []
            let planName: String? = {
                if key.planId == "free" { return nil }
                // plan 还在 → 用现名 (改名联动); 被删 → 记录里的落库名快照, 不退化"自由训练"
                return data.plans.first(where: { $0.id == key.planId })?.name
                    ?? recs.compactMap(\.planName).first
            }()
            let uniqueExercises = Set(recs.map { $0.exerciseId })
            var seenMuscles = Set<MuscleGroup>()
            var muscles: [MuscleGroup] = []
            for r in recs {
                guard let ex = data.exById[r.exerciseId] else { continue }
                for m in ex.muscleGroups where seenMuscles.insert(m).inserted {
                    muscles.append(m)
                }
            }
            let categories = Set(recs.map { $0.category })
            // 数这一场训练里 PR 的组数 — Epley 1RM 估算超过之前历史最高
            let prCount = recs.reduce(0) { $0 + (data.isPR($1) ? 1 : 0) }
            return SessionSummary(
                id: "\(key.planId)-\(Int(key.day.timeIntervalSince1970))",
                planId: key.planId == "free" ? nil : key.planId,
                day: key.day,
                planName: planName,
                exerciseCount: uniqueExercises.count,
                setCount: recs.count,
                muscles: muscles,
                categories: categories,
                lastPerformedAt: recs.map { $0.performedAt }.max() ?? key.day,
                prCount: prCount
            )
        }
        return summaries.sorted { $0.lastPerformedAt > $1.lastPerformedAt }
    }

    /// session 内每个动作的统计 (用于 detail sheet 的"动作列表"区)
    private func exerciseStats(for session: SessionSummary) -> [SessionExerciseStat] {
        let cal = Calendar.current
        let dayRecs = data.sets.filter { rec in
            let day = cal.startOfDay(for: rec.performedAt)
            let recPid = rec.planId ?? "free"
            let sessionPid = session.planId ?? "free"
            return day == session.day && recPid == sessionPid
        }
        // 按 exerciseId 分组并保持首次出现顺序 (匹配训练时的顺序)
        var order: [String] = []
        var buckets: [String: [SetRecord]] = [:]
        for r in dayRecs.sorted(by: { $0.performedAt < $1.performedAt }) {
            if buckets[r.exerciseId] == nil { order.append(r.exerciseId) }
            buckets[r.exerciseId, default: []].append(r)
        }
        return order.compactMap { exId in
            guard let recs = buckets[exId], let ex = data.exById[exId] else { return nil }
            // 取每组里最重的 weight × reps 作展示 (代表"最佳"那组)
            let bestWeight = recs.compactMap { $0.weight }.max()
            let bestReps = recs.compactMap { $0.reps }.max()
            let totalDuration = recs.compactMap { $0.duration }.reduce(0, +)
            return SessionExerciseStat(
                id: ex.id,
                exercise: ex,
                setCount: recs.count,
                bestWeight: bestWeight,
                bestReps: bestReps,
                totalDuration: totalDuration > 0 ? totalDuration : nil
            )
        }
    }

    /// 回放: 关联了 plan 的 session 直接拿原 plan; 自由训练的 session 从历史 set
    /// 合成一个临时 plan (复用 exerciseStats 拿到当天动作 + 每动作的 set 数 / reps / weight).
    /// 这样自由训练也能"再练一遍" — 跟 plan-based session 同款体验.
    /// 找出某 session 的可回放 plan. 走两条路:
    ///   1. session.planId 还存在于 data.plans 里 → 直接用原 plan (保留用户编辑后的最新版本)
    ///   2. 原 plan 已删除 / session 是自由训练 → 从 SetRecord 现合成一份 (中位数取动作负荷)
    /// 之前只在自由训练 case 走 synthesis, 导致用户删了 plan 后, 历史记录变得不能重播.
    /// 现在保证: 只要有 SetRecord, 这个 session 就能重播.
    private func replayPlan(for session: SessionSummary) -> Plan? {
        if let pid = session.planId, let plan = data.plans.first(where: { $0.id == pid }) {
            return plan
        }
        return synthesizeFreeReplayPlan(for: session)
    }

    /// 从 SetRecord 合成临时 Plan 用于回放. 不入 DataStore (id 固定 "session-replay-{sessionId}",
    /// 反复点不会污染 Plans 列表; PlanPlayer 通过 startTrainingNow 拿到 Plan 直接展开 segments).
    /// 支持两种情况:
    ///   - session 是自由训练 (planId == nil)
    ///   - session 原 plan 已删除 (planId != nil 但 data.plans 里查不到)
    ///
    /// 2026-05-24 改: 之前依赖 exerciseStats(for:) 拿 stats, 但 stats 里 compactMap 会把
    /// data.exById 里查不到的 exerciseId 过滤掉. 老用户 (iPhone 真机) 数据里有 v1 schema 的
    /// exerciseId 在 v2 库里没对应 (orphaned 572 个), 整 session 的 stats 就空了 → synthesis 返回 nil
    /// → replay 按钮不显示. 现在直接从 SetRecord 构造 steps, 不要求 exerciseId 能 resolve.
    /// PlanPlayer 拿不到 Exercise 时走 placeholder 兜底, 至少按钮总有.
    private func synthesizeFreeReplayPlan(for session: SessionSummary) -> Plan? {
        let cal = Calendar.current
        let dayRecs = data.sets.filter { rec in
            cal.startOfDay(for: rec.performedAt) == session.day && rec.planId == session.planId
        }
        guard !dayRecs.isEmpty else { return nil }

        // 按 exerciseId 分桶, 保持首次出现顺序 (匹配训练时的顺序)
        var order: [String] = []
        var perEx: [String: [SetRecord]] = [:]
        for r in dayRecs.sorted(by: { $0.performedAt < $1.performedAt }) {
            if perEx[r.exerciseId] == nil { order.append(r.exerciseId) }
            perEx[r.exerciseId, default: []].append(r)
        }

        var steps: [PlanStep] = []
        for (idx, exId) in order.enumerated() {
            guard let recs = perEx[exId], !recs.isEmpty else { continue }
            let reps: Int? = median(recs.compactMap { $0.reps })
            let weight: Double? = median(recs.compactMap { $0.weight }.map { Double($0) })
            let duration: Int? = median(recs.compactMap { $0.duration })
            steps.append(PlanStep(
                id: "step-replay-\(session.id)-\(idx)",
                exerciseId: exId,
                sets: recs.count,
                reps: reps,
                weight: weight,
                duration: duration,
                restBetweenSets: 90,
                rest: 0
            ))
        }
        guard !steps.isEmpty else { return nil }
        // 原 plan 被删但记录里有落库名快照 → 重练播放器/Live Activity 沿用真名,
        // 跟历史卡标题一致 (不然卡上 "Push Day", 点重练却变 "Free workout").
        let name = session.planName ?? NSLocalizedString("Free workout", comment: "")
        return Plan(
            id: "session-replay-\(session.id)",
            name: name,
            steps: steps,
            createdAt: session.day,
            updatedAt: Date()
        )
    }

    /// 整数 / Double 通用的中位数 helper. 空数组 → nil.
    private func median<T: Comparable & FloatingPoint>(_ arr: [T]) -> T? {
        guard !arr.isEmpty else { return nil }
        let sorted = arr.sorted()
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }
    private func median(_ arr: [Int]) -> Int? {
        guard !arr.isEmpty else { return nil }
        let sorted = arr.sorted()
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }
}

// MARK: - Session aggregation model

struct SessionSummary: Identifiable, Hashable {
    let id: String
    let planId: String?     // nil = 自由组
    let day: Date
    /// nil 表示自由组训练
    let planName: String?
    let exerciseCount: Int
    let setCount: Int
    let muscles: [MuscleGroup]
    let categories: Set<ExerciseCategory>
    let lastPerformedAt: Date
    /// 这一场训练里 PR 的组数 (Epley 1RM 估算超过历史最高). 0 = 没 PR.
    /// 渲染时 > 0 → SessionCard 右上角小🏆+ count, 不弹通知不庆祝 (理念 4 "沉默的进步反馈")
    var prCount: Int = 0
}

struct SessionExerciseStat: Identifiable, Hashable {
    let id: String
    let exercise: Exercise
    let setCount: Int
    let bestWeight: Double?
    let bestReps: Int?
    let totalDuration: Int?
}

// MARK: - SessionCard

private struct SessionCard: View {
    let session: SessionSummary
    /// 用户为该 session 加的照片 (DataStore.sessionPhoto). nil = 无照片, 不渲染缩略图.
    /// 卡片左侧渲染一个 48x48 圆角缩略图 — 跟 PlanRow / Exercise list 的 56pt thumbnail 同款大小区间,
    /// 但用户照片更 "个人化", 视觉上稍小一点低调.
    var photo: UIImage? = nil
    /// 点右下角播放按钮 → "再次训练这次的内容". nil 时不显示按钮.
    let onReplay: (() -> Void)?

    private var kicker: String {
        // 始终显示训练时间 (Today / Yesterday / X days ago / "5月8日"),
        // 即使是自由训练 — 之前 kicker 跟 title 都显示"自由训练"重复, 现在 kicker 是时间.
        prettyDay(session.day)
    }
    private var title: String {
        session.planName ?? NSLocalizedString("Free workout", comment: "")
    }
    private var subtitleLine: String {
        "\(pluralizedExercises(session.exerciseCount)) · \(pluralizedSets(session.setCount))"
    }

    var body: some View {
        // 统一布局 (跟 Plans PlanRow 同款), History 顶部多一行日期 kicker:
        //   行0: 日期 kicker (TODAY / YESTERDAY / ...)
        //   行1: title + 右箭头 (整行 tap 进 detail)
        //   行2: exercises · sets
        //   行3: [photo (有时)] [BodyHint 居中] [右下角 replay 按钮]
        //
        // 照片之前是 48×48 缩略图挂在 title 左侧, 现在挪到底部跟 BodyHint 并列 —
        // 让 muscle map + 训练照同时映入眼帘, 加强"训练日记"感.
        VStack(alignment: .leading, spacing: 6) {
            // History 独有: 训练日期
            Text(kicker.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                    // 删 minimumScaleFactor → 超长走默认 truncationMode .tail (...),
                    // 不再先缩小字号到 75% 才省略.
                // PR 标记 — 沉默的进步反馈 (理念 4): 不弹通知不庆祝, 一个小🏆 + 数字一眼可见
                if session.prCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text("\(session.prCount)")
                            .font(.system(size: 11, weight: .heavy).monospacedDigit())
                    }
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(MasoColor.accent.opacity(0.14))
                    .clipShape(Capsule())
                    .accessibilityLabel("\(session.prCount) personal records")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }

            Text(subtitleLine)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)

            // Muscle Map + replay 按钮 — ZStack(.bottomTrailing): muscle map 水平居中,
            // replay button 贴右下角. 按钮到卡片底 / 右 距离都 = cardPadding (16pt), 视觉对称.
            // ⚠️ PlanRow 同款布局, 改这里同步改 PlanRow.
            ZStack(alignment: .bottomTrailing) {
                // 居中层 — muscle map 水平居中
                HStack {
                    Spacer()
                    MuscleVisualBlock(
                        muscles: session.muscles,
                        sideLength: 100,
                        photo: photo
                    )
                    .fixedSize()
                    Spacer()
                }

                // Replay button — bottomTrailing 自动贴右下角, 32pt 跟 PlanRow 同款
                if let onReplay {
                    Button(action: onReplay) {
                        ZStack {
                            Circle()
                                .fill(MasoColor.accent.opacity(0.18))
                                .overlay(
                                    Circle().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5)
                                )
                                .frame(width: 32, height: 32)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(MasoColor.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat Workout")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MasoMetrics.cardPadding - 4)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}

// 复用 Theme/Formatters 的 relativeDay (Today / Yesterday / N days ago / "MMM d")
private func prettyDay(_ d: Date) -> String { relativeDay(d) }

// MARK: - SessionDetailSheet

private struct SessionDetailSheet: View {
    @Environment(DataStore.self) private var data
    let session: SessionSummary
    let exerciseStats: [SessionExerciseStat]
    /// 如果是基于 plan 的训练, 这里给出原 plan, 可以一键回放
    let replayPlan: Plan?
    let onReplay: (Plan) -> Void

    @Environment(\.dismiss) private var dismiss
    /// list ↔ grid 切换 — 跟 PlanDetailSheet 共享同一 @AppStorage key, 两个 sheet 偏好同步.
    @AppStorage("planStepCardLayout") private var useCardLayout: Bool = false
    /// 点图片 → 弹动作详情 sheet
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 — 待删 exerciseId. 二次确认 alert 触发实际删除.
    @State private var pendingDeleteExerciseId: String? = nil
    /// 加/换/删训练照片 — 跟 ShareCustomizeSheet 同款 confirmationDialog + PhotoPicker flow.
    @State private var showPhotoOptions: Bool = false
    @State private var activePicker: PhotoPickerSource? = nil
    @State private var pickedPhoto: UIImage? = nil
    @State private var isCameraAvailable: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        NavigationStack {
            // List + Section 让 stepListSection 里的 ForEach 能用原生 .swipeActions (不支持 onMove —
            // 历史时间顺序是 ground truth, 不允许重排). 跟 PlanDetailSheet 同模式, 用户跨 tab 体验一致.
            List {
                // 用户照片 banner — 有照片 tap 弹换/删 dialog; 没照片显示"加照片"占位也可点.
                // 视觉跟 share card 顶部的 SharePhotoBanner 同款 (1:1 正方形).
                Section {
                    sessionPhotoBlock
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    headerCard
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 20, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                exerciseStatsSection
                if let plan = replayPlan {
                    Section {
                        Button(action: { onReplay(plan) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                                Text("Repeat Workout").font(.system(size: 14, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MasoColor.accent)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 32, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
            .background(MasoColor.background.ignoresSafeArea())
            // 点图片弹详情 sheet
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
                .presentationDragIndicator(.visible)
            }
            // 加/换/删训练照片 dialog + picker — 跟 ShareCustomizeSheet 同一套 flow
            .confirmationDialog(
                NSLocalizedString("Add photo", comment: ""),
                isPresented: $showPhotoOptions,
                titleVisibility: .visible
            ) {
                if isCameraAvailable {
                    Button(NSLocalizedString("Take Photo", comment: "")) {
                        activePicker = .camera
                    }
                }
                Button(NSLocalizedString("Choose from Library", comment: "")) {
                    activePicker = .photoLibrary
                }
                if data.sessionPhoto(forSessionId: session.id) != nil {
                    Button(NSLocalizedString("Remove Photo", comment: ""), role: .destructive) {
                        data.removeSessionPhoto(forSessionId: session.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $activePicker) { source in
                PhotoPicker(image: $pickedPhoto, source: source)
                    .ignoresSafeArea()
                .presentationDragIndicator(.visible)
            }
            .onChange(of: pickedPhoto) { _, newPhoto in
                if let img = newPhoto {
                    data.setSessionPhoto(img, forSessionId: session.id)
                    pickedPhoto = nil   // 重置, 下次再 pick 还能触发 onChange
                }
            }
            // 右滑 / contextMenu 删除单个 exercise 的二次确认
            .alert("Delete exercise?", isPresented: Binding(
                get: { pendingDeleteExerciseId != nil },
                set: { if !$0 { pendingDeleteExerciseId = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let exId = pendingDeleteExerciseId {
                        data.deleteExerciseFromSession(
                            planId: session.planId,
                            day: session.day,
                            exerciseId: exId
                        )
                    }
                    pendingDeleteExerciseId = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteExerciseId = nil }
            } message: {
                Text("All sets of this exercise from this workout will be removed.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 分享这次训练 — 生成 UnifiedShareCard (workout section default on).
                    // 三个 section data 始终算好传入; toggle 状态由卡内 inline toggle / ShareCardMode 控制.
                    let workoutData = sessionWorkoutSection()
                    let muscleData = sessionMuscleStatusSection()
                    let calendarData = sessionCalendarSection()
                    ShareImageButton(
                        previewTitle: NSLocalizedString("My Workout", comment: ""),
                        defaultSections: ShareSections(workout: true),
                        initialPhoto: data.sessionPhoto(forSessionId: session.id),
                        shareContent: { photo, onTapAdd, mode in
                            switch mode {
                            case .editing(let binding):
                                UnifiedShareCard(
                                    userPhoto: photo,
                                    onTapAddPhoto: onTapAdd,
                                    workoutSection: workoutData,
                                    muscleStatusSection: muscleData,
                                    calendarSection: calendarData,
                                    editToggles: binding
                                )
                            case .rendering(let visible):
                                UnifiedShareCard(
                                    userPhoto: photo,
                                    onTapAddPhoto: onTapAdd,
                                    workoutSection: workoutData,
                                    muscleStatusSection: muscleData,
                                    calendarSection: calendarData,
                                    visibleSections: visible
                                )
                            }
                        },
                        onPersistPhoto: { image in
                            if let image {
                                data.setSessionPhoto(image, forSessionId: session.id)
                            } else {
                                data.removeSessionPhoto(forSessionId: session.id)
                            }
                        },
                        label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                        }
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            .tint(MasoColor.text)
        }
    }

    /// 训练照片 block — 有照片显示 240pt 正方形, 没照片显示"加照片" row (跟动作列表行同款 row 高度).
    @ViewBuilder
    private var sessionPhotoBlock: some View {
        if let photo = data.sessionPhoto(forSessionId: session.id) {
            // 已加照片: 严格 1:1 圆角正方形 — 用 Color.clear 强制 aspect ratio,
            // 图片 overlay 内 fill + clipped 裁中, 这样容器一定是正方形不会被父布局压扁.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                        .stroke(MasoColor.borderSoft, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { showPhotoOptions = true }
        } else {
            // 未加照片: 紧凑 row, 高度像动作列表 row (56pt), 全宽 + 虚线描边占位感
            Button(action: { showPhotoOptions = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(MasoColor.textDim)
                        .frame(width: 32, height: 32)
                    Text("Add a photo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MasoColor.textDim)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(MasoColor.surface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                        .strokeBorder(
                            MasoColor.borderSoft,
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            }
            .buttonStyle(.plain)
        }
    }

    /// 动作列表 Section — list / grid 两种模式. 跟 PlanDetailSheet 同结构: header 行 + 各 row,
    /// list mode 支持 swipeActions delete (历史不允许 reorder, 时间是 ground truth).
    @ViewBuilder
    private var exerciseStatsSection: some View {
        Section {
            // Header — "Exercises" kicker + 右侧 list/grid 切换 (跟 PlanDetailSheet 一致)
            HStack {
                Text("Exercises")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(MasoColor.textFaint)
                Spacer()
                LayoutToggle(useCardLayout: Binding(
                    get: { useCardLayout },
                    set: { useCardLayout = $0 }
                ))
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if exerciseStats.isEmpty {
                Text("No exercises in this workout")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
            } else if useCardLayout {
                // grid 模式 — 2 列 card. 不支持 swipe / 拖拽 (LazyVGrid 不支持). 删除走 contextMenu.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(exerciseStats) { stat in
                        ExerciseStatCard(stat: stat, onTapImage: { detailExercise = stat.exercise })
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeleteExerciseId = stat.exercise.id
                                } label: {
                                    Label {
                                        Text("Delete")
                                    } icon: {
                                        Image(systemName: "trash").foregroundStyle(.white)
                                    }
                                }
                            }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                // list 模式 — 原生 swipeActions 右滑删除. 历史时间顺序是 ground truth, 不允许 reorder.
                ForEach(exerciseStats) { stat in
                    ExerciseStatRow(stat: stat, onTapImage: { detailExercise = stat.exercise })
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // icon-only → 圆形按钮, tint negative (design.md).
                            Button(role: .destructive) {
                                pendingDeleteExerciseId = stat.exercise.id
                            } label: {
                                Image(systemName: "trash.fill")
                            }
                            .tint(MasoColor.negative)
                            .accessibilityLabel(NSLocalizedString("Delete", comment: ""))
                        }
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            BodyHint(muscles: session.muscles, height: 96, region: .full, square: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(prettyDay(session.day).uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(MasoColor.accent)
                Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatPill(text: pluralizedExercises(session.exerciseCount))
                    StatPill(text: pluralizedSets(session.setCount))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MasoMetrics.cardPadding)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    // MARK: - Share section data helpers

    /// 这次 session 的 WorkoutSectionData — 主要分享内容.
    fileprivate func sessionWorkoutSection() -> WorkoutSectionData {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return WorkoutSectionData(
            dateLabel: df.string(from: session.day),
            planName: session.planName ?? NSLocalizedString("Free workout", comment: ""),
            durationLabel: "~\(max(5, session.setCount * 2))m",
            setCount: session.setCount,
            exerciseCount: session.exerciseCount,
            prCount: session.prCount,
            muscles: session.muscles,
            exerciseNames: exerciseStats.prefix(4).map { $0.exercise.displayName }
        )
    }

    /// 本周肌肉状态 (用 DataStore 全局累计 fatigue mapping).
    fileprivate func sessionMuscleStatusSection() -> MuscleStatusSectionData {
        let fatigueMap = muscleFatigueMap()
        return MuscleStatusSectionData(
            muscleOpacity: { m in shareOpacityFor(muscle: m, fatigueMap: fatigueMap) },
            coarseOnly: !data.settings.muscleDetailEnabled,
            workoutsThisWeek: workoutsThisWeekCount(),
            totalSetsThisWeek: totalSetsThisWeek(),
            muscleSectionsHit: muscleSectionsHitThisWeek()
        )
    }

    /// 本周训练日历 frequency.
    fileprivate func sessionCalendarSection() -> CalendarSectionData {
        CalendarSectionData(
            sessionDates: workoutDateSet(),
            totalSets: totalSetsThisWeek(),
            streakDays: currentStreakDays()
        )
    }

    // 内部计算 — 走共享 MuscleStatusCompute. 累计 volume + 时间衰减.
    private func muscleFatigueMap() -> [MuscleGroup: Double] {
        MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById)
    }

    private func shareOpacityFor(muscle m: MuscleGroup, fatigueMap: [MuscleGroup: Double]) -> Double? {
        MuscleStatusCompute.opacityFor(muscle: m, fatigueMap: fatigueMap)
    }

    private func workoutsThisWeekCount() -> Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let days = Set(data.sets.filter { $0.performedAt >= cutoff }.map { cal.startOfDay(for: $0.performedAt) })
        return days.count
    }

    private func totalSetsThisWeek() -> Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        return data.sets.filter { $0.performedAt >= cutoff }.count
    }

    private func muscleSectionsHitThisWeek() -> Int {
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        var sections = Set<MuscleGroup>()
        for set in data.sets where set.performedAt >= cutoff {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups {
                if let s = m.section { sections.insert(s) }
            }
        }
        return sections.count
    }

    private func currentStreakDays() -> Int {
        let cal = Calendar.current
        let days = workoutDateSet()
        let today = cal.startOfDay(for: Date())
        // P2-3: 今天没练但昨天练了 → 连胜仍存活 (见上方同名实现注释).
        var cursor = today
        if !days.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = cal.startOfDay(for: y)
            if !days.contains(cursor) { return 0 }
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = cal.startOfDay(for: prev)
        }
        return streak
    }

    private func workoutDateSet() -> Set<Date> {
        let cal = Calendar.current
        var out: Set<Date> = []
        for s in data.sets {
            out.insert(cal.startOfDay(for: s.performedAt))
        }
        return out
    }
}

private struct StatPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(MasoColor.textDim)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
    }
}

private struct ExerciseStatRow: View {
    let stat: SessionExerciseStat
    /// 点图片 → 弹动作详情. parent 接收 callback, 在它身上挂 sheet.
    var onTapImage: (() -> Void)? = nil

    fileprivate static func detailLine(for stat: SessionExerciseStat) -> String {
        if let d = stat.totalDuration {
            return "\(pluralizedSets(stat.setCount)) · \(d)s"
        }
        if let w = stat.bestWeight, let r = stat.bestReps {
            if w > 0 { return "\(pluralizedSets(stat.setCount)) · \(weightLabel(w)) × \(r)" }
            return "\(pluralizedSets(stat.setCount)) × \(r)"
        }
        return pluralizedSets(stat.setCount)
    }

    private var detailLine: String { Self.detailLine(for: stat) }

    var body: some View {
        // 视觉跟"训练中" InlinePlaylist.playlistRow 完全对齐 — 全 app 动作行统一规格.
        HStack(spacing: 14) {
            Button(action: { onTapImage?() }) {
                ExerciseImage(
                    category: stat.exercise.category,
                    imageFolder: stat.exercise.imageFolder,
                    photoURL: stat.exercise.photoURL,
                    customImageData: stat.exercise.customImageData,
                    cornerRadius: 8,
                    size: 56,
                    animated: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), stat.exercise.displayName))
            VStack(alignment: .leading, spacing: 5) {
                Text(stat.exercise.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                ExerciseTagsRow(
                    muscleGroups: stat.exercise.muscleGroups,
                    equipment: stat.exercise.equipment,
                    muscleLimit: 1
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .padding(.vertical, 10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// grid 模式的卡片版本 — 跟 PlansScreen.PlanStepCard 同款 layout (大图正方形 + 名字 + 详情).
private struct ExerciseStatCard: View {
    let stat: SessionExerciseStat
    var onTapImage: (() -> Void)? = nil

    private var detailLine: String { ExerciseStatRow.detailLine(for: stat) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { onTapImage?() }) {
                GeometryReader { geo in
                    ExerciseImage(
                        category: stat.exercise.category,
                        imageFolder: stat.exercise.imageFolder,
                        photoURL: stat.exercise.photoURL,
                        customImageData: stat.exercise.customImageData,
                        cornerRadius: 8,
                        size: geo.size.width,
                        animated: false
                    )
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), stat.exercise.displayName))

            VStack(alignment: .leading, spacing: 4) {
                Text(stat.exercise.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(detailLine)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ExerciseTagsRow(
                    muscleGroups: stat.exercise.muscleGroups,
                    equipment: stat.exercise.equipment,
                    muscleLimit: 1,
                    compact: true
                )
            }
        }
        .padding(10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 文件级 helper (给 @State 默认值用 — 不能在属性初始化器里调实例方法).

/// 当前月份的月初 — calendarMonthAnchor 的默认值 + 收起重置都用它.
private func historyCurrentMonthStart() -> Date {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: Date())
    return cal.date(from: comps) ?? Date()
}
