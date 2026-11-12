import SwiftUI
import Charts
import StoreKit

private struct HistoryWorkoutDetail: Hashable {
    let plan: Plan
}

// 训练状态页 — 显示 7 天活跃肌群 + 训练记录卡片
//
// 卡片设计: 按 "训练计划 (plan)" 维度展示, 而不是按动作组拆分.
// 一张卡片 = 一次完整的训练 session (同一 planId + 同一 calendar 日).
// 没有 planId 的记录 (自由训练) 单独成卡, kicker 显示训练日期, 标题 "Free workout".
//
// 点卡片 → 从右侧推入该场训练详情, 可查看每个动作的组数 + 再次训练.
struct HistoryScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subs
    /// 点 "再次训练" 时回调到 RootView, 用统一的 startTraining 入口启动
    let onReplay: (Plan) -> Void
    /// 右上角齿轮 → 弹 Settings sheet (RootView 持有 sheet state)
    let onOpenSettings: () -> Void

    enum Mode { case records, insights, archive }
    var mode: Mode = .records
    @State private var selectedPlan: HistoryWorkoutDetail?
    @State private var selectedSession: SessionSummary?
    /// 长按 → contextMenu Delete → 二次确认 alert. 存待删 session (planId + day) 区分.
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
    @State private var insightRange: InsightsTimeRange?
    @State private var trainingPreferencesPresented = false
    @State private var targetInfoPresented = false
    @State private var updateRoutinesAfterPreferences = false

    /// Default to the same current calendar week shown in the Home overview.
    private var selectedInsightRange: Binding<InsightsTimeRange> {
        Binding(
            get: {
                if let insightRange { return insightRange }
                #if DEBUG
                // Marketing capture only: the deck shows a populated range instead of an
                // empty current week. Never reachable from a normal launch.
                if ProcessInfo.processInfo.environment["MASO_SCREENSHOT_CAPTURE"] == "1",
                   let raw = ProcessInfo.processInfo.environment["MASO_MARKETING_INSIGHTS_RANGE"],
                   let forced = InsightsTimeRange(rawValue: raw) {
                    return forced
                }
                #endif
                return InsightsTimeRange.defaultValue(
                    records: data.sets,
                    calendar: data.settings.calendar,
                    now: Date()
                )
            },
            set: { insightRange = $0 }
        )
    }

    /// 头部分享菜单 → 两个 customize sheet 的呈现开关. Menu item 里不能内嵌 ShareImageButton
    /// (menu 收起时挂在 item 上的 .sheet 呈现不可靠), 所以 sheet 提到 screen 层, menu 只翻 bool.
    @State var insightsSharePresented = false

    /// ProBanner kicker 的"起步价/月" — 取 yearly product 月均价 (年价 ÷ 12), locale-aware.
    /// product 还没 load 出来时返回 nil → banner 只显示 "MASSO PRO", 不写死假价格.
    private var proFromPrice: String? {
        guard let yearly = subs.product(for: .yearly) else { return nil }
        let perMonth = yearly.price / 12
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    /// 过往训练按"周"分组 (settings.calendar 的周): 组内按日期降序, 组按周降序 (最近的周在上).
    private func weekGroupedSessions(_ sessions: [SessionSummary]) -> [(weekStart: Date, sessions: [SessionSummary])] {
        let cal = data.settings.calendar
        let grouped = Dictionary(grouping: sessions) { s in
            cal.dateInterval(of: .weekOfYear, for: s.day)?.start ?? cal.startOfDay(for: s.day)
        }
        return grouped
            .map { (weekStart: $0.key, sessions: $0.value.sorted { $0.day > $1.day }) }
            .sorted { $0.weekStart > $1.weekStart }
    }

    /// 周分组 section 标题: 本周 / 上周 / "Jun 9 – 15" 区间 (locale-aware).
    private func weekLabel(_ weekStart: Date) -> String {
        let cal = data.settings.calendar
        if let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start {
            if cal.isDate(weekStart, inSameDayAs: thisWeek) {
                return NSLocalizedString("This week", comment: "history week group")
            }
            if let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek),
               cal.isDate(weekStart, inSameDayAs: lastWeek) {
                return NSLocalizedString("Last week", comment: "history week group")
            }
        }
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startStr = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let sameMonth = cal.isDate(weekStart, equalTo: end, toGranularity: .month)
        let endStr = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startStr) – \(endStr)"
    }

    @ViewBuilder
    private var pages: some View {
        if mode == .archive {
            RecordHistoryArchiveScreen(kind: .workout, onReplay: onReplay, sessionSelection: $selectedSession)
        } else {
            ScrollView {
                if mode == .insights {
                    insightRows(forSharing: false)
                        .padding(MasoMetrics.pagePaddingHorizontal)
                } else {
                    LazyVStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
                        recordRows(forSharing: false)
                    }
                    .padding(MasoMetrics.pagePaddingHorizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func recordRows(forSharing: Bool) -> some View {
        workoutTargetCard
        if !forSharing {
            Button { targetInfoPresented = true } label: {
                Label("Why this target?", systemImage: "info.circle").font(.footnote)
            }.tint(MasoColor.textFaint)
        }
        if !forSharing, let plan = data.suggestedTodayPlan {
            WorkoutCard(plan: plan, exById: data.exById, kicker: NSLocalizedString("Today's Workout", comment: ""),
                        onStart: { onReplay(plan) }, onShowDetail: { selectedPlan = HistoryWorkoutDetail(plan: plan) }, compactLayout: true)
        }
        if forSharing {
            let sessions = data.recordedWorkoutSessions(on: Date())
            if !sessions.isEmpty {
                Text("Today").font(.headline)
                ForEach(sessions) { session in
                    SessionCard(session: session, photo: data.sessionPhoto(forSessionId: session.id), compact: true, onReplay: nil)
                }
            }
            ForEach(data.recordedExternalWorkouts(on: Date())) { workout in
                ExternalWorkoutRecordCard(workout: workout)
            }
        } else {
            RecordHistorySection(kind: .workout, onReplay: onReplay, sessionSelection: $selectedSession)
        }
    }

    private func insightRows(forSharing: Bool) -> some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardPadding) {
            InsightsChartsView(data: data, forSharing: forSharing, onUnlock: { paywallPresented = true }, range: selectedInsightRange)
            if !forSharing {
                RecordHistorySection(kind: .workout, range: selectedInsightRange.wrappedValue,
                                     limitsToPreview: false, onReplay: onReplay, sessionSelection: $selectedSession)
            }
        }
    }

    var body: some View {
        pages
        // (撤销 scroll-based 展开/收起 — 现在完全交给用户主动点击 strip / chevron 控制)
        // 页面底色 #121212 — 跟 Plans / Today 一致, 不再透出 NavigationStack 默认纯黑底.
        // ignoresSafeArea 让底色延伸到 home indicator 区. NavigationStack 的 large title /
        // material blur 仍正常叠在这个底色之上 (跟 Plans 同视觉).
        // 试验性: 换成共享背景 (#121212 + 底部液态光斑).
        .background(AppBackground())
        // B2: 收起→重新展开时把日历重置回当前月 (不停在上次翻到的月份). 在展开瞬间重置 —
        // expandedView 是全新插入, 直接渲染当前月, 没有 grid 滑动残影.
        .onChange(of: calendarCollapsed) { _, collapsed in
            if !collapsed { calendarMonthAnchor = historyCurrentMonthStart() }
        }
        .navigationTitle(LocalizedStringKey(mode == .insights ? "Workout Insights" : mode == .archive ? "Workout History" : "Workout"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarRole(.navigationStack)
        .toolbar {
            if mode == .insights {
                ToolbarItem(placement: .topBarTrailing) { shareButton }
            }
            if mode == .records {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { trainingPreferencesPresented = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .tint(MasoColor.text)
                    .accessibilityLabel("Training Preferences")
                }
            }
        }
        .sheet(isPresented: $trainingPreferencesPresented, onDismiss: {
            guard updateRoutinesAfterPreferences else { return }
            updateRoutinesAfterPreferences = false
            AppRouter.shared.pendingTrainingPreferencesUpdate = true
            AppRouter.shared.requestedDestination = .coach
        }) {
            TrainingPreferencesSheet(onConfirm: { updateRoutinesAfterPreferences = true })
                .tint(MasoColor.text)
        }
        .navigationDestination(item: $selectedPlan) { route in
            PlanDetailSheet(initialPlan: route.plan, onStart: { plan in
                selectedPlan = nil
                DispatchQueue.main.async { onReplay(plan) }
            }, usesParentNavigation: true)
            .accessibilityIdentifier("page.workoutDetail")
        }
        .navigationDestination(item: $selectedSession) { session in
            SessionDetailSheet(session: session, exerciseStats: data.recordedExerciseStats(for: session),
                               replayPlan: data.recordedReplayPlan(for: session), onReplay: { plan in
                selectedSession = nil
                DispatchQueue.main.async { onReplay(plan) }
            }, pushed: true)
        }
        .sheet(isPresented: $targetInfoPresented) { GoalCompletionRulesSheet(kind: .workout) }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
            .presentationDragIndicator(.visible)
        }
        // 分享 customize sheet ×2 — 由页面右上角分享按钮驱动 (不走 ShareImageButton,
        // 它自带的 Button+sheet 放不进 Menu item; 这里直接 present 同一个 ShareCustomizeSheet).
        .sheet(isPresented: $insightsSharePresented) {
            insightsCustomizeSheet
        }

    }

    /// The same target → calendar → current records structure as Diet and Sleep.
    private var workoutTargetCard: some View {
        let goal = max(1, min(7, data.settings.weeklyTrainingDays))
        let calendar = data.settings.calendar
        let now = Date()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let days = data.recordedWorkoutDates(now: now).filter { day in
            week.map { day >= $0.start && day < $0.end } ?? false
        }.count
        return VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Workout target").foregroundStyle(MasoColor.text)
            } icon: {
                Image(systemName: "dumbbell").foregroundStyle(MasoColor.accent)
            }.font(.headline)
            TargetValueLabel(value: String(goal), unit: "days / week")
            ProgressView(value: Double(min(days, goal)), total: Double(goal)).tint(MasoColor.accent)
            Text(String.localizedStringWithFormat(NSLocalizedString("%d of %d days this week", comment: "workout target progress"), days, goal))
                .targetProgressTextStyle()

        }.cardChrome()
    }

    // MARK: - 顶部 3 metrics 卡 (跟 calendar 状态切换本周 / 本月)

    /// 顶部 stats row — 跟着 calendar 是 strip 还是月展示不同口径:
    ///   - 7 天 strip (collapsed): "Days this week / Week streak / Sets this week"
    ///   - 月 grid (expanded):   "Days this month / Week streak / Sets this month"
    /// Week streak 跟两种状态都一样 (连续达标周数 — 每周训练天数 ≥ 周目标, 跟显示的周/月无关).
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
        let setsThisWeek = setsThisWeekCount()
        // 中列原是 "Week streak" (连胜) — 踩 DESIGN.md「不做连胜绑架」红线且口径传达不了
        // (本周练了 2 天却显示 0 = 反激励). 换成累计训练次数: 只增不减的沉默进步反馈.
        let total = groupedSessions().count
        statsCard(
            value1: "\(daysThisWeek)", label1: daysThisWeek == 1 ? "Day this week" : "Days this week",
            value2: "\(total)", label2: total == 1 ? "Workout total" : "Workouts total",
            value3: "\(setsThisWeek)", label3: setsThisWeek == 1 ? "Set this week" : "Sets this week"
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
        let monthDayCount = monthDays.count
        let setsThisMonth = setsThisMonthCount()
        let total = groupedSessions().count
        statsCard(
            value1: "\(monthDayCount)", label1: monthDayCount == 1 ? "Day this month" : "Days this month",
            value2: "\(total)", label2: total == 1 ? "Workout total" : "Workouts total",
            value3: "\(setsThisMonth)", label3: setsThisMonth == 1 ? "Set this month" : "Sets this month"
        )
    }

    /// 共享 stats 卡渲染 — 三列, 浅 surface 底色, 圆角.
    private func statsCard(
        value1: String, label1: String,
        value2: String, label2: String,
        value3: String, label3: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            statColumn(value: value1, label: label1)
            statDivider
            statColumn(value: value2, label: label2)
            statDivider
            statColumn(value: value3, label: label3)
        }
        .frame(maxWidth: .infinity)
        // owner: 卡片上下左右留白都加宽一档, 让整卡视觉更大更透气 (12 → 20 竖 / 新增 8 横).
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        // 卡片底色/圆角交给外层合成卡 (stats + 日历 同一张卡).
    }

    private var statDivider: some View {
        Rectangle().fill(MasoColor.borderSoft).frame(width: 0.5, height: 40)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 32, weight: .heavy).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(MasoColor.accent)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .tracking(0.5)
                .textCase(nil)
                .foregroundStyle(MasoColor.textDim)
                // 数字放大到 32pt 后列宽变紧 —— label 必须能折两行, 否则
                // "DAYS THIS MONTH" 被截成 "DAYS THIS MO…".
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 训练日历 helpers (InlineWorkoutCalendar 喂数据用)

    /// 用户有训练的日历日集合 (供 InlineWorkoutCalendar 高亮)
    private func workoutDateSet() -> Set<Date> {
        data.recordedWorkoutDates(calendar: Calendar.current)
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
    /// 连续达标周数 — 每周训练天数 ≥ 周目标 (settings.weeklyTrainingDays) 才算"达标".
    /// 旧版按"连续天"算: lifter 一周练 3-5 天而非每天, 连天数恒为 0-1, 这指标基本没意义.
    /// 改成周维度后真正奖励"每周坚持到量"的习惯, 跟用户自己设的训练频率挂钩.
    /// 本周还在进行中: 已达标 → 计入并往回数; 未达标 → 不算断 (不归零), 从上周开始数.
    private func currentWeekStreak() -> Int {
        let cal = data.settings.calendar
        let goal = max(1, data.settings.weeklyTrainingDays)
        let days = workoutDateSet()
        // 某周 (含 date) 内的训练天数.
        func trainedDays(inWeekContaining date: Date) -> Int {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            guard let weekStart = cal.date(from: comps) else { return 0 }
            let weekDays: Set<Date> = Set((0..<7).compactMap {
                cal.date(byAdding: .day, value: $0, to: weekStart).map { cal.startOfDay(for: $0) }
            })
            return days.intersection(weekDays).count
        }
        var cursor = Date()  // 本周
        // 本周未达标 → 还在进行中, 不归零, 从上周开始往回数.
        if trainedDays(inWeekContaining: cursor) < goal {
            guard let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = lastWeek
        }
        var streak = 0
        while trainedDays(inWeekContaining: cursor) >= goal {
            streak += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// 把 SetRecord 按 (planId, 日历日) 聚合成 session 卡; 按时间倒序返回
    // MARK: - 分享 (#history-share #insights-share)

    /// Share the content of the current surface.
    private var shareButton: some View {
        Button {
            openInsightsShare()
        } label: {
            ShareIcon()
        }
        .accessibilityLabel(Text(mode == .insights ? "Share Workout Insights" : "Share Workout"))
    }

    /// Open a full-page Insights preview.
    private func openInsightsShare() {
        insightsSharePresented = true
    }

    private var insightsCustomizeSheet: some View {
        FullPageShareSheet(title: NSLocalizedString("Share Workout Insights", comment: ""), surface: "insights") {
            progressShareContent(insights: true)
        }
    }

    private func progressShareContent(insights: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
            Text(insights ? "Workout Insights" : "Workout")
                .font(.largeTitle.bold())
                .foregroundStyle(MasoColor.text)
            if insights {
                insightRows(forSharing: true)
            } else {
                // A regular VStack is intentional: export every record, including offscreen rows.
                recordRows(forSharing: true)
            }
            }.padding(ShareLayout.contentInset)
            ShareCardFooter(qrPayload: MasoLinks.appStore, qrSize: 64)
        }
        .background(MasoColor.background)
        .environment(data)
        .environment(subs)
        .environment(\.colorScheme, .dark)
    }

    /// 最近一次训练 — 没有任何记录时返回 nil, 该 section 整节不出现.
    private func historyWorkoutSection() -> WorkoutSectionData? {
        guard let s = groupedSessions().first else { return nil }
        let df = DateFormatter()
        df.locale = LanguageManager.currentLocale
        df.dateStyle = .full
        df.timeStyle = .none
        return WorkoutSectionData(
            dateLabel: df.string(from: s.day),
            planName: s.planName ?? NSLocalizedString("Free workout", comment: ""),
            // 真实时长 (首末组时间差), 不再是"组数×2"的编造估算 (P1#17) — 所以去掉 "~".
            durationLabel: "\(s.durationMinutes)m",
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
            muscleStyle: { m in MasoColor.recoveryHeatStyle(muscle: m, fatigueMap: fatigueMap) },
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
        // 连胜 — 周口径 (连续达标周数, currentWeekStreak): 跟 tab 内 stats strip 和
        // session 详情分享同一套语义 — 同一张卡的 🔥Streak 不再随入口变含义.
        // (旧实现按"连续天"数, 跟 stats strip 早已改掉的口径不一致.)
        return CalendarSectionData(
            sessionDates: dates,
            totalSets: weekSetCount,
            streakDays: currentWeekStreak()
        )
    }

    private func groupedSessions() -> [SessionSummary] { data.recordedWorkoutSessions() }
    private func exerciseStats(for session: SessionSummary) -> [SessionExerciseStat] { data.recordedExerciseStats(for: session) }
    private func replayPlan(for session: SessionSummary) -> Plan? { data.recordedReplayPlan(for: session) }

}

extension DataStore {
    func recordedSets(for session: SessionSummary) -> [SetRecord] {
        sets.filter { settings.calendar.isDate($0.performedAt, inSameDayAs: session.day) && $0.planId == session.planId && $0.performedAt <= Date() }
            .sorted { $0.performedAt < $1.performedAt }
    }
    func recordedWorkoutSessions(on date: Date? = nil) -> [SessionSummary] {
        let cal = settings.calendar
        struct Key: Hashable { let planId: String; let day: Date }
        var bucket: [Key: [SetRecord]] = [:]
        var order: [Key] = []
        for rec in sets where rec.performedAt <= Date() {
            if let date, !cal.isDate(rec.performedAt, inSameDayAs: date) { continue }
            let day = cal.startOfDay(for: rec.performedAt)
            let key = Key(planId: rec.planId ?? "free", day: day)
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(rec)
        }
        let summaries: [SessionSummary] = order.map { key in
            let recs = bucket[key] ?? []
            let planName: String? = {
                if key.planId == "free" { return recs.compactMap(\.planName).first ?? NSLocalizedString("Custom workout", comment: "") }
                // Prefer the recorded title; a later plan rename cannot rewrite history.
                return recs.compactMap(\.planName).first
                    ?? plans.first(where: { $0.id == key.planId })?.name
            }()
            let uniqueExercises = Set(recs.map { $0.exerciseId })
            var seenMuscles = Set<MuscleGroup>()
            var muscles: [MuscleGroup] = []
            for r in recs {
                guard let ex = exById[r.exerciseId] else { continue }
                for m in ex.muscleGroups where seenMuscles.insert(m).inserted {
                    muscles.append(m)
                }
            }
            let categories = Set(recs.map { $0.category })
            // 数这一场训练里 PR 的组数 — Epley 1RM 估算超过之前历史最高
            let prCount = recs.reduce(0) { $0 + (isPR($1) ? 1 : 0) }
            return SessionSummary(
                id: "\(key.planId)-\(Int(key.day.timeIntervalSince1970))",
                planId: key.planId == "free" ? nil : key.planId,
                day: key.day,
                planName: planName,
                exerciseCount: uniqueExercises.count,
                setCount: recs.count,
                muscles: muscles,
                categories: categories,
                firstPerformedAt: recs.map { $0.performedAt }.min() ?? key.day,
                lastPerformedAt: recs.map { $0.performedAt }.max() ?? key.day,
                prCount: prCount
            )
        }
        return summaries.sorted { $0.lastPerformedAt > $1.lastPerformedAt }
    }

    /// session 内每个动作的统计 (用于 detail sheet 的"动作列表"区)
    func recordedExerciseStats(for session: SessionSummary) -> [SessionExerciseStat] {
        let dayRecs = recordedSets(for: session)
        // 按 exerciseId 分组并保持首次出现顺序 (匹配训练时的顺序)
        var order: [String] = []
        var buckets: [String: [SetRecord]] = [:]
        for r in dayRecs.sorted(by: { $0.performedAt < $1.performedAt }) {
            if buckets[r.exerciseId] == nil { order.append(r.exerciseId) }
            buckets[r.exerciseId, default: []].append(r)
        }
        return order.compactMap { exId in
            guard let recs = buckets[exId], let ex = exById[exId] else { return nil }
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
    ///   1. session.planId 还存在于 plans 里 → 直接用原 plan (保留用户编辑后的最新版本)
    ///   2. 原 plan 已删除 / session 是自由训练 → 从 SetRecord 现合成一份 (中位数取动作负荷)
    /// 之前只在自由训练 case 走 synthesis, 导致用户删了 plan 后, 历史记录变得不能重播.
    /// 现在保证: 只要有 SetRecord, 这个 session 就能重播.
    func recordedReplayPlan(for session: SessionSummary) -> Plan? {
        if let pid = session.planId, let plan = plans.first(where: { $0.id == pid }) {
            return plan
        }
        return recordedReplayFallback(for: session)
    }

    /// A historical card always reflects recorded exercises, never a later edited plan.
    func recordedWorkoutPlan(for session: SessionSummary) -> Plan? {
        recordedReplayFallback(for: session)
    }
    func recordedWorkoutLibrary(for session: SessionSummary) -> [String: Exercise] {
        var result: [String: Exercise] = [:]
        for record in recordedSets(for: session) where result[record.exerciseId] == nil {
            result[record.exerciseId] = exById[record.exerciseId] ?? Exercise(
                id: record.exerciseId, name: record.exerciseName, category: record.category,
                tags: [], primaryMuscles: [], muscleGroups: [], imageFolder: nil, instructions: [])
        }
        return result
    }

    /// 从 SetRecord 合成临时 Plan 用于回放. 不入 DataStore (id 固定 "session-replay-{sessionId}",
    /// 反复点不会污染 Plans 列表; PlanPlayer 通过 startTrainingNow 拿到 Plan 直接展开 segments).
    /// 支持两种情况:
    ///   - session 是自由训练 (planId == nil)
    ///   - session 原 plan 已删除 (planId != nil 但 plans 里查不到)
    ///
    /// 2026-05-24 改: 之前依赖 recordedExerciseStats(for:) 拿 stats, 但 stats 里 compactMap 会把
    /// exById 里查不到的 exerciseId 过滤掉. 老用户 (iPhone 真机) 数据里有 v1 schema 的
    /// exerciseId 在 v2 库里没对应 (orphaned 572 个), 整 session 的 stats 就空了 → synthesis 返回 nil
    /// → replay 按钮不显示. 现在直接从 SetRecord 构造 steps, 不要求 exerciseId 能 resolve.
    /// PlanPlayer 拿不到 Exercise 时走 placeholder 兜底, 至少按钮总有.
    private func recordedReplayFallback(for session: SessionSummary) -> Plan? {
        let dayRecs = recordedSets(for: session)
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
    /// 这场第一组的落库时间 — 跟 lastPerformedAt 一起算真实时长.
    let firstPerformedAt: Date
    let lastPerformedAt: Date
    /// 这一场训练里 PR 的组数 (Epley 1RM 估算超过历史最高). 0 = 没 PR.
    /// 渲染时 > 0 → SessionCard 右上角小🏆+ count, 不弹通知不庆祝 (理念 4 "沉默的进步反馈")
    var prCount: Int = 0

    /// 真实训练时长 (分钟) — 首末组 performedAt 差 (共享 sessionDurationMinutes, 下限 5 分钟).
    /// 卡片副标题 / 详情 StatPill / 分享卡统一用它, 不再用"组数×2"编造 (P1#17).
    var durationMinutes: Int { sessionDurationMinutes(first: firstPerformedAt, last: lastPerformedAt) }
}

struct SessionExerciseStat: Identifiable, Hashable {
    let id: String
    let exercise: Exercise
    let setCount: Int
    let bestWeight: Double?
    let bestReps: Int?
    let totalDuration: Int?
}

/// History date-row and completion Workout Report capsule. No leading icon.
/// Visible glass matches AddToPlansButton: footnote semibold, 14×8 padding.
/// The 44pt frame sits outside that glass so the pill is not forced to 44pt.
struct WorkoutReportButton: View {
    var title: LocalizedStringKey = "Report"
    var keepsIntrinsicWidth = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MasoColor.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: keepsIntrinsicWidth ? nil : .infinity)
            .glassCapsuleButtonBackground(fallback: MasoColor.surfaceHi)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: keepsIntrinsicWidth, vertical: true)
        .accessibilityLabel("Workout report")
    }
}

/// Shared recorded-workout row for the preview and full archive.
struct WorkoutHistoryRecordRow: View {
    @Environment(DataStore.self) private var data
    let session: SessionSummary
    var embedded = false
    var showsDate = true
    var dayHeader: Date? = nil
    var paddedInDay = false
    var dayTopPadding: CGFloat = 0
    let onReplay: (Plan) -> Void
    var onOpenSession: ((SessionSummary) -> Void)? = nil
    @State private var reportPresented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let dayHeader {
                    Text(dayHeader, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                        .font(.headline)
                } else if showsDate {
                    Text(relativeDay(session.day)).font(.caption).foregroundStyle(MasoColor.textDim)
                }
                Spacer(minLength: 8)
                WorkoutReportButton { reportPresented = true }
                    .accessibilityIdentifier("workout.history.report")
            }
            .padding(.horizontal, paddedInDay ? MasoMetrics.cardPadding : 0)
            .padding(.top, paddedInDay ? MasoMetrics.cardPadding : 0)
            .padding(.bottom, 8)
            SessionCard(session: session, photo: data.sessionPhoto(forSessionId: session.id),
                        compact: true, embedded: embedded, showsDate: false, onReplay: nil)
                .applyIf(paddedInDay) { view in
                    view.padding(.horizontal, MasoMetrics.cardPadding)
                        .padding(.bottom, MasoMetrics.cardPadding).padding(.top, dayTopPadding)
                }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpenSession?(session) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("workout.history.card")
            .workoutRecordDeletion(session: session)
            .sheet(isPresented: $reportPresented) {
                AppNavigationStack {
                    WorkoutReportView(records: data.recordedSets(for: session), workoutName: session.planName)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { reportPresented = false } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Close")
                                    .accessibilityIdentifier("workout.report.close")
                            }
                        }
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
            }
    }
}

