import SwiftUI

// Maso Pro 付费墙 — 外部 (Polar) 网页结账版.
//
// 为什么不是 Apple IAP: 账号身份签不了美国 Paid Apps 协议. 改走 Polar (merchant of record,
// 代收税). 仅美区显示 (Epic v. Apple 判决后美区 app 内可放外链付费, 0 抽成); 其他区
// isPro 恒 true, 根本不会弹这个墙 (见 UserSettings.isPro / showProUpsell).
//
// 流程:
//   1. 选月/年档 → Continue → 打开该档 Polar checkout (Safari 外链).
//   2. 结账成功 → Polar 回跳 /pro/return → 深链 maso://activate?key= 自动回 app 激活.
//   3. 兜底: 「Enter code」手动输 Polar 邮件里的激活码 → Worker 校验 → 解锁.
//   价格是外部定价, 硬编码显示 (非 StoreKit); 真值在 Polar product.
struct PaywallScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var source: String = "unknown"

    @State private var selectedPlan: SubscriptionTier = .yearly
    @State private var showConfirm: Bool = false
    @State private var codeSheetShown: Bool = false

    static let termsURL = URL(string: "https://wuyumo.github.io/Maso/terms.html")!
    static let privacyURL = URL(string: "https://wuyumo.github.io/Maso/privacy-policy.html")!

    // 硬编码外部定价 (跟 Polar product 对齐). 仅美区显示 → 美元.
    private static let monthlyPrice = "$4.99"
    private static let yearlyPrice = "$29.99"

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection.padding(.top, 8).padding(.bottom, 28)
                        featureList.padding(.bottom, 32)
                        planCards.padding(.bottom, 24)
                        ctaButton.padding(.bottom, 16)
                        footer.padding(.bottom, 24)
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(MasoColor.text)
        }
        .preferredColorScheme(.dark)
        .alert("You're now Maso Pro!", isPresented: $showConfirm) {
            Button("Done") { dismiss() }
        } message: {
            Text("Enjoy unlimited plans, unlimited AI, and deep analytics. Welcome aboard.")
        }
        .sheet(isPresented: $codeSheetShown) {
            ActivationCodeSheet(onActivated: {
                codeSheetShown = false
                showConfirm = true
            })
            .environment(data)
        }
        .task {
            Analytics.shared.track("paywall_shown", ["source": .string(source)])
        }
    }

    // MARK: - sections

    private var backgroundGradient: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [MasoColor.accent.opacity(0.18), .clear],
                center: .init(x: 0.5, y: 0.12), startRadius: 20, endRadius: 320
            )
        }
    }

    private var heroSection: some View {
        VStack(spacing: 16) {
            MasoMarkIcon(color: MasoColor.accent)
                .frame(width: 72, height: 72)
            VStack(spacing: 6) {
                Text("Maso Pro")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(MasoColor.text)
                Text("Unlock your full training.")
                    .font(.system(size: 14))
                    .foregroundStyle(MasoColor.textDim)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // 卖点与真实 gate 一一对应 (不画饼): ①3-plan cap ②AI 每日额度 ③深度力量分析卡 (逐动作
    // 1RM/e1RM/MEV·MAV) + 周报 AI 小结 ④逐肌恢复精度 (muscleDetailEnabled) ⑤自建动作. 原
    // "Full history"(历史本就免费) / "Smart progression"(无 gate) / "Apple Health"(免费) 已移除.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(icon: "infinity", title: "Unlimited workout plans",
                       desc: "No more 3-plan cap — build a plan for every split.")
            FeatureRow(icon: "sparkles", title: "Unlimited AI coach",
                       desc: "Generate and refine plans in chat with no daily limit.")
            FeatureRow(icon: "chart.bar.xaxis", title: "Deep analytics",
                       desc: "Per-lift 1RM trends, weak spots, and weekly AI summaries.")
            FeatureRow(icon: "figure.run.circle", title: "Fine-grained recovery",
                       desc: "Per-muscle recovery status, not just broad zones.")
            FeatureRow(icon: "plus.app.fill", title: "Custom exercises",
                       desc: "Add your own moves with notes and photos.")
        }
        .padding(.horizontal, 4)
    }

    private var planCards: some View {
        HStack(spacing: 12) {
            ExternalPlanCard(
                label: "Monthly", price: Self.monthlyPrice, period: "/ month",
                detail: "Billed monthly", badge: nil,
                selected: selectedPlan == .monthly,
                onTap: { selectedPlan = .monthly }
            )
            ExternalPlanCard(
                label: "Yearly", price: Self.yearlyPrice, period: "/ year",
                detail: "Best value", badge: "POPULAR",
                selected: selectedPlan == .yearly,
                onTap: { selectedPlan = .yearly }
            )
        }
    }

    private var ctaButton: some View {
        Button(action: handleContinue) {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.system(size: 16, weight: .heavy))
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 13, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(MasoColor.accent)
            .foregroundStyle(.black)
            .clipShape(Capsule())
            .shadow(color: MasoColor.accent.opacity(0.35), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(checkoutURL(for: selectedPlan) == nil)
        .opacity(checkoutURL(for: selectedPlan) == nil ? 0.6 : 1)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // 诚实说明: 结账在 Polar 网页 (非 Apple), recurring, 网页可管理.
            Text(String(format: NSLocalizedString("Secure checkout on the web via Polar. %@ / %@, renews until cancelled — manage or cancel anytime on the Polar page.", comment: "external paywall disclaimer"),
                        selectedPlan == .monthly ? Self.monthlyPrice : Self.yearlyPrice,
                        NSLocalizedString(selectedPlan == .monthly ? "month" : "year", comment: "")))
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                Button(action: { codeSheetShown = true }) {
                    Text("Enter code")
                }
                Link("Terms", destination: Self.termsURL)
                Link("Privacy", destination: Self.privacyURL)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textDim)
        }
    }

    // MARK: - Actions

    /// 从 Info.plist 读该档的 Polar checkout 链接 (Polar 后台建 product 后填).
    private func checkoutURL(for tier: SubscriptionTier) -> URL? {
        let key = tier == .monthly ? "MasoCheckoutMonthlyURL" : "MasoCheckoutYearlyURL"
        guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !s.isEmpty, s.hasPrefix("http"), let u = URL(string: s) else { return nil }
        return u
    }

    private func handleContinue() {
        guard let url = checkoutURL(for: selectedPlan) else { return }
        Analytics.shared.track("paywall_checkout_open", ["plan": .string(selectedPlan.rawValue)])
        Haptics.tap()
        openURL(url)   // Safari 外链 — 美区合规
    }
}

