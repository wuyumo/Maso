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
    @State private var showExerciseLibrary: Bool = false

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
                        DoubleStepperContent(
                            value: Binding(
                                get: { data.settings.weight ?? 70 },
                                set: { data.settings.weight = $0 }
                            ),
                            range: 30...200,
                            step: 0.5,
                            suffix: "kg"
                        )
                    }
                }

                // 训练 — 跟 Profile (个人信息) 一起放上面, 都属于"用户偏好".
                // 6 行内容抽到 TrainingSettingsSection (共享给 PlanRationaleCard 的快捷 sheet).
                Section_(title: "Training") {
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

                Section_(title: "Data") {
                    // Plans 入口删除 — Plans tab 已经是底部 tab bar 的一级入口, 这里重复.
                    // Exercise library: 弹 sheet 浏览全部动作
                    Button(action: { showExerciseLibrary = true }) {
                        Row(label: "Exercise library") {
                            HStack(spacing: 6) {
                                Text("\(data.exercises.count)").foregroundStyle(MasoColor.textDim)
                                if !data.exercises.isEmpty {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(MasoColor.textFaint)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(data.exercises.isEmpty)
                }

                Text("Plans and workout records stay on your device.")
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textFaint)
                    .padding(.horizontal, 6)
                    // 紧贴上面 section (顶层 VStack spacing 24, 这里抵消 16 → 实际间距 8pt)
                    .padding(.top, -16)

                // 健康提示 + 法律链接 — Apple 1.4.1 要求健身类 app 给出医疗免责;
                // Terms / Privacy 是 paywall + App Store metadata 强制要求的合规链接.
                Section_(title: "Health & Safety") {
                    Text("Maso is for informational and motivational purposes only — not medical advice. Consult a physician before starting any new exercise program, especially if you have a medical condition, are pregnant, or have not exercised recently. Stop immediately and seek help if you feel pain, dizziness, or shortness of breath.")
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textDim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

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
                    Row(label: "Version") {
                        Text(appVersionLabel)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(MasoColor.textDim)
                    }
                }

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
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(manager: languageManager)
        }
        .sheet(isPresented: $showExerciseLibrary) {
            ExerciseLibraryBrowser()
        }
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
        if let sub = data.settings.proSubscription {
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

    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            valueField
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
        .toolbar {
            // numberPad 没自带 Return / Done — 手挂一个键盘 toolbar 的"完成"
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .foregroundStyle(MasoColor.accent)
                }
            }
        }
    }

    private var valueField: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(focused ? MasoColor.accent : MasoColor.text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onAppear { text = "\(value)" }
                .onChange(of: value) { _, newValue in
                    // 外部 (e.g. Stepper +/-) 改了 value → 同步显示
                    if !focused { text = "\(newValue)" }
                }
            if let suffix {
                Text(NSLocalizedString(suffix, comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
            }
        }
        .frame(width: 70, alignment: .trailing)
        // 整块 (含 suffix) 都是 tap 热区 — 点单位也能拉键盘
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Int(trimmed) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            value = clamped
            text = "\(clamped)"
        } else {
            // 空 / 非法 → 回退
            text = "\(value)"
        }
    }
}

private struct DoubleStepperContent: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var suffix: String? = nil

    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            valueField
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .foregroundStyle(MasoColor.accent)
                }
            }
        }
    }

    private var valueField: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(focused ? MasoColor.accent : MasoColor.text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onAppear { text = format(value) }
                .onChange(of: value) { _, newValue in
                    if !focused { text = format(newValue) }
                }
            if let suffix {
                Text(NSLocalizedString(suffix, comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
            }
        }
        .frame(width: 70, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 处理欧洲 locale 用 "," 当小数点
        if let parsed = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            value = clamped
            text = format(clamped)
        } else {
            text = format(value)
        }
    }

    /// 整数显整数, 否则保留 1 位小数 (e.g. 70 → "70"; 70.5 → "70.5")
    private func format(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
        return String(format: "%.1f", v)
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
