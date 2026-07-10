import SwiftUI
import UIKit

// 统一分享卡 — 取代 SessionShareCard / WorkoutCompleteShareCard / MuscleStatusShareCard /
// WeeklyFrequencyShareCard 三/四张专用卡的逻辑, 把内容拆成 3 个 section, 每个 section
// 通过 caller 传入对应 *SectionData 来决定是否渲染.
//
// 卡片有两个工作模式 — 由 caller 二选一:
//   editToggles != nil → 编辑模式 (preview in ShareCustomizeSheet):
//       - 每个 section 的"大标题"右侧渲染一个 inline Toggle
//       - toggle off 仅隐藏 section 内容 (stats / BodyHint / chips / DayDots), header 保留,
//         让用户能再切回 on. 三个 section 永远 占位/header 都在.
//   editToggles == nil → 渲染模式 (final image, ShareImageRenderer.render 里):
//       - 不画任何 toggle UI
//       - 只渲染 visibleSections 里 on 的 section, off 的 section 整块不画.
//
// 视觉规格 — section 间用一个细小 kicker (大写 + spaced) 标分隔, 主标题不重复;
// 数据规格跟原 4 张卡 1:1 保留 (复用 ShareStat / BodyHint / detectBodyRegion / FlowLayout
// 等已经存在的视觉单元), 上面再加一个 kicker 区分边界.
struct UnifiedShareCard: View {
    var userPhoto: UIImage? = nil
    /// 卡内"添加照片"占位区 tap 触发. preview 模式传非 nil; 渲染最终图时 nil.
    var onTapAddPhoto: (() -> Void)? = nil

    // 三个 section 的数据 — nil = caller 一开始就不打算让该 section 入卡 (e.g. 没数据时),
    // 这种情况不论 edit/render 模式, 该 section 都完全不画.
    var workoutSection: WorkoutSectionData? = nil
    var muscleStatusSection: MuscleStatusSectionData? = nil
    var calendarSection: CalendarSectionData? = nil

    /// 非 nil = 编辑模式 (preview):
    ///   - 每个 section 的大标题右侧显示 inline Toggle
    ///   - off 的 section 只渲染 header, 不渲染 content
    /// nil = 渲染模式 (final share image):
    ///   - 不画 toggle UI
    ///   - 只渲染 visibleSections 里 on 的 section
    var editToggles: Binding<ShareSections>? = nil

    /// 仅渲染模式 (editToggles == nil) 用 — caller 决定 final 图中哪些 section 入图.
    /// 编辑模式下读取 editToggles.wrappedValue, 此值被忽略.
    var visibleSections: ShareSections = ShareSections(workout: true, muscleStatus: true, calendar: true)

    /// 编辑模式 → 用 editToggles 的当前值; 渲染模式 → 用 visibleSections.
    private var effectiveVisible: ShareSections {
        editToggles?.wrappedValue ?? visibleSections
    }

    /// 是否至少有一个 section 启用 — caller 用于 toggle UI 的 "至少留一个" 校验.
    var hasAnyEnabledSection: Bool {
        let v = effectiveVisible
        return v.todayStatus
            || (workoutSection != nil && v.workout)
            || (muscleStatusSection != nil && v.muscleStatus)
            || (calendarSection != nil && v.calendar)
    }

