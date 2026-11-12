import SwiftUI

/// A first-run draft; previews never write preferences, routines or workout records.
struct OnboardingDraft {
    enum Goal: String, CaseIterable, Identifiable {
        case buildMuscle, getStronger, loseFat, generalFitness
        var id: String { rawValue }
        /// Word only. These keys are not the Settings labels: Settings keeps
        /// "增力" / "Lose fat / get lean" and still offers endurance.
        var titleKey: String { "onboarding.goal.\(rawValue)" }
        var title: LocalizedStringKey { LocalizedStringKey(titleKey) }
        var kind: TrainingGoalKind {
            switch self {
            case .buildMuscle: .buildMuscle
            case .getStronger: .getStronger
            case .loseFat: .loseFat
            case .generalFitness: .generalFitness
            }
        }
    }
    var goal: Goal = .buildMuscle
    static let focusOrder: [MuscleGroup] = [.core, .legs, .chest, .back, .shoulders, .arms]
    var focus: Set<MuscleGroup> = []
    var weekdays: Set<Int> = [1, 3, 5]
    var days: Int {
        get { weekdays.count }
        set {
            guard newValue != weekdays.count else { return }
            weekdays = Set(TrainingWeekSchedule.automatic(days: newValue))
        }
    }
    var minutes = TrainingSessionLength.defaultMinutes
    var equipment = TrainingEquipmentDraft()

    mutating func toggle(_ muscle: MuscleGroup) {
        guard let section = muscle.section, MuscleSelector.focusSections.contains(section) else { return }
        if focus.contains(section) { focus.remove(section) } else { focus.insert(section) }
    }

    func applying(to original: UserSettings) -> UserSettings {
        var settings = original
        settings.trainingGoalKind = goal.kind
        settings.defaultSetsPerExercise = goal.kind.recommendedSetsFloor()
        settings.wantStrengthen = MuscleSelector.focusSections.filter(focus.contains)
        settings.weeklyTrainingDays = days
        settings.trainingWeekdays = weekdays.sorted()
        settings.trainingSessionMinutes = minutes
        settings.exercisesPerSession = TrainingSessionLength.exerciseLimit(for: minutes)
        equipment.apply(to: &settings)
        return settings
    }

    @MainActor
    func preview(settings: UserSettings, exercises: [String: Exercise], now: Date = Date()) -> [Plan] {
        guard days > 0 else { return [] }
        let effective = applying(to: settings)
        // Six/seven training days repeat a three-routine PPL rotation, rather
        // than requiring six/seven saved routines for a free first-run profile.
        let routineCount = days > 5 ? 3 : days
        return DataStore.markBuiltIn(Array(DataStore.tunedRecommendedPlans(
            forDays: days, settings: effective, exById: exercises, sets: [], now: now
        ).filter { !$0.steps.isEmpty }.prefix(routineCount))).map { plan in
            var plan = plan
            // No profile or load history has been collected. Ask the user to set
            // working loads rather than presenting the template's reference weights.
            plan.steps = plan.steps.map { step in
                var step = step
                step.weight = nil
                step.setWeights = nil
                return step
            }
            return plan
        }
    }
}