// MARK: - SessionCard

private struct SessionCard: View {
    let session: SessionSummary
    /// 用户为该 session 加的照片 (DataStore.sessionPhoto). nil = 无照片, 不渲染缩略图.
    /// 用于成就行中的小缩略图；查看和编辑仍通过训练详情。
    var photo: UIImage? = nil
    var compact: Bool = false
    var embedded = false
    var showsDate = true
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
        // 时长是真实首末组时间差 (P1#17) — "我这次练了多久"在列表就能看到.
        "\(pluralizedExercises(session.exerciseCount)) · \(pluralizedSets(session.setCount)) · \(session.durationMinutes)m"
    }

    private var compactCard: some View {
        HStack(alignment: .center, spacing: MasoMetrics.rowPaddingH) {
            compactMuscleVisual
            compactSummary
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .applyIf(!embedded) { $0.cardChrome() }
    }

    private var compactMuscleVisual: some View {
        MuscleVisualBlock(
            muscles: session.muscles,
            sideLength: MasoMetrics.sessionMuscleMapSide
        )
        .frame(width: MasoMetrics.sessionMuscleMapSide)
        .allowsHitTesting(false)
    }

    private var compactSummary: some View {
        VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {
            if showsDate {
                Text(kicker)
                    .font(.caption)
                    .foregroundStyle(MasoColor.textDim)
            }
            HStack(alignment: .firstTextBaseline, spacing: MasoMetrics.rowPaddingV) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MasoColor.textFaint)
            }
            Text(subtitleLine)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            if session.prCount > 0 || photo != nil {
                HStack(spacing: 8) {
                    if session.prCount > 0 {
                        Label("\(session.prCount)", systemImage: "trophy")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MasoColor.accent)
                            .accessibilityLabel("\(session.prCount) personal records")
                    }
                    photoThumbnail
                }
            }
        }
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable().scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MasoColor.borderSoft, lineWidth: 0.5))
                .accessibilityLabel("Workout photo")
                .accessibilityIdentifier("workout.history.photo-thumbnail")
        }
    }

    @ViewBuilder
    var body: some View {
        if compact { compactCard } else { fullCard }
    }

    private var fullCard: some View {
        // 统一布局 (跟 Plans PlanRow 同款), History 顶部多一行日期 kicker:
        //   行0: 日期 kicker (TODAY / YESTERDAY / ...)
        //   行1: title + 右箭头 (整行 tap 进 detail)
        //   行2: exercises · sets
        //   照片缩略图与奖杯同排；肌肉图保留独立位置。
        VStack(alignment: .leading, spacing: MasoMetrics.cardHeaderGap) {   // kicker↔标题↔副文案 统一节奏
            // History 独有: 训练日期
            Text(kicker)
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)                       // owner: 超长用 … 截断不折行
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
                photoThumbnail
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }

            Text(subtitleLine)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(1)

            // Muscle Map (左对齐) + Redo 按钮 (右下角) — ZStack(.bottomTrailing).
            ZStack(alignment: .bottomTrailing) {
                // muscle map 靠左 (尾部 Spacer 把它推到左缘).
                HStack {
                    MuscleVisualBlock(
                        muscles: session.muscles,
                        sideLength: MasoMetrics.sessionMuscleMapSide
                    )
                    .fixedSize()
                    Spacer()
                }

                // Redo button — 文字按钮 (跟 AI Routines 的 Save 同款: accent 半透明胶囊, 无描边环),
                // bottomTrailing 贴右下角.
                if let onReplay {
                    Button(action: onReplay) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                            Text("Repeat")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .foregroundStyle(MasoColor.accent)
                        // 次级胶囊钮 → accent 低浓度玻璃 (映射表②), 旧系统保留半透明底.
                        .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                      fallback: MasoColor.accent.opacity(0.15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat Workout")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MasoMetrics.cardPadding)
        .glassCardBackground()
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}

// 复用 Theme/Formatters 的 relativeDay (Today / Yesterday / N days ago / "MMM d")
private func prettyDay(_ d: Date) -> String { relativeDay(d) }

// MARK: - SessionDetailSheet

struct SessionDetailSheet: View {
    @Environment(DataStore.self) private var data
    let session: SessionSummary
    let exerciseStats: [SessionExerciseStat]
    /// 如果是基于 plan 的训练, 这里给出原 plan, 可以一键回放
    let replayPlan: Plan?
    let onReplay: (Plan) -> Void
    var embedded = false
    /// Shown by the surrounding navigation stack, with the system back button and swipe.
    var pushed = false

    @Environment(\.dismiss) private var dismiss
    /// list ↔ grid 切换 — 跟 PlanDetailSheet 共享同一 @AppStorage key, 两个 sheet 偏好同步.
    @AppStorage("planStepCardLayout") private var useCardLayout: Bool = false
    /// 点图片 → 弹动作详情 sheet
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 — 待删 exerciseId. 二次确认 alert 触发实际删除.
    @State private var deleteWorkout = false
    @State private var showWorkoutReport = false
    @State private var showShare = false
    @State private var pendingDeleteExerciseId: String? = nil
    /// 加/换/删训练照片 — 跟 ShareCustomizeSheet 同款 confirmationDialog + PhotoPicker flow.
    @State private var showPhotoOptions: Bool = false
    @State private var activePicker: PhotoPickerSource? = nil
    @State private var pickedPhoto: UIImage? = nil
    @State private var isCameraAvailable: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        NavStackIf(embedded: embedded || pushed) {
            // List + Section 让 stepListSection 里的 ForEach 能用原生 .swipeActions (不支持 onMove —
            // 历史时间顺序是 ground truth, 不允许重排). 跟 PlanDetailSheet 同模式, 用户跨 tab 体验一致.
            Group {
                if embedded { recordSections }
                else {
                    List { recordSections }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
                        .background(MasoColor.background.ignoresSafeArea())
                }
            }
            .navigationDestination(isPresented: $showWorkoutReport) {
                WorkoutReportView(records: data.recordedSets(for: session), workoutName: session.planName)
            }
            .sheet(isPresented: $showShare) {
                let records = data.recordedSets(for: session)
                let fact = AccomplishmentShare.sessionFact(
                    records: records,
                    name: session.planName ?? NSLocalizedString("Free workout", comment: ""),
                    calendar: data.settings.calendar)
                AccomplishmentShareSheet(title: "Share Workout", model: { privacy in
                    .session(fact, AccomplishmentShare.present(fact, privacy: privacy))
                }, allowsExactTime: !fact.isAggregate, allowsPhoto: true, canShare: fact.setCount > 0)
            }
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
            .alert("Delete workout?", isPresented: $deleteWorkout) {
                Button("Delete", role: .destructive) {
                    data.deleteSession(planId: session.planId, day: session.day)
                    if !embedded || pushed { dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All sets and PRs from this workout will be removed. Your plans stay.")
            }
            .applyIf(!embedded || pushed) { view in view.navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("page.sessionDetail")
            .toolbar {
                if !pushed {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Share", systemImage: "square.and.arrow.up") { showShare = true }
                        Button("Workout report") { showWorkoutReport = true }
                            .accessibilityIdentifier("workout.report.open")
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("workout.history.more")
                }
                ToolbarItem(placement: .principal) {
                    Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            }
            .tint(MasoColor.text)
        }
    }

    @ViewBuilder
    private var recordSections: some View {
                // 用户照片 banner — 有照片 tap 弹换/删 dialog; 没照片显示"加照片"占位也可点.
                // 视觉跟 share card 顶部的 SharePhotoBanner 同款 (1:1 正方形).
                Section {
                    sessionPhotoBlock
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    sessionOverview
                        .contextMenu {
                            Button("Delete workout", systemImage: "trash", role: .destructive) { deleteWorkout = true }
                        }

                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 20, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                exerciseStatsSection
                Section {
                    if let plan = replayPlan {
                        PrimaryActionButton(title: "Repeat Workout", icon: "play.fill") { onReplay(plan) }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    Button(role: .destructive) { deleteWorkout = true } label: {
                        TrainingCardActionLabel(title: "Delete workout", icon: "trash", accent: MasoColor.text,
                                                prominent: false, fillsWidth: true)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
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
            Button(action: { showPhotoOptions = true }) {
                AddPhotoPlaceholder(compact: true).frame(height: 56)
            }
            .buttonStyle(.plain)
        }
    }

    private var exerciseStatsSection: some View {
        let records = Dictionary(grouping: data.recordedSets(for: session), by: \.exerciseId)
        return WorkoutExercisesSection(
            items: data.recordedExerciseStats(for: session),
            useCardLayout: $useCardLayout,
            emptyTitle: "No exercises in this workout"
        ) { stat in
            if useCardLayout {
                historyExerciseEntry(stat, records: records[stat.exercise.id] ?? [])
                    .contextMenu {
                        Button(role: .destructive) { pendingDeleteExerciseId = stat.exercise.id } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            } else {
                historyExerciseEntry(stat, records: records[stat.exercise.id] ?? [])
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDeleteExerciseId = stat.exercise.id } label: {
                            Image(systemName: "trash.fill")
                        }
                        .tint(MasoColor.negative)
                        .accessibilityLabel(NSLocalizedString("Delete", comment: ""))
                    }
            }
        }
    }

    private func historyExerciseEntry(_ stat: SessionExerciseStat, records: [SetRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { detailExercise = stat.exercise } label: {
                if useCardLayout {
                    WorkoutExerciseGridCard(detailLine: pluralizedSets(records.count), exercise: stat.exercise,
                                            onTapImage: { detailExercise = stat.exercise })
                } else {
                    WorkoutExerciseRow(detailLine: pluralizedSets(records.count), exercise: stat.exercise,
                                       onTapImage: { detailExercise = stat.exercise }, showsChevron: true)
                }
            }
            .buttonStyle(.plain)
            // Recorded-set controls must be siblings, never children of the detail button.
            RecordedExerciseParameters(records: records)
                .padding(.leading, useCardLayout ? 0 : 70)
                .padding(.bottom, 8)
        }
    }

    /// Direct page content, with native type styles rather than a nested card.
    private var sessionOverview: some View {
        HStack(alignment: .center, spacing: 16) {
            BodyHint(muscles: session.muscles, height: 96, region: .full, square: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(prettyDay(session.day))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let plan = replayPlan {
                        PlanSourceBadge(source: plan.resolvedSource)
                    }
                }
                Text(session.planName ?? NSLocalizedString("Free workout", comment: ""))
                    .font(.title2.bold())
                    .foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(pluralizedExercises(session.exerciseCount)) · \(pluralizedSets(session.setCount)) · \(session.durationMinutes)m")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Share section data helpers

    /// 这次 session 的 WorkoutSectionData — 主要分享内容.

}

// MARK: - 文件级 helper (给 @State 默认值用 — 不能在属性初始化器里调实例方法).

/// 当前月份的月初 — calendarMonthAnchor 的默认值 + 收起重置都用它.
private func historyCurrentMonthStart() -> Date {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month], from: Date())
    return cal.date(from: comps) ?? Date()
}

/// Every recorded workout card uses the same deletion confirmation and data operation.
private struct WorkoutRecordDeletion: ViewModifier {
    @Environment(DataStore.self) private var data
    let session: SessionSummary
    @State private var confirming = false
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Delete workout", systemImage: "trash", role: .destructive) { confirming = true }
        }
        .alert("Delete workout?", isPresented: $confirming) {
            Button("Delete", role: .destructive) { data.deleteSession(planId: session.planId, day: session.day) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sets and PRs from this workout will be removed. Your plans stay.")
        }
    }
}

extension View {
    func workoutRecordDeletion(session: SessionSummary) -> some View {
        modifier(WorkoutRecordDeletion(session: session))
    }
}

/// A local set timeline. Sensor samples never enter share cards or AI payloads.
struct WorkoutReportView: View {
    @Environment(DataStore.self) private var data
    @State private var heartSettingsPresented = false
    @State private var selectedHeartDate: Date?
    @State private var heartSelectionTouched = false
    @State private var heartWarningsExpanded = false
    @State private var summaryWidth: CGFloat = 0
    @State private var heartTooltipHeight: CGFloat = 0
    @State private var heartTooltipPosition: CGPoint?
    let records: [SetRecord]
    var workoutName: String? = nil
    private var report: WorkoutTimelineReport { .init(records: records.sorted { $0.performedAt < $1.performedAt }) }
    private var blocks: [WorkoutReportExerciseBlock] { WorkoutReportExerciseBlock.group(records) }
    private var durationGroups: [WorkoutReportExerciseBlock] { WorkoutReportExerciseBlock.totalsByExercise(records) }
    private var heart: [WorkoutHeartSample] {
        var seen = Set<String>()
        return report.records.flatMap { WorkoutHeartLocalStore.shared.samples(for: $0) }
            .filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
    }
    private struct HeartPoint: Identifiable {
        let id: String
        let date: Date
        let bpm: Double
        let series: String
        let limit: Int?
        let blockID: String
        let intervalStart: Date
        let intervalEnd: Date
    }
    private struct HeartSegment: Identifiable {
        let first: HeartPoint
        let last: HeartPoint
        var id: String { first.id + "|" + last.id }
    }
    private var heartPoints: [HeartPoint] {
        var recordBlocks: [String: String] = [:]
        for block in blocks { for record in block.records { recordBlocks[record.id] = block.id } }
        return report.records.flatMap { record in
            (record.activeIntervals ?? []).enumerated().flatMap { index, interval -> [HeartPoint] in
                let samples = WorkoutHeartLocalStore.shared.samples(for: record)
                    .filter { $0.date >= interval.start && $0.date < interval.end }.sorted { $0.date < $1.date }
                var prior: Date?
                var part = 0
                return samples.map { sample in
                    if let prior, sample.date.timeIntervalSince(prior) > 20 { part += 1 }
                    prior = sample.date
                    return HeartPoint(id: "\(record.id)|\(sample.id)", date: sample.date, bpm: sample.bpm,
                                      series: "\(record.id)|\(index)|\(part)", limit: sample.reminderLimit,
                                      blockID: recordBlocks[record.id] ?? record.id,
                                      intervalStart: interval.start, intervalEnd: interval.end)
                }
            }
        }
    }
    private var heartSegments: [HeartSegment] {
        Dictionary(grouping: heartPoints, by: \.series).values.flatMap { points -> [HeartSegment] in
            let sorted = points.sorted { $0.date < $1.date }
            guard sorted.count > 1 else { return [] }
            return zip(sorted, sorted.dropFirst()).map { HeartSegment(first: $0.0, last: $0.1) }
        }
    }
    private var selectedHeartPoint: HeartPoint? {
        if !heartSelectionTouched {
            return heartPoints.max { a, b in a.bpm == b.bpm ? a.date > b.date : a.bpm < b.bpm }
        }
        guard let date = selectedHeartDate else { return nil }
        return heartPoints.filter { date >= $0.intervalStart && date < $0.intervalEnd && abs($0.date.timeIntervalSince(date)) <= 20 }
            .min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
    private func name(_ block: WorkoutReportExerciseBlock) -> String {
        data.exById[block.exerciseId]?.displayName ?? block.records[0].exerciseName
    }
    private func time(_ value: Double?) -> String {
        value.map { Duration.seconds(Int($0.rounded())).formatted(.time(pattern: .minuteSecond)) } ?? "—"
    }
    private struct MarkedBlock: Identifiable {
        let block: WorkoutReportExerciseBlock
        let event: WorkoutHeartExceedance
        var id: String { block.id + "|" + event.id }
    }
    private var heartDomain: ClosedRange<Date> {
        let start = blocks.compactMap(\.start).min() ?? heart.first?.date ?? Date()
        let end = blocks.compactMap(\.end).max() ?? heart.last?.date ?? start
        return start...max(end, start.addingTimeInterval(1))
    }
    private var heartYDomain: ClosedRange<Double> {
        let low = max(0, floor(((heart.map(\.bpm).min() ?? 0) - 10) / 10) * 10)
        let high = ceil(((heart.map(\.bpm).max() ?? low) + 10) / 10) * 10
        return low...max(low + 20, high)
    }
    private var markedBlocks: [MarkedBlock] {
        blocks.flatMap { block in
            let samples = block.records.flatMap { WorkoutHeartLocalStore.shared.samples(for: $0) }
            return WorkoutHeartExceedanceDetector.events(in: samples).map { MarkedBlock(block: block, event: $0) }
        }
    }
    private func refreshHeart() async {
        await HealthKitService.shared.backfillWorkoutHeart(records: records, enabled: data.settings.workoutHeartRateEnabled == true)
    }
    private var reportName: String? {
        if let workoutName, !workoutName.isEmpty { return workoutName }
        let names = Set(records.compactMap(\.planName).filter { !$0.isEmpty })
        return names.count == 1 && records.allSatisfy({ $0.planName == names.first }) ? names.first : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let reportName { Text(verbatim: reportName).font(.largeTitle.bold()) }
                        else { Text("Workout report").font(.largeTitle.bold()) }
                        if let date = report.records.first?.performedAt,
                           report.records.allSatisfy({ data.settings.calendar.isDate($0.performedAt, inSameDayAs: date) }) {
                            Text(date, format: .dateTime.year().month(.abbreviated).day().locale(LanguageManager.currentLocale))
                                .font(.subheadline).foregroundStyle(MasoColor.textDim)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    summaryRow
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { summaryWidth = $0 }
                    if report.measuredSets.count < records.count {
                        Text(String(format: NSLocalizedString("%d of %d sets have timing", comment: ""), locale: LanguageManager.currentLocale, report.measuredSets.count, records.count))
                            .font(.footnote).foregroundStyle(MasoColor.textDim)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercises and heart rate").font(.title3.weight(.semibold))
                    heartReportCard.contentCardChrome()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercise duration").font(.title3.weight(.semibold)).accessibilityIdentifier("workout.report.timeline")
                    durationReportCard.contentCardChrome()
                }
                DisclosureGroup("Logged sets") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(report.records) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(data.exById[record.exerciseId]?.displayName ?? record.exerciseName).font(.subheadline.weight(.semibold))
                                Text(record.performedAt, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(MasoColor.textDim)
                                HStack {
                                    if let weight = record.weight { Text(weightLabel(weight)) }
                                    if let reps = record.reps { Text(String(format: NSLocalizedString("%d reps", comment: ""), reps)) }
                                }.font(.footnote)
                                LabeledContent("Tracked set time", value: time(record.activeSeconds))
                                if let rest = record.restBeforeSeconds { LabeledContent("Recorded rest", value: time(rest)) }
                                if let target = record.duration, target > 0 { LabeledContent("Target duration", value: time(Double(target))) }
                            }.accessibilityIdentifier("workout.report.set.\(record.id)")
                        }
                    }.padding(.top, 12)
                }.contentCardChrome()
                DisclosureGroup("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tracked time follows the workout controls, not time under tension.")
                        if !heart.isEmpty { Text("Gaps indicate missing or untracked samples.") }
                        Text("Heart-rate data stays on this device and is not sent to AI Coach.")
                    }.font(.footnote).foregroundStyle(MasoColor.textDim).padding(.top, 12)
                }.contentCardChrome()
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 16).padding(.bottom, 32)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .sheet(isPresented: $heartSettingsPresented, onDismiss: { Task { await refreshHeart() } }) { WorkoutHeartRateSettingsSheet() }
        .task { await refreshHeart() }
        .refreshable { await refreshHeart() }
        .navigationTitle("Workout report").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workout.report")
    }

    private var heartReportCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !heart.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Peak heart rate").font(.caption).foregroundStyle(MasoColor.textDim)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Int((heart.map(\.bpm).max() ?? 0).rounded()).formatted(.number.locale(LanguageManager.currentLocale)))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                        Text("bpm").font(.caption).foregroundStyle(MasoColor.textDim)
                    }
                }
                heartChart
                if heart.contains(where: { $0.reminderLimit == nil }) {
                    Text("Some samples have no saved reminder limit.").font(.footnote).foregroundStyle(MasoColor.textDim)
                }
                DisclosureGroup(isExpanded: $heartWarningsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        if markedBlocks.isEmpty {
                            Text(heart.contains(where: { $0.reminderLimit != nil }) ? LocalizedStringKey("No sustained above-limit episodes") : LocalizedStringKey("Some samples have no saved reminder limit."))
                                .font(.footnote).foregroundStyle(MasoColor.textDim)
                        }
                        ForEach(markedBlocks) { marked in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(name(marked.block)).font(.subheadline)
                                    Spacer(minLength: 8)
                                    Text("\(Int(marked.event.peak.rounded()).formatted(.number.locale(LanguageManager.currentLocale))) \(NSLocalizedString("bpm", comment: ""))")
                                        .font(.subheadline.monospacedDigit()).fixedSize()
                                }
                                Text(marked.event.start, format: .dateTime.hour().minute().locale(LanguageManager.currentLocale))
                                    .font(.caption).foregroundStyle(MasoColor.textDim)
                            }.foregroundStyle(.orange).accessibilityIdentifier("workout.report.heart.insight.\(marked.id)")
                        }
                        if !markedBlocks.isEmpty {
                            Text("Consider slowing down or resting.").font(.footnote).foregroundStyle(MasoColor.textDim)
                        }
                    }.padding(.top, 12)
                } label: {
                    HStack {
                        Label("Above your reminder limit", systemImage: "heart.fill")
                        Spacer()
                        Text(heart.contains(where: { $0.reminderLimit != nil }) ? markedBlocks.count.formatted(.number.locale(LanguageManager.currentLocale)) : "—")
                            .foregroundStyle(MasoColor.textDim).monospacedDigit()
                    }.accessibilityIdentifier("workout.report.heart.reminders")
                }
                if data.settings.workoutHeartRateEnabled != true {
                    Button("Connect heart rate", systemImage: "heart") { heartSettingsPresented = true }
                        .font(.footnote).foregroundStyle(MasoColor.textDim)
                        .accessibilityIdentifier("workout.report.connect-heart")
                }
            } else if data.settings.workoutHeartRateEnabled != true {
                Button { heartSettingsPresented = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "heart.text.square").font(.title2).foregroundStyle(MasoColor.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Connect heart rate").font(.headline).foregroundStyle(MasoColor.text)
                            Text("Allow heart-rate access to see available workout readings.").font(.footnote).foregroundStyle(MasoColor.textDim)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MasoColor.textDim)
                    }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("workout.report.connect-heart")
            } else {
                Text("No heart-rate samples yet")
                    .font(.subheadline).foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .accessibilityIdentifier("workout.report.no-heart-samples")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationReportCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if blocks.isEmpty { Text("No workout timing yet").foregroundStyle(MasoColor.textDim) }
            let maximum = durationGroups.compactMap(\.trackedSeconds).max() ?? 0
            ForEach(durationGroups) { block in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(name(block)).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        if block.trackedSeconds != nil, maximum > 0 {
                            GeometryReader { geometry in
                                let measured = block.records.compactMap(\.activeSeconds).filter { $0 > 0 }
                                ZStack(alignment: .leading) {
                                    Capsule().fill(MasoColor.textDim.opacity(0.2))
                                    HStack(spacing: 0) {
                                        ForEach(Array(measured.enumerated()), id: \.offset) { index, duration in
                                            Rectangle().fill(MasoColor.accent.opacity(index.isMultiple(of: 2) ? 1 : 0.62))
                                                .frame(width: geometry.size.width * duration / maximum)
                                        }
                                    }.clipShape(Capsule())
                                }
                            }.frame(maxWidth: .infinity).frame(height: 8).accessibilityHidden(true)
                        }
                        Text(time(block.trackedSeconds)).font(.subheadline.monospacedDigit()).fixedSize()
                    }
                    if block.hasMissingTiming { Text("Some timing is unavailable").font(.caption).foregroundStyle(MasoColor.textDim) }
                }.accessibilityIdentifier("workout.report.exercise.\(block.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var heartChart: some View {
        Chart {
            ForEach(heartSegments) { segment in
                let hasMatchingLimits = segment.first.limit != nil && segment.first.limit == segment.last.limit
                let gradient = LinearGradient(
                    colors: [WorkoutHeartWarningColor.color(bpm: Int(segment.first.bpm.rounded()), limit: hasMatchingLimits ? segment.first.limit : nil),
                             WorkoutHeartWarningColor.color(bpm: Int(segment.last.bpm.rounded()), limit: hasMatchingLimits ? segment.last.limit : nil)],
                    startPoint: .leading, endPoint: .trailing)
                LineMark(x: .value(NSLocalizedString("Time", comment: ""), segment.first.date), y: .value(NSLocalizedString("bpm", comment: ""), segment.first.bpm), series: .value("segment", segment.id))
                    .foregroundStyle(gradient).alignsMarkStylesWithPlotArea(false)
                LineMark(x: .value(NSLocalizedString("Time", comment: ""), segment.last.date), y: .value(NSLocalizedString("bpm", comment: ""), segment.last.bpm), series: .value("segment", segment.id))
                    .foregroundStyle(gradient).alignsMarkStylesWithPlotArea(false)
            }
            ForEach(heartPoints) { point in
                PointMark(x: .value(NSLocalizedString("Time", comment: ""), point.date), y: .value(NSLocalizedString("bpm", comment: ""), point.bpm))
                    .foregroundStyle(WorkoutHeartWarningColor.color(bpm: Int(point.bpm.rounded()), limit: point.limit)).symbolSize(9)
            }
            if let point = selectedHeartPoint {
                RuleMark(x: .value(NSLocalizedString("Time", comment: ""), point.date)).foregroundStyle(MasoColor.textDim.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: heartDomain)
        .chartYScale(domain: heartYDomain)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let placement: CGPoint? = {
                    if let point = selectedHeartPoint,
                       let frame = proxy.plotFrame, let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.bpm) {
                        let plot = geometry[frame]
                        let width = min(220, max(1, geometry.size.width - 56))
                        let left = plot.minX + width / 2 + 4
                        let right = geometry.size.width - width / 2 - 4
                        let tooltipX = max(left, min(right, plot.minX + x))
                        let height = heartTooltipHeight > 0 ? heartTooltipHeight : 72
                        let pointY = plot.minY + y
                        let preferredY = pointY - height - 8 >= 0 ? pointY - height / 2 - 8 : pointY + height / 2 + 8
                        let tooltipY = max(height / 2, min(geometry.size.height - height / 2, preferredY))
                        return CGPoint(x: tooltipX, y: tooltipY)
                    }
                    return nil
                }()
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let frame = proxy.plotFrame else { return }
                        let x = value.location.x - geometry[frame].minX
                        heartSelectionTouched = true
                        selectedHeartDate = proxy.value(atX: x, as: Date.self)
                    })
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height),
                              let frame = proxy.plotFrame else { return }
                        let x = value.location.x - geometry[frame].minX
                        heartSelectionTouched = true
                        selectedHeartDate = proxy.value(atX: x, as: Date.self)
                    })
                    .onChange(of: placement, initial: true) { _, position in heartTooltipPosition = position }
            }
        }
        .chartXAxis {
            let span = heartDomain.upperBound.timeIntervalSince(heartDomain.lowerBound)
            AxisMarks(values: [heartDomain.lowerBound.addingTimeInterval(span * 0.25),
                               heartDomain.lowerBound.addingTimeInterval(span * 0.75)]) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .accessibilityIdentifier("workout.report.heart")
        .overlay {
            GeometryReader { geometry in
                if let point = selectedHeartPoint, let block = blocks.first(where: { $0.id == point.blockID }), let position = heartTooltipPosition {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name(block)).font(.subheadline.weight(.semibold))
                        HStack {
                            Text("\(Int(point.bpm.rounded()).formatted(.number.locale(LanguageManager.currentLocale))) \(NSLocalizedString("bpm", comment: ""))")
                                .font(.headline.monospacedDigit())
                            Spacer(minLength: 4)
                            Text(point.date, format: .dateTime.hour().minute().second().locale(LanguageManager.currentLocale))
                                .font(.caption).foregroundStyle(MasoColor.textDim)
                        }
                    }
                    .padding(12).frame(width: min(220, max(1, geometry.size.width - 56)), alignment: .leading)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heartTooltipHeight = $0 }
                    .position(position)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("workout.report.heart.selection")
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity).frame(height: 178)
        .environment(\.layoutDirection, .leftToRight)
    }
    private var summaryRow: some View {
        let unit = data.settings.weightUnit
        let volume = report.volumeKg.map {
            unit.fromKg($0).formatted(.number.precision(.fractionLength(0...1)).locale(LanguageManager.currentLocale))
        } ?? "—"
        let sets = records.count.formatted(.number.locale(LanguageManager.currentLocale))
        let duration = time(report.activeSeconds)
        let columnWidth = max(1, ((summaryWidth > 0 ? summaryWidth : 320) - 32) / 3)
        let values = [sets, duration, volume]
        let fontSize: CGFloat = [20, 17, 14, 11].first { size in
            let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            return values.allSatisfy { ($0 as NSString).size(withAttributes: [.font: font]).width <= columnWidth }
        } ?? 11
        return HStack(alignment: .top, spacing: 16) {
            summaryValue("Logged sets", sets, fontSize: fontSize).frame(width: columnWidth)
            summaryValue("Tracked set time", duration, fontSize: fontSize).frame(width: columnWidth)
            summaryValue("Volume", volume, unit: unit.label, fontSize: fontSize).frame(width: columnWidth)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryValue(_ label: LocalizedStringKey, _ value: String, unit: String? = nil, fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(MasoColor.text)
            (Text(label) + Text(verbatim: unit.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(MasoColor.textDim)
                .lineLimit(2).multilineTextAlignment(.leading).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
