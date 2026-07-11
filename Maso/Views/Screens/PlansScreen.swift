import SwiftUI

// MARK: - 共享计划组件 (原 PlansScreen 正文已退役 — Coach tab 接管, docs/coach-tab-design.md 拆迁清单)
//
// PlansScreen struct (单页 IA 正文) 与 Plans tab 挂载已在批次 3 拆除; 本文件现在只装被
// Coach / Today / RootView 复用的组件: ClassicsSheet / PlanRationaleCard / TrainingPreferencesSheet /
// PlanRow / PlanDetailSheet (+EditStepView) / ExercisePickerSheet / ShareActivityView.


// MARK: - ClassicsSheet — 经典模板列表 (原 communityPage 分段整体迁来, #single-page-IA)
//
// Routines 单页的 Classics 入口卡 → 这个 sheet. 自包含: Level/Days 筛选条固定钉在顶部 (sheet 语境
// 走简单固定, 不用 safeAreaBar), 计划卡 / 详情预览 / 满额 paywall 都挂在 sheet 内部 (sheet 之上
// 再叠 sheet 是允许的; 若挂回底下的 PlansScreen 会撞"一次只能 present 一个 sheet").
// internal (非 private) — CoachScreen 的 [+] 工具菜单 "Browse Classics" 也拉起它 (coach-tab-design.md §1).
struct ClassicsSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 详情页 Start → 先关本 sheet 再启动训练 (player 是 RootView 的 fullScreenCover).
    let onStart: (Plan) -> Void

    /// Classics 筛选 (#filters): 等级 + 每周天数. nil = 全部.
    @State private var communityLevel: String? = nil
    @State private var communityDays: Int? = nil
    @State private var detailPlan: Plan? = nil
    /// detailPlan 是哪套 Classics 项目的预览 — 详情页 Save 要按"整套"存 (所有训练日), 不能只存
    /// 预览的那一张, 所以得记住来源 CommunityPlan. 跟 detailPlan 同时设置.
    @State private var detailCP: CommunityPlan? = nil
    /// Save 满额 (免费上限) → paywall — 跟 PlansScreen.addToSaved 同规则, 付费/上限逻辑不变.
    @State private var paywallPresented = false
    /// 保存成功 toast ("已添加 N 个训练日") — 多日项目存的是 N 张 Plan, 必须明确告知, 否则用户
    /// 以为只存了一张. ~2.2s 自动消失 (跟 HistoryScreen.applyToast 同款).
    @State private var addedToast: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 筛选条固定钉在导航栏下方, 不随列表滚动.
                classicsFilterBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let plans = filteredCommunityPlans
                        if plans.isEmpty {
                            Text("No Classics match these filters.")
                                .font(.system(size: 13))
                                .foregroundStyle(MasoColor.textDim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        } else {
                            ForEach(plans) { cp in communityCard(cp) }
                        }
                        Spacer(minLength: MasoMetrics.pageBottomInset)
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 4)
                }
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Classics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
            // 保存成功 toast — 底部浮一句 "已添加 N 个训练日", 自动消失.
            .overlay(alignment: .bottom) {
                if let addedToast {
                    Text(addedToast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(MasoColor.surfaceHi))
                        .padding(.bottom, MasoMetrics.pageBottomInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .presentationDragIndicator(.visible)
        // 详情预览 — sheet 之上叠 sheet (挂在本 sheet 的内容树上, 不回落到 PlansScreen).
        .sheet(item: $detailPlan) { plan in
            PlanDetailSheet(
                initialPlan: plan,
                onStart: { p in
                    detailPlan = nil
                    dismiss()   // player 是 RootView 的 fullScreenCover — 先把 Classics 层收掉
                    DispatchQueue.main.async { onStart(p) }
                },
                // Save 存整套 (所有训练日), 不是预览的这一张 — 见 addClassics (P0#3).
                onAddToSaved: { _ in
                    if let cp = detailCP { addClassics(cp) }
                },
                classicsDayCount: detailCP.map(\.sessions.count)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen()
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Classics filters (#filters)

    private var communityLevelOptions: [String] { Array(Set(CommunityPlans.all.map(\.levelKey))).sorted() }
    private var communityDayOptions: [Int] { Array(Set(CommunityPlans.all.map(\.frequencyDaysPerWeek))).sorted() }
    private var filteredCommunityPlans: [CommunityPlan] {
        CommunityPlans.all.filter {
            (communityLevel == nil || $0.levelKey == communityLevel) &&
            (communityDays == nil || $0.frequencyDaysPerWeek == communityDays)
        }
    }

    /// Classics 筛选条 — Level / Days-week 两个 FilterMenuButton (.systemMenu 样式), 跟 Exercises 页
    /// 的 Muscle / Equipment 筛选完全同款 (tinted 文字 + chevron.up.chevron.down, 无绿胶囊).
    private var classicsFilterBar: some View {
        HStack(spacing: 8) {
            FilterMenuButton(
                title: NSLocalizedString("Level", comment: "Classics filter placeholder"),
                allLabel: NSLocalizedString("All levels", comment: ""),
                selected: $communityLevel,
                options: communityLevelOptions.map { lv in
                    FilterMenuOption(value: lv, label: NSLocalizedString(lv, comment: "community plan level"))
                },
                style: .systemMenu
            )
            FilterMenuButton(
                title: NSLocalizedString("Days/week", comment: "Classics filter placeholder"),
                allLabel: NSLocalizedString("Any frequency", comment: ""),
                selected: $communityDays,
                options: communityDayOptions.map { d in
                    FilterMenuOption(value: d, label: String(format: NSLocalizedString("%lld days/wk", comment: ""), d))
                },
                style: .systemMenu
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.vertical, 8)
    }

    /// 社区精选卡 — 跟 AI 卡同款 WorkoutCard 排版 (肌肉图 + 动作 chip + 计数), 不再是单薄的文字行.
    /// kicker 用 cp.kicker (FULL BODY / STRENGTH / PUSH·PULL·LEGS …); 点卡片 → 预览; 底部星标按钮 → 存进 My Plans.
    private func communityCard(_ cp: CommunityPlan) -> some View {
        Group {
            if let plan = communityDisplayPlan(cp) {
                WorkoutCard(
                    plan: plan,
                    exById: data.exById,
                    kicker: classicsKicker(cp),
                    onStart: { detailCP = cp; detailPlan = plan },
                    onShowDetail: { detailCP = cp; detailPlan = plan },
                    prominentStart: false,
                    addAction: { addClassics(cp) },
                    compactLayout: true
                )
            }
        }
    }

    /// 卡片 kicker — 多日项目追加 "· N 个训练日": 卡片上的动作/组数只是第一天的量, 不标注天数
    /// 会跟 "PPL 6-day" 这类标题自相矛盾 (P0#3 附带问题). 单日项目保持原 kicker.
    private func classicsKicker(_ cp: CommunityPlan) -> String {
        guard cp.sessions.count > 1 else { return cp.kicker }
        return cp.kicker + " · " + String(format: NSLocalizedString("%lld training days", comment: "classics card day count"), cp.sessions.count)
    }

    /// 社区 plan → 卡片展示用的 Plan. 只取第一张 session 作**预览** (卡片/详情展示用),
    /// 标题改回整套项目名. ⚠️ 仅供展示 — 真正保存必须走 addClassics (整套 materialize).
    private func communityDisplayPlan(_ cp: CommunityPlan) -> Plan? {
        guard var plan = cp.materialize(byId: data.exById).first else { return nil }
        plan.name = NSLocalizedString(cp.nameKey, comment: "community plan name")
        return plan
    }

    /// 详情页 Save / 卡片星标 → 把整套项目的**所有训练日**逐张存进 My Routines (P0#3).
    /// materialize 返回每 session 一张 Plan (命名 "项目名 · Session名"); 之前只存第一张却顶着
    /// 整套名字 — 存 "PPL 6-day" 实际只拿到 Push 日. 语义对齐旧 CommunityScreen.handleAdd.
    private func addClassics(_ cp: CommunityPlan) {
        detailPlan = nil
        // 免费上限按"整套"预检 — 一套 PPL = 6 张 Plan, 放不下就整套弹 paywall, 不存一半.
        if !data.settings.isPro && data.plans.count + cp.sessions.count > FreeLimit.maxPlans {
            paywallPresented = true
            return
        }
        let newPlans = cp.materialize(byId: data.exById)
        guard !newPlans.isEmpty else { return }
        data.plans.append(contentsOf: newPlans)
        data.save()
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            addedToast = String(format: NSLocalizedString("Added %lld workout days", comment: "classics saved toast"), newPlans.count)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeIn(duration: 0.25)) { addedToast = nil }
        }
    }
}


// MARK: - PlanRationaleCard — 解释为什么 plans 长这样
//
// 设计哲学 (style "A" — 冷静解释型):
//   - 不做激励 slogan, 给用户事实
//   - kicker (FOR YOU / 为你设计) + data row (每周 N · style · 重点 muscles) + 一句 rationale
//   - 数据全部从 settings 拿, 用户改了 onboarding 偏好 → card 自动更新
//   - Plan 列表空时不显示 (没东西可解释)
//
// rationale 副文案逻辑:
//   - 没填 wantStrengthen → 走 "全身均衡" 文案
//   - days >= 5 → 高频
//   - days 3-4 → 中频 (经典每周 2× / muscle)
//   - days 1-2 → 维持频率
// 完全复刻 AI Coach Summary 卡 (AISummaryCard) 的壳/表头/配色/字号:
//   - 壳: cardChrome() (padding 14 + surface 填充 + corner 16) — 跟 AISummaryCard 逐像素同一片.
//   - 表头: 12pt bold accent 图标 + 14pt bold text 标题 + Spacer + 13pt semibold textDim 尾图标
//     (AISummaryCard 表头是 sparkles + 标题 + arrow.clockwise; 这里图标换成 slider.horizontal.3,
//      sparkles 留给 AI 生成的小结卡, 让两张卡读起来是"兄弟"不是"双胞胎"; 尾图标 = pencil —
//      owner 指定的"编辑"语义: 这张卡点开是去改偏好, 不是导航跳转, chevron 会误读成"进下一页").
// 自然语言偏好入口收进编辑层底部的 "Tell your AI coach" 编辑器 — 卡上不再有单独的 tune 入口.
struct PlanRationaleCard: View {
    @Environment(DataStore.self) private var data
    /// 点编辑 → 拉起 Training Preferences 层 (sheet). 层里改完点 Generate → 重生成.
    @State private var showEditor = false
    /// 点 "Generate routines" 应用偏好后回调 — 调用方 (aiPage) 拿来跑生成动画.
    var onApplyPreferences: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 表头 — 复刻 AISummaryCard.header: spacing 8, 12pt bold accent 图标 + 14pt bold text 标题
            // + Spacer + 13pt semibold textDim chevron. 整行 onTapGesture → 结构化偏好编辑层.
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MasoColor.accent)
                Text("Training Preferences")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
            }
            .contentShape(Rectangle())
            .onTapGesture { showEditor = true }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Adjust training preferences"))
            .accessibilityAddTraits(.isButton)

            // 已选参数以纯文字小字展示 (灰色) — 一行 skimmable 概览, 直接在表头下方.
            Text(prefSummary)
                .font(.system(size: 12))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)

        }
        .cardChrome()
        .sheet(isPresented: $showEditor) {
            TrainingPreferencesSheet(onConfirm: onApplyPreferences)
        }
    }

    // MARK: - 偏好摘要 (纯文字小字, 不再用 chip)

    /// 已选参数拼成一行小字 (天数 · 目标 · 动作数 · 组数 · 器械 · 重点肌群), 用 " · " 分隔.
    /// e.g. "3 days / week · Build muscle · 4 exercises · 3 sets · Dumbbells, Barbell · Focus: Chest, Back".
    private var prefSummary: String {
        let s = data.settings
        var parts: [String] = []
        parts.append(String(format: NSLocalizedString("%lld days / week", comment: ""), s.weeklyTrainingDays))
        parts.append(s.trainingGoalKind.displayName)
        parts.append(String(format: NSLocalizedString("%d exercises", comment: ""), s.exercisesPerSession))
        parts.append(String(format: NSLocalizedString("%d sets", comment: ""), s.defaultSetsPerExercise))
        if s.availableEquipment.isEmpty {
            parts.append(NSLocalizedString("Any equipment", comment: ""))
        } else {
            let cats = s.availableEquipment.compactMap { EquipmentCategory(rawValue: $0)?.displayName }
            let shown = cats.prefix(2).joined(separator: ", ")
            parts.append(shown + (cats.count > 2 ? " +\(cats.count - 2)" : ""))
        }
        let majors = MuscleSelector.focusSummary(Set(s.wantStrengthen))
        if !majors.isEmpty {
            let names = majors.prefix(3).map(\.displayName).joined(separator: ", ")
            parts.append(String(format: NSLocalizedString("Focus: %@", comment: "training prefs focus muscles"),
                                names + (majors.count > 3 ? " +\(majors.count - 3)" : "")))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Training Preferences 编辑层 (sheet)
//
// 点 Training Preferences 卡 → 拉起这层 (large detent). 内容 = Settings 同款 TrainingSettingsSection
// (live 写 data.settings). 偏好是"生成物料"但也可独立维护, 所以给两条出口 (owner 指定):
//   · 右上 Save (粗体, 编辑型 sheet 规范) → 只存盘关层, 不触发生成 — 单纯改偏好.
//   · 底部 ✨ Save & generate routines 大 CTA → 存盘 + 关层 + 触发重生成 — 改完直接要新计划.
// Cancel → 回滚到进入时快照.
// internal (非 private) — 历史上给 Coaching sheet 复用过, 现仅本文件用, 保持 internal 无害.
struct TrainingPreferencesSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 关层 + 重生成的回调 (= aiPage 的 startGenerateRoutines / Coach 的 send).
    var onConfirm: () -> Void
    /// 进入时的偏好快照 — Cancel 时回滚 (TrainingSettingsSection 是 live 编辑).
    @State private var original: UserSettings? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                TrainingSettingsSection()
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .background(MasoColor.background)
            .navigationTitle("Training Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 顶栏规范: 编辑型 sheet = 左上 Cancel + 右上粗体主操作.
                // 右上 Save = 只保存不生成; "生成"是升格路径, 放底部大 CTA 不进顶栏.
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) { saveOnly() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveAndGenerate) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 14, weight: .heavy))
                        Text("Save & generate routines").font(.system(size: 15, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.black)
                    // 主 CTA 统一系统玻璃 (owner 映射表①): iOS 26 accent 高浓度玻璃 + 黑字, 旧系统保留实心.
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.85), fallback: MasoColor.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(MasoColor.background)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { if original == nil { original = data.settings } }
    }

    private func cancel() {
        if let o = original { data.settings = o; data.save() }   // 回滚未确认的改动
        dismiss()
    }

    /// 链路①: 只保存 — 偏好独立维护, 下次生成 (AI 今日推荐 / Coach 首轮) 自然生效.
    private func saveOnly() {
        Haptics.tap()
        data.save()
        original = nil
        dismiss()
    }

    /// 链路②: 保存并立即触发生成.
    private func saveAndGenerate() {
        Haptics.tap()
        data.save()
        original = nil
        dismiss()
        onConfirm()   // → startGenerateRoutines / Coach send: loading → 新 routine
    }
}

