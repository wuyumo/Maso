import SwiftUI

// MARK: - CoachScreen — Coach tab 两段式 (docs/coach-tab-design.md §1; SAVED 货架已撤)
//
// 结构:
//   ┌ 对话流   — CoachSession.messages 渲染: 用户气泡 (accent 12% 底, 禁实心绿 — IA 评审裁定) /
//   │             assistant 短评 + DAY 1..N 卡组; 生成中 = 诚实渐进清单 (无假打字机/假流式).
//   └ Composer — [+] 工具菜单 / 输入框 / 发送; chips 行只放"点了即发"的建议.
//               训练中 (TrainingSessionStore 有活跃 session) 整体收起成一行提示,
//               避免 TabBar+MiniBar+Composer+键盘四层叠 (设计文档 风险③).
//
// SAVED 货架 (owner 拍板迁移): 已存 routines 现住 Today tab 的横滑轮播 (TodayScreen
// #today-carousel), 保存反馈 = 生成卡 bookmark 变实心. 完整管理面 SavedRoutinesAllSheet
// 仍定义在本文件 (Today 的 "All" 入口与本页 [+] "Import from photo" 两处共用),
// 本页保留 sheet host 只为照片导入路径 (openPhotoImport).
//
// 本 view 只渲染内容, 导航容器 (NavigationStack) 由 RootView 提供 (批次 3 接线);
// 参数化注入跟 PlansScreen 同构: onStart / onNewPlan / onOpenSettings.
// 会话状态全在 data.coachSession (DataStore 持有) — 切 tab / 视图销毁, 对话与生成任务都不丢.
struct CoachScreen: View {
    @Environment(DataStore.self) private var data
    /// 训练会话 — 只用来判断"训练中" (composer 收起), 不做任何写操作.
    @Environment(TrainingSessionStore.self) private var training

    let onStart: (Plan) -> Void
    /// 新建空白计划 — RootView 注入 (走共享 sheet 容器); 本页只在 "All" sheet 的 "+" 菜单里转发.
    let onNewPlan: () -> Void
    /// 导航栏齿轮 → Settings sheet (RootView 持有).
    let onOpenSettings: () -> Void
    /// showcase "exercises" 路由的动作库触发 — RootView 翻 true, 这里拉起 library sheet 后复位
    /// (跟 TodayScreen.triggerImport 同套路: 挂载后才收得到, RootView 侧延迟翻).
    @Binding var libraryRequested: Bool

    // ── sheet / 弹层 ──
    /// 完整管理 sheet (TodayScreen .myPlans: 删/编辑/照片导入/优化卡整块复用) —
    /// 货架撤走后本页唯一入口是 [+] 菜单 "Import from photo" (先开 sheet 再翻 triggerImport).
    @State private var allSheetPresented = false
    /// "All" sheet 里的照片导入触发 (先开 sheet 再翻 true).
    @State private var allSheetTriggerImport = false
    /// 导航栏 dumbbell → 动作库 sheet (组件本就支持 sheet 形态, asTab:false 自带 Done).
    @State private var libraryPresented = false
    /// [+] 菜单 → 经典模板 sheet (子 sheet 挂各自 presenter 内容树, 见 ClassicsSheet 注释).
    @State private var classicsPresented = false
    /// [+] 菜单 → 训练偏好 sheet; 确认后无言重生成 (feedback nil, 不追加用户气泡).
    @State private var prefsPresented = false
    /// 保存撞免费上限 → paywall (saveCoachPlan 返回 false).
    @State private var paywallPresented = false
    /// "新对话" 二次确认 — 误触会清掉整段对话, 必须确认.
    @State private var confirmNewConversation = false
    /// 生成卡 tap → 详情 (browse 态: Save toggle + Start).
    @State private var detailPlan: Plan? = nil

    // ── composer ──
    @State private var composerText = ""
    @FocusState private var composerFocused: Bool
    /// 长按动作 pill 的引用式定向反馈 — 发送时作 onlyModify 传给 coachGenerate.
    /// 用户清空输入框即取消定向 (onChange 里复位); 改写但没清空则仍视为针对该动作 (V1 从简).
    @State private var pendingOnlyModify: String? = nil
    /// 最近一次发送的 (feedback, onlyModify) — fallback 提示条的 Retry 用原参数重发.
    @State private var lastFeedback: String? = nil
    @State private var lastOnlyModify: String? = nil

