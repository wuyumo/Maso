import SwiftUI

struct SettingsScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall: Bool = false
    @State private var showLanguagePicker: Bool = false
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

                // 训练 — 跟 Profile (个人信息) 一起放上面, 都属于"用户偏好".
                // 6 行内容抽到 TrainingSettingsSection (共享给 PlanRationaleCard 的快捷 sheet).
                Section_(title: "Training Preferences") {
                    TrainingSettingsSection()
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

                // 召回提醒 — 默认关 (opt-in, 符合"不打扰"品牌). 开 → 请求通知权限; 被拒则弹回关.
                // 全本地通知, 停训后在恢复窗口轻推一次. 见 WorkoutReminderScheduler.
                Section_(title: "Reminders") {
                    ToggleRow(
                        title: "Workout reminders",
                        desc: "When you've taken a few days off, Masso sends a gentle reminder once your muscles have had time to recover. Off by default, and the reminder never leaves your device.",
                        isOn: Binding(
                            get: { data.settings.workoutRemindersEnabled },
                            set: { on in
                                if on {
                                    data.settings.workoutRemindersEnabled = true   // 乐观置 → toggle 立刻亮
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

                // 动作参数全局同步 (R3) — 默认开, 用户可关.
                Section_(title: "Exercise data") {
                    ToggleRow(
                        title: "Sync params across routines",
                        desc: "When on, changing an exercise's sets, reps, weight, or rest in one routine (or during a workout) updates it everywhere that exercise appears. When off, each routine keeps its own params, and a new routine starts an exercise from your most recent values.",
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
        // (Exercise library sheet 已搬到 PlansScreen 底部入口, 这里不再附加.)
        // (showMusclePicker sheet 已搬到 TrainingSettingsSection 内部)
    }

    /// App 版本号 — "1.0 (1)" 格式. 从 Bundle 读 CFBundleShortVersionString + CFBundleVersion.
    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - Maso Pro banner / status row

    @ViewBuilder
    private var proSection: some View {
        if !MasoFlags.iapEnabled {
            EmptyView()   // 免费版上线: 整段 Pro 区 (升级 banner / 订阅状态) 都不渲染, 不露内购入口.
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