// MARK: - Plan list row

struct PlanRow: View {
    let plan: Plan
    let exById: [String: Exercise]
    let onTap: () -> Void
    /// 圆形播放按钮独立 action — tap 圆按钮 = 启动训练 (绕过 detail sheet).
    /// 跟整卡 tap (进 detail) 分开, 让"快速开练" 跟"编辑/查看" 两个意图清楚.
    let onStart: () -> Void
    /// "请求删除" callback — parent (PlansScreen) 接管二次确认 alert, 跟右滑删除走同一路径.
    /// PlanRow 自己不再 own confirm state.
    let onDelete: () -> Void

    private var muscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for s in plan.steps {
            guard let ex = exById[s.exerciseId] else { continue }
            for m in ex.muscleGroups where seen.insert(m).inserted {
                out.append(m)
            }
        }
        return out
    }

    var body: some View {
        // 紧凑横排布局: 左侧肌肉图 + 右侧文字, 播放键钉在卡片右下角.
        //   左: MuscleVisualBlock (72pt)
        //   右: plan name (16pt bold) + 小 chevron  →  meta subtitle
        //   右下角: 圆形播放键, 距右边缘 & 底边等距 (各 12pt)
        // 高度由肌肉图主导 (~72pt) + 垂直 padding, 比原"竖排三行"版本矮约 50pt.
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .center, spacing: 14) {

                // ── 左: 肌肉图 ──
                MuscleVisualBlock(muscles: muscles, sideLength: 72)
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                // ── 右: 文字区 (tap → detail) ──
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        PlanSourceBadge(source: plan.resolvedSource)   // AI / Classics 来源标签
                        Text(plan.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
            }
            // padding 放 HStack 上 (而不是整张卡), 这样下面播放键的 .padding(12) 是相对
            // 卡片外缘算的 → 距右 & 距底都正好 12pt, 完全对称.
            .padding(.horizontal, MasoMetrics.cardPadding - 2)
            .padding(.vertical, 12)

            // ── 播放键 — 钉在卡片右下角, 距右边缘 & 底边等距 (各 12pt) ──
            // 自绘圆底图标钮 → 玻璃圆 (映射表④): 弱播放键跟 WorkoutCard.startButtonLabel 弱态同配方
            // (accent 低浓度玻璃 + accent icon); 旧系统保留原半透圆 + 描边.
            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(MasoColor.accent)
                    .offset(x: 0.5)
                    .frame(width: 28, height: 28)
                    .glassCircleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                 fallback: MasoColor.accent.opacity(0.18))
                    .overlay(Circle().stroke(systemGlassAvailable ? .clear : MasoColor.accent.opacity(0.4),
                                             lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Workout")
            .padding(12)
        }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // 长按整卡 → 删除菜单. parent (PlansScreen) 接管 confirm — 跟右滑删除走同一 alert.
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label {
                    Text("Delete Plan")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - PlanDetailSheet — 可编辑版 (RootView 也用它做新建)

struct PlanDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let initialPlan: Plan
    let onStart: (Plan) -> Void
    /// Discover 用 — 非 nil 时右上角显示系统默认 "+" 加进 Saved (并隐藏 …/Delete 菜单, 因为这张还没拥有).
    let onAddToSaved: ((Plan) -> Void)?
    /// Classics 预览专用 — 整套项目的训练日数. > 1 时在 Save CTA 下标注 "含 N 个训练日":
    /// 预览显示的只是第一天, 不标注会让用户以为整套就这几个动作 (P0#3). 其他调用方不传 (nil 不显示).
    let classicsDayCount: Int?
    /// 书签态覆盖 (Coach 生成卡详情用 — savedIdMap 反查, 副本改名后不失灵).
    /// nil → 现状 data.isPlanSaved(draft) (签名匹配), 其它调用方不受影响.
    let savedOverride: Bool?

    @State private var draft: Plan
    @State private var showAddPicker: Bool = false
    /// 删除整个 plan 的确认 alert. 走 sheet 的"…"菜单触发.
    @State private var confirmDelete: Bool = false
    /// 点 step 行 / 卡片图片缩略图弹的动作详情. tap 文字区域走 NavigationLink 进编辑页.
    @State private var detailExercise: Exercise? = nil
    /// 右滑删除 step / contextMenu Delete 的待删 stepId — alert 二次确认才真删.
    @State private var pendingDeleteStepId: String? = nil
    /// 右滑 Edit / NavigationLink tap 共用同一 navigation path — append stepId 触发 push 进编辑页.
    @State private var stepEditPath = NavigationPath()
    /// 动作列表的视图模式 — 单列 row (default) 还是 2 列 grid card.
    /// 持久化到 UserDefaults — 跨 sheet 开关 / app 重启都保留, 用户偏好一旦设定不会"忘".
    @AppStorage("planStepCardLayout") private var useCardLayout: Bool = false
    /// Share plan — 点 toolbar 分享按钮 → 拉起 UIActivityViewController 分享 maso:// 链接.
    /// 分享图 — RoutineShareCard 渲染产物 (含 maso:// 深链 QR). 设了就弹 share sheet.
    @State private var shareImage: UIImage? = nil
    /// Share encode 失败时弹的简单 alert (理论上不会触发).
    @State private var shareFailed: Bool = false
    /// 右滑"替换动作"流程: stepId set 非 nil 时弹 ExercisePickerSheet 让用户挑新动作,
    /// 选完后只换 exerciseId, 保留 sets/reps/weight 等参数 (用户调过的负荷不要被替换抹掉).
    /// 跟 showAddPicker (append) 走两套 sheet, 语义清楚.
    @State private var stepToReplaceId: String? = nil

    init(initialPlan: Plan, onStart: @escaping (Plan) -> Void, onAddToSaved: ((Plan) -> Void)? = nil,
         classicsDayCount: Int? = nil, savedOverride: Bool? = nil) {
        self.initialPlan = initialPlan
        self.onStart = onStart
        self.onAddToSaved = onAddToSaved
        self.classicsDayCount = classicsDayCount
        self.savedOverride = savedOverride
        self._draft = State(initialValue: initialPlan)
    }

    private var muscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var out: [MuscleGroup] = []
        for s in draft.steps {
            guard let ex = data.exById[s.exerciseId] else { continue }
            for m in ex.muscleGroups where seen.insert(m).inserted {
                out.append(m)
            }
        }
        return out
    }

    private var totalSets: Int { draft.steps.reduce(0) { $0 + $1.sets } }

    var body: some View {
        // NavigationStack(path:) — 让 swipe Edit 能 programmatic push step 进编辑页 (跟 tap 整行
        // 走 NavigationLink 同终点). path 用 NavigationPath, append stepId 即触发 destination.
        NavigationStack(path: $stepEditPath) {
            // List + Section 让 stepListSection 里的 ForEach 能用原生 .onMove + .swipeActions.
            // ScrollView+VStack 不支持. 清掉 List 默认样式后视觉跟原来一致.
            List {
                Section {
                    headerCard
                        .listRowSeparator(.hidden)
                        // top 28 — 标题离顶部留多点空间, 不顶着导航栏 (之前 12 太挤).
                        .listRowInsets(EdgeInsets(top: 28, leading: 0, bottom: 20, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                stepListSection
                Section {
                    addExerciseButton
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 32, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, MasoMetrics.pagePaddingHorizontal, for: .scrollContent)
            .background(MasoColor.background.ignoresSafeArea())
            // 不显示 nav title — 用户要求 Edit Workout 系列页面都不要标题
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 拥有的计划 (Today/Saved): 右上角显眼的"分享"按钮 (一键分享 routine 图 + QR),
                // 左上角直接摆删除按钮 (owner 拍板: 原 "…" overflow 里只有一个 Delete, 多一跳没意义;
                // 破坏性动作有 confirmDelete 二次确认兜底).
                if onAddToSaved == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            handleSharePlan()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(NSLocalizedString("Share plan", comment: ""))
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(NSLocalizedString("Delete Plan", comment: ""))
                    }
                }
                // Tab 2 browse 预览: 主操作 = body 的 "★ Add to my plans" 大 CTA, 顶栏不再放 "+" (去重).
                // 顶栏 Start 胶囊也删了 — body 大 CTA 够显眼; iOS sheet 自带下拉关闭, 不需要 Done.
            }
            // Share sheet — UIActivityViewController 桥. 分享 RoutineShareCard 渲染图 (深链在图内 QR).
            .sheet(isPresented: Binding(
                get: { shareImage != nil },
                set: { if !$0 { shareImage = nil } }
            )) {
                if let img = shareImage {
                    ShareActivityView(activityItems: [img])
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .alert("Couldn't create share link", isPresented: $shareFailed) {
                Button("OK", role: .cancel) {}
            }
            .alert("Delete plan?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    // 先关 sheet 再删 — 否则 sheet 关闭时引用的 initialPlan 已经被 data store 删了,
                    // 中间过渡会闪一下黑色 placeholder. 顺序: dismiss → 下一个 runloop tick 删.
                    dismiss()
                    let planId = draft.id
                    DispatchQueue.main.async {
                        data.deletePlan(planId)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your training history will be kept.")
            }
            // 右滑 / contextMenu 删除 step 的二次确认 alert
            .alert("Delete exercise?", isPresented: Binding(
                get: { pendingDeleteStepId != nil },
                set: { if !$0 { pendingDeleteStepId = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDeleteStepId,
                       let idx = draft.steps.firstIndex(where: { $0.id == id }) {
                        draft.steps.remove(at: idx)
                        commit()
                    }
                    pendingDeleteStepId = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteStepId = nil }
            } message: {
                Text("This only removes the exercise from this plan, not from your library.")
            }
            // 子页面 nav 目的地: 编辑某个 step
            .navigationDestination(for: PlanStep.ID.self) { stepId in
                if let idx = draft.steps.firstIndex(where: { $0.id == stepId }),
                   let ex = data.exById[draft.steps[idx].exerciseId] {
                    EditStepView(
                        exercise: ex,
                        step: $draft.steps[idx],
                        onDelete: {
                            draft.steps.remove(at: idx)
                            commit()
                        },
                        // Replace 入口挪进编辑页顶部 (跟播放列表 Edit sheet 一致): 点后弹回列表并弹替换 picker.
                        onReplace: {
                            stepEditPath = NavigationPath()   // 先 pop 回列表
                            stepToReplaceId = stepId           // 再弹 ExercisePickerSheet
                        }
                    )
                    .onChange(of: draft.steps[safe: idx]) { _, _ in commit() }
                }
            }
            .sheet(isPresented: $showAddPicker) {
                // 添加动作 = 多选勾选 (跟 Free Workout 一致), 一次可选多个 → 底部 "Add (N)" 一并加入.
                ExercisePickerSheet(
                    onPick: { _ in },   // multiSelect 模式不走单选回调
                    multiSelect: true,
                    onPickMultiple: { exercises in
                        for (i, ex) in exercises.enumerated() {
                            // R3: 参数按"全局同步开/关"取默认 — 开则采用已有 routine 里该动作的参数,
                            // 否则从该动作最近一次记录回填 (取代过去硬编码的 3 组 / 10 次 / 90s).
                            draft.steps.append(data.makeSeededStep(
                                for: ex,
                                stepId: "step-\(ex.id)-\(Int(Date().timeIntervalSince1970))-\(i)"
                            ))
                        }
                        commit()
                        showAddPicker = false
                    },
                    startTitle: NSLocalizedString("Add", comment: "add selected exercises CTA")
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // 替换动作 sheet — 跟 add 走同款 ExercisePickerSheet, 但 onPick 只替换 exerciseId,
            // 保留 sets/reps/weight 等强度参数. 用 isPresented bool binding 而不是 item, 因为
            // body 已经很大, item: Binding 让编译器 type-check 超时.
            .sheet(isPresented: replaceSheetPresented) {
                ExercisePickerSheet(
                    onPick: handleReplacePick,
                    // 替换: 预选原动作部位 (动作 + 器械留空).
                    initialMuscle: {
                        guard let id = stepToReplaceId,
                              let exId = draft.steps.first(where: { $0.id == id })?.exerciseId,
                              let ex = data.exById[exId] else { return nil }
                        return ex.primaryMuscles.first?.section
                    }()
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            // 点 PlanStepRow / Card 图片 → 弹动作详情 (跟其它 5 个列表共用 ExerciseDetailSheet).
            // 整行 tap 仍走 NavigationLink 进 EditStepView (改 sets/reps/weight). 图片是 Button,
            // hit-test 优先级高于 NavigationLink, 不会同时触发.
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
                .presentationDragIndicator(.visible)
            }
            .tint(MasoColor.text)
        }
    }

    // 把 draft 写回 data store
    private func commit() {
        draft.updatedAt = Date()
        data.updatePlan(draft)
    }

    /// 替换动作 sheet 的 isPresented binding — 拆出来减轻 body type-check 负担.
    private var replaceSheetPresented: Binding<Bool> {
        Binding(
            get: { stepToReplaceId != nil },
            set: { if !$0 { stepToReplaceId = nil } }
        )
    }

    /// 替换动作完成回调 — ExercisePickerSheet 选了新 ex 后调进来.
    /// PlanStep.exerciseId 是 let, 不能直接改, 用整 step 替换 (保留 sets/reps/weight/duration
    /// 等强度参数, 避免用户调过的负荷被抹).
    private func handleReplacePick(_ newExercise: Exercise) {
        defer { stepToReplaceId = nil }
        guard let id = stepToReplaceId,
              let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let old = draft.steps[idx]
        draft.steps[idx] = PlanStep(
            id: old.id,
            exerciseId: newExercise.id,
            sets: old.sets,
            reps: old.reps,
            weight: old.weight,
            duration: old.duration,
            restBetweenSets: old.restBetweenSets,
            rest: old.rest
        )
        commit()
    }

    /// Share — 渲染 RoutineShareCard 分享图 (计划内容 + 品牌 footer + App Store QR).
    /// QR 指向 App Store (引导没装 app 的人下载); 收图的人 "从照片导入" 时走 OCR 读卡上动作名+组数还原.
    /// 渲染失败 → 弹 alert 兜底, 不静默.
    private func handleSharePlan() {
        guard let img = ShareImageRenderer.render(width: 390, {
            RoutineShareCard(plan: draft, exById: data.exById, qrPayload: MasoLinks.appStore)
        }) else {
            shareFailed = true
            return
        }
        Haptics.tap()
        Analytics.shared.track("routine_share")   // 无 PII: 不带计划名/动作
        shareImage = img
    }

    // 顶部信息卡 — 简化版.
    // 之前: BodyHint 左 + WORKOUT kicker + TextField + 2 StatPills 信息密. 用户反馈"信息过多 + TextField 不明显".
    // 现在: TextField 独立一行带明显 input 样式 + BodyHint 单独居中. 信息层级清楚.
    //   - StatPill (exercises/sets count) 移除 — stepList header 已能看出动作数
    //   - WORKOUT kicker 移除 — nav title "Edit Workout" 重复
    private var headerCard: some View {
        VStack(spacing: 14) {
            // Plan name — 15pt regular (iOS HIG Subhead 字号), 比之前 .body (17pt) 小一档.
            // 视觉上跟 Settings row 输入风格一致 — 是普通可编辑文本, 不抢戏.
            // padding 也同步收 (12 → 10pt 垂直), 让输入框整体瘦一些.
            TextField("Workout name", text: Binding(
                get: { draft.name },
                set: { draft.name = $0; commit() }
            ))
            .font(.system(size: 15))
            .foregroundStyle(MasoColor.text)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MasoColor.borderSoft, lineWidth: 0.5)
            )

            // Muscle map — Edit Workout 顶部居中 (跟 PlanRow / SessionCard 列表行的左对齐不同).
            // 这里没有右侧 play/replay 按钮压在同一行, 单纯展示 plan 命中的肌群; 居中视觉更
            // 端正, 不会"左重右空"。fixedSize 阻止 MuscleVisualBlock 撑全宽 (它默认 maxWidth: .infinity).
            HStack {
                Spacer(minLength: 0)
                MuscleVisualBlock(muscles: muscles, sideLength: 110)
                    .fixedSize()
                Spacer(minLength: 0)
            }

            // 主 CTA — body 显眼位置, 实心 accent 胶囊 (Apple Music / Apple Fitness detail 同套路).
            //   - 拥有的计划 (Tab 1): "Start workout"
            //   - Tab 2 browse 预览 (onAddToSaved != nil): "★ Add to my plans" — browse 主操作是加进我的计划.
            if let onAddToSaved {
                VStack(spacing: 8) {
                    addToPlansCTA(onAddToSaved)
                    // Classics 多日项目: 明示 Save 存的是整套 (预览只展示第一天) — 见 classicsDayCount.
                    if let n = classicsDayCount, n > 1 {
                        Text(String(format: NSLocalizedString("Includes %lld training days — Save adds all of them", comment: "classics detail day note"), n))
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                startWorkoutCTA
            }
        }
    }

    /// 全宽 "Start workout" 大胶囊 CTA — body 主操作. 跟 toolbar 右上的小 Start 是同一个 action,
    /// 一冗余一隐性: 用户错过 toolbar 也不会错过这个; 已经知道流程的高频用户直接走 toolbar 一步到位.
    private var startWorkoutCTA: some View {
        Button(action: handleStart) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("Start workout")
                    .font(.system(size: 15, weight: .heavy))
            }
            // 不撑满 — 胶囊只包住 图标 + 文字 (用户要求). VStack(.center) 让它居中.
            .padding(.vertical, 13)
            .padding(.horizontal, 28)
            .foregroundStyle(.black)
            // 主 CTA 系统玻璃 (映射表①); 阴影只留给旧系统实心版, 玻璃自带层次不再叠影.
            .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.85), fallback: MasoColor.accent)
            .shadow(color: systemGlassAvailable ? .clear : MasoColor.accent.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)  // 跟 muscle map 之间留 18pt (VStack spacing 14 + 4) — 视觉分组
    }

    /// Tab 2 browse / Coach 预览的主 CTA — Save ↔ Saved 书签开关 (跟 AddToPlansButton 同一套
    /// bookmark 语言, coach-tab-design.md §2). 跟 startWorkoutCTA 同视觉规格 (实心 accent 胶囊).
    /// **两态都可点** — action 恒触发, toggle 语义由调用方决定 (已存再点 = unsave, 按钮随 plans 响应式翻回 Save).
    private func addToPlansCTA(_ action: @escaping (Plan) -> Void) -> some View {
        let saved = savedOverride ?? data.isPlanSaved(draft)
        return Button { action(draft) } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .heavy))
                // 去向点名 (owner 反馈裸 "Save" 不知道存到哪) — 跟 AddToPlansButton 同文案.
                Text(saved ? "Saved to routines" : "Save to routines")
                    .font(.system(size: 15, weight: .heavy))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 28)
            .foregroundStyle(saved ? MasoColor.textDim : .black)
            // 主 CTA 系统玻璃 (映射表①): 未存 = accent 高浓度玻璃 + 黑字; 已存 = 素玻璃 + 灰字
            // (跟 AddToPlansButton 已存态同配方). 旧系统保留原实心/surfaceHi.
            .glassCapsuleButtonBackground(tint: saved ? nil : MasoColor.accent.opacity(0.85),
                                          fallback: saved ? MasoColor.surfaceHi : MasoColor.accent)
            .shadow(color: (saved || systemGlassAvailable) ? .clear : MasoColor.accent.opacity(0.35), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: saved)
        .padding(.top, 4)
    }

    /// 开始训练 — toolbar Start 和 body CTA 都走这. dismiss → 下一 runloop 调 onStart,
    /// 避免 sheet 还在动画时 push 新 sheet 出问题 (PlanPlayer 是 RootView 上的另一个 sheet).
    private func handleStart() {
        Haptics.tap()
        let plan = draft  // 抓快照 — dismiss 后 self 已经销毁, 不能再读 self.draft
        dismiss()
        DispatchQueue.main.async { onStart(plan) }
    }

    /// 右滑删除 step 的二次确认 — 跟 PlansScreen 同模式, 存待删 stepId, alert 弹.
    @ViewBuilder
    private var stepListSection: some View {
        Section {
            // Header — "EXERCISES" kicker + 右侧 list/grid 切换.
            HStack {
                Text("Exercises")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(MasoColor.textFaint)
                Spacer()
                layoutToggle
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if draft.steps.isEmpty {
                Text("No exercises yet — tap “Add Exercise” to start")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
            } else if useCardLayout {
                // 2 列 grid 模式 — 卡片纵向: 大图 + 名字 + 详情.
                // grid 不支持原生 .onMove / .swipeActions, 改动只走 contextMenu 路径.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(draft.steps) { stp in
                        if let ex = data.exById[stp.exerciseId] {
                            stepEntry(step: stp, exercise: ex)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                // 单列 row 模式 (default) — 支持原生拖拽排序 + 右滑删除 + alert 二次确认.
                ForEach(draft.steps) { stp in
                    if let ex = data.exById[stp.exerciseId] {
                        stepEntry(step: stp, exercise: ex)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // 跟播放列表 (InlinePlaylist) 左滑一致: 只 Delete + Edit 两个 icon-only 钮.
                                // Replace 收进 Edit 页顶部 (EditStepView.onReplace), 不再单列左滑钮.
                                // 顺序 (从右往左, trailing edge): Delete → Edit.
                                Button(role: .destructive) {
                                    pendingDeleteStepId = stp.id
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .tint(MasoColor.negative)
                                .accessibilityLabel(NSLocalizedString("Delete", comment: ""))

                                Button {
                                    // programmatic push — 跟 NavigationLink tap 整行同 destination
                                    stepEditPath.append(stp.id)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .tint(MasoColor.accent)
                                .accessibilityLabel(NSLocalizedString("Edit", comment: ""))
                            }
                    }
                }
                .onMove { source, destination in
                    draft.steps.move(fromOffsets: source, toOffset: destination)
                    commit()
                    Haptics.tap()
                }
            }
        }
    }

    /// 单个 step 入口 — list / grid 共用.
    /// ZStack trick: 把 NavigationLink 包 EmptyView 隐到底层(.opacity 0), 自定义 row 显前面.
    /// 这样 List 不会因为 NavigationLink 自动加 disclosure chevron, 视觉干净.
    /// (PlanStepRow 已经自己在右侧加了 chevron — 默认 List chevron + 它自己的 = 重叠.)
    @ViewBuilder
    private func stepEntry(step stp: PlanStep, exercise ex: Exercise) -> some View {
        ZStack {
            // invisible navigation 触发器, 占满 row 区域接收 tap
            NavigationLink(value: stp.id) { EmptyView() }
                .opacity(0)

            // 实际渲染的 row / card — 显示在前面, NavigationLink 的 chevron 不会出来
            if useCardLayout {
                PlanStepCard(step: stp, exercise: ex, onTapImage: { detailExercise = ex })
            } else {
                PlanStepRow(step: stp, exercise: ex, onTapImage: { detailExercise = ex })
            }
        }
        .contextMenu {
            // 用 Label { Text } icon: { Image.foregroundStyle(.white) } 拆 init,
            // 强制 icon 走白色而不是系统 tint (accent 绿). label 文字保留默认.
            if canMoveUp(stp.id) {
                Button { moveStep(stp.id, by: -1) } label: {
                    Label {
                        Text("Move up")
                    } icon: {
                        Image(systemName: "arrow.up").foregroundStyle(.white)
                    }
                }
            }
            if canMoveDown(stp.id) {
                Button { moveStep(stp.id, by: 1) } label: {
                    Label {
                        Text("Move down")
                    } icon: {
                        Image(systemName: "arrow.down").foregroundStyle(.white)
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                pendingDeleteStepId = stp.id  // 走二次确认 alert, 跟右滑删除同路径
            } label: {
                // icon 统一强制白色 (跟 Move up/Down 一致). text 跟随 destructive role 红色.
                Label {
                    Text("Delete")
                } icon: {
                    Image(systemName: "trash").foregroundStyle(.white)
                }
            }
        }
    }

    /// list / grid 切换 — 两个 icon 按钮, 当前 mode 高亮 accent, 另一个 textFaint.
    /// withAnimation spring 切换时 grid <-> list 之间动画平滑, 不"跳"
    private var layoutToggle: some View {
        // 共享组件 — 跟 SessionDetailSheet 用同一份, 视觉 + 行为统一.
        LayoutToggle(useCardLayout: Binding(
            get: { useCardLayout },
            set: { useCardLayout = $0 }
        ))
    }

    // (P3: 删了死代码 layoutButton — LayoutToggle 组件早接管了, 这个 helper 无任何引用.)

    /// Step 上下移 + 删除 — 给 contextMenu 用. 改完直接 commit() 持久化.
    private func canMoveUp(_ id: String) -> Bool {
        guard let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return false }
        return idx > 0
    }
    private func canMoveDown(_ id: String) -> Bool {
        guard let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return false }
        return idx < draft.steps.count - 1
    }
    private func moveStep(_ id: String, by delta: Int) {
        guard let idx = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0, newIdx < draft.steps.count else { return }
        let step = draft.steps.remove(at: idx)
        draft.steps.insert(step, at: newIdx)
        commit()
        Haptics.tap()
    }
    // (P3: 删了死代码 removeStep — 删除都走 pendingDeleteStepId 二次确认路径, 这个无引用.)

    private var addExerciseButton: some View {
        Button(action: { showAddPicker = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Add Exercise")
                    .font(.system(size: 13, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.text.opacity(0.18), style: .init(lineWidth: 1, dash: [5, 4]))
            )
            .foregroundStyle(MasoColor.textDim)
        }
        .buttonStyle(.plain)
    }
}


/// 把一个 step 的 sets / reps / weight / duration 拼成一行短文案
/// (row 和 card 都用同一份格式, 一处改两处生效)
private func planStepDetailLine(_ step: PlanStep) -> String {
    if let d = step.duration {
        return "\(pluralizedSets(step.sets)) · \(d)s"
    }
    let reps = step.reps.map { "\($0)" } ?? "?"
    if let w = step.weight, w > 0 {
        return "\(pluralizedSets(step.sets)) · \(weightLabel(w)) × \(reps)"
    }
    return "\(pluralizedSets(step.sets)) × \(reps)"
}

// 单个 step 行 — 动作图 + 名字 + (sets × reps × weight 或 duration) + chevron
private struct PlanStepRow: View {
    let step: PlanStep
    let exercise: Exercise
    /// 点图片 → 弹动作详情. parent 传 closure, sheet 在 parent 挂.
    var onTapImage: (() -> Void)? = nil

    private var detailLine: String { planStepDetailLine(step) }

    var body: some View {
        // 视觉跟"训练中" InlinePlaylist.playlistRow 完全对齐:
        //   - HStack spacing 14 (原 12)
        //   - 缩略图 56 + cornerRadius 8 (原 48 / 8)
        //   - VStack spacing 5 (原 4)
        //   - 名字 15pt bold (原 14)
        //   - detailLine 12pt monospaced — 保留单 Text, 内容跟 playlistRow 同信息密度
        //   - ExerciseTagsRow muscleLimit 1 (原默认 2) — 行更瘦
        //   - 删了右侧 chevron — playlistRow 没 chevron, "tap → navigate" 用户直觉知
        //   - cornerRadius 10 (原 12)
        //   - padding.vertical 10 (原 rowPaddingV)
        HStack(spacing: 14) {
            Button(action: { onTapImage?() }) {
                ExerciseImage(
                    category: exercise.category,
                    imageFolder: exercise.imageFolder,
                    photoURL: exercise.photoURL,
                    customImageData: exercise.customImageData,
                    cornerRadius: 8,
                    size: 56,
                    animated: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), exercise.displayName))
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                ExerciseTagsRow(
                    muscleGroups: exercise.muscleGroups,
                    equipment: exercise.equipment,
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

// 单个 step 卡片 — 纵向布局 (图大 + 名字 + 详情). LazyVGrid 2 列时用.
// 视觉跟 Spotify / Apple Music 的 grid item 一致 — 图占大头, 文字"贴"图下面.
private struct PlanStepCard: View {
    let step: PlanStep
    let exercise: Exercise
    /// 点图片 → 弹动作详情. parent 传 closure, sheet 在 parent 挂.
    var onTapImage: (() -> Void)? = nil

    private var detailLine: String { planStepDetailLine(step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 图: 正方形, 铺满卡片宽度. GeometryReader 拿到实际 cell 宽度后传给 ExerciseImage,
            // 不然 ExerciseImage 默认 size=48 太小, grid 里会缩成小图.
            // 包 Button — tap 图片优先于外层 NavigationLink, 走详情而非编辑.
            Button(action: { onTapImage?() }) {
                GeometryReader { geo in
                    ExerciseImage(
                        category: exercise.category,
                        imageFolder: exercise.imageFolder,
                        photoURL: exercise.photoURL,
                        customImageData: exercise.customImageData,
                        cornerRadius: 8,
                        size: geo.size.width,
                        animated: false
                    )
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("Show details for %@", comment: "exercise detail a11y"), exercise.displayName))

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
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
                // 卡片宽度受限, 用 compact + muscleLimit 1 — 只显 1 个肌肉 + equipment.
                ExerciseTagsRow(
                    muscleGroups: exercise.muscleGroups,
                    equipment: exercise.equipment,
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

// MARK: - EditStepView — 改一个动作的 sets / reps / weight / rest

private struct EditStepView: View {
    let exercise: Exercise
    @Binding var step: PlanStep
    let onDelete: () -> Void
    /// 替换动作 — 跟播放列表 Edit sheet 一致, Replace 入口放编辑页顶部 (参数之上). nil = 不显示.
    var onReplace: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 动作头部 — 大图 hero + 名字 + tag.
                // 之前 64×64 缩略图太小, 用户在动作详情页是来看清这个动作的, 图应该 prominence.
                // full-width 正方形 (跟卡片宽度等高), animated:true 让用户看到动作的两帧流.
                GeometryReader { geo in
                    ExerciseImage(
                        category: exercise.category,
                        imageFolder: exercise.imageFolder,
                        photoURL: exercise.photoURL,
                        customImageData: exercise.customImageData,
                        cornerRadius: 16,
                        size: geo.size.width,
                        animated: true
                    )
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(2)
                    if let first = exercise.tags.first {
                        Text(first)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 替换动作入口 — 跟播放列表的 Edit sheet 一致, 放编辑页顶部 (参数之上).
                // 点后由 parent 弹回列表并弹 ExercisePickerSheet; 只换 exerciseId, 参数(组/次/重量)保留.
                if let onReplace {
                    Button(action: onReplace) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .bold))
                            Text("Replace exercise")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(MasoColor.accent.opacity(0.16))
                        .foregroundStyle(MasoColor.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // 参数编辑 section
                paramSection

                // 删除动作
                Button(role: .destructive, action: { confirmDelete = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                        Text("Delete Exercise")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(MasoColor.negative.opacity(0.18))
                    .foregroundStyle(MasoColor.negative)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(MasoColor.background.ignoresSafeArea())
        // 不显示 nav title — 用户要求 Edit Workout 系列页面都不要标题
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove this exercise?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(exercise.displayName)” will be removed from this workout. Past records are kept.")
        }
    }

    @ViewBuilder
    private var paramSection: some View {
        VStack(spacing: 0) {
            // 组数 — 共用 (strength + cardio + flexibility)
            EditRow(label: "Sets") {
                NumStepperField(intValue: $step.sets, range: 1...10)
            }
            Divider().background(MasoColor.borderSoft)

            if exercise.category == .strength {
                EditRow(label: "Reps") {
                    NumStepperField(
                        intValue: Binding(
                            get: { step.reps ?? 0 },
                            set: { step.reps = max(0, $0) }
                        ),
                        range: 0...50
                    )
                }
                Divider().background(MasoColor.borderSoft)
                EditRow(label: "Weight") {
                    // 按用户单位 (kg/lb) 展示+编辑, 存储 canonical kg.
                    NumStepperField(
                        doubleValue: Binding(
                            get: { step.weight ?? 0 },
                            set: { step.weight = max(0, $0) }
                        ).inUnit(WeightUnitProvider.current),
                        range: 0...WeightUnitProvider.current.weightMax,
                        step: WeightUnitProvider.current.weightStep,
                        suffix: WeightUnitProvider.current.label,
                        decimal: true
                    )
                }
            } else {
                EditRow(label: "Duration") {
                    NumStepperField(
                        intValue: Binding(
                            get: { step.duration ?? 0 },
                            set: { step.duration = max(0, $0) }
                        ),
                        range: 5...600,
                        step: 5,
                        suffix: "s"
                    )
                }
            }
            // "Set rest" 行已移除 — 组间 / 跨动作休息一律跟随 Settings → Training Preferences,
            // 不再 per-plan 存 (expandPlan 也忽略 step 里的 rest 字段).
        }
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EditRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MasoColor.text)
            Spacer()
            content()
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .frame(height: 56)
    }
}

// MARK: - ExercisePickerSheet — 选一个动作加进 plan
// 不再 private — PlanPlayer 的"替换动作"也复用同一个 sheet (训练中边练边换).

struct ExercisePickerSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void
    /// J4: true = 点动作行直接确认 (onPick + dismiss), 不先弹详情. 替换动作流程用这个.
    var directPick: Bool = false
    /// 替换流程: 用原动作的"部位"预选 Part chip (movement + equipment 留空), 让用户落在
    /// "换个练同一部位的动作"的状态. nil = 不预选.
    var initialMuscle: MuscleGroup? = nil
    /// 多选模式 (自由训练): 点行切换勾选, 底部 Start CTA 把整组动作通过 onPickMultiple 交回.
    /// 单选 (默认) 保持 tap → 详情 / directPick 路径.
    var multiSelect: Bool = false
    var onPickMultiple: (([Exercise]) -> Void)? = nil
    /// multiSelect 底部 CTA 文案 (例 "Start workout"). nil → "Add".
    var startTitle: String? = nil

    @State private var query: String = ""
    /// 顶层 section 筛选 (nil = 全部). 6 个: chest/back/shoulders/arms/core/legs.
    @State private var muscleFilter: MuscleGroup? = nil
    /// 器械筛选 (nil = 不限). "other" + None 都归到 "other".
    @State private var equipmentFilter: String? = nil
    /// 动作家族筛选 (Press / Row / Fly / Curl / Dip …). nil = 全部.
    @State private var movementFilter: MovementFacet? = nil
    /// 已选动作 id (multiSelect 用; 单选模式忽略).
    @State private var selectedIds: Set<String> = []
    /// tap 列表行 → 弹动作详情. 详情里点 "Add to workout" 才真正 onPick.
    @State private var detailExercise: Exercise? = nil
    /// 小众动作模式 — false (默认): 主库. true: 只看小众库 (从底部入口进).
    @State private var nicheMode: Bool = false
    /// 搜索空结果时点"添加自己的动作" → 弹 CustomExerciseFormSheet (用当前搜索词预填名字).
    @State private var customFormOpen: Bool = false
    /// 当前展开的"变种组" key (= ExerciseGroup.id). 一次只展开一组.
    @State private var expandedGroupKey: String? = nil
    /// initialMuscle 只灌一次, 避免每次重绘覆盖用户后续操作.
    @State private var didSeedInitial: Bool = false

    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    // 注: equipment 列表 + display name 提到 Exercise model (Exercise.knownEquipments /
    // Exercise.equipmentDisplayName), 让 Library Browser / Quick workout / Plans picker 共用一份.

    /// filter 应用 helper — 同一逻辑用在 `filtered` 和各 availability 计算上.
    /// 传 nil 表示该维度不限制. 部位 / 器械 / 文本三者都是 AND 关系.
    private func applyFilters(
        _ arr: [Exercise],
        muscle: MuscleGroup?,
        equipment: String?,
        movement: MovementFacet? = nil,
        text: String?
    ) -> [Exercise] {
        var result = arr
        if let m = muscle {
            // 严格筛选 — 只匹配 primaryMuscles (主练肌), 不含 secondary/协同肌.
            // 例: deadlift primaryMuscles = [lowerBack], 选 "core" 时不会出现 (即使它 secondary 含 core).
            result = result.filter { ex in
                ex.primaryMuscles.contains(where: { $0.section == m })
            }
        }
        if let eq = equipment {
            result = result.filter { ex in
                if eq == "other" {
                    return ex.equipment == "other" || ex.equipment == nil
                }
                return ex.equipment == eq
            }
        }
        if let mv = movement {
            result = result.filter { $0.movementFacet == mv }
        }
        let words = exerciseSearchWords(text ?? "")
        if !words.isEmpty {
            // 多维分词搜索 — 动作家族 / 部位 / 器械 / 变体 任意组合.
            result = result.filter { $0.matchesSearch(words) }
        }
        return result
    }

    /// 当前模式下作为 base 的动作集合 — 主库 (data.userLibrary: 非 niche + adopted niche + custom)
    /// 或小众库 (data.unadoptedNicheExercises: 仍然在 niche stash 里没采纳的).
    /// 两个集合永远无重叠 — 用户采纳一个 niche 后, 它从 unadopted 里消失, 在 userLibrary 里出现.
    private var sourceExercises: [Exercise] {
        nicheMode
            ? data.unadoptedNicheExercises
            : data.userLibrary
    }

    private var filtered: [Exercise] {
        let arr = applyFilters(
            sourceExercises,
            muscle: muscleFilter,
            equipment: equipmentFilter,
            movement: movementFilter,
            text: query
        )
        // 收藏置顶 — 在 filter 之后排序, 让收藏的动作在当前 filter 结果里排最前.
        // 不截断 (曾经 prefix(200)): List 是 lazy 的; 截断会把字母序靠后的动作和自创动作静默切掉.
        return data.sortByFavorites(arr)
    }

    /// filtered 按"基础名"折叠成 group. Picker 列表迭代这个, 而不是 flat filtered.
    /// "Bench Press" + "Bench Press (Machine)" + "Bench Press (Dumbbell)" → 1 个 group.
    /// "Speed Bench Press" 独立成自己的 group (它没括号, base = 自身).
    private var filteredGroups: [ExerciseGroup] {
        ExerciseGrouping.group(filtered)
    }

    /// 是不是处于"主动筛选"状态 (有搜索词 / equipment 选定) — 此时所有 group 强制展开,
    /// 用户能直接看见命中的具体变种, 不用每个 group 自己点 disclosure.
    /// 仅 muscle / sub filter 选了不算 (那两个筛肌肉, 不太关心变种).
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var forceExpandAll: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || equipmentFilter != nil || movementFilter != nil
    }

    // MARK: - filter availability — 两维 (部位 / 器械) 互相 narrow 时, 让用户知道哪些选项当前可选

    /// 当前 muscle/text filter (不算 equipment) 下还有动作的 equipment set.
    /// 用菜单项 "dim disabled" 视觉提示 — 让用户知道选了某 muscle 后哪些 equipment 是空集.
    private var availableEquipments: Set<String> {
        let arr = applyFilters(sourceExercises, muscle: muscleFilter, equipment: nil, movement: movementFilter, text: query)
        var out: Set<String> = []
        for ex in arr {
            // nil + "other" 都映射到 "other" chip
            out.insert(ex.equipment == nil ? "other" : ex.equipment!)
        }
        return out
    }

    /// 当前 equipment/text filter (不算 muscle) 下还有动作的 muscle section set.
    /// 用 primaryMuscles 跟 filter 实际行为对齐 — 不然选项显示"有"但点了 0 结果.
    private var availableMuscles: Set<MuscleGroup> {
        let arr = applyFilters(sourceExercises, muscle: nil, equipment: equipmentFilter, movement: movementFilter, text: query)
        var out: Set<MuscleGroup> = []
        for ex in arr {
            for sec in Self.muscleSections {
                if ex.primaryMuscles.contains(where: { $0.section == sec }) {
                    out.insert(sec)
                }
            }
        }
        return out
    }

    /// 给定肌群 section 下当前 (equipment + text) 还有动作的 movement family (有序) — 肌群子菜单用.
    private func movementsForSection(_ sec: MuscleGroup) -> [MovementFacet] {
        let arr = applyFilters(sourceExercises, muscle: sec, equipment: equipmentFilter, movement: nil, text: query)
        var set = Set<MovementFacet>()
        for ex in arr { if let mf = ex.movementFacet { set.insert(mf) } }
        return MovementFacet.ordered.filter { set.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索 + Muscle / Equipment 筛选 — 用全 app 共享的 ExerciseSearchFilterBar
                // (跟 Exercises 子页同一组件, 钉在列表上方, 调一处两边都变).
                ExerciseSearchFilterBar(
                    query: $query,
                    muscleFilter: $muscleFilter,
                    movementFilter: $movementFilter,
                    equipmentFilter: $equipmentFilter,
                    muscleSections: Self.muscleSections,
                    availableMuscles: availableMuscles,
                    movementsFor: movementsForSection,
                    availableEquipments: availableEquipments
                )
                exerciseList()

                // CTA 默认不显示, 选了动作才出现.
                if multiSelect && !selectedIds.isEmpty {
                    startBar
                }
            }
            .animation(.easeOut(duration: 0.22), value: muscleFilter)
            .animation(.easeOut(duration: 0.22), value: equipmentFilter)
            .animation(.easeOut(duration: 0.22), value: movementFilter)
            .animation(.easeOut(duration: 0.2), value: selectedIds.isEmpty)
            .sheet(item: $detailExercise) { ex in
                // 详情里的 "Add" — multiSelect 加入勾选; 否则走 onPick (加到 plan / 替换).
                ExerciseDetailSheet(exercise: ex, onAdd: {
                    if multiSelect { selectedIds.insert(ex.id) } else { onPick(ex) }
                })
                .presentationDragIndicator(.visible)
            }
            // 搜索空 → "添加自己的动作" 表单 (预填搜索词). 创建后 multiSelect 自动勾选这个新动作.
            .sheet(isPresented: $customFormOpen) {
                CustomExerciseFormSheet(
                    initialName: trimmedQuery,
                    onCreated: { ex in if multiSelect { selectedIds.insert(ex.id) } }
                )
                .presentationDragIndicator(.visible)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // 小众库标题 — 让用户一眼知道"我在哪个库". 主库时不显示标题 (跟之前一致).
            .navigationTitle(nicheMode ? NSLocalizedString("Rare exercises", comment: "") : "")
            .toolbar {
                if multiSelect {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .tint(MasoColor.text)
            // initialMuscle (替换流程) 只灌一次, 之后用户操作不被覆盖.
            .onAppear {
                if !didSeedInitial {
                    didSeedInitial = true
                    if let m = initialMuscle { muscleFilter = m }
                }
            }
        }
    }

    /// 列表末尾的"切换库"入口 — 主库 ↔ 小众库. 模式不同, 文案与图标都不一样, 用户一眼能看出
    /// 现在按下去会去哪边. tap 后切换 nicheMode + 清掉所有筛选 (两个库的肌群 / 器械分布差很多,
    /// 沿用旧筛选很容易跳进去就 "No exercises match" 一片空).
    @ViewBuilder
    private var nicheToggleFooter: some View {
        let nicheCount = data.exercises.filter { $0.isNiche }.count
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                nicheMode.toggle()
                muscleFilter = nil
                equipmentFilter = nil
                movementFilter = nil
                query = ""
            }
            Haptics.tap()
        }) {
            HStack(spacing: 12) {
                Image(systemName: nicheMode ? "arrow.uturn.backward" : "questionmark.diamond")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(MasoColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(nicheMode
                         ? NSLocalizedString("Back to standard library", comment: "")
                         : NSLocalizedString("Browse rare exercises", comment: ""))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Text(nicheMode
                         ? NSLocalizedString("Return to the everyday library", comment: "")
                         : String(format: NSLocalizedString("%d specialized / unusual exercises (foam rollers, battle ropes, machine isolations, etc.)", comment: ""), nicheCount))
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(MasoColor.textFaint)
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 14)
            .background(MasoColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.borderSoft, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
        .buttonStyle(.plain)
    }

    /// multiSelect 底部 Start CTA (自由训练用) — 只在选了动作后才渲染 (caller 控制).
    @ViewBuilder
    private var startBar: some View {
        let picked = selectedIds.compactMap { data.exById[$0] }
        let base = startTitle ?? NSLocalizedString("Start", comment: "")
        Button(action: {
            guard !picked.isEmpty else { return }
            onPickMultiple?(picked)
            dismiss()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 14, weight: .heavy))
                Text(String(format: "%@ (%d)", base, picked.count))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(MasoColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.vertical, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 共用 exercise list

    /// Picker 单行 — canonical 或 variant 共用. 区别:
    ///   - canonical: tap 主体打开 detail; 末尾若有变种, 显 "+N" disclosure 胶囊.
    ///   - variant: 行左侧多一道竖线缩进 + 一个 equipment SF Symbol (machine.fill / dumbbell.fill ...).
    ///             名字省略 base 前缀, 只显括号内的 "(Machine)" / "(Dumbbell, Decline)".
    @ViewBuilder
    private func exercisePickerRow(exercise ex: Exercise, isVariant: Bool, group: ExerciseGroup) -> some View {
        // 共用 GroupedExerciseRow — 跟 Exercise Library 同一份展示/收折逻辑. 这里只注入 picker 行为.
        GroupedExerciseRow(
            exercise: ex,
            isVariant: isVariant,
            group: group,
            isExpanded: expandedGroupKey == group.id,
            showDisclosure: !group.isSingleton && !forceExpandAll,
            showVariantCategoryLabel: false,
            highlighted: multiSelect && selectedIds.contains(ex.id),
            trailing: {
                if multiSelect {
                    Image(systemName: selectedIds.contains(ex.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selectedIds.contains(ex.id) ? MasoColor.accent : MasoColor.textFaint.opacity(0.5))
                }
            },
            onTap: {
                if multiSelect {
                    if selectedIds.contains(ex.id) { selectedIds.remove(ex.id) } else { selectedIds.insert(ex.id) }
                    Haptics.tap()
                } else if directPick {
                    onPick(ex); dismiss()
                } else {
                    detailExercise = ex
                }
            },
            onTapImage: { detailExercise = ex },
            onToggleExpand: {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedGroupKey = (expandedGroupKey == group.id) ? nil : group.id
                }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                data.toggleFavorite(ex.id)
                Haptics.tap()
            } label: {
                Image(systemName: data.isFavorite(ex.id) ? "pin.slash.fill" : "pin.fill")
            }
            .tint(MasoColor.accent)
            .accessibilityLabel(NSLocalizedString(data.isFavorite(ex.id) ? "Unpin" : "Pin to top", comment: ""))
        }
    }


    @ViewBuilder
    private func exerciseList() -> some View {
        // List + 原生 .swipeActions — 替换自制 SwipeableRow.
        // 自制版跟 ScrollView 的 vertical pan 抢手势 → 上下滑动失效.
        List {
            ForEach(filteredGroups) { group in
                // Canonical 行 — 折叠态唯一可见的一行. 跟旧 row 视觉一致 + 末尾多一个 "+N variants"
                // disclosure 胶囊 (仅有变种时). tap 主体 → 弹 detail; tap disclosure → toggle 组.
                exercisePickerRow(
                    exercise: group.canonical,
                    isVariant: false,
                    group: group
                )

                // 展开时渲染变种 — 拆 "Variation"(动作) / "Equipment"(器械) 两段, 各自带小节头;
                // 每个变种作为独立 List row, 可独立 swipe pin, 缩进区分层级.
                if group.variants.isEmpty == false,
                   forceExpandAll || expandedGroupKey == group.id {
                    groupedVariantSections(for: group) { variant in
                        exercisePickerRow(
                            exercise: variant,
                            isVariant: true,
                            group: group
                        )
                    }
                }
            }
            if filtered.isEmpty {
                VStack(spacing: 16) {
                    Text(nicheMode
                         ? NSLocalizedString("No rare exercises match your search", comment: "")
                         : NSLocalizedString("No exercises match your search", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                    // 找不到 → 一键创建自己的动作 (带搜索词预填名字). 主库 / 小众库都给这个入口.
                    Button(action: { customFormOpen = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .heavy))
                            Text(trimmedQuery.isEmpty
                                 ? NSLocalizedString("Add your own exercise", comment: "")
                                 : String(format: NSLocalizedString("Add “%@” as your own", comment: "create custom exercise from search"), trimmedQuery))
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(MasoColor.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(MasoColor.accent.opacity(0.14))
                        .overlay(Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // 列表末尾的"切换库"入口 — 主库结尾邀请进小众库, 小众库结尾邀请回主库.
            // 用 list footer 而不是浮动按钮: 让用户在自然滚到底时遇到这个入口, 没在找的时候不打扰.
            nicheToggleFooter
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 24, leading: MasoMetrics.pagePaddingHorizontal,
                                          bottom: 24, trailing: MasoMetrics.pagePaddingHorizontal))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // P2-10: 任何 filter / 搜索 / 库切换变化 → 收起手风琴, 避免残留某组展开态 (尤其 orphan
        // group 的 id 含 filtered canonical, filter 变了 id 也变, 旧 expandedGroupKey 成孤儿).
        .onChange(of: query) { _, _ in expandedGroupKey = nil }
        .onChange(of: equipmentFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: muscleFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: movementFilter) { _, _ in expandedGroupKey = nil }
        .onChange(of: nicheMode) { _, _ in expandedGroupKey = nil }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

// MARK: - ShareActivityView — UIActivityViewController 桥
//
// 用于"分享计划"功能 — 把 maso:// URL 丢给系统 share sheet, 用户选 Messages/AirDrop/Copy/...
// (跟 SettingsScreen 里的 ShareSheet 是同款桥, 但放这里方便 PlanDetailSheet 直接用,
//  不想跨文件依赖私有类型.)
struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