    var body: some View {
        // 算出每个 section 实际是否要画
        // 今日状态 section: render 模式下只有 photo 存在才画; edit 模式下不管有没 photo 都画 (用户能看到 toggle)
        let isEditMode = editToggles != nil
        let hasPhotoContent = userPhoto != nil || onTapAddPhoto != nil
        let showTodayStatus = shouldShowSection(visible: effectiveVisible.todayStatus)
            && (isEditMode || (userPhoto != nil && effectiveVisible.todayStatus))
            && (hasPhotoContent || isEditMode)
        let showWorkout = workoutSection != nil && shouldShowSection(visible: effectiveVisible.workout)
        let showMuscle = muscleStatusSection != nil && shouldShowSection(visible: effectiveVisible.muscleStatus)
        let showCalendar = calendarSection != nil && shouldShowSection(visible: effectiveVisible.calendar)

        return VStack(spacing: 0) {
            VStack(spacing: 20) {  // section 间 spacing, 配 SectionDivider 总间距 ≈ 41pt
                Spacer(minLength: 24)

                if showTodayStatus {
                    TodayStatusSectionView(
                        userPhoto: userPhoto,
                        onTapAddPhoto: onTapAddPhoto,
                        toggleBinding: todayStatusToggleBinding(),
                        isContentVisible: effectiveVisible.todayStatus
                    )
                }
                if showTodayStatus && (showWorkout || showMuscle || showCalendar) {
                    SectionDivider()
                }
                if showWorkout, let workout = workoutSection {
                    WorkoutSectionView(
                        data: workout,
                        toggleBinding: workoutToggleBinding(),
                        isContentVisible: effectiveVisible.workout
                    )
                }
                if showWorkout && (showMuscle || showCalendar) {
                    SectionDivider()
                }
                if showMuscle, let muscle = muscleStatusSection {
                    MuscleStatusSectionView(
                        data: muscle,
                        toggleBinding: muscleStatusToggleBinding(),
                        isContentVisible: effectiveVisible.muscleStatus
                    )
                }
                if showMuscle && showCalendar {
                    SectionDivider()
                }
                if showCalendar, let cal = calendarSection {
                    CalendarSectionView(
                        data: cal,
                        toggleBinding: calendarToggleBinding(),
                        isContentVisible: effectiveVisible.calendar
                    )
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 带上 App Store 二维码 — 跟完成卡 / routine 卡一致, 让 History 分享出去的图也能扫码下载.
            ShareCardFooter(qrPayload: MasoLinks.appStore)
        }
        .background(MasoColor.background)
    }

    private func todayStatusToggleBinding() -> Binding<Bool>? {
        guard let editToggles else { return nil }
        return Binding(
            get: { editToggles.wrappedValue.todayStatus },
            set: { editToggles.wrappedValue.todayStatus = $0 }
        )
    }

    /// 编辑模式 → 始终画 (含 header + toggle); 渲染模式 → 只画 visible == true 的 section.
    private func shouldShowSection(visible: Bool) -> Bool {
        editToggles != nil || visible
    }

    // MARK: - Toggle bindings (仅编辑模式生效)

    private func workoutToggleBinding() -> Binding<Bool>? {
        guard let editToggles else { return nil }
        return Binding(
            get: { editToggles.wrappedValue.workout },
            set: { editToggles.wrappedValue.workout = $0 }
        )
    }

    private func muscleStatusToggleBinding() -> Binding<Bool>? {
        guard let editToggles else { return nil }
        return Binding(
            get: { editToggles.wrappedValue.muscleStatus },
            set: { editToggles.wrappedValue.muscleStatus = $0 }
        )
    }

    private func calendarToggleBinding() -> Binding<Bool>? {
        guard let editToggles else { return nil }
        return Binding(
            get: { editToggles.wrappedValue.calendar },
            set: { editToggles.wrappedValue.calendar = $0 }
        )
    }
}

// MARK: - Section data

/// 训练 (一次性 session) — 在"训练完成"和"训练记录详情"两个入口用.
struct WorkoutSectionData {
    /// 显示在 kicker 之外的"日期"行 (e.g. "Monday, Jan 12"). nil = 不显示日期 (e.g. 自由训练
    /// 的训练完成屏会传 nil, 不强行展示日期).
    var dateLabel: String? = nil
    /// 训练计划名. 自由训练时传 "Free workout" (或本地化的 "Quick Workout") — 不为空,
    /// 让卡片标题永远有内容.
    var planName: String
    var durationLabel: String?    // "12m 30s" / "~24m" — nil 时该 stat 不显示
    var setCount: Int
    var exerciseCount: Int?       // nil 时该 stat 不显示 (训练完成屏没记录这个)
    var prCount: Int
    /// 显示在 BodyHint 上的肌群 (训练涉及的). 空数组 → 不渲染 BodyHint.
    var muscles: [MuscleGroup]
    /// 前 4 个动作名 (用 chip 渲染). 空数组 → 不渲染 chip row.
    var exerciseNames: [String]

    init(
        dateLabel: String? = nil,
        planName: String,
        durationLabel: String? = nil,
        setCount: Int,
        exerciseCount: Int? = nil,
        prCount: Int = 0,
        muscles: [MuscleGroup] = [],
        exerciseNames: [String] = []
    ) {
        self.dateLabel = dateLabel
        self.planName = planName
        self.durationLabel = durationLabel
        self.setCount = setCount
        self.exerciseCount = exerciseCount
        self.prCount = prCount
        self.muscles = muscles
        self.exerciseNames = exerciseNames
    }
}

/// 肌肉状态 (本周 muscle activity) — HistoryScreen 顶部肌肉卡入口默认开.
struct MuscleStatusSectionData {
    /// muscle → opacity 衰减映射 (跟 HistoryScreen 的 opacityFor 同义). 没数据 → 该肌群默认灰.
    var muscleOpacity: (MuscleGroup) -> Double?
    /// 是否仅显示大肌群 (无细分) — 跟 Settings.muscleDetailEnabled 取反.
    var coarseOnly: Bool
    var workoutsThisWeek: Int
    var totalSetsThisWeek: Int
    var muscleSectionsHit: Int
}

/// 训练日历 (本周 7 天 frequency) — WorkoutCalendarScreen 默认开.
struct CalendarSectionData {
    /// 本周训练过的 startOfDay set
    var sessionDates: Set<Date>
    var totalSets: Int
    var streakDays: Int
}

// MARK: - Section subviews

/// 通用 section kicker — 全大写 + spaced, 跟主卡片标题视觉区分.
/// 仅在多 section 同时存在时显示, 单 section 模式不必加 kicker (避免视觉冗余).
private struct SectionKicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(2)
            .foregroundStyle(MasoColor.accent)
    }
}

