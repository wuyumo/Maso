import SwiftUI

struct SettingsScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall: Bool = false
    @State private var showLanguagePicker: Bool = false
    /// 训练偏好独立编辑 sheet (owner 拍板: Settings 不再内嵌 6 行, 只留入口).
    @State private var showTrainingPrefs: Bool = false
    @State private var aiDiagnostics: [AIWorkoutService.Diagnostic] = []
    @State private var aiTesting: Bool = false
    /// 导出产物 — 非 nil 时拉起系统分享面板 (Files / AirDrop / 邮件…)
    @State private var exportItems: [Any]? = nil
    @State private var exportError: String? = nil
    // showMusclePicker / musclesSummaryText 已搬到 TrainingSettingsSection 内部
    /// 跟着 LanguageManager 走 — 切换时强制本页 re-render 显示新语言
    @State private var languageManager = LanguageManager.shared
    /// Exercise library 浏览 sheet
    // (showExerciseLibrary 删了 — 入口已挪到 Plans tab 底部.)

    var body: some View {
        @Bindable var data = data
        content
            .toolbar {
                // iOS 默认风格 — 系统自带"Done"文字按钮 (Settings sheet 关闭)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(MasoColor.text)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var data = data
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Maso Pro 入口 — 永远顶部 (Pro 时显示状态; Free 时是 upgrade banner)
                proSection

                // Profile — onboarding 收集的基础信息. 在 Settings 里查看/修改.
                Section_(title: "Profile") {
                    Row(label: "Gender") {
                        Choice(value: Binding(
                            get: { data.settings.gender ?? .male },
                            set: { data.settings.gender = $0 }
                        ), options: [
                            (.male, "Male"),
                            (.female, "Female"),
                            (.other, "Other"),
                        ])
                    }
                    Divider().background(MasoColor.borderSoft)
                    Row(label: "Age") {
                        IntStepperContent(
                            value: Binding(
                                get: { data.settings.age ?? 25 },
                                set: { data.settings.age = $0 }
                            ),
                            range: 12...90,
                            suffix: "yrs"
                        )
                    }
                    Divider().background(MasoColor.borderSoft)
                    Row(label: "Body weight") {
                        // 按用户单位 (kg/lb) 展示+编辑, 存储 canonical kg.
                        DoubleStepperContent(
                            value: Binding(
                                get: { data.settings.weight ?? 70 },
                                set: { data.settings.weight = $0 }
                            ).inUnit(data.settings.weightUnit),
                            range: data.settings.weightUnit.fromKg(30)...data.settings.weightUnit.fromKg(200),
                            step: data.settings.weightUnit.bodyWeightStep,
                            suffix: data.settings.weightUnit.label
                        )
                    }
                }

                // 训练 — 入口行拉起独立 TrainingPreferencesSheet (跟 Coach 左上角同一张 sheet,
                // 双链路: 右上 Save 只保存 / 底部保存并生成). 不再内嵌 6 行编辑.
                Section_(title: "Training") {
                    Button(action: { showTrainingPrefs = true }) {
                        Row(label: "Training Preferences") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MasoColor.textFaint)
                        }
                        // 整行可点 — Row 中段空白默认不参与 hit-test (实测点中间没反应).
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // 单位
                Section_(title: "Units") {
                    Row(label: "Weight") {
                        Choice(value: $data.settings.weightUnit, options: [(.kg, "kg"), (.lb, "lb")])
                    }
                    Divider().background(MasoColor.borderSoft)
                    Row(label: "Distance") {
                        Choice(value: $data.settings.distanceUnit, options: [(.km, "km"), (.mi, "mi")])
                    }
                    Divider().background(MasoColor.borderSoft)
                    // "周从哪天开始" — 影响 History 日历 / 本周 stats / 任何 weekOfYear 分组.
                    // 默认 Auto = 跟随 iOS 系统 locale (US/JP 周日, 欧洲中国周一).
                    Row(label: "Week starts") {
                        Choice(value: $data.settings.weekStartDay, options: [
                            (.system, "Auto"),
                            (.sunday, "Sun"),
                            (.monday, "Mon"),
                        ])
                    }
                }
                // settings_toggle — 单位类设置改动 (无 PII: key + value 枚举).
                .onChange(of: data.settings.weightUnit) { _, v in
                    Analytics.shared.track("settings_toggle", ["key": .string("weight_unit"), "value": .string(v.rawValue)])
                }
                .onChange(of: data.settings.weekStartDay) { _, v in
                    Analytics.shared.track("settings_toggle", ["key": .string("week_start"), "value": .string(v.rawValue)])
                }

                // 展示偏好 — Routines 卡动作标签的部位前缀: 文字 (默认) vs 迷你肌肉图 (owner 的可切换偏好).
                Section_(title: "Display") {
                    ToggleRow(
                        title: "Muscle charts on exercise tags",
                        desc: "On routine cards, show a mini muscle chart instead of the muscle name in front of each exercise.",
                        isOn: Binding(
                            get: { data.settings.exerciseChipMuscleIcon },
                            set: { on in
                                data.settings.exerciseChipMuscleIcon = on
                                Analytics.shared.track("settings_toggle", [
                                    "key": .string("chip_muscle_icon"), "value": .string(on ? "on" : "off"),
                                ])
                            }
                        )
                    )
                }

                // Apple 健康 — 在 UI 里明确标识 HealthKit 功能 (Apple 2.5.1: 用了 HealthKit 必须可见地告知用户).
                // 开关打开 → 弹系统授权; 之后完成的训练写入 Apple 健康. 默认关 (用户主动开启).
                Section_(title: "Apple Health") {
                    ToggleRow(
                        title: "Save workouts to Apple Health",
                        desc: "Masso saves your completed workouts to Apple Health, so they appear in your Activity rings and the Health app. On Apple Watch, Masso reads heart rate and active energy during a workout.",
                        isOn: Binding(
                            get: { data.settings.healthKitSyncEnabled },
                            set: { on in
                                data.settings.healthKitSyncEnabled = on
                                // 开启时拉起系统 HealthKit 授权对话框; 关闭则只停写新数据 (已写入的不动).
                                if on {
                                    Task {
                                        // settings_toggle (health) — 带授权结果. requestAuthorization throws → 视为未授权.
                                        var granted = false
                                        do { try await HealthKitService.shared.requestAuthorization(); granted = true }
                                        catch { granted = false }
                                        Analytics.shared.track("settings_toggle", [
                                            "key": .string("health"), "value": .string("on"),
                                            "permission_granted": .bool(granted),
                                        ])
                                    }
                                } else {
                                    Analytics.shared.track("settings_toggle", [
                                        "key": .string("health"), "value": .string("off"),
                                    ])
                                }
                            }
                        )
                    )
                }

                // 召回提醒 — 默认开 (opt-out). 开 → 请求通知权限; 被拒则弹回关.
                // 全本地通知, 停训后在恢复窗口轻推一次. 见 WorkoutReminderScheduler.
                Section_(title: "Reminders") {
                    ToggleRow(
                        title: "Workout reminders",
                        desc: "On by default: when you've taken a few days off, Masso sends one gentle reminder once your muscles have recovered. It only ever lives on your device, and you can turn it off anytime.",
                        isOn: Binding(
                            get: { data.settings.workoutRemindersEnabled },
                            set: { on in
                                if on {
                                    data.settings.workoutRemindersEnabled = true   // 乐观置 → toggle 立刻亮
                                    // 用户在设置里主动处理过权限 → 消费掉训练完成时的那次软问, 不重复弹.
                                    data.settings.hasOfferedReminderPrompt = true
                                    Task { @MainActor in
                                        let granted = await WorkoutReminderScheduler.shared.requestAuthorization()
                                        data.settings.workoutRemindersEnabled = granted  // 被拒 → 弹回 off
                                        if granted { data.rescheduleWorkoutReminders() }
                                        // settings_toggle (reminders) + reminder_opt_in — accepted = 最终授权结果.
                                        Analytics.shared.track("settings_toggle", [
                                            "key": .string("reminders"), "value": .string(granted ? "on" : "off"),
                                            "permission_granted": .bool(granted),
                                        ])
                                        Analytics.shared.track("reminder_opt_in", ["accepted": .bool(granted)])
                                    }
                                } else {
                                    data.settings.workoutRemindersEnabled = false
                                    WorkoutReminderScheduler.shared.cancelAll()
                                    Analytics.shared.track("settings_toggle", [
                                        "key": .string("reminders"), "value": .string("off"),
                                    ])
                                    Analytics.shared.track("reminder_opt_in", ["accepted": .bool(false)])
                                }
                            }
                        )
                    )
                }

                // 动作参数全局同步 (R3) — 默认关 (opt-in, P0#4): 默认开会静默压平
                // "重量日/轻量日"这类逐计划周期化配置. 文案按 opt-in 语义写 (先说默认态).
                Section_(title: "Exercise data") {
                    ToggleRow(
                        title: "Sync params across routines",
                        desc: "Off by default: each routine keeps its own sets, reps, weight, and rest, so heavy and light days stay independent. Turn on to apply a change to an exercise everywhere it appears.",
                        isOn: $data.settings.globalExerciseParamSyncEnabled
                    )
                }
                .onChange(of: data.settings.globalExerciseParamSyncEnabled) { _, on in
                    Analytics.shared.track("settings_toggle", [
                        "key": .string("exercise_sync"), "value": .string(on ? "on" : "off"),
                    ])
                }

                // 语言
                Section_(title: "Language") {
                    Button(action: { showLanguagePicker = true }) {
                        Row(label: "App Language") {
                            HStack(spacing: 6) {
                                Text(languageManager.effectiveLanguage.nativeName)
                                    .foregroundStyle(MasoColor.text)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MasoColor.textFaint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // AI 连接自检 — "Couldn't reach the AI coach" 对用户是黑箱, 给他一个能自己按的按钮.
                Section_(title: "AI coach") {
                    aiDiagnosticsRow
                }

                // 数据导出 —— 竞品第二大痛点是"历史数据把人锁死", 而没有一家因可导出被夸过.
                Section_(title: "Your data") {
                    Button(action: runExport) {
                        Row(label: "Export my data") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("A JSON backup of everything plus a CSV of every set you've logged — open it in Numbers, Excel, or any other app. Your data is yours; you can take it and go.")
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MasoMetrics.cardPadding)
                        .padding(.bottom, 12)

                    Divider().background(MasoColor.borderSoft)

                    // ⚠️ 用了分析就**必须**在界面里能看见、能关 —— 1.0(5) 那次被 Apple 按
                    //    Guideline 2.5.1 拒过一模一样的问题 (用了 HealthKit 但 UI 里没有任何体现).
                    //    取反绑定: 存的是 optOut, 展示的是"参与", 开=发, 关=一条都不发.
                    ToggleRow(
                        title: "Share anonymous usage data",
                        desc: "Sends anonymous counts like \"a routine was generated\" or \"onboarding finished\" so I can see which parts of the app work. Never your workouts, weights, notes, or anything you typed. No account, no ads, no third-party ad networks. Turn it off and nothing is sent at all.",
                        isOn: Binding(
                            get: { !data.settings.analyticsOptOut },
                            set: { data.settings.analyticsOptOut = !$0 }
                        )
                    )
                }

                // Exercise library 入口已挪到 Plans tab 底部 — 那是用户实际"用"动作的地方,
                // 跟 plan 编辑/选动作动线更顺. Settings 这里不再展示, 也不再 import 整张
                // ExerciseLibraryBrowser sheet.

                Text("Plans and workout records stay on your device.")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textFaint)
                    .padding(.horizontal, 6)
                    // 紧贴上面 section (顶层 VStack spacing 24, 这里抵消 16 → 实际间距 8pt)
                    .padding(.top, -16)

                // 法律 + 健康合规链接. 医疗免责正文 (Apple 1.4.1 必需) 不再首页平铺,
                // 收进二级页 (HealthSafetyDetail), 入口放 About 里 — 仍可访问 = 合规, 首页更清爽.
                Section_(title: "About") {
                    Link(destination: PaywallScreen.privacyURL) {
                        Row(label: "Privacy Policy") {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                    Link(destination: PaywallScreen.termsURL) {
                        Row(label: "Terms of Service") {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                    // 健康与安全 — push 进二级页看医疗免责正文.
                    NavigationLink(destination: HealthSafetyDetail()) {
                        Row(label: "Health & Safety") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MasoColor.textFaint)
                        }
                    }
                    .buttonStyle(.plain)
                    Row(label: "Version") {
                        Text(appVersionLabel)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(MasoColor.textDim)
                    }
                    // 部分动作缩略图来自 Pexels (Pexels License, 免费可商用) — 鸣谢.
                    Row(label: "Exercise photos") {
                        Text("Pexels")
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }

                #if DEBUG
                // ⚠️ 调试专用 — 整段被 #if DEBUG 包裹, Xcode archive 出的 Release/上架包**不编译**,
                // 无需上线前手动删. install_iphone.sh 装的是 Debug 包, 故真机上能看到并使用.
                Section_(title: "Debug") {
                    ToggleRow(
                        title: "Unlock Pro (debug)",
                        desc: "Force-unlocks all Pro features for testing. Debug builds only — this toggle never ships to the App Store.",
                        isOn: $data.settings.debugProUnlock
                    )
                    Divider().background(MasoColor.borderSoft)
                    ToggleRow(
                        title: "Force US storefront (debug)",
                        desc: "Pretend the App Store region is the US so the paywall + activation flow show on a non-US Apple ID. Turn OFF 'Unlock Pro' above to actually see the paywall. Debug builds only.",
                        isOn: Binding(
                            get: { data.settings.debugForceUSStorefront },
                            set: { data.settings.debugForceUSStorefront = $0; data.save()
                                   Task { await data.refreshStorefrontCountry() } }
                        )
                    )
                    Divider().background(MasoColor.borderSoft)
                    // 本地分析事件查看器 — 看 track() 真的在触发 (Phase 0 NoOpSink, 事件只在本机).
                    NavigationLink(destination: AnalyticsInspectorScreen()) {
                        HStack {
                            Text("Analytics events")
                                .font(.system(size: 15))
                                .foregroundStyle(MasoColor.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                #endif

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 16)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallScreen()
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(manager: languageManager)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTrainingPrefs) {
            // 保存并生成 → 走 Coach 会话生成管线 (结果落 Coach tab 对话流, 跟 Coach 入口一致).
            TrainingPreferencesSheet(onConfirm: { data.startCoachGenerate(surface: "settings_prefs") })
        }
        // 导出 —— items 非 nil 就拉起系统面板; 关掉时清空, 下次导出重新生成带新时间戳的文件.
        .sheet(isPresented: Binding(get: { exportItems != nil },
                                    set: { if !$0 { exportItems = nil } })) {
            if let items = exportItems { ShareSheet(activityItems: items) }
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil },
                                                     set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        // (Exercise library sheet 已搬到 PlansScreen 底部入口, 这里不再附加.)
        // (showMusclePicker sheet 已搬到 TrainingSettingsSection 内部)
    }

    /// App 版本号 — "1.0 (1)" 格式. 从 Bundle 读 CFBundleShortVersionString + CFBundleVersion.
    // 主/备两个 endpoint 各发一次真请求, 把 "Couldn't reach the AI coach" 换成具体错误码.
    // 结论行故意分主/备两条: 只有"两条都红"才是用户网络的问题, "主红备绿"= AI 其实能用.
    @ViewBuilder
    private var aiDiagnosticsRow: some View {
        Button(action: runAIDiagnostics) {
            Row(label: "Test connection") {
                if aiTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MasoColor.textFaint)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(aiTesting)

        if !aiDiagnostics.isEmpty {
            Divider().background(MasoColor.borderSoft)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(aiDiagnostics) { d in
                    HStack(spacing: 8) {
                        Image(systemName: d.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(d.ok ? MasoColor.accent : MasoColor.textDim)
                        Text(LocalizedStringKey(d.role))
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Text(d.detail)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(MasoColor.textDim)
                    }
                    Text(d.host)
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 21)
                }
                Text(LocalizedStringKey(aiDiagnosticsVerdict))
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 14)
        }
    }

    private var aiDiagnosticsVerdict: String {
        if aiDiagnostics.contains(where: \.ok) {
            return "The AI coach is reachable from this device."
        }
        return "The AI coach can't be reached on this network. Try mobile data instead of Wi-Fi (or the other way round); if you use a VPN or proxy, switch it on or off and test again."
    }

    /// 生成 JSON + CSV 并拉起系统分享面板. 失败必须**说出来** —— 备份功能静默失败最伤信任.
    private func runExport() {
        do {
            let b = try DataExport.makeBundle(from: data)
            exportItems = [b.jsonURL, b.csvURL]
            Analytics.shared.track("data_export", [
                "sets": .int(data.sets.count), "plans": .int(data.plans.count),
            ])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func runAIDiagnostics() {
        aiTesting = true
        Task {
            let result = await AIWorkoutService.diagnose()
            await MainActor.run {
                aiDiagnostics = result
                aiTesting = false
            }
            Analytics.shared.track("ai_diagnostics_run", [
                "reachable": .string(result.contains(where: \.ok) ? "yes" : "no"),
            ])
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - Maso Pro banner / status row

    @ViewBuilder
    private var proSection: some View {
        if MasoFlags.externalPaywallEnabled
            && !data.settings.showProUpsell
            && !(data.settings.polarProActive && data.settings.appStoreCountry == MasoFlags.usStorefrontCode) {
            EmptyView()   // 非美区 (免费全解锁) → 不显示任何 Pro/购买 区.
        } else if MasoFlags.externalPaywallEnabled
            && data.settings.polarProActive
            && data.settings.appStoreCountry == MasoFlags.usStorefrontCode {
            polarActiveCard   // 美区已付费.
        } else if !MasoFlags.externalPaywallEnabled && !MasoFlags.iapEnabled {
            EmptyView()   // 旧 StoreKit 免费版路径.
        } else if let sub = data.settings.proSubscription {
            // Pro 用户 — 显示订阅状态卡 (轻量, 不抢戏)
            HStack(spacing: 12) {
                MasoMarkIcon(color: MasoColor.accent)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Maso Pro")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                        Text(sub.tier.label.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(MasoColor.accent)
                            .clipShape(Capsule())
                    }
                    Text(sub.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                }
                Spacer()
            }
            .padding(MasoMetrics.cardPadding)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5)
            )
        } else {
            // Free 用户 — Upgrade banner, 整张可点
            Button(action: { showPaywall = true }) {
                HStack(spacing: 12) {
                    MasoMarkIcon(color: MasoColor.accent)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try Maso Pro")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(MasoColor.text)
                        Text("Unlimited plans, full history, custom moves, and more.")
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textDim)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MasoColor.accent)
                }
                .padding(MasoMetrics.cardPadding)
                .background(
                    LinearGradient(
                        colors: [MasoColor.accent.opacity(0.18), MasoColor.surface],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                        .stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// 美区已付费 (Polar) 的 Pro 状态卡 — 无 tier (外部付费不存档位), 提示网页管理.
    private var polarActiveCard: some View {
        HStack(spacing: 12) {
            MasoMarkIcon(color: MasoColor.accent)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Maso Pro")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(MasoColor.accent)
                        .clipShape(Capsule())
                }
                Text("Thanks for supporting Masso. Manage or cancel on the Polar page.")
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textDim)
            }
            Spacer()
        }
        .padding(MasoMetrics.cardPadding)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                .stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5)
        )
    }
}

private extension SubscriptionTier {
    var label: String {
        switch self {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }
}

private extension ProSubscription {
    var statusLine: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US")
        fmt.dateFormat = "MMM d, yyyy"
        if let renews = renewsAt {
            return "Renews \(fmt.string(from: renews))"
        }
        return "Active forever — thanks for buying."
    }
}

// MARK: - Helpers (跟 web 端 Section / Row / Toggle 视觉对齐)
//
// 这一段 helper 不再是 private — TrainingSettingsSection 也用它们,
// 让 PlanRationaleCard 的"快捷设置 sheet"和 Settings 这边视觉/行为完全一致.
// 同步改 helper 就同时影响两处, 单一来源.

struct Section_<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString(title, comment: "").uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(MasoColor.textDim)
                .padding(.horizontal, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct Row<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 8) {
            // Text(stringVar) 默认走 String overload, 不查 Localizable.strings.
            // 显式包 LocalizedStringKey 让 SwiftUI 把它当 key 查表 → 跟着系统语言走.
            Text(LocalizedStringKey(label))
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Spacer()
            content()
        }
        .padding(.horizontal, MasoMetrics.cardPadding)
        .frame(height: 56)
    }
}

// MARK: - Stepper rows (iOS native `Stepper` + 可编辑数字)
//
// 布局: [可编辑数字] [单位] [系统胶囊 - / + 连体 Stepper]
//   - 数字区是 TextField, 点击拉起 numberPad / decimalPad, 用户可全删重输
//   - 加减按钮用 iOS 原生 Stepper, 视觉 / 长按连按跟系统 Settings 一致
//   - 失焦 / Done / submit 时 commit: parse → clamp 到 range → 写回 Binding
//   - 空串 / 解析失败 → 恢复成上一次的合法值 (不会出现 0 或空白脏值)
//
// 数字宽度固定 70pt + 右对齐 — 让 5 行 stepper 数字竖向对齐, 不会因为 "3" / "100"
// 字符数差异让 Stepper 横向跳动.

struct IntStepperContent: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String? = nil

    // 全 app 统一步进控件 — 圆形 −/+ + 可输入数字框, 跟训练中"动作详情页"同款 (NumStepperField).
    var body: some View {
        NumStepperField(intValue: $value, range: range, step: step,
                        suffix: suffix.map { NSLocalizedString($0, comment: "") })
    }
}

private struct DoubleStepperContent: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix: String? = nil

    var body: some View {
        NumStepperField(doubleValue: $value, range: range, step: step,
                        suffix: suffix.map { NSLocalizedString($0, comment: "") }, decimal: true)
    }
}

private struct Choice<Value: Hashable>: View {
    @Binding var value: Value
    let options: [(Value, String)]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { (val, label) in
                Button(action: { value = val }) {
                    // 同 Row: 走 LocalizedStringKey 让 "kg" / "lb" / "km" / "mi" 这类
                    // 单位 label 在阿拉伯文 / 俄文等环境下能查到对应翻译
                    Text(LocalizedStringKey(label))
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)   // 段内 label 恒单行 (防 "Mon" 被挤成两行)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(value == val ? MasoColor.accent : Color.clear)
                        .foregroundStyle(value == val ? .black : MasoColor.textDim)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    let desc: String?
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    // title + desc 都走 LocalizedStringKey
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    if let desc {
                        Text(LocalizedStringKey(desc))
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textDim)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $isOn).labelsHidden().tint(MasoColor.accent)
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

/// UIActivityViewController 的 SwiftUI 桥 — 给 Export 文件用系统 share sheet 选目的地
/// (Files app / AirDrop / 邮件 / Messages 等)
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - HealthSafetyDetail — 医疗免责二级页 (Apple 1.4.1 必需正文, 从 Settings 首页收进来)
private struct HealthSafetyDetail: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Maso is for informational and motivational purposes only — not medical advice. Consult a physician before starting any new exercise program, especially if you have a medical condition, are pregnant, or have not exercised recently. Stop immediately and seek help if you feel pain, dizziness, or shortness of breath.")
                    .font(.system(size: 14))
                    .foregroundStyle(MasoColor.textDim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 16)
        }
        .background(MasoColor.background.ignoresSafeArea())
        .navigationTitle("Health & Safety")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MasoColor.text)
    }
}
