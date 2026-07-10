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
    /// "#" 模板面板 (取代旧 chips 行 — owner 拍板: 建议入口收进模板系统).
    @State private var templatesPresented = false
    /// 半填空选区 (iOS 18 TextSelection) — 点模板/点"下一空"时程序化选中占位符整体,
    /// 选中态下直接打字即替换. 绑在 TextField 的 selection: 上, 用户手动移光标也会写回来.
    @State private var composerSelection: TextSelection? = nil
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
                // 输入态点对话区任意处收键盘 (owner 指定). simultaneousGesture — 不抢卡片/chip
                // 自己的 tap (点卡 = 收键盘 + 照常开详情), 也不挡 ScrollView 拖拽.
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
            bottomBar
        }
        // 试验性: 共享背景 = #121212 + 底部液态光斑.
        .background(AppBackground())
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
        .onAppear {
            suggestion = data.routineSuggestion()
            // showcase 截图路由 (仅截图流水线注入 env; 生产恒空 no-op) — 拉起对应 sheet.
            switch ProcessInfo.processInfo.environment["MASO_SHOWCASE"] ?? "" {
            case "coach_templates":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { templatesPresented = true }
            case "coach_prefs":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { prefsPresented = true }
            default: break
            }
        }
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
        // 清空输入框 = 取消长按发起的定向反馈 + 复位模板选区 (一切复位).
        .onChange(of: composerText) { _, text in
            if text.isEmpty {
                pendingOnlyModify = nil
                composerSelection = nil
            }
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
        .sheet(isPresented: $templatesPresented) {
            // "#" 模板面板 — 点行回填 composer 并选中第一个占位符 (半填空交互).
            CoachTemplatesSheet(onPick: { applyTemplate($0) })
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
                    // 空态建议 Apply chip → 次级玻璃胶囊 (映射表②), 旧系统保留半透明底.
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                  fallback: MasoColor.accent.opacity(0.15))
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
                // 失败条 Retry → 次级玻璃胶囊 (映射表②, 跟 TodayScreen 失败条同款); 旧系统保留裸文字.
                Text("Retry").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(systemGlassAvailable ? MasoColor.accent : MasoColor.textDim)
                    .padding(.horizontal, systemGlassAvailable ? 12 : 0)
                    .padding(.vertical, systemGlassAvailable ? 6 : 0)
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25))
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
            // chips 行已拆除 (被 "#" 模板面板取代 — owner 拍板), composer 独占底栏.
            composerRow
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
    }

    private var composerRow: some View {
        // 大输入框容器 (owner 拍板, ChatGPT 式): 文本区在上占满宽, [+] 与发送钉在容器内左右下角 —
        // 不再是"小胶囊输入框 + 两侧按钮"的一行式.
        VStack(alignment: .leading, spacing: 6) {
            // selection: 绑定 (iOS 18 TextSelection) — 模板半填空要程序化选中占位符整体.
            TextField(NSLocalizedString("Tell me how you want to train…", comment: "coach composer placeholder"),
                      text: $composerText, selection: $composerSelection, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 16))
                .foregroundStyle(MasoColor.text)
                .focused($composerFocused)
                .frame(minHeight: 44, alignment: .topLeading)

            // 底部按钮行 — [+|#] 玻璃药丸钉左下角, 发送 (glassProminent 圆) 钉右下角
            // (owner 拍板: iOS 26 系统 Liquid Glass 样式 + 默认控件尺寸 44pt, 旧 30pt 太小).
            HStack(spacing: 10) {
                toolsPill

                // "下一空" 胶囊 — 只在还有占位符没填时出现; tap 选中光标之后的下一个占位符
                // (到结尾绕回第一个). 填完 (regex 无命中) 自动消失.
                if hasPlaceholders {
                    Button(action: selectNextPlaceholder) {
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Next blank", comment: "coach template next placeholder"))
                            Text("⇥")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MasoColor.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        // 小工具胶囊 → 素玻璃 (映射表③), 字色不变; 旧系统保留原描边样式.
                        .glassCapsuleButtonBackground()
                        .overlay {
                            if !systemGlassAvailable {
                                Capsule().strokeBorder(MasoColor.textDim.opacity(0.5), lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Next blank"))
                }

                Spacer(minLength: 0)

                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .glassCardBackground(cornerRadius: 22)
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
        // guard rail: 占位符没填完不给发 — 防止把「部位」这种模板原文送进 LLM.
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isGenerating
            && !hasPlaceholders
    }

    /// [+|#] 玻璃药丸 (owner 拍板): 两键合成一枚系统 Liquid Glass 胶囊, 44pt 默认控件高;
    /// iOS 26 走 .glassEffect (跟导航栏胶囊同一套材质), 之前系统回退 surfaceHi 胶囊.
    private var toolsPill: some View {
        let content = HStack(spacing: 0) {
            // [+] 菜单 — 只放工具, 一行一语义 (IA 评审裁定;
            // Training Preferences 已移出, 导航栏 slider.horizontal.3 是唯一常驻入口).
            Menu {
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
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 46, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("New conversation"))

            // 细分隔 — 两键同丸但语义可分.
            Rectangle()
                .fill(MasoColor.text.opacity(0.15))
                .frame(width: 0.5, height: 20)

            Button { templatesPresented = true } label: {
                Image(systemName: "number")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MasoColor.text)
                    .frame(width: 46, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Prompt templates"))
        }
        return Group {
            if #available(iOS 26.0, *) {
                // .interactive 跟发送键同配方 — 两枚按键玻璃观感一致 (owner 反馈过不一致).
                content.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content.background(MasoColor.surfaceHi).clipShape(Capsule())
            }
        }
    }

    /// 发送键 — iOS 26 液态玻璃圆 (accent tint), 44pt 跟 [+|#] 药丸同高 (owner 拍板);
    /// 可发送 = 高浓度绿玻璃 + 黑箭头, 禁用 = 近透明玻璃 + 灰箭头. 之前系统回退 44pt circle.fill.
    private var sendButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: sendFromComposer) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(canSend ? .black : MasoColor.textDim)
                        .frame(width: 44, height: 44)
                        // 禁用态 = 无 tint 素玻璃, 跟左边 [+|#] 药丸完全同配方 (owner 反馈两键
                        // 背景不一致 — 之前禁用态掺了 8% 绿); 点亮才上 accent 标记主操作.
                        .glassEffect(canSend ? .regular.tint(MasoColor.accent.opacity(0.85)).interactive()
                                             : .regular.interactive(),
                                     in: Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: sendFromComposer) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(canSend ? MasoColor.accent : MasoColor.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(!canSend)
        .accessibilityLabel(Text("Send"))
    }

    // MARK: - "#" 模板半填空 (占位符选中/导航)

    /// composerText 里还有没填的模板占位符 (「…」或 […]) — 驱动"下一空"胶囊显隐 + canSend guard.
    private var hasPlaceholders: Bool {
        !CoachTemplates.placeholderRanges(in: composerText).isEmpty
    }

    /// 点模板行 → 回填 composer + 聚焦 + 选中第一个占位符 (选中态下直接打字即替换).
    /// 聚焦/选区要等模板 sheet 收场后再设 — sheet 在场时 focus 会被吃掉, 选区也随之作废.
    private func applyTemplate(_ template: String) {
        composerText = template
        pendingOnlyModify = nil   // 模板是全新一句话, 取消长按定向残留
        composerFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            composerFocused = true
            // 下一 runloop 再选中 — TextField 得先吃到新文本, 立刻设选区会被旧内容覆盖.
            DispatchQueue.main.async { selectPlaceholder(after: nil) }
        }
    }

    /// "下一空"胶囊 — 选中当前光标之后的下一个占位符 (到结尾绕回第一个).
    private func selectNextPlaceholder() {
        composerFocused = true
        selectPlaceholder(after: currentCursorIndex)
    }

    /// 选中 cursor 之后 (nil = 从头) 的第一个占位符整体; 无命中则绕回第一个.
    private func selectPlaceholder(after cursor: String.Index?) {
        let ranges = CoachTemplates.placeholderRanges(in: composerText)
        guard !ranges.isEmpty else { return }
        let target: Range<String.Index>
        if let cursor, let next = ranges.first(where: { $0.lowerBound >= cursor }) {
            target = next
        } else {
            target = ranges[0]
        }
        composerSelection = TextSelection(range: target)
    }

    /// 当前光标位置 — 取现有选区/插入点的末端; 拿不到就当从头找.
    private var currentCursorIndex: String.Index? {
        guard let sel = composerSelection else { return nil }
        switch sel.indices {
        case .selection(let r): return r.upperBound
        case .multiSelection(let rs): return rs.ranges.last?.upperBound
        @unknown default: return nil
        }
    }

    // MARK: - Actions

    private func sendFromComposer() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
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

// MARK: - "#" 模板目录 + 面板 (owner 拍板的完整设计)
//
// 目录 = 4 组 × 3 条, 逐字锁定 (勿改措辞); key 用 en 原句, zh 译文占位符用「」/ en 用 [ ].
// 半填空: 占位符 regex 两种括号都认 — 中文模板「…」+ 英文模板 […] 同一套逻辑.
fileprivate enum CoachTemplates {
    /// 占位符 regex: 「[^「」]*」 与 \[[^\[\]]*\] — NSRegularExpression (避开 Swift Regex 的并发标注).
    static let placeholderPattern = "「[^「」]*」|\\[[^\\[\\]]*\\]"

    /// 分组: (kicker 本地化 key, 模板本地化 keys). 顺序 = FOCUS / SWAP / TIME & STRUCTURE / INTENSITY.
    static let groups: [(kicker: String, keys: [String])] = [
        ("FOCUS", [
            "Train [muscle] more and [muscle] less",
            "Put extra focus on my [upper chest / rear delts]",
            "Add more volume for my [weak spot]",
        ]),
        ("SWAP", [
            "Swap out [exercise] because [reason]",
            "My [body part] hurts — avoid [movement type]",
            "Use more [dumbbells / cables] and less [barbell / machines]",
        ]),
        ("TIME & STRUCTURE", [
            "Keep each session under [45] minutes",
            "Make it [4] days a week, split by [push/pull/legs]",
            "Only change Day [1] — keep the rest as is",
        ]),
        ("INTENSITY", [
            "I'm [worn out / not recovering] — dial the intensity down",
            "Make it [4] sets of [6-8] reps per exercise",
            "I'm in a [cutting / bulking] phase — tune for that",
        ]),
    ]

    /// 文本里所有占位符的 range (出现顺序) — 面板染色 + composer 选区导航共用.
    static func placeholderRanges(in text: String) -> [Range<String.Index>] {
        guard let re = try? NSRegularExpression(pattern: placeholderPattern) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: full).compactMap { Range($0.range, in: text) }
    }
}

/// 模板面板 sheet — 4 组 kicker + 模板行; 占位符染 accent 绿, tap 行 → onPick(本地化模板串) → dismiss.
private struct CoachTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(CoachTemplates.groups, id: \.kicker) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            // kicker — 跟 app 其它 section kicker 同款 10pt heavy tracking.
                            Text(NSLocalizedString(group.kicker, comment: "coach template group kicker"))
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1.5)
                                .textCase(.uppercase)
                                .foregroundStyle(MasoColor.textDim)
                            ForEach(group.keys, id: \.self) { key in
                                templateRow(NSLocalizedString(key, comment: "coach prompt template"))
                            }
                        }
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Prompt templates", comment: "coach templates sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            // 顶栏规范: 纯浏览/挑选型 sheet — 右上 Done, 左上不放按钮 (拖拽关闭照常).
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 模板行 — 占位符 accent 绿, 其余 text 色; surface 圆角 12 底.
    private func templateRow(_ template: String) -> some View {
        Button {
            onPick(template)
            dismiss()
        } label: {
            Text(Self.styled(template))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MasoColor.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(MasoColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// AttributedString 按占位符 regex 分段染色 — 占位符 (连括号) 整段 accent 绿.
    private static func styled(_ template: String) -> AttributedString {
        var attr = AttributedString(template)
        for r in CoachTemplates.placeholderRanges(in: template) {
            if let ar = Range(r, in: attr) {
                attr[ar].foregroundColor = MasoColor.accent
            }
        }
        return attr
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