// MARK: Today's Status section (顶部"加照片")

private struct TodayStatusSectionView: View {
    let userPhoto: UIImage?
    let onTapAddPhoto: (() -> Void)?
    var toggleBinding: Binding<Bool>? = nil
    var isContentVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header — kicker + 大标题 + (optional) inline toggle
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(text: "Today")
                HStack(alignment: .center, spacing: 8) {
                    Text("My Workout")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(2)
                    Spacer()
                    if let toggleBinding {
                        InlineSectionToggle(isOn: toggleBinding)
                    }
                }
            }

            // 照片 / 占位 content — toggle off 时隐藏
            if isContentVisible {
                photoContent
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var photoContent: some View {
        if let photo = userPhoto {
            // 已加照片 — 严格 1:1 圆角正方形 + 细描边. tap 弹 confirmationDialog 换/删.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(MasoColor.borderSoft, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { onTapAddPhoto?() }
        } else if let onTapAddPhoto {
            // 还没加照片 + preview 模式: 虚线占位框
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                MasoColor.borderSoft,
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(MasoColor.textDim)
                            Text("Add a photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                        }
                    }
                    .background(MasoColor.surface.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .contentShape(Rectangle())
                .onTapGesture { onTapAddPhoto() }
        }
        // 渲染模式 + 无 photo: 不画 (UnifiedShareCard 已经在 showTodayStatus 那一关挡掉了)
    }
}

/// Section 之间的细分隔线 — 半透明 borderSoft, 1pt 厚.
/// 配合 VStack spacing 20pt, section 间总间距 ≈ 41pt (够宽 + 视觉有明确分界).
private struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(MasoColor.borderSoft)
            .frame(height: 1)
    }
}

/// 内联 section toggle — 缩放到 ~40×24 跟 22pt bold 标题在同一行显得不喧宾夺主.
/// 仅编辑模式 (toggleBinding 非 nil) 出现.
private struct InlineSectionToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(MasoColor.accent)
            .scaleEffect(0.78)
            .frame(width: 40)
    }
}

// MARK: Workout section

private struct WorkoutSectionView: View {
    let data: WorkoutSectionData
    var toggleBinding: Binding<Bool>? = nil  // 非 nil = 编辑模式 → 大标题右侧画 toggle
    var isContentVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: kicker + 大标题 + (optional) toggle
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(text: data.dateLabel ?? "Workout")
                HStack(alignment: .center, spacing: 8) {
                    Text(data.planName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(2)
                    Spacer()
                    if let toggleBinding {
                        InlineSectionToggle(isOn: toggleBinding)
                    }
                }
            }