/// Approved direction 01: goal + body focus → schedule → actual plan preview.
struct OnboardingScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var previewOnly = false
    let onDone: (Plan?) -> Void

    private enum Page: Hashable { case schedule, preview }
    @State private var path: [Page] = []
    @State private var draft = OnboardingDraft()
    @State private var previewPlans: [Plan] = []
    @State private var selectedPlanID: String?
    @State private var saveFlow = WorkoutSaveFlow()
    @State private var showPaywall = false
    @State private var showSaveLimit = false
    @State private var didTrackStart = false
    @State private var committing = false
    @State private var generating = false
    @State private var generationTask: Task<Void, Never>?

    private var selectedPlan: Plan? {
        previewPlans.first { $0.id == selectedPlanID } ?? previewPlans.first
    }

    var body: some View {
        AppNavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    CoachConversationContent {
                        if path.isEmpty {
                            goalCard
                        } else {
                            submittedMessage(goalSummary, identifier: "onboarding.answer.goal")
                            if !path.contains(.preview) {
                                scheduleCard.id(Page.schedule)
                            } else {
                                submittedMessage(scheduleSummary, identifier: "onboarding.answer.schedule")
                                previewContent.id(Page.preview)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: path) { _, value in
                    if let page = value.last {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(page, anchor: .top) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if path.contains(.preview) && !generating { conversationFooter }
            }
            .background(AppBackground())
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !path.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            generationTask?.cancel()
                            generating = false
                            path.removeLast()
                        } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Back")
                    }
                }
                if previewOnly {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onDone(nil) } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
            }
        }
        .tint(MasoColor.text)
        .background(MasoColor.background.ignoresSafeArea())
        .sheet(isPresented: $showPaywall) { PaywallScreen(source: "onboarding_save", context: .upgrade) }
        .alert("Routine limit reached", isPresented: $showSaveLimit) {
            Button("Continue without saving") { complete(with: nil) }
            Button("Upgrade") { showPaywall = true }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear { generationTask?.cancel() }
        .onAppear {
            if !previewOnly, !didTrackStart {
                didTrackStart = true
                Analytics.shared.track("onboarding_start")
            }
        }
        .onChange(of: path) { _, new in
            if !previewOnly { Analytics.shared.track("onboarding_step_advance", ["to_step": .int(new.count + 1)]) }
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are your training goals and focus areas?")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.question.goal")
            MuscleBody3DView(fatigueMap: [:], autoRotates: false,
                selectedMuscles: draft.focus, allowsZoom: true, initialZoom: 1.12,
                showsFatigueColors: false, accessibilityID: "onboarding.body",
                selectionHint: "Tap muscles to select; tap again to clear",
                onMuscleTap: { region, _ in
                    if let muscle = region.muscles.first { draft.toggle(muscle); Haptics.selection() }
                })
                .frame(height: 300).frame(maxWidth: .infinity).clipped()
            goalOptions
            sendButton { path.append(.schedule) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground(cornerRadius: 20)
    }

    private var goalSummary: String {
        let goalKey = draft.goal.titleKey
        let muscles = OnboardingDraft.focusOrder.filter(draft.focus.contains).map(\.displayName)
        let focus = muscles.isEmpty ? NSLocalizedString("Full body", comment: "") : muscles.joined(separator: ", ")
        return NSLocalizedString("Training goal", comment: "") + ": " + NSLocalizedString(goalKey, comment: "")
            + "\n" + NSLocalizedString("Muscles", comment: "") + ": " + focus
    }

    private var scheduleSummary: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.currentLocale
        let names = formatter.shortStandaloneWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = draft.weekdays.sorted().map { names[$0 % 7] }.joined(separator: ", ")
        let equipment = HomeTrainingEquipment.allCases.filter(draft.equipment.homeEquipment.contains).map(\.title)
        let environment = draft.equipment.displayedEnvironment.title
            + (draft.equipment.displayedEnvironment == .home && !equipment.isEmpty ? " · " + equipment.joined(separator: ", ") : "")
        return NSLocalizedString("Training days", comment: "") + ": " + days
            + "\n" + NSLocalizedString("Session length", comment: "") + ": " + onboardingMinutes(draft.minutes)
            + "\n" + NSLocalizedString("Training environment", comment: "") + ": " + environment
    }

    private func submittedMessage(_ text: String, identifier: String) -> some View {
        CoachUserTextBubble(text: text)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
            .accessibilityIdentifier(identifier)
    }

    private func sendButton(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        PrimaryActionButton(title: "Send", icon: "arrow.up", size: .regular, action: action)
            .disabled(!enabled).opacity(enabled ? 1 : 0.45)
            .accessibilityIdentifier("onboarding.continue")
    }

    private var goalOptions: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Muscles").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("Tap to select · Pinch to zoom").font(.caption).foregroundStyle(.secondary)
                }
                MuscleSelector(selected: $draft.focus, sectionsOnly: true, showsBalancedOption: true,
                    usesNativeSelectionButtons: true, sectionOrder: OnboardingDraft.focusOrder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Training goal").font(.subheadline.weight(.semibold))
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { goalButtons }
                } else {
                    FlowLayout(spacing: 8, alignment: .leading) { goalButtons }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var goalButtons: some View {
        ForEach(OnboardingDraft.Goal.allCases) { goal in
            NativeSelectionButton(title: Text(goal.title), isSelected: draft.goal == goal) {
                draft.goal = goal
                Haptics.selection()
            }
            .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When and where would you like to train?")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.question.schedule")
            VStack(alignment: .leading, spacing: 12) {
                Text("Training days").font(.headline)
                weekdayPicker
                HStack {
                    Text("Days per week")
                    Spacer(minLength: 12)
                    NumericValueField(value: $draft.days, range: 1...7,
                        accessibilityLabel: NSLocalizedString("Days per week", comment: ""))
                        .frame(width: 52, height: 44)
                        .accessibilityIdentifier("onboarding.days")
                }
                if draft.days == 0 {
                    Text("Choose at least one training day").font(.footnote).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Session length").font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(TrainingSessionLength.options, id: \.self) { minutes in
                        NativeSelectionButton(title: Text(onboardingMinutes(minutes)), isSelected: draft.minutes == minutes) {
                            draft.minutes = minutes; Haptics.selection()
                        }.accessibilityIdentifier("onboarding.duration.\(minutes)")
                    }
                }
            }
            TrainingEnvironmentPicker(draft: $draft.equipment, identifierPrefix: "onboarding")
            sendButton(enabled: draft.days > 0) { generatePreview() }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCardBackground(cornerRadius: 20)
    }

    private func generatePreview() {
        guard !generating else { return }
        let currentDraft = draft
        let effectiveSettings = currentDraft.applying(to: data.settings)
        let fallback = currentDraft.preview(settings: data.settings, exercises: data.exById)
        generating = true
        previewPlans = []
        selectedPlanID = nil
        path.append(.preview)
        generationTask = Task { @MainActor in
            let generated: [Plan]
            #if DEBUG
            if ProcessInfo.processInfo.environment["MASO_ONBOARDING_UI_TEST"] == "1" {
                generated = fallback
            } else {
                let isolated = DataStore(exercises: data.exercises, plans: [], sets: [], settings: effectiveSettings)
                isolated.aiAccess = data.aiAccess
                let result = await isolated.generateAIRoutines(surface: "onboarding")
                generated = result.usedFallback ? fallback : result.plans
            }
            #else
            let isolated = DataStore(exercises: data.exercises, plans: [], sets: [], settings: effectiveSettings)
            isolated.aiAccess = data.aiAccess
                let result = await isolated.generateAIRoutines(surface: "onboarding")
            generated = result.usedFallback ? fallback : result.plans
            #endif
            guard !Task.isCancelled, path.contains(.preview) else { return }
            let maxRoutines = currentDraft.days > 5 ? 3 : currentDraft.days
            previewPlans = Array(generated.filter { !$0.steps.isEmpty }.prefix(maxRoutines)).map { plan in
                var plan = plan
                plan.steps = DataStore.applyTrainingGoal(plan.steps, settings: effectiveSettings, exById: data.exById)
                plan.steps = plan.steps.map { step in
                    var step = step
                    step.weight = nil
                    step.setWeights = nil
                    return step
                }
                return plan
            }
            selectedPlanID = previewPlans.first?.id
            generating = false
            if let first = previewPlans.first {
                await ExerciseDemoService.shared.prefetch(first.steps.map(\.exerciseId), priority: true)
                await ExerciseDemoService.shared.prefetch(previewPlans.dropFirst().flatMap { $0.steps.map(\.exerciseId) })
            }
        }
    }

    private var conversationFooter: some View {
        footer(title: previewOnly ? "Done" : "Save plans & start", enabled: selectedPlan != nil && !committing) {
            if previewOnly { onDone(nil) } else { finish() }
        }
    }

    private var weekdayPicker: some View {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.currentLocale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let fullNames = formatter.standaloneWeekdaySymbols ?? symbols
        return GeometryReader { geometry in
            let diameter = max(24, min(44, (geometry.size.width - 24) / 7))
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { weekday in
                    let selected = draft.weekdays.contains(weekday)
                    Button {
                        if draft.weekdays.contains(weekday) { draft.weekdays.remove(weekday) } else { draft.weekdays.insert(weekday) }
                        Haptics.selection()
                    } label: {
                        Text(symbols[weekday % 7]).font(.caption.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(width: diameter - 16, height: diameter - 16)
                    }
                    .controlSize(.small).buttonBorderShape(.circle)
                    .tint(selected ? MasoColor.accent : MasoColor.text)
                    .applyIf(selected) { $0.nativeGlassProminentButtonStyle() }
                    .applyIf(!selected) { $0.nativeGlassButtonStyle() }
                    .frame(width: diameter, height: diameter)
                    .accessibilityLabel(Text(fullNames[weekday % 7]))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.weekday.\(weekday)")
                }
            }
        }.frame(height: 44)
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if generating {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Building your plan").font(.subheadline).foregroundStyle(MasoColor.textDim)
                }
                .padding(14).background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("onboarding.generating")
            } else {
                Text("Your plan is ready")
                    .font(.system(size: 15)).lineSpacing(3).foregroundStyle(MasoColor.text)
            }
            if generating {
                EmptyView()
            } else if previewPlans.isEmpty {
                ContentUnavailableView("No exercises match", systemImage: "dumbbell")
            } else {
                PlanCardCarousel(plans: previewPlans, horizontalInset: MasoMetrics.pagePaddingHorizontal, onSelectionChange: { id in
                    selectedPlanID = id
                    if let plan = previewPlans.first(where: { $0.id == id }) {
                        Task { await ExerciseDemoService.shared.prefetch(plan.steps.map(\.exerciseId), priority: true) }
                    }
                }) { index, plan in
                    WorkoutCard(
                        plan: plan, exById: data.exById,
                        kicker: String(format: NSLocalizedString("DAY %lld", comment: "coach chat day-card kicker"), index + 1),
                        onStart: {}, prominentStart: false, showStart: false,
                        compactLayout: true, showsExercisePills: true
                    )
                }
                .padding(.horizontal, -MasoMetrics.pagePaddingHorizontal)
                .accessibilityIdentifier("onboarding.planPicker")
                Text("Set your working weights when you train")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func footer(title: LocalizedStringKey, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        footer {
            PrimaryActionButton(title: title, icon: "", size: .large, action: action)
                .disabled(!enabled).opacity(enabled ? 1 : 0.45)
                .accessibilityIdentifier("onboarding.continue")
        }
    }

    private func footer<Control: View>(@ViewBuilder control: () -> Control) -> some View {
        control()
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal).padding(.vertical, 10)
            .background(MasoColor.background)
    }

    private func finish() {
        guard !committing, let selectedPlan else { return }
        committing = true
        saveFlow.commit(previewPlans, replacing: false, data: data) { showSaveLimit = true }
        guard data.areCoachPlansSaved(previewPlans) else { committing = false; return }
        let saved = data.plans.first { $0.name == selectedPlan.name && $0.steps.map(\.exerciseId) == selectedPlan.steps.map(\.exerciseId) } ?? selectedPlan
        complete(with: saved)
    }

    private func complete(with plan: Plan?) {
        data.settings = draft.applying(to: data.settings)
        data.flushSave()
        Analytics.shared.track("onboarding_complete", ["weekly_days": .int(draft.days), "focus_count": .int(draft.focus.count)])
        onDone(plan)
    }
}