// MARK: - 激活码 sheet

private struct ActivationCodeSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    var onActivated: () -> Void

    @State private var code: String = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enter your activation code")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(MasoColor.text)
                    Text("After buying on the web, your code was emailed to you (and shown on the confirmation page). Paste it here to unlock Pro on this device.")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)

                    TextField("XXXX-XXXX-XXXX", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 16, weight: .semibold).monospaced())
                        .padding(14)
                        .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(MasoColor.text)

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.negative)
                    }

                    Button(action: activate) {
                        HStack(spacing: 8) {
                            if checking { ProgressView().tint(.black) }
                            Text("Activate").font(.system(size: 16, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(MasoColor.accent)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(checking || code.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(code.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)

                    Spacer()
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(MasoColor.text)
    }

    private func activate() {
        error = nil
        checking = true
        Task {
            do {
                let ok = try await data.activatePolar(key: code)
                checking = false
                Analytics.shared.track("pro_activate_result", ["success": .bool(ok)])
                if ok {
                    Haptics.trainingComplete()
                    dismiss()
                    onActivated()
                } else {
                    error = NSLocalizedString("That code isn't active yet. Double-check it, or try again in a moment.", comment: "")
                }
            } catch {
                checking = false
                self.error = NSLocalizedString("Couldn't verify — check your connection and try again.", comment: "")
            }
        }
    }
}

// MARK: - 小组件

private struct FeatureRow: View {
    let icon: String
    let title: String
    let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MasoColor.accent)
                .frame(width: 30, height: 30)
                .background(MasoColor.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Text(LocalizedStringKey(desc))
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(2)
            }
        }
    }
}

private struct ExternalPlanCard: View {
    let label: String
    let price: String
    let period: String
    let detail: String
    let badge: String?
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(LocalizedStringKey(label))
                    .font(.system(size: 11, weight: .bold)).tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(selected ? MasoColor.accent : MasoColor.textDim)
                Text(price)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(MasoColor.text)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(LocalizedStringKey(period))
                    .font(.system(size: 10))
                    .foregroundStyle(MasoColor.textDim)
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? MasoColor.accent : MasoColor.textFaint)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.vertical, 14).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(MasoColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? MasoColor.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .top) {
                if let badge {
                    Text(LocalizedStringKey(badge))
                        .font(.system(size: 9, weight: .heavy)).tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(MasoColor.accent)
                        .clipShape(Capsule())
                        .offset(y: -9)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallScreen()
        .environment(DataStore.makeMock())
}