            if isContentVisible {
                // 关键数据 — 标签走本地化 (跟 ShareCardFooter 的 stat 标签同一套键)
                HStack(spacing: 18) {
                    if let dur = data.durationLabel {
                        ShareStat(value: dur, label: NSLocalizedString("Duration", comment: ""))
                    }
                    ShareStat(value: "\(data.setCount)", label: NSLocalizedString("Sets", comment: ""))
                    if let exc = data.exerciseCount {
                        ShareStat(value: "\(exc)", label: NSLocalizedString("Exercises count", comment: "exercise count stat label"))
                    }
                    if data.prCount > 0 {
                        ShareStat(value: "🏆\(data.prCount)", label: NSLocalizedString("PR", comment: "share stat — personal record"))
                    }
                }
                .padding(.top, 2)

                // 动作 chip 列表 (前 4 个 + "+N more")
                if !data.exerciseNames.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(data.exerciseNames.prefix(4), id: \.self) { name in
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MasoColor.text.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(MasoColor.surfaceHi)
                                .clipShape(Capsule())
                        }
                        if let exc = data.exerciseCount, exc > 4 {
                            Text(String(format: NSLocalizedString("+%lld more", comment: ""), exc - 4))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(MasoColor.surfaceHi)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }

                // BodyHint
                if !data.muscles.isEmpty {
                    HStack {
                        Spacer()
                        BodyHint(
                            muscles: data.muscles,
                            height: 140,
                            region: detectBodyRegion(data.muscles)
                        )
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Muscle status section

private struct MuscleStatusSectionView: View {
    let data: MuscleStatusSectionData
    var toggleBinding: Binding<Bool>? = nil
    var isContentVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: kicker + "Muscle Status" 标题 + (optional) toggle
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(text: "Muscles this week")
                HStack(alignment: .center, spacing: 8) {
                    Text("Muscle Status")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Spacer()
                    if let toggleBinding {
                        InlineSectionToggle(isOn: toggleBinding)
                    }
                }
            }

            if isContentVisible {
                // BodyHint — 同 HistoryScreen 同尺寸 + 同衰减 mapping
                HStack {
                    Spacer()
                    BodyHint(
                        muscles: [],
                        height: 180,
                        opacityFor: data.muscleOpacity,
                        coarseOnly: data.coarseOnly
                    )
                    Spacer()
                }
                .padding(.top, 2)

                // 关键数据 — 标签走本地化 (跟 ShareCardFooter 的 stat 标签同一套键)
                HStack(spacing: 18) {
                    ShareStat(value: "\(data.workoutsThisWeek)", label: NSLocalizedString("Workouts", comment: ""))
                    ShareStat(value: "\(data.totalSetsThisWeek)", label: NSLocalizedString("Total Sets", comment: "share stat — weekly total sets"))
                    ShareStat(value: "\(data.muscleSectionsHit)", label: NSLocalizedString("Groups Hit", comment: "share stat — muscle sections hit"))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Calendar section

private struct CalendarSectionView: View {
    let data: CalendarSectionData
    var toggleBinding: Binding<Bool>? = nil
    var isContentVisible: Bool

    /// 本周 7 天 — 今天 - 6 到今天
    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            cal.date(byAdding: .day, value: -offset, to: today)!
        }
    }

    private var rangeLabel: String {
        let start = weekDates.first ?? Date()
        let end = weekDates.last ?? Date()
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let s = df.string(from: start)
        let e = df.string(from: end)
        return "\(s) – \(e)"
    }

    private var workoutCount: Int {
        weekDates.filter { data.sessionDates.contains($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionKicker(text: rangeLabel)
                HStack(alignment: .center, spacing: 8) {
                    Text("Weekly Workouts")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Spacer()
                    if let toggleBinding {
                        InlineSectionToggle(isOn: toggleBinding)
                    }
                }
            }

            if isContentVisible {
                // 7 天 mini 日历 — 居中显示
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(weekDates, id: \.self) { date in
                            UnifiedDayDot(date: date, trained: data.sessionDates.contains(date))
                        }
                    }
                    Spacer()
                }
                .padding(.top, 4)

                // 关键数据 — 跟上方 7 day dots 一样居中, 保持视觉对齐
                HStack {
                    Spacer()
                    HStack(spacing: 18) {
                        ShareStat(value: "\(workoutCount)/7", label: NSLocalizedString("Days", comment: "share stat — trained days out of 7"))
                        ShareStat(value: "\(data.totalSets)", label: NSLocalizedString("Total Sets", comment: "share stat — weekly total sets"))
                        if data.streakDays > 0 {
                            // 周口径 — 数值 = 连续达标周数 (跟 History tab 的 Week streak 一致)
                            ShareStat(value: "🔥\(data.streakDays)", label: NSLocalizedString("Streak", comment: "share stat — week streak"))
                        }
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 单天的圆点 — 跟 WeeklyFrequencyShareCard 内部 DayDot 同款 (那个是 private, 这里独立一份).
/// 训练日 accent 实心, 未训练 灰圆描边.
private struct UnifiedDayDot: View {
    let date: Date
    let trained: Bool

    private static let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "E"
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
