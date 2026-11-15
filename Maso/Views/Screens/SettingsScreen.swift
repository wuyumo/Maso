import SwiftUI
#if DEBUG
import StoreKit
#endif

/// One neutral trailing action indicator for settings actions and external links.
private struct SettingsActionIcon: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.body)
            .foregroundStyle(.secondary)
    }
}

struct SettingsScreen: View {
    let onStartWorkout: (Plan) -> Void
    var isPushed = false
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationPermissionDenied = false
    @State private var workoutImportFailed = false
    @State private var libraryAddRequested = false
    @State private var showPaywall: Bool = false
    @State private var showReferralCode = false
    @State private var showLanguagePicker: Bool = false
    /// 训练偏好独立编辑 sheet (owner 拍板: Settings 不再内嵌 6 行, 只留入口).
    @State private var showTrainingPrefs: Bool = false
    @State private var updateRoutinesAfterPreferences = false
    @State private var showFeedback: Bool = false
    #if DEBUG
    @State private var showOnboardingPreview = false
    @State private var sandboxRefundMessage = ""
    @State private var showSandboxRefundMessage = false
    #endif
    @State private var feedbackSuccessToastVisible = false
    @State private var testingAIConnection = false
    @State private var aiDiagnostics: [AIWorkoutService.Diagnostic] = []
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
            .alert("Unable to import workouts. Try again.", isPresented: $workoutImportFailed) {
                Button("OK", role: .cancel) {}
            }
            .alert("Notifications are off", isPresented: $notificationPermissionDenied) {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                // iOS 默认风格 — 系统自带"Done"文字按钮 (Settings sheet 关闭)
                if !isPushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.tint(MasoColor.text)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var data = data
        Form {
                Section("Membership") { proSection }

                Section {
                    Button { showTrainingPrefs = true } label: {
                        LabeledContent {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        } label: {
                            Text("Training Preferences")
                        }
                    }.buttonStyle(.plain).foregroundStyle(MasoColor.text)
                    Toggle("Hide rare variants", isOn: Binding(
                        get: { data.settings.hidesRareVariants },
                        set: { data.settings.hideRareVariants = $0; data.save() }
                    ))
                    .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    .accessibilityIdentifier("settings.hideRareVariants")
                    Toggle(
                         "Sync params across routines",
                        isOn: $data.settings.globalExerciseParamSyncEnabled
                    ).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Toggle("Show recovery in workout calendar", isOn: Binding(
                        get: { data.settings.showCalendarRecovery ?? false },
                        set: { data.settings.showCalendarRecovery = $0; data.save() }
                    )).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                } header: {
                    Text("Training")
                } footer: {
                    Text("After a recorded workout, the calendar shows a shorter green bar for two rest days. This is a time-based guide, not a muscle recovery measurement.")
                }

                .onChange(of: data.settings.globalExerciseParamSyncEnabled) { _, on in
                    Analytics.shared.track("settings_toggle", [
                        "key": .string("exercise_sync"), "value": .string(on ? "on" : "off"),
                    ])
                }

                Section("Workout resources") {
                    NavigationLink {
                        ExerciseLibraryBrowser(embedded: true, addRequested: $libraryAddRequested)
                            .navigationTitle("Exercises")
                            .navigationBarTitleDisplayMode(.large)
                            .toolbarRole(.navigationStack)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button { libraryAddRequested = true } label: { Image(systemName: "plus") }
                                        .tint(MasoColor.text).accessibilityLabel("Add exercise")
                                }
                            }
                    } label: {
                        Text("Exercises").foregroundStyle(MasoColor.text)
                    }
                    NavigationLink {
                        ClassicsScreen(onStart: onStartWorkout)
                    } label: {
                        Text("Classic Routines").foregroundStyle(MasoColor.text)
                    }
                }
                // Profile — onboarding 收集的基础信息. 在 Settings 里查看/修改.
                Section("Profile") {
                    NavigationLink("Body measurements") { BodyProfileScreen() }
                        .accessibilityIdentifier("settings.health-body")
                    LabeledContent("Gender") {
                        NativeSettingsChoice(value: Binding(
                            get: { data.settings.gender ?? .male },
                            set: { data.settings.gender = $0 }
                        ), options: [
                            (.male, "Male"),
                            (.female, "Female"),
                            (.other, "Other"),
                        ])
                    }
                    LabeledContent("Age") {
                        NativeSettingsIntStepper(
                            value: Binding(
                                get: { data.settings.age ?? 25 },
                                set: { data.settings.age = $0 }
                            ),
                            range: 12...90,
                            suffix: "yrs"
                        )
                    }
                }