func onboardingMinutes(_ minutes: Int) -> String {
    let formatter = DateComponentsFormatter()
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = LanguageManager.currentLocale
    formatter.calendar = calendar
    formatter.allowedUnits = [.minute]
    formatter.unitsStyle = .short
    return formatter.string(from: TimeInterval(minutes * 60)) ?? minutes.formatted(.number.locale(LanguageManager.currentLocale))
}

// MARK: - Flow layout (全 app 复用: MuscleSelector / 动作库 / 分享卡 等)

// 极简 flow layout — chips 自动换行 (SwiftUI 在 iOS 16+ 有 Layout 协议, 这里用一个最小实现)
/// Tag-cloud 风格 wrap layout — chips 横向排满一行就换行.
/// 支持 leading / center / trailing 横向对齐 (per-row 居中是 QuickMuscleStep 的需求,
/// 让"选择肌群"区每一行 chip 都视觉居中, 不是默认靠左).
enum FlowAlignment { case leading, center, trailing }

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// 每一行内 chip 的横向对齐. 默认 leading (兼容老调用方).
    var alignment: FlowAlignment = .leading

    /// 内部计算: 把所有 subview 按 maxWidth 切成 rows. 每个 row 记录子 size 列表 + content 宽 + 行高.
    private struct LayoutResult {
        var rows: [Row]
        var totalSize: CGSize
        struct Row {
            var sizes: [CGSize]
            var contentWidth: CGFloat   // 包含 chip 间 spacing 的实际总宽
            var height: CGFloat
        }
    }

    private func compute(subviews: Subviews, maxWidth: CGFloat) -> LayoutResult {
        var rows: [LayoutResult.Row] = []
        var curSizes: [CGSize] = []
        var curWidth: CGFloat = 0
        var curHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            let projected = curSizes.isEmpty ? size.width : curWidth + spacing + size.width
            if !curSizes.isEmpty && projected > maxWidth {
                rows.append(.init(sizes: curSizes, contentWidth: curWidth, height: curHeight))
                curSizes = [size]
                curWidth = size.width
                curHeight = size.height
            } else {
                if !curSizes.isEmpty { curWidth += spacing }
                curSizes.append(size)
                curWidth += size.width
                curHeight = max(curHeight, size.height)
            }
        }
        if !curSizes.isEmpty {
            rows.append(.init(sizes: curSizes, contentWidth: curWidth, height: curHeight))
        }
        let totalH = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        let maxRowW = rows.map(\.contentWidth).max() ?? 0
        return LayoutResult(rows: rows, totalSize: CGSize(width: maxRowW, height: totalH))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return compute(subviews: subviews, maxWidth: maxWidth).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = compute(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        var idx = 0
        for row in result.rows {
            // 每行起点 X 跟 alignment 走 — center 用 (bounds.w - rowContent) / 2 把行视觉拉到中线
            let startX: CGFloat
            switch alignment {
            case .center:   startX = bounds.minX + (bounds.width - row.contentWidth) / 2
            case .trailing: startX = bounds.maxX - row.contentWidth
            case .leading:  startX = bounds.minX
            }
            var x = startX
            for size in row.sizes {
                // 垂直方向: 把每个 subview 在 row.height 范围内居中.
                // 解决场景: major chip 14pt 字号 比 sub chip 11pt 字号高, top-align 会让小 chip
                // 浮在大 chip 上沿, 视觉错位. 改成中线对齐, 不管 chip 高矮都视觉平.
                let yCentered = y + (row.height - size.height) / 2
                subviews[idx].place(at: CGPoint(x: x, y: yCentered), proposal: ProposedViewSize(size))
                x += size.width + spacing
                idx += 1
            }
            y += row.height + spacing
        }
    }
}