    /// 空态主动建议 — routineSuggestion() 每次算要扫全部 sets, 进页缓存一次, 不在 body 里反复算.
    @State private var suggestion: DataStore.RoutineSuggestion? = nil
    /// 深链路由 — Progress AI 小结 Apply 经 AppRouter 送 pendingSummaryFocus 过来 (设计文档 §4).
    @State private var router = AppRouter.shared

    /// 对话流自动滚到底的锚点 id.
    private static let bottomAnchor = "coach-bottom"

    /// 渐进清单文案 — 复用 AIGeneratingView 那套 key (en+zh 都已有), 跟 CoachSession.generationStep 对应.
    private static let generationStepKeys = [
        "Uploading your data",
        "Analyzing your stats",
        "Building your plan",
    ]

    private var session: CoachSession { data.coachSession }

    /// 是否有进行中的训练 — 判据跟 RootView.hasActiveSession 一致 (MiniBar 在场 = composer 收起).
    private var hasActiveTraining: Bool {
        guard let s = training.session else { return false }
        return !s.completed && training.currentSegment != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            conversation
            bottomBar
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // dumbbell — Exercises 不再是 tab, 从这里一步直达动作库 (设计文档 §0).
                Button { libraryPresented = true } label: {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 16, weight: .regular))
                }
                .accessibilityLabel(NSLocalizedString("Exercise library", comment: ""))
                // 训练偏好独立入口 (owner 指定: dumbbell 与 gear 之间) — 跟 [+] 菜单里那项同目的地;
                // 空态的偏好卡 (PlanRationaleCard) 保留, 三处都开 TrainingPreferencesSheet.
                Button { prefsPresented = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .regular))
                }
                .accessibilityLabel(NSLocalizedString("Training Preferences", comment: ""))
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .regular))
                }
                .accessibilityLabel("Settings")
            }
        }
        .onAppear { suggestion = data.routineSuggestion() }
        // showcase "exercises" 路由 — RootView 翻 true, 这里拉起动作库 sheet 后复位.
        .onChange(of: libraryRequested) { _, requested in
            guard requested else { return }
            libraryRequested = false
            libraryPresented = true
        }
        // Progress AI 小结 Apply 深链 (设计文档 §4 深链改道): 带来源 kicker 的用户气泡 + 到达即自动发送.
        // initial:true — 首次深链时 CoachScreen 可能在置值之后才挂载, 普通 onChange 收不到那次翻转.
        .onChange(of: router.pendingSummaryFocus, initial: true) { _, note in
            guard let note else { return }
            router.pendingSummaryFocus = nil
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            send(feedback: trimmed.isEmpty ? nil : trimmed,
                 sourceKicker: NSLocalizedString("FROM WEEKLY SUMMARY", comment: "coach chat deep-link kicker"),
                 surface: "summary")
        }
        // Today 侧 All sheet 的优化卡 Apply 深链 — 同 summary 管道 (Pro gate 已在 Today 侧过闸),
        // kicker / surface 用 optimize 语义, 跟本页 All sheet 的 onOptimize 一致.
        .onChange(of: router.pendingOptimizeFocus, initial: true) { _, note in
            guard let note else { return }
            router.pendingOptimizeFocus = nil
            send(feedback: note,
                 sourceKicker: NSLocalizedString("FROM OPTIMIZE", comment: "coach chat deep-link kicker"),
                 surface: "optimize")
        }
        // 清空输入框 = 取消长按发起的定向反馈.
        .onChange(of: composerText) { _, text in
            if text.isEmpty { pendingOnlyModify = nil }
        }
        // ── sheet 层 (子 sheet 各挂各自 presenter 的内容树, 一次只会开一个) ──
        .sheet(item: $detailPlan) { plan in
            // 生成卡详情 — browse 态: Save = 书签 toggle (不关 sheet, CTA 随 savedOverride 实时翻);
            // Start 先关本 sheet 再启动 (player 是 RootView 的 fullScreenCover).
            PlanDetailSheet(
                initialPlan: plan,
                onStart: { p in detailPlan = nil; DispatchQueue.main.async { onStart(p) } },
                onAddToSaved: { p in toggleSave(p) },
                savedOverride: data.isCoachPlanSaved(plan)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $allSheetPresented) {
            SavedRoutinesAllSheet(
                triggerImport: $allSheetTriggerImport,
                onStart: onStart,
                onNewPlan: onNewPlan,
                // 优化卡 → 化身 coach 对话轮: 关 sheet 后把诊断的 focusNote 当反馈发送 (带来源 kicker).
                // Pro gate 原样保留 (原 PlansScreen.handleOptimize 同规则 — Pro feature ②, 卡对所有人
                // 可见 teaser, 动作才 gate); 过闸后走深链同管道 (surface:"optimize").
                onOptimize: { sug in
                    guard data.settings.isPro else { paywallPresented = true; return }
                    send(feedback: sug.focusNote,
                         sourceKicker: NSLocalizedString("FROM OPTIMIZE", comment: "coach chat deep-link kicker"),
                         surface: "optimize")
                }
            )
        }
        .sheet(isPresented: $libraryPresented) {
            ExerciseLibraryBrowser()   // asTab:false → 自带 NavigationStack + Done
        }
        .sheet(isPresented: $classicsPresented) {
            ClassicsSheet(onStart: onStart)
        }
        .sheet(isPresented: $prefsPresented) {
            // 改完偏好点 "Generate routines" → 无言生成一轮 (feedback nil 不追加用户气泡).
            TrainingPreferencesSheet(onConfirm: { send(feedback: nil) })
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Start a new conversation?", isPresented: $confirmNewConversation, titleVisibility: .visible) {
            Button(NSLocalizedString("New conversation", comment: ""), role: .destructive) {
                data.resetCoachConversation()
                lastFeedback = nil
                lastOnlyModify = nil
                pendingOnlyModify = nil
                composerText = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the current chat. Saved routines are kept.")
        }
    }

    // MARK: - ① 对话流

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if session.messages.isEmpty && !session.isGenerating {
                        emptyState
                    }
                    ForEach(session.messages) { msg in
                        messageView(msg)
                    }
                    if session.isGenerating {
                        generatingChecklist
                    } else if let note = session.fallbackNote {
                        fallbackBanner(note)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            .onChange(of: session.messages.count) { scrollToBottom(proxy) }
            .onChange(of: session.isGenerating) { scrollToBottom(proxy) }
            .onChange(of: session.generationStep) { scrollToBottom(proxy) }
            .onChange(of: composerFocused) { _, focused in
                if focused { scrollToBottom(proxy) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    /// 空态三层 (设计文档 §1): AI 问候/主动建议 → Context 偏好卡 (已带铅笔) → chips (在 composer 上方常驻).
    @ViewBuilder
    private var emptyState: some View {
        if let sug = suggestion {
            // 优化建议卡化身主动建议气泡 — 有近况数据时 coach 先开口, 不等用户想话题.
            VStack(alignment: .leading, spacing: 8) {
                Text(sug.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Text(sug.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    // Apply → 发对应 focusNote (英文指令原样进 prompt; 气泡带来源 kicker 说明它是建议的应用).
                    send(feedback: sug.focusNote,
                         sourceKicker: NSLocalizedString("COACH SUGGESTION", comment: "coach chat deep-link kicker"))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                        Text("Apply").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(MasoColor.accent.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        } else {
            // 通用问候 — 直接展示, 不做打字机 (owner: 核心内容直接展示).
            Text("Hey! Tell me how you want to train — I'll build your weekly routines.")
                .font(.system(size: 14))
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Context 偏好卡 — kicker + prefSummary 一行灰字 + 铅笔尾 icon → TrainingPreferencesSheet.
        // 卡内自带 sheet; 确认 → 无言重生成.
        PlanRationaleCard(onApplyPreferences: { send(feedback: nil) })
    }

    @ViewBuilder
    private func messageView(_ msg: CoachMessage) -> some View {
        switch msg.role {
        case .user: userBubble(msg)
        case .assistant: assistantMessage(msg)
        }
    }

    /// 用户气泡 — accent 12% 底 + 浅绿字, 右对齐, 圆角 12 (禁实心绿大底 — IA 评审裁定).
    /// 深链消息 (sourceKicker 非 nil) 顶部加 10pt uppercase kicker + arrow.turn.down.right.
    private func userBubble(_ msg: CoachMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let kicker = msg.sourceKicker {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .heavy))
                    Text(kicker)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .textCase(.uppercase)
                }
                .foregroundStyle(MasoColor.textDim)
            }
            // 15pt + 舒展行距 + 加大 padding, 气泡 minHeight 对齐 iOS 默认控件高 (~36pt),
            // 圆角 18 — 跟系统消息类 app 的气泡体量一致 (owner 指定做大).
            Text(msg.text)
                .font(.system(size: 15, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(MasoColor.accent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: 36)
                .background(MasoColor.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)   // 气泡不顶满左缘, 保住"对话"的左右体感
    }

    /// assistant 消息 — 教练短评正文 + DAY 1..N 卡组.
    /// 旧轮消息的卡组保持可交互 (Save / 详情) = V1 版本捞回达标 (设计文档 §1);
    /// 但长按定向反馈只挂最新一轮卡 — onlyModify 针对的是 currentRoutines, 旧版动作可能已不在场.
    private func assistantMessage(_ msg: CoachMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 正文跟用户气泡同 15pt + 舒展行距 (owner 指定做大).
            Text(msg.text)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let plans = msg.plans {
                let isLatest = msg.id == session.messages.last(where: { $0.plans != nil })?.id
                ForEach(Array(plans.enumerated()), id: \.element.id) { i, plan in
                    WorkoutCard(
                        plan: plan,
                        exById: data.exById,
                        kicker: String(format: NSLocalizedString("DAY %lld", comment: "coach chat day-card kicker"), i + 1),
                        onStart: { detailPlan = plan },   // addAction 非 nil 时 play 钮本就隐藏
                        onShowDetail: { detailPlan = plan },
                        prominentStart: false,
                        addAction: { toggleSave(plan) },
                        compactLayout: true,
                        savedOverride: data.isCoachPlanSaved(plan),
                        onExercisePillLongPress: (isLatest && !hasActiveTraining)
                            ? { name in beginTargetedSwap(name) } : nil
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 生成中 — 诚实渐进清单 (复用 AIGeneratingView 的逐步 ✓ 模式) + 明示预期时长.
    /// 步骤由 CoachSession.generationStep 驱动 (最后一步等真实完成), 绝不做假打字机.
    private var generatingChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<CoachSession.generationStepCount, id: \.self) { i in
                if i <= session.generationStep {
                    HStack(spacing: 10) {
                        ZStack {
                            if i < session.generationStep {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(MasoColor.accent)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(MasoColor.accent)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(LocalizedStringKey(Self.generationStepKeys[i]))
                            .font(.system(size: 14, weight: i < session.generationStep ? .semibold : .medium))
                            .foregroundStyle(i < session.generationStep ? MasoColor.text : MasoColor.textDim)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
                }
            }
            Text("Usually takes 30–60 seconds")
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .padding(.top, 2)
        }
        .padding(14)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.generationStep)
    }

    /// 失败/回落提示条 + Retry (原参数重发) — 跟 PlansScreen 的 fallback 条同款.
    private func fallbackBanner(_ note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 12, weight: .bold))
            Text(note).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                send(feedback: lastFeedback, onlyModify: lastOnlyModify)
            } label: {
                Text("Retry").font(.system(size: 12, weight: .bold))
            }
        }
        .foregroundStyle(MasoColor.textDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - ② Composer

    @ViewBuilder
    private var bottomBar: some View {
        if hasActiveTraining {
            // 训练中 — composer 整体收起成一行提示 (设计文档 风险③: 避免 TabBar+MiniBar+Composer+键盘四层叠).
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MasoColor.accent)
                Text("Training in progress — keep tuning after your session.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 8) {
                if !session.isGenerating {
                    chipsRow
                }
                composerRow
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    /// chips 行 — 只放"点了即发"的建议 (IA 评审: 工具进 [+], 建议进 chips); 生成中隐藏.
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestionChips, id: \.self) { chip in
                    Button {
                        send(feedback: chip)
                    } label: {
                        Text(chip)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MasoColor.text.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(MasoColor.surfaceHi)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
    }

    /// 按偏好/近况生成 3-4 个即发建议. 文案本地化, 点击原文发送 (LLM 中英都看得懂).
    private var suggestionChips: [String] {
        var out: [String] = []
        if session.currentRoutines.isEmpty {
            out.append(NSLocalizedString("Plan my training week", comment: "coach chip"))
            out.append(NSLocalizedString("Dumbbells only", comment: "coach chip"))
            out.append(NSLocalizedString("Under 30 minutes", comment: "coach chip"))
        } else {
            // 修订轮语境 — 换成"针对现有方案改"的建议.
            out.append(NSLocalizedString("Make it shorter", comment: "coach chip"))
            out.append(NSLocalizedString("Use different equipment", comment: "coach chip"))
        }
        if let m = data.settings.wantStrengthen.first {
            out.append(String(format: NSLocalizedString("Train %@ more", comment: "coach chip — focus muscle"),
                              MuscleSelector.majorOf(m).displayName))
        }
        return out
    }

    private var composerRow: some View {
        // 大输入框容器 (owner 拍板, ChatGPT 式): 文本区在上占满宽, [+] 与发送钉在容器内左右下角 —
        // 不再是"小胶囊输入框 + 两侧按钮"的一行式.
        VStack(alignment: .leading, spacing: 6) {
            TextField(NSLocalizedString("Tell me how you want to train…", comment: "coach composer placeholder"),
                      text: $composerText, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 16))
                .foregroundStyle(MasoColor.text)
                .focused($composerFocused)
                .frame(minHeight: 44, alignment: .topLeading)

            // 底部按钮行 — [+] 左下角, 发送右下角 (都在框内).
            HStack {
                // [+] 菜单 — 只放工具, 一行一语义 (IA 评审裁定).
                Menu {
                    // (Training Preferences 已移出 — 导航栏 slider.horizontal.3 是唯一常驻入口, owner 拍板.)
                    Button { classicsPresented = true } label: {
                        Label("Browse Classics", systemImage: "rosette")
                    }
                    Button { openPhotoImport() } label: {
                        Label("Import from photo", systemImage: "photo")
                    }
                    Divider()
                    Button { confirmNewConversation = true } label: {
                        Label("New conversation", systemImage: "square.and.pencil")
                    }
                } label: {
                    // iOS 系统观感: plus.circle.fill 镂空透底, 不自绘圆底.
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(MasoColor.textDim)
                }
                .accessibilityLabel(Text("New conversation"))

                Spacer(minLength: 0)

                Button(action: sendFromComposer) {
                    // 发送 = arrow.up.circle.fill (accent), 禁用态灰 — 系统默认渲染.
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? MasoColor.accent : MasoColor.textFaint)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(Text("Send"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        // 0.5pt 细描边 (owner 指定) — 很 subtle 的一圈, 只比 surface 亮一点, 勾出输入框轮廓.
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(MasoColor.text.opacity(0.10), lineWidth: 0.5)
        )
        // 点文本区外的容器空白也能聚焦 — 整个大框都是输入的可点热区.
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { composerFocused = true }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
    }

    private var canSend: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isGenerating
    }

    // MARK: - Actions

    private func sendFromComposer() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isGenerating else { return }
        let only = pendingOnlyModify
        composerText = ""
        pendingOnlyModify = nil
        send(feedback: text, onlyModify: only)
    }

    /// 发送一轮 — 统一入口 (composer / chips / Apply / Retry / 深链都走这).
    /// surface: 生成事件的来源面 — 常规聊天 "coach_chat"; 深链透传 "summary"/"optimize" (设计文档 §4).
    /// ⚠️ 聊天文本属 PII: analytics 只报长度和是否定向, 不报内容 (生成事件本身在 DataStore 层埋).
    private func send(feedback: String?, onlyModify: String? = nil, sourceKicker: String? = nil,
                      surface: String = "coach_chat") {
        guard !session.isGenerating else { return }
        Haptics.tap()
        lastFeedback = feedback
        lastOnlyModify = onlyModify
        Analytics.shared.track("coach_chat_send", [
            "length": .int(feedback?.count ?? 0),
            "targeted": .bool(onlyModify != nil),
            "surface": .string(surface),
        ])
        data.startCoachGenerate(feedback: feedback, onlyModify: onlyModify,
                                sourceKicker: sourceKicker, surface: surface)
    }

    /// 长按动作 pill → 引用式定向反馈: 预填 composer + 聚焦, 发送时该动作名作 onlyModify.
    private func beginTargetedSwap(_ exerciseName: String) {
        composerText = String(format: NSLocalizedString("Swap %@: ", comment: "coach targeted feedback prefill"), exerciseName)
        pendingOnlyModify = exerciseName
        composerFocused = true
    }

    /// 书签 toggle — 已存 → unsave; 未存 → saveCoachPlan (false = 撞免费上限 → paywall).
    private func toggleSave(_ plan: Plan) {
        if data.isCoachPlanSaved(plan) {
            data.unsavePlan(matching: plan)
        } else if data.saveCoachPlan(plan) {
            Haptics.tap()
        } else {
            paywallPresented = true
        }
    }

    /// [+] "Import from photo" → 打开 "All" sheet 并触发照片导入 (导入 UI 整块住在 TodayScreen .myPlans).
    /// triggerImport 延迟翻 true: TodayScreen 用 onChange 监听 (无 initial), sheet 内容上场后再翻才收得到.
    private func openPhotoImport() {
        allSheetPresented = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            allSheetTriggerImport = true
        }
    }
}

// MARK: - SavedRoutinesAllSheet — 已存 routines 完整管理 sheet (Today "All" 入口 + Coach 照片导入共用)
//
// = 现 TodayScreen(mode:.myPlans) 整块复用 (删/编辑/照片导入/优化卡, 一件不丢 — 设计文档 §1).
// 子 sheet (PlanDetail / import picker / paywall) 都在 TodayScreen 内部, 挂本 sheet 内容树,
// 不会撞 "一次只能 present 一个 sheet" (同 ClassicsSheet 的叠层规则).
// internal (非 private): Today 轮播标题行的 "All" 入口也 present 它 — 货架撤走后管理面的家.
struct SavedRoutinesAllSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 照片导入触发 — CoachScreen 持有 (composer [+] 菜单先开本 sheet 再翻 true).
    @Binding var triggerImport: Bool
    let onStart: (Plan) -> Void
    let onNewPlan: () -> Void
    /// 优化卡 → 回 coach 对话流发 focusNote (调用方负责 send; 本 sheet 只管先关自己).
    let onOptimize: (DataStore.RoutineSuggestion) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TodayScreen(
                        // player / 新建计划 都是 RootView 层的 presentation — 先关本 sheet 再转发,
                        // 否则两层 present 打架 (同 ClassicsSheet.onStart 的处理).
                        onStart: { p in dismiss(); DispatchQueue.main.async { onStart(p) } },
                        onFreeWorkout: {},
                        onNewPlan: { dismiss(); DispatchQueue.main.async { onNewPlan() } },
                        onOpenSettings: {},
                        onOptimize: { sug in dismiss(); DispatchQueue.main.async { onOptimize(sug) } },
                        embedded: true,
                        mode: .myPlans,
                        embeddedInScroll: true,
                        triggerImport: $triggerImport
                    )
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 8)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("My Routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // "+" 菜单跟 PlansScreen 同款两项 — 新建走 RootView (先关 sheet), 导入就地触发.
                    Menu {
                        Button { dismiss(); DispatchQueue.main.async { onNewPlan() } } label: {
                            Label("Create my own", systemImage: "square.and.pencil")
                        }
                        Button { triggerImport = true } label: {
                            Label("Import from photo", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .accessibilityLabel(Text("New routine"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
        .presentationDragIndicator(.visible)
    }
}