                Section("Health & Features") {
                    Toggle(
                         "Save workouts to Apple Health",
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
                    ).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Toggle("Import workouts from Apple Health", isOn: Binding(
                        get: { data.settings.externalWorkoutImportEnabled ?? false },
                        set: { enabled in
                            data.settings.externalWorkoutImportEnabled = enabled
                            data.save()
                            if enabled {
                                Task {
                                    do {
                                        try await HealthKitService.shared.connectWorkouts()
                                        try await data.refreshExternalWorkouts()
                                    } catch { workoutImportFailed = true }
                                }
                            }
                        }
                    )).toggleStyle(.switch).tint(MasoColor.toggleAccent).disabled(data.importingExternalWorkouts)
                    if data.settings.externalWorkoutImportEnabled == true,
                       data.recordedExternalWorkouts().isEmpty, !data.importingExternalWorkouts {
                        Text("No imported workouts yet. Check Workout access in Apple Health.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Toggle("Diet", isOn: Binding(get: { data.settings.dietEnabled ?? true }, set: { data.settings.dietEnabled = $0; data.save() })).toggleStyle(.switch).tint(MasoColor.dietAccent)
                    Toggle("Sleep", isOn: Binding(get: { data.settings.sleepEnabled ?? true }, set: { data.settings.sleepEnabled = $0; data.save() })).toggleStyle(.switch).tint(MasoColor.sleepAccent)

                }

                Section("Reminders") {
                    Toggle(
                         "Workout reminders",
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
                                        notificationPermissionDenied = !granted
                                        data.save()
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
                    ).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Toggle("Meal reminders", isOn: Binding(
                        get: { data.settings.mealRemindersEnabled ?? false },
                        set: { enabled in
                            if enabled {
                                Task { @MainActor in
                                    let granted = await WorkoutReminderScheduler.shared.requestAuthorization()
                                    data.settings.mealRemindersEnabled = granted
                                    notificationPermissionDenied = !granted
                                    data.save()
                                }
                            } else {
                                data.settings.mealRemindersEnabled = false
                                data.save()
                            }
                        }
                    )).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Toggle("Bedtime reminder", isOn: Binding(
                        get: { data.settings.sleepPreferences?.bedtimeReminderEnabled ?? false },
                        set: { enabled in
                            if enabled {
                                Task { @MainActor in
                                    let granted = await WorkoutReminderScheduler.shared.requestAuthorization()
                                    var preferences = data.settings.sleepPreferences ?? SleepPreferences()
                                    preferences.bedtimeReminderEnabled = granted
                                    data.settings.sleepPreferences = preferences
                                    notificationPermissionDenied = !granted
                                    data.save()
                                }
                            } else {
                                var preferences = data.settings.sleepPreferences ?? SleepPreferences()
                                preferences.bedtimeReminderEnabled = false
                                data.settings.sleepPreferences = preferences
                                data.save()
                            }
                        }
                    )).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                }

                Section("App Preferences") {
                    Button(action: { showLanguagePicker = true }) {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(languageManager.effectiveLanguage.nativeName)
                                    .foregroundStyle(MasoColor.text)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        } label: {
                            Label("App Language", systemImage: "globe")
                                .foregroundStyle(MasoColor.text)
                        }
                    }
                    .buttonStyle(.plain)

                    LabeledContent("Weight") {
                        NativeSettingsChoice(value: Binding(
                            get: { data.settings.weightUnit },
                            set: { data.selectWeightUnit($0) }
                        ), options: [(.kg, "kg"), (.lb, "lb")])
                    }
                    LabeledContent("Distance") {
                        NativeSettingsChoice(value: $data.settings.distanceUnit, options: [(.km, "km"), (.mi, "mi")])
                    }
                    // "周从哪天开始" — 影响 History 日历 / 本周 stats / 任何 weekOfYear 分组.
                    // 默认 Auto = 跟随 iOS 系统 locale (US/JP 周日, 欧洲中国周一).
                    LabeledContent("Week starts") {
                        NativeSettingsChoice(value: $data.settings.weekStartDay, options: [
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

                Section("Privacy & Data") {
                    Toggle("AI data sharing", isOn: Binding(
                        get: { AIDataConsent.shared.isGranted },
                        set: { allowed in
                            if allowed { Task { try? await AIDataConsent.shared.requirePermission() } }
                            else { AIDataConsent.shared.revoke() }
                        }))
                        .toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Button(action: runExport) {
                        LabeledContent("Export my data") {
                            SettingsActionIcon()
                        }
                    }
                    .buttonStyle(.plain)

                    // ⚠️ 用了分析就**必须**在界面里能看见、能关 —— 1.0(5) 那次被 Apple 按
                    //    Guideline 2.5.1 拒过一模一样的问题 (用了 HealthKit 但 UI 里没有任何体现).
                    //    取反绑定: 存的是 optOut, 展示的是"参与", 开=发, 关=一条都不发.
                    Toggle(
                         "Share anonymous usage data",
                        isOn: Binding(
                            get: { Analytics.shared.sharingConsentGranted && !data.settings.analyticsOptOut },
                            set: { enabled in
                                Analytics.shared.setSharingEnabled(enabled)
                                data.settings.analyticsOptOut = !enabled
                                if !enabled { Analytics.shared.clearPendingEvents() }
                            }
                        )
                    ).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Link("Privacy Policy", destination: PaywallScreen.privacyURL)
                }

                Section("Support") {
                    #if DEBUG
                    Button("Preview onboarding") { showOnboardingPreview = true }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("settings.onboarding.preview")
                    #endif
                    Button {
                        testingAIConnection = true
                        aiDiagnostics = []
                        Task {
                            aiDiagnostics = await AIWorkoutService.diagnose()
                            testingAIConnection = false
                        }
                    } label: {
                        HStack {
                            Text("Test connection")
                            Spacer()
                            if testingAIConnection { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(testingAIConnection)
                    .accessibilityIdentifier("settings.ai.test")
                    ForEach(aiDiagnostics) { diagnostic in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(diagnostic.role)).font(.subheadline)
                            Text(diagnostic.host).font(.caption).foregroundStyle(.secondary)
                            Text(diagnostic.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.ai.\(diagnostic.role)")
                    }
                    Button { showFeedback = true } label: {
                        LabeledContent("Report a bug") {
                            SettingsActionIcon()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("About") {
                    Link(destination: PaywallScreen.termsURL) {
                        LabeledContent("Terms of Service") {
                            SettingsActionIcon()
                        }
                    }
                    .buttonStyle(.plain)
                    // 健康与安全 — push 进二级页看医疗免责正文.
                    NavigationLink(destination: HealthSafetyDetail()) { Text("Health & Safety") }
                    .buttonStyle(.plain)
                    NavigationLink(destination: CreditsScreen()) { Text("Credits") }
                    .buttonStyle(.plain)
                    LabeledContent("Version") {
                        Text(appVersionLabel)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                #if DEBUG
                // ⚠️ 调试专用 — 整段被 #if DEBUG 包裹, Xcode archive 出的 Release/上架包**不编译**,
                // 无需上线前手动删. install_iphone.sh 装的是 Debug 包, 故真机上能看到并使用.
                Section("Debug") {
                    Button("Inspect sandbox transactions") {
                        Task {
                            var rows: [(Date, String)] = []
                            for await result in Transaction.all {
                                guard case .verified(let transaction) = result,
                                      transaction.environment == .sandbox,
                                      SubscriptionManager.subscriptionProductIDs.contains(transaction.productID) else { continue }
                                rows.append((transaction.purchaseDate, "Product: \(transaction.productID)\nID: \(transaction.id)\nPurchased: \(transaction.purchaseDate)\nExpires: \(transaction.expirationDate?.description ?? "none")\nRevoked: \(transaction.revocationDate?.description ?? "no")"))
                            }
                            var active: [String] = []
                            for await result in Transaction.currentEntitlements {
                                if case .verified(let transaction) = result, transaction.environment == .sandbox {
                                    active.append("\(transaction.productID): \(transaction.id)")
                                }
                            }
                            let sorted = rows.sorted { $0.0 > $1.0 }
                            let revoked = sorted.filter { !$0.1.hasSuffix("Revoked: no") }
                            sandboxRefundMessage = "Current: \(active.joined(separator: ", "))\n\nRevoked:\n" + (revoked.first?.1 ?? "none") + "\n\nLatest:\n" + sorted.prefix(2).map(\.1).joined(separator: "\n\n")
                            showSandboxRefundMessage = true
                        }
                    }
                    Button("Request sandbox refund") {
                        Task {
                            do {
                                var candidates: [StoreKit.Transaction] = []
                                for await result in Transaction.currentEntitlements {
                                    if case .verified(let transaction) = result,
                                       transaction.environment == .sandbox,
                                       transaction.revocationDate == nil,
                                       SubscriptionManager.subscriptionProductIDs.contains(transaction.productID) {
                                        candidates.append(transaction)
                                    }
                                }
                                guard let transaction = candidates.max(by: { $0.purchaseDate < $1.purchaseDate }),
                                      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else {
                                    sandboxRefundMessage = "No verified active sandbox subscription or active window."
                                    showSandboxRefundMessage = true
                                    return
                                }
                                let status = try await transaction.beginRefundRequest(in: scene)
                                sandboxRefundMessage = status == .success ? "Refund request submitted for \(transaction.productID), ID: \(transaction.id). Check the updated entitlement." : "Refund request cancelled."
                            } catch {
                                sandboxRefundMessage = error.localizedDescription
                            }
                            showSandboxRefundMessage = true
                        }
                    }
                    Toggle(
                         "Unlock Pro (debug)",
                        isOn: Binding(
                            get: { data.settings.debugProUnlock },
                            set: { data.settings.debugProUnlock = $0; data.save() }
                        )
                    ).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    Toggle(
                         "Force US storefront (debug)",
                        isOn: Binding(
                            get: { data.settings.debugForceUSStorefront },
                            set: { data.settings.debugForceUSStorefront = $0; data.save()
                                   Task { await data.refreshStorefrontCountry() } }
                        )
                    ).toggleStyle(.switch).tint(MasoColor.toggleAccent)
                    // 本地分析事件查看器 — 看 track() 真的在触发 (Phase 0 NoOpSink, 事件只在本机).
                    NavigationLink(destination: AnalyticsInspectorScreen()) { Text("Analytics events") }
                    .buttonStyle(.plain)
                }
                #endif

        }
        // Keep native dropdowns / pickers neutral; tint workout toggles individually above.
        .tint(MasoColor.text)
        .navigationTitle("Settings")
        .toolbarRole(.navigationStack)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if feedbackSuccessToastVisible {
                MasoToast(message: "Report sent")
                    .padding(.bottom, MasoMetrics.pageBottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if DEBUG
        .alert("Sandbox refund", isPresented: $showSandboxRefundMessage) {
            Button("OK", role: .cancel) { }
        } message: { Text(sandboxRefundMessage) }
        .sheet(isPresented: $showOnboardingPreview) {
            OnboardingScreen(previewOnly: true) { _ in showOnboardingPreview = false }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        #endif
        .sheet(isPresented: $showPaywall) {
            PaywallScreen()
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReferralCode) { ReferralCodeSheet() }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(manager: languageManager)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTrainingPrefs, onDismiss: {
            guard updateRoutinesAfterPreferences else { return }
            updateRoutinesAfterPreferences = false
            AppRouter.shared.pendingTrainingPreferencesUpdate = true
            AppRouter.shared.requestedDestination = .coach
        }) {
            TrainingPreferencesSheet(onConfirm: { updateRoutinesAfterPreferences = true })
                .tint(MasoColor.text)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(onSuccess: showFeedbackSuccessToast)
                .presentationDragIndicator(.visible)
        }
        // 导出 —— items 非 nil 就拉起系统面板; 关掉时清空, 下次导出重新生成带新时间戳的文件.
        .sheet(isPresented: Binding(get: { exportItems != nil },
                                    set: { if !$0 { exportItems = nil } })) {
            if let items = exportItems { ActivityViewController(activityItems: items) }
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

    private func showFeedbackSuccessToast() {
        withAnimation(.easeOut(duration: 0.2)) { feedbackSuccessToastVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeIn(duration: 0.2)) { feedbackSuccessToastVisible = false }
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - Masso Pro banner / status row

    @ViewBuilder
    private var proSection: some View {
        if let subscription = data.settings.proSubscription, data.settings.isPro {
            LabeledContent("Masso Pro") {
                Text(LocalizedStringKey(subscription.tier.label)).foregroundStyle(.secondary)
            }
            Button("Manage Subscription") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
            }
        } else if data.settings.hasActiveLegacyPro {
            polarActiveCard
        } else if data.settings.showProUpsell {
            ProBanner(squareBottom: MasoFlags.iapEnabled) { showPaywall = true }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        if MasoFlags.iapEnabled {
            Button("Restore Purchases") { Task { await subscriptions.restore() } }
            Button("Referral code") { showReferralCode = true }
                .accessibilityIdentifier("settings.referral")
        }
    }

    private var polarActiveCard: some View {
        LabeledContent("Masso Pro") {
            Text("ACTIVE").foregroundStyle(.secondary)
        }
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
    var desc: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(alignment: .center, spacing: 12) {
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
                Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(MasoColor.toggleAccent)
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

/// UIActivityViewController 的 SwiftUI 桥 — 给 Export 文件用系统 share sheet 选目的地
/// (Files app / AirDrop / 邮件 / Messages 等)


// MARK: - HealthSafetyDetail — 医疗免责二级页 (Apple 1.4.1 必需正文, 从 Settings 首页收进来)
private struct HealthSafetyDetail: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Masso is for informational and motivational purposes only — not medical advice. Consult a physician before starting any new exercise program, especially if you have a medical condition, are pregnant, or have not exercised recently. Stop immediately and seek help if you feel pain, dizziness, or shortness of breath.")
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

private struct NativeSettingsChoice<Value: Hashable>: View {
    @Binding var value: Value
    let options: [(Value, String)]
    var body: some View {
        Picker("", selection: $value) {
            ForEach(options, id: \.0) { option in
                Text(LocalizedStringKey(option.1)).tag(option.0)
            }
        }
        .labelsHidden()
    }
}

private struct NativeSettingsIntStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""
    var body: some View {
        Stepper(value: $value, in: range) {
            Text("\(value) \(suffix)").monospacedDigit()
        }
    }
}

private struct NativeSettingsDoubleStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(suffix)")
                .monospacedDigit()
        }
    }
}
