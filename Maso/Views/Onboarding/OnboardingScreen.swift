import SwiftUI

// Onboarding — 一问一屏的精细向导 (替代旧的"单页渐进展开").
//   1 性别  2 年龄  3 体重  4 每周训练次数  5 想加强的肌群
//
// 交互规则:
//   · 选项型 (性别 / 每周次数): 单选, 点一下即自动跳下一步 (带 0.18s 让选中态可感知).
//   · 拨盘型 (年龄 / 体重): 上下滚动的 wheel, 选体重时默认落在该性别平均值, 调完点"下一步"确定.
//   · 多选型 (肌群): 不能自动跳, 用"确认, 生成计划"收尾 (顺带进 AI 生成过渡).
//   · 第 2 步起, 左下角恒有"返回"回到上一步重选 (即便上一步是自动跳进来的).
struct OnboardingScreen: View {
    @Environment(DataStore.self) private var data
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        case gender = 1, age, weight, days, focus
        static let total = Step.allCases.count
    }

    @State private var step: Step = .gender
    /// 切屏滑动方向 — 前进=新屏从右进, 返回=从左进.
    @State private var goingForward = true

    @State private var gender: Gender? = nil
    @State private var age: Int = 25
    /// 体重: 选完性别按平均值 re-seed, 除非用户已手动拨过 (weightTouched).
    @State private var weight: Double = 75
    @State private var weightTouched = false
    @State private var daysPerWeek: Int = 3               // 拨盘默认 3 天/周 (拨盘必有位置, 同年龄/体重)
    @State private var strengthen: Set<MuscleGroup> = []  // 不预选 — 留空 = 均衡
    /// 确认后进入"AI 生成中"过渡 (感知型 — seedStarterRoutines 是瞬时本地生成).
    @State private var generating = false
    /// 真 AI 首份计划生成完成 (成功或回落) → 过渡页"Building"步据此落定, 把动画绑到真实调用延迟.
    @State private var aiReady = false

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
            Text(String(format: NSLocalizedString("STEP %lld / 5", comment: ""), step.rawValue))
                .font(.system(size: 12, weight: .bold)).tracking(2)
                .foregroundStyle(MasoColor.accent)
        }
    }

    // MARK: - 分步内容

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .gender: genderStep
        case .age:    ageStep
        case .weight: weightStep
        case .days:   daysStep
        case .focus:  focusStep
        }
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

    // 2) 年龄 — 拨盘.
    private var ageStep: some View {
        stepBody("How old are you?", "Helps us tune your training volume.") {
            wheel(selection: Binding(get: { age }, set: { age = $0 }),
                  range: 12...90) { "\($0)" }
        }
    }

    // 3) 体重 — 拨盘, 默认落在该性别平均值.
    private var weightStep: some View {
        stepBody("What's your weight?", "We seed your starting loads from this — change any later.") {
            wheel(selection: Binding(get: { Int(weight) },
                                     set: { weight = Double($0); weightTouched = true }),
                  range: 30...200) { "\($0) kg" }
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
            Spacer(minLength: 40)   // 跟下方"Build My Routine"按钮的间隔
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
                    .background(MasoColor.surface)
                    .clipShape(Capsule())
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
                        .background(MasoColor.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var primaryAction: (title: String, action: () -> Void)? {
        switch step {
        case .gender: return nil                            // 性别仍是选项型, 单选自动跳
        case .age:    return ("Next", { advance(to: .weight) })
        case .weight: return ("Next", { advance(to: .days) })
        case .days:   return ("Next", { advance(to: .focus) })   // 改拨盘后需"下一步"
        case .focus:  return ("Build My Routine", confirm)
        }
    }

    // MARK: - 导航 / 选择

    private func advance(to s: Step) {
        goingForward = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = s }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        goingForward = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = prev }
    }

    private func selectGender(_ g: Gender) {
        gender = g
        if !weightTouched { weight = avgWeight(g) }   // 体重拨盘默认 = 该性别平均值
        Haptics.tap()
        SoundPlayer.shared.playTap()
        // 0.18s 让选中态 (绿底 + ✓) 被看见再滑走, 不显得突兀.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { advance(to: .age) }
    }

    /// 各性别的起始平均体重 (kg) — 仅作体重拨盘默认值, 用户可调.
    private func avgWeight(_ g: Gender) -> Double {
        switch g { case .male: return 75; case .female: return 60; case .other: return 68 }
    }

    private func genderLabel(_ g: Gender) -> String {
        switch g { case .male: return "Male"; case .female: return "Female"; case .other: return "Other" }
    }

    private func confirm() {
        data.settings.gender = gender
        data.settings.age = age
        data.settings.weight = weight
        data.settings.weeklyTrainingDays = daysPerWeek
        data.settings.wantStrengthen = Array(strengthen)
        data.flushSave()   // 先持久化偏好 (即使 AI 调用挂掉, 偏好也已落盘)
        // ⚠️ 不在这里置 onboardingCompleted —— RootView 用它做门控, 一置就立刻切走 OnboardingScreen,
        //    "AI 生成中"过渡(generating overlay 挂在 OnboardingScreen 上)就来不及显示.
        //    改由过渡结束时的 onDone() 去置 (见 RootView). 这里只点亮过渡.
        withAnimation(.easeInOut(duration: 0.35)) { generating = true }
        // Path B: 真 AI 生成首份计划 (generateFirstPlanViaAI 内部先种本地起步保证非空, 再尝试真 LLM
        // 作为今日推荐, 失败回落). 完成后 aiReady=true → 过渡页"Building"步落定.
        Task {
            await data.generateFirstPlanViaAI()
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
            selection = n
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
