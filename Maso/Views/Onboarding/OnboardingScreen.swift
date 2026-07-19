import SwiftUI

// Onboarding — 一问一屏的精细向导 (替代旧的"单页渐进展开").
//   1 性别  2 训练目标  3 年龄  4 体重  5 每周训练次数  6 想加强的肌群  7 可用器材
//
// 交互规则:
//   · 选项型 (性别 / 训练目标): 单选, 点一下即自动跳下一步 (带 0.18s 让选中态可感知).
//   · 拨盘型 (年龄 / 体重): 上下滚动的 wheel, 选体重时默认落在该性别平均值, 调完点"下一步"确定.
//   · 多选型 (肌群 / 器材): 不能自动跳, 用"下一步 / 生成计划"收尾.
//   · 第 2 步起, 左下角恒有"返回"回到上一步重选 (即便上一步是自动跳进来的).
struct OnboardingScreen: View {
    @Environment(DataStore.self) private var data
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        case gender = 1, goal, age, weight, days, focus, equipment, note
        static let total = Step.allCases.count
        /// 步骤短名 — 分析事件 to_step_name 用 (无 PII, 纯枚举名).
        var name: String {
            switch self {
            case .gender: return "gender"
            case .goal: return "goal"
            case .age: return "age"
            case .weight: return "weight"
            case .days: return "days"
            case .focus: return "focus"
            case .equipment: return "equipment"
            case .note: return "note"
            }
        }
    }

    @State private var step: Step = .gender
    /// 切屏滑动方向 — 前进=新屏从右进, 返回=从左进.
    @State private var goingForward = true

    @State private var gender: Gender? = nil
    /// 训练目标 (5 档) — 选项型(自动跳, 无 Next), 故**不预选**: 预选会让用户以为已完成、
    /// 不知道还要点一下卡片才前进. 选完才有值; confirm 用 ?? .buildMuscle 兜底
    /// (实际到不了 confirm 时仍 nil —— 目标步无 Next, 必须先点一个目标才能离开).
    @State private var goal: TrainingGoalKind? = nil
    @State private var age: Int = 25
    /// 体重: 选完性别按平均值 re-seed, 除非用户已手动拨过 (weightTouched). 存储恒 canonical kg.
    @State private var weight: Double = 75
    @State private var weightTouched = false
    /// 体重步的 kg/lb 分段 — 默认跟系统度量制 (美区 lb), 不逼 lb 用户做磅→公斤心算 (P1#21).
    /// confirm 时写进 settings.weightUnit, 全 app 单位从第一天就跟引导一致.
    @State private var weightUnit: WeightUnit =
        Locale.current.measurementSystem == .metric ? .kg : .lb
    @State private var daysPerWeek: Int = 3               // 拨盘默认 3 天/周 (拨盘必有位置, 同年龄/体重)
    @State private var strengthen: Set<MuscleGroup> = []  // 不预选 — 留空 = 均衡
    /// 可用器材 — 多选. 留空 = 不限制 (= 健身房全器械, 跟 settings.availableEquipment 的"空=不限"语义一致).
    @State private var equipment: Set<EquipmentCategory> = []
    /// 收尾一步的自由输入 (伤病/喜好/时长, 可留空跳过) — confirm 时写进 coachMemory (长期生效)
    /// 并作 focusNote 喂给首份 AI 生成 (PRIORITY 行 + 定向检索, 立即生效).
    @State private var coachNote: String = ""
    @FocusState private var coachNoteFocused: Bool
    /// 确认后进入"AI 生成中"过渡 (感知型 — seedStarterRoutines 是瞬时本地生成).
    @State private var generating = false
    /// 真 AI 首份计划生成完成 (成功或回落) → 过渡页"Building"步据此落定, 把动画绑到真实调用延迟.
    @State private var aiReady = false
    /// onboarding_start 只报一次 (root body 首次出现于 gender 步时).
    @State private var didTrackStart = false

    var body: some View {
        ZStack {
            MasoColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                progressHeader
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, MasoMetrics.pagePaddingTop)

                // 问题贴顶 + 选项沉底: stepContent 填满 header 与 bottomBar 之间,
                // 内部 = 标题(靠上) → Spacer → 选项(靠下), 拇指更易触及.
                stepContent
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .id(step)
                    .transition(slideTransition)

                bottomBar
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.bottom, 10)
            }
        }
        // 确认后盖上"AI 生成中"过渡 — 自身全屏不透明, 结束自动 onDone() 落地 Today.
        .overlay {
            if generating {
                AIGeneratingView(isReady: aiReady, onComplete: onDone)
                    .transition(.opacity)
            }
        }
        // onboarding_start — 引导首屏 (gender 步) 出现时一次性上报.
        .onAppear {
            if !didTrackStart, step == .gender {
                didTrackStart = true
                Analytics.shared.track("onboarding_start")
            }
        }
    }

    // MARK: - 顶部进度

    private var progressHeader: some View {
        VStack(alignment: .center, spacing: 10) {
            // 5 段进度条 — 直观传达"被拆成 5 个细步".
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? MasoColor.accent : MasoColor.surface)
                        .frame(height: 5)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            Text(String(format: NSLocalizedString("STEP %1$lld / %2$lld", comment: "onboarding step counter"), step.rawValue, Step.total))
                .font(.system(size: 12, weight: .bold)).tracking(2)
                .foregroundStyle(MasoColor.accent)
        }
    }

    // MARK: - 分步内容

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .gender: genderStep
        case .goal:   goalStep
        case .age:    ageStep
        case .weight: weightStep
        case .days:   daysStep
        case .focus:  focusStep
        case .equipment: equipmentStep
        case .note:   noteStep
        }
    }

    // 8) 自由输入 (收尾) — 用户用自己的话补要求 (伤病/喜好/时长), AI 综合画像 + 动作库 + 这段话
    //    生成首份 routine. 可留空跳过 (按钮恒可点); 文字会存进教练记忆, 以后每次生成都生效.
    private var noteStep: some View {
        stepBody("Anything else for your AI coach?",
                 "Injuries, preferences, time limits — in your own words. The AI combines this with everything above. Optional.") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $coachNote)
                    .focused($coachNoteFocused)
                    .font(.system(size: 16))
                    .foregroundStyle(MasoColor.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 150, maxHeight: 200)
                    .background(MasoColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if coachNote.isEmpty {
                    // placeholder — TextEditor 原生没有, 手叠一层; 不拦点击.
                    Text("e.g. Old shoulder injury — avoid overhead pressing. I like dumbbells, 45 minutes max.")
                        .font(.system(size: 15))
                        .foregroundStyle(MasoColor.textFaint)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        // 点输入框外收键盘 — 主按钮在键盘上方仍可直接点.
        .contentShape(Rectangle())
        .onTapGesture { coachNoteFocused = false }
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(subtitle))
                .font(.system(size: 16))
                .foregroundStyle(MasoColor.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)   // 标题 / 副标题 居中
    }

    /// 每步统一骨架: 问题贴顶居中, 选项沉到底部 (拇指易触), 中间 Spacer 撑开.
    @ViewBuilder
    private func stepBody<Input: View>(_ title: String, _ subtitle: String,
                                       @ViewBuilder _ input: () -> Input) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 16)   // 标题离进度条一点距离 — 整体靠上
            stepTitle(title, subtitle)
            Spacer(minLength: 24)           // 把选项推到下方
            input()
                .frame(maxWidth: .infinity) // 选项区横向居中
            Color.clear.frame(height: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 1) 性别 — 选项型, 单选自动跳.
    private var genderStep: some View {
        stepBody("What's your gender?", "We use this to set sensible starting weights.") {
            VStack(spacing: 14) {
                ForEach([Gender.male, .female, .other], id: \.self) { g in
                    Button { selectGender(g) } label: {
                        // genderLabel 返回 key — Text(LSK) 才走本地化. 文字居中, ✓ 叠右侧.
                        Text(LocalizedStringKey(genderLabel(g)))
                            .font(.system(size: 21, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(gender == g ? MasoColor.accent : MasoColor.surface)
                            .foregroundStyle(gender == g ? .black : MasoColor.text)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .trailing) {
                                if gender == g {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.trailing, 20)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 2) 训练目标 — 选项型, 单选自动跳. 每行 icon + 标题 + 副标题 (比性别多一行说明,
    //    因为目标直接决定 reps/组间歇/动作选择, 用户得看清差别).
    private var goalStep: some View {
        stepBody("What's your main goal?", "We'll tune reps, rest, and exercise picks to match.") {
            VStack(spacing: 12) {
                ForEach(TrainingGoalKind.allCases, id: \.self) { g in
                    let on = goal == g
                    Button { selectGoal(g) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: g.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(g.displayName)   // displayName 已走 NSLocalizedString
                                    .font(.system(size: 18, weight: .bold))
                                Text(g.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(on ? .black.opacity(0.7) : MasoColor.textDim)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if on {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? MasoColor.accent : MasoColor.surface)
                        .foregroundStyle(on ? .black : MasoColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 3) 年龄 — 拨盘.
    private var ageStep: some View {
        stepBody("How old are you?", "Helps us tune your training volume.") {
            wheel(selection: Binding(get: { age }, set: { age = $0 }),
                  range: 12...90) { "\($0)" }
        }
    }

    // 3) 体重 — 拨盘, 默认落在该性别平均值. kg/lb 分段切换, 存储仍 canonical kg.
    private var weightStep: some View {
        stepBody("What's your weight?", "We seed your starting loads from this — change any later.") {
            VStack(spacing: 18) {
                // kg / lb 分段 — 两个胶囊 (跟性别选项同套视觉语言, 选中 = accent 底黑字).
                HStack(spacing: 8) {
                    ForEach([WeightUnit.kg, .lb], id: \.self) { u in
                        Button {
                            guard u != weightUnit else { return }
                            Haptics.tap(); SoundPlayer.shared.playTick()
                            weightUnit = u
                        } label: {
                            Text(u.label)
                                .font(.system(size: 15, weight: .heavy))
                                .padding(.horizontal, 24).padding(.vertical, 9)
                                .background(weightUnit == u ? MasoColor.accent : MasoColor.surface)
                                .foregroundStyle(weightUnit == u ? .black : MasoColor.textDim)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 拨盘按当前单位显示/取值; 存储换算回 kg. lb 范围 ≈ 30...200 kg 的等值区间.
                wheel(selection: Binding(
                    get: { Int(weightUnit.fromKg(weight).rounded()) },
                    set: { weight = weightUnit.toKg(Double($0)); weightTouched = true }),
                      range: weightUnit == .kg ? 30...200 : 66...440) { "\($0) \(weightUnit.label)" }
                // 换单位重建滚轮 — WheelPicker 的 centerID 是内部 state, 不重建不会滚到换算后的新值;
                // 重建也让它的 ready 门重置, 初始程序化定位不会误置 weightTouched.
                .id(weightUnit)
            }
        }
    }

    // 4) 每周次数 — 拨盘 (同年龄/体重: 转到目标值后点"下一步").
    private var daysStep: some View {
        stepBody("How many days a week do you train?", "We'll size your weekly plan to fit.") {
            wheel(selection: $daysPerWeek, range: 1...6) { "\($0)" }
        }
    }

    // 5) 重点肌群 — 多选, 需确认. chip 放大 + 落在屏幕中下段 (上 2 : 下 1 的 Spacer 比例),
    //    并跟底部按钮留 ≥40 间隔.
    private var focusStep: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 16)
            stepTitle("Which muscles do you want to focus on?", "Pick any — or none for a balanced routine.")
            Spacer(minLength: 24)
            Spacer(minLength: 24)
            // 只 6 个大 section — 跟 Settings / 选动作页 Muscle 筛选一致. 居中 + 放大.
            MuscleSelector(selected: $strengthen, sectionsOnly: true, chipAlignment: .center, largeChips: true)
            Spacer(minLength: 40)   // 跟下方"Next"按钮的间隔
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 6) 可用器材 — 多选. 留空 = 健身房全器械; 选了 = 推荐计划只用这些 (做不了的动作自动换可用替代).
    //    让 day-1 首份计划就贴合用户实际器材, 不再给哑铃用户塞杠铃动作.
    private var equipmentStep: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 16)
            stepTitle("What can you train with?", "Pick what you have — leave all off if you train at a full gym.")
            Spacer(minLength: 24)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(EquipmentCategory.allCases) { cat in
                    let on = equipment.contains(cat)
                    Button {
                        Haptics.tap(); SoundPlayer.shared.playTick()
                        if on { equipment.remove(cat) } else { equipment.insert(cat) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cat.icon).font(.system(size: 15, weight: .semibold))
                            Text(cat.displayName)   // displayName 已走 NSLocalizedString
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? MasoColor.accent : MasoColor.surface)
                        .foregroundStyle(on ? .black : MasoColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 拨盘 — 自定义滚轮 (年龄 / 体重共用).
    /// 不用原生 `.wheel`: 它行高固定, 字号一大数字就重叠, 选中框也加不高。自己做才能
    /// 同时满足"数字大 + 行距松 + 选中框高 + 字距宽"。
    private func wheel(selection: Binding<Int>, range: ClosedRange<Int>,
                       label: @escaping (Int) -> String) -> some View {
        WheelPicker(selection: selection, values: Array(range), label: label)
    }

    // MARK: - 底部导航 (返回 / 下一步·确认)

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 第 2 步起 左下角 返回.
            if step != .gender {
                Button(action: { SoundPlayer.shared.playTick(); goBack() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                        Text("Back").font(.system(size: 17, weight: .semibold))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .foregroundStyle(MasoColor.text)
                    // 工具钮 → 素玻璃胶囊 (映射表③), 字色不变; 旧系统保留 surface 底.
                    .glassCapsuleButtonBackground(fallback: MasoColor.surface)
                }
                .buttonStyle(.plain)
            }
            // 主按钮填满剩余宽度 (更宽好按) + 单行不折行. 选项型 (性别) 自动跳, 无主按钮.
            if let primary = primaryAction {
                Button(action: { SoundPlayer.shared.playTap(); primary.action() }) {
                    Text(LocalizedStringKey(primary.title))
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.black)
                        // 主 CTA 系统玻璃 (映射表①), 旧系统保留实心 accent; 选项行/拨盘不动.
                        .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.85), fallback: MasoColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var primaryAction: (title: String, action: () -> Void)? {
        switch step {
        case .gender: return nil                            // 性别仍是选项型, 单选自动跳
        case .goal:   return nil                            // 目标也是选项型, 单选自动跳
        case .age:    return ("Next", { advance(to: .weight) })
        case .weight: return ("Next", { advance(to: .days) })
        case .days:   return ("Next", { advance(to: .focus) })   // 改拨盘后需"下一步"
        case .focus:  return ("Next", { advance(to: .equipment) })
        case .equipment: return ("Next", { advance(to: .note) })
        // 收尾自由输入 — 可留空 (Optional 写在副标题里), 按钮恒可点; 有字没字都从这里生成.
        case .note: return ("Build My Routine", { coachNoteFocused = false; confirm() })
        }
    }

    // MARK: - 导航 / 选择

    private func advance(to s: Step) {
        Analytics.shared.track("onboarding_step_advance", [
            "to_step": .int(s.rawValue),
            "to_step_name": .string(s.name),
            "direction": .string("forward"),
        ])
        goingForward = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = s }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        Analytics.shared.track("onboarding_step_advance", [
            "to_step": .int(prev.rawValue),
            "to_step_name": .string(prev.name),
            "direction": .string("back"),
        ])
        goingForward = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = prev }
    }

    private func selectGender(_ g: Gender) {
        gender = g
        if !weightTouched { weight = avgWeight(g) }   // 体重拨盘默认 = 该性别平均值
        Haptics.tap()
        SoundPlayer.shared.playTap()
        // 0.18s 让选中态 (绿底 + ✓) 被看见再滑走, 不显得突兀.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { advance(to: .goal) }
    }

    private func selectGoal(_ g: TrainingGoalKind) {
        goal = g
        Haptics.tap()
        SoundPlayer.shared.playTap()
        // 同性别: 0.18s 让选中态可感知再滑走.
        // guard step == .goal — 0.18s 窗口内用户可能已点 Back 回到 gender (goBack 不取消这个闭包),
        // 无条件 advance 会把 Back 吞掉直落 age 步; 只有仍停在 goal 步时才前进.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard step == .goal else { return }
            advance(to: .age)
        }
    }

    /// 各性别的起始平均体重 (kg) — 仅作体重拨盘默认值, 用户可调.
    private func avgWeight(_ g: Gender) -> Double {
        switch g { case .male: return 75; case .female: return 60; case .other: return 68 }
    }

    private func genderLabel(_ g: Gender) -> String {
        switch g { case .male: return "Male"; case .female: return "Female"; case .other: return "Other" }
    }

    /// 年龄分桶 — 事件里只报区间, 不报原值 (无 PII).
    private static func ageBand(_ age: Int) -> String {
        switch age {
        case ..<18: return "<18"
        case 18...24: return "18-24"
        case 25...34: return "25-34"
        case 35...44: return "35-44"
        case 45...54: return "45-54"
        case 55...64: return "55-64"
        default: return "65+"
        }
    }

    /// 体重 (kg) 分桶 — 事件里只报区间, 不报原值 (无 PII).
    private static func weightBand(_ kg: Double) -> String {
        switch kg {
        case ..<50: return "<50"
        case 50..<60: return "50-59"
        case 60..<70: return "60-69"
        case 70..<80: return "70-79"
        case 80..<90: return "80-89"
        case 90..<100: return "90-99"
        default: return "100+"
        }
    }

    private func confirm() {
        data.settings.gender = gender
        // ⚠️ 先写 trainingGoalKind —— didSet 会级联设 trainingGoal + defaultRestSeconds.
        //    填补了旧引导从不设目标 (struct 默认 hypertrophy) 的缺口.
        data.settings.trainingGoalKind = goal ?? .buildMuscle
        data.settings.age = age
        data.settings.weight = weight
        data.settings.weightUnit = weightUnit   // 体重步选的单位 = 全 app 单位 (RootView 同步 WeightUnitProvider)
        data.settings.weeklyTrainingDays = daysPerWeek
        data.settings.wantStrengthen = Array(strengthen)
        data.settings.availableEquipment = equipment.map { $0.rawValue }   // 器材约束 → 首份计划只用可用器材
        // 收尾自由输入 → 教练记忆 (COACH NOTES 块, 以后每次 AI 生成都带上; Settings "Tell your AI coach" 可改).
        let note = coachNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { data.appendCoachNote(note) }
        data.flushSave()   // 先持久化偏好 (即使 AI 调用挂掉, 偏好也已落盘)
        // onboarding_complete — 画像锁定时上报. ⚠️ 无 PII: 年龄/体重**分桶** (非原值), 其余只报计数/枚举.
        Analytics.shared.track("onboarding_complete", [
            "gender": .string(gender?.rawValue ?? "unspecified"),
            "goal_kind": .string((goal ?? .buildMuscle).rawValue),
            "age_band": .string(Self.ageBand(age)),
            "weight_band": .string(Self.weightBand(weight)),
            "weekly_days": .int(daysPerWeek),
            "focus_count": .int(strengthen.count),
            "equipment_count": .int(equipment.count),
            "note_length": .int(note.count),   // 只报长度 — 自由文本内容属 PII, 不上报
        ])
        // ⚠️ 不在这里置 onboardingCompleted —— RootView 用它做门控, 一置就立刻切走 OnboardingScreen,
        //    "AI 生成中"过渡(generating overlay 挂在 OnboardingScreen 上)就来不及显示.
        //    改由过渡结束时的 onDone() 去置 (见 RootView). 这里只点亮过渡.
        withAnimation(.easeInOut(duration: 0.35)) { generating = true }
        // Path B: 真 AI 生成首份计划 (generateFirstPlanViaAI 内部先种本地起步保证非空, 再尝试真 LLM
        // 作为今日推荐, 失败回落). 完成后 aiReady=true → 过渡页"Building"步落定.
        Task {
            // 自由输入作 focusNote — PRIORITY 行 + 定向检索, 首份计划立即体现 (coachMemory 管长期).
            await data.generateFirstPlanViaAI(userPrompt: note.isEmpty ? nil : note)
            withAnimation { aiReady = true }
        }
    }
}

// MARK: - 自定义滚轮 (拨盘)

/// 自定义滚轮选择器 — 替代原生 `.wheel` (后者行高固定, 放大字号会重叠, 选中框也加不高)。
/// 用 ScrollView + `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(anchor:.center)`
/// 实现居中吸附; 行高 / 字号 / 选中框 / 字距全可控。居中那行放大加亮, 其余缩小淡出。
private struct WheelPicker: View {
    @Binding var selection: Int
    let values: [Int]
    let label: (Int) -> String

    /// 当前吸附到中心的值; 滚动时实时更新. 初始 nil, 出现后再设为 selection 才会真正居中
    /// (scrollPosition 已知毛病: 初值在首次 layout 时不生效, 必须出现后变化一次).
    @State private var centerID: Int?
    /// 居中定位完成前不外抛 selection — 否则初始那次程序化定位会误把 weightTouched 置真.
    @State private var ready = false
    /// 触觉/音效节流时间戳 — 大力甩动时 centerID 以帧率连续变, 每帧都发 Haptics + scheduleBuffer
    /// 会把主线程/触觉引擎打满一小会儿, 甩完立即点下方「Next」会被丢 (体重量程最大甩得最远, 最明显).
    /// 限到 ~55ms 发一次: 慢速逐格滚动仍每格响, 快甩不再机枪连发. selection 写回保持即时 (帧率级无碍).
    @State private var lastTickAt: Date = .distantPast

    private let rowHeight: CGFloat = 64    // 行高调高 → 选中框更高 + 行距更松
    private let visibleRows: CGFloat = 5

    private var height: CGFloat { rowHeight * visibleRows }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { v in
                    let isCenter = centerID == v
                    Text(label(v))
                        .font(.system(size: isCenter ? 40 : 30, weight: isCenter ? .bold : .regular))
                        .tracking(3)                                   // 字距放宽
                        .foregroundStyle(isCenter ? MasoColor.text : MasoColor.textDim.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {                                // 点某行 → 吸附到中心
                            withAnimation(.easeInOut(duration: 0.2)) { centerID = v }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centerID, anchor: .center)
        // 上下留白 = 让首尾值也能滚到正中.
        .contentMargins(.vertical, (height - rowHeight) / 2, for: .scrollContent)
        .frame(height: height)
        // 固定在正中的选中框 (在内容之后, 滚动数字从其上方掠过).
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MasoColor.surface)
                .frame(height: rowHeight)
        }
        .onAppear {
            // 出现后再设 (nil → selection), scrollPosition 才会把它滚到正中.
            DispatchQueue.main.async {
                centerID = selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ready = true }
            }
        }
        .onChange(of: centerID) { _, new in
            guard ready, let n = new else { return }   // 初始定位期不外抛
            selection = n                              // 写回即时 (帧率级, 不是瓶颈)
            // 触觉 + 音效节流 (~55ms/次): 防大力甩动把主线程打满 → 甩完点 Next 被丢.
            let now = Date()
            guard now.timeIntervalSince(lastTickAt) >= 0.055 else { return }
            lastTickAt = now
            Haptics.selection()               // 轻"咔哒"触觉 (同系统 Picker)
            SoundPlayer.shared.playTick()     // 极轻 tick 声 (随静音开关静默)
        }
    }
}

// MARK: - AI 生成中过渡

/// Onboarding 确认后的"AI 正在生成训练计划"过渡.
/// 设计: 不一次性把步骤列完, 而是**逐步揭示** —— 每步先转圈 (进行中), 完成打 ✓ 累积成清单,
/// 让用户感知 AI 在分阶段工作; 末步落定后中央大 ✓ 弹跳庆祝, 再落地主界面.
/// 每步带极轻 tick, 庆祝用 chime + success 触觉. 总时长 ~4s (够感知, 不拖沓).
private struct AIGeneratingView: View {
    /// 真 AI 首份计划是否已生成完 (成功或回落) — "Building"步据此落定, 把动画绑到真实 LLM 延迟.
    let isReady: Bool
    let onComplete: () -> Void

    /// 步骤文案 (本地化 key). 前 2 条是"准备请求"步 (固定计时), 第 3 条"Building"等真 AI, 第 4 条成功 + 庆祝.
    private let steps = [
        "Uploading your data",
        "Analyzing your stats",
        "Building your plan",
        "Your plan is ready",
    ]

    @State private var current = 0     // 已上场到第几步 (0-based)
    @State private var done = -1       // 已打勾到第几步索引
    @State private var celebrate = false
    @State private var pulse = false
    @State private var buildingMinElapsed = false   // "Building"步至少停留过最短时长
    @State private var finished = false             // 防止落定逻辑重复触发

    var body: some View {
        ZStack {
            MasoColor.background.ignoresSafeArea()
            VStack(spacing: 40) {
                centerBadge
                Text(celebrate ? "All set!" : "Creating your AI plan")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .contentTransition(.opacity)
                checklist
            }
            .padding(.horizontal, 40)
        }
        .onAppear(perform: run)
        // 真 AI 调用完成 → 尝试落定 (若 Building 最短时长也满足).
        .onChange(of: isReady) { _, _ in finishIfReady() }
    }

    // 中央品牌徽标 — 进行中光晕呼吸; 庆祝时品牌标淡出, 大 ✓ 弹跳登场 + 光环放大变亮.
    private var centerBadge: some View {
        ZStack {
            Circle()
                .fill(MasoColor.accent.opacity(celebrate ? 0.20 : 0.10))
                .frame(width: 132, height: 132)
                .scaleEffect(celebrate ? 1.22 : (pulse ? 1.1 : 0.92))
            MasoBrandLogo()
                .frame(width: 60, height: 60)
                .scaleEffect(pulse ? 1.03 : 0.97)
                .opacity(celebrate ? 0 : 1)
            Image(systemName: "checkmark")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(MasoColor.accent)
                .scaleEffect(celebrate ? 1 : 0.3)
                .opacity(celebrate ? 1 : 0)
        }
        .frame(height: 132)
    }

    // 渐进式步骤清单 — 已完成 ✓ 累积, 当前步转圈, 未上场的步不显示.
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(steps.indices, id: \.self) { i in
                if i <= current {
                    HStack(spacing: 14) {
                        ZStack {
                            if i <= done {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(MasoColor.accent)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(MasoColor.accent)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(LocalizedStringKey(steps[i]))
                            .font(.system(size: 17, weight: i <= done ? .semibold : .medium))
                            .foregroundStyle(i <= done ? MasoColor.text : MasoColor.textDim)
                        Spacer(minLength: 0)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
                }
            }
        }
        .frame(width: 260, alignment: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: current)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
    }

    private func run() {
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        SoundPlayer.shared.playTick()   // 第一步上场
        // 步 0 "Uploading" 0.8s → 打勾 + 揭示步 1.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            done = 0; SoundPlayer.shared.playTick(); Haptics.selection(); current = 1
            // 步 1 "Analyzing" 1.0s → 打勾 + 揭示步 2 "Building" (开始等真 AI).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                done = 1; SoundPlayer.shared.playTick(); Haptics.selection(); current = 2
                // "Building" 至少停留 0.8s, 然后看真 AI 是否已就绪.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    buildingMinElapsed = true
                    finishIfReady()
                }
                // 安全兜底: 真 AI 9s 还没回 (网络极慢) → 强制落定 (本地起步计划已种好, 不会卡死).
                DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
                    buildingMinElapsed = true
                    finishIfReady(force: true)
                }
            }
        }
    }

    /// "Building"最短时长满足 + 真 AI 就绪 (或兜底强制) → 打勾 Building、揭示成功步、庆祝、落地.
    private func finishIfReady(force: Bool = false) {
        guard !finished, current >= 2, buildingMinElapsed, (isReady || force) else { return }
        finished = true
        done = 2; SoundPlayer.shared.playTick(); Haptics.selection(); current = 3   // Building ✓ + 揭示成功步
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            done = steps.count - 1
            Haptics.restEnded()
            SoundPlayer.shared.playSetComplete()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { celebrate = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + 0.8) { onComplete() }
    }
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
