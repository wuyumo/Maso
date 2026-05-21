import SwiftUI
import StoreKit

// Maso Pro 付费 paywall — StoreKit 2 真接.
//
// 设计思路 (参考 Strong / Hevy / Apple Fitness+ 等主流付费墙):
//   1. 顶部 logo + 标题 — 品牌识别
//   2. 价值清单 (6 条) — 让用户在 5 秒内明白买的是什么
//   3. 3 个 plan 卡片 (Monthly / Yearly / Lifetime), Yearly 默认选中 + POPULAR badge
//   4. 大 CTA (Start free trial / Buy lifetime), 跟 plan 选择联动
//   5. 底部 Restore Purchases + Terms + Privacy 链接 (App Store 合规要求)
//
// 实现:
//   - 价格 / 文案 来自 StoreKit Product (locale-aware, $4.99 在 EU 会自动显示 €4.99)
//   - 购买走 SubscriptionManager.purchase() → Product.purchase() → 校验 → 写 entitlement
//   - Restore 走 SubscriptionManager.restore() → AppStore.sync() → 刷新 entitlements
//   - 错误用 alert 弹出 (StoreKit 错误信息已经本地化)
struct PaywallScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subs
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionTier = .yearly
    @State private var processing: Bool = false
    @State private var showConfirm: Bool = false
    @State private var errorAlertShown: Bool = false

    // Legal URLs — 部署在 GitHub Pages 上 (repo: wuyumo/Maso, source: docs/ on main branch).
    // Markdown 源文件: docs/privacy-policy.md, docs/terms.md. Jekyll 自动渲染成 .html.
    // 若以后换 custom domain (e.g. maso.app), 改这两行即可.
    static let termsURL = URL(string: "https://wuyumo.github.io/Maso/terms.html")!
    static let privacyURL = URL(string: "https://wuyumo.github.io/Maso/privacy-policy.html")!

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.top, 8)
                            .padding(.bottom, 28)

                        featureList
                            .padding(.bottom, 32)

                        planCards
                            .padding(.bottom, 24)

                        ctaButton
                            .padding(.bottom, 16)

                        footer
                            .padding(.bottom, 24)
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
            Text("Enjoy unlimited plans, full history, and everything else. Welcome aboard.")
        }
        .alert("Purchase issue", isPresented: $errorAlertShown) {
            Button("OK", role: .cancel) { subs.lastError = nil }
        } message: {
            Text(subs.lastError ?? "")
        }
        .onChange(of: subs.lastError) { _, newError in
            errorAlertShown = (newError != nil)
        }
        // 进 paywall 时如果还没 load products, 触发一次 load. SubscriptionManager.configure
        // 已经在 app 启动时跑过, 这里是兜底 — 万一第一次 load 失败, paywall 弹出再试一次.
        .task {
            if subs.products.isEmpty {
                await subs.loadProducts()
            }
        }
    }

    // MARK: - sections

    private var backgroundGradient: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [MasoColor.accent.opacity(0.18), .clear],
                center: .init(x: 0.5, y: 0.12),
                startRadius: 20,
                endRadius: 320
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

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(icon: "infinity", title: "Unlimited workout plans",
                       desc: "No more 3-plan cap — build a plan for every split.")
            FeatureRow(icon: "clock.arrow.circlepath", title: "Full history",
                       desc: "Permanent record + PR tracking + volume trends.")
            FeatureRow(icon: "chart.bar.xaxis", title: "Advanced analytics",
                       desc: "Muscle balance, weekly volume, weak spots.")
            FeatureRow(icon: "plus.app.fill", title: "Custom exercises",
                       desc: "Add your own moves with notes and photos.")
            FeatureRow(icon: "heart.text.square", title: "Apple Health sync",
                       desc: "Two-way sync — workouts go in, weight comes out.")
            // ⚠️ "Cloud sync" 行暂时下架 — iCloud Drive ubiquity 兑现没做, 不能在
            // paywall 列了用户却用不上, 否则 Apple 审核会按"功能未兑现"打回 + 用户投诉退款.
            // 实现后 (见 docs/cloudkit-todo.md), 把这一行恢复:
            // FeatureRow(icon: "icloud.fill", title: "Cloud sync",
            //            desc: "Plans + history follow you across devices.")
        }
        .padding(.horizontal, 4)
    }

    /// Plan cards — 价格从 StoreKit Product 拿 (locale-aware), 没 load 完时显示 placeholder.
    private var planCards: some View {
        HStack(spacing: 10) {
            PlanCard(
                tier: .monthly,
                product: subs.product(for: .monthly),
                badge: nil,
                selected: selectedPlan == .monthly,
                onTap: { selectedPlan = .monthly }
            )
            PlanCard(
                tier: .yearly,
                product: subs.product(for: .yearly),
                badge: "POPULAR",
                selected: selectedPlan == .yearly,
                onTap: { selectedPlan = .yearly }
            )
            PlanCard(
                tier: .lifetime,
                product: subs.product(for: .lifetime),
                badge: nil,
                selected: selectedPlan == .lifetime,
                onTap: { selectedPlan = .lifetime }
            )
        }
    }

    private var ctaButton: some View {
        Button(action: handlePurchase) {
            HStack(spacing: 8) {
                if processing {
                    ProgressView().tint(.black)
                }
                Text(ctaTitle)
                    .font(.system(size: 16, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(MasoColor.accent)
            .foregroundStyle(.black)
            .clipShape(Capsule())
            .shadow(color: MasoColor.accent.opacity(0.35), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(processing || subs.product(for: selectedPlan) == nil)
        .opacity(subs.product(for: selectedPlan) == nil ? 0.6 : 1)
    }

    /// CTA 文案 — 带 trial 的 (monthly / yearly) 显示 "Start 7-day free trial"; lifetime 显示
    /// "Buy lifetime — $79.99". 价格走 StoreKit displayPrice, fallback 到硬编码兜底.
    private var ctaTitle: String {
        switch selectedPlan {
        case .monthly, .yearly:
            // 如果 StoreKit product 有 introductoryOffer 就显示 trial 文案
            if let p = subs.product(for: selectedPlan), p.subscription?.introductoryOffer != nil {
                return NSLocalizedString("Start 7-day free trial", comment: "")
            }
            // 没有 trial → 直接显示价格
            let price = subs.product(for: selectedPlan)?.displayPrice ?? ""
            return String(format: NSLocalizedString("Subscribe for %@", comment: ""), price)
        case .lifetime:
            let price = subs.product(for: .lifetime)?.displayPrice ?? "$79.99"
            return String(format: NSLocalizedString("Buy lifetime — %@", comment: ""), price)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // 续费 / trial → 转付费 说明 (App Store 合规)
            renewalDisclaimer

            HStack(spacing: 20) {
                Button(action: handleRestore) {
                    Text("Restore Purchases")
                }
                Link("Terms", destination: Self.termsURL)
                Link("Privacy", destination: Self.privacyURL)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textDim)
        }
    }

    @ViewBuilder
    private var renewalDisclaimer: some View {
        if selectedPlan == .lifetime {
            Text("One-time purchase. No subscription, no recurring charges.")
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .multilineTextAlignment(.center)
        } else {
            // displayPrice 是 locale-aware 的, 比硬编码 $4.99 更准.
            // 没 load product 时回落到无价格的简版.
            if let p = subs.product(for: selectedPlan) {
                let periodLabel = selectedPlan == .monthly ? "month" : "year"
                Text(String(
                    format: NSLocalizedString("Free for 7 days, then %@ / %@. Cancel anytime in Settings.", comment: ""),
                    p.displayPrice,
                    NSLocalizedString(periodLabel, comment: "")
                ))
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .multilineTextAlignment(.center)
            } else {
                Text("Free for 7 days, then auto-renews. Cancel anytime in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    private func handlePurchase() {
        guard let product = subs.product(for: selectedPlan) else { return }
        processing = true
        Task {
            let ok = await subs.purchase(product)
            processing = false
            if ok {
                Haptics.trainingComplete()
                showConfirm = true
            }
            // 错误已经写到 subs.lastError, onChange 会触发 alert
        }
    }

    private func handleRestore() {
        processing = true
        Task {
            await subs.restore()
            processing = false
            // restore 成功且现在是 Pro → 弹同款庆祝 alert
            if subs.currentSubscription != nil {
                showConfirm = true
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

/// 价格 / 周期 / detail 全部从 StoreKit Product 读. Product 还没 load 时显示 dash placeholder
/// (避免 layout 在 product 到达瞬间跳).
private struct PlanCard: View {
    let tier: SubscriptionTier
    let product: Product?
    let badge: String?
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(LocalizedStringKey(label))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(selected ? MasoColor.accent : MasoColor.textDim)
                Text(priceText)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(MasoColor.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(LocalizedStringKey(period))
                    .font(.system(size: 10))
                    .foregroundStyle(MasoColor.textDim)
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? MasoColor.accent : MasoColor.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
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
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
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

    private var priceText: String {
        product?.displayPrice ?? "—"
    }

    private var label: String {
        switch tier {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    private var period: String {
        switch tier {
        case .monthly:  return "/ month"
        case .yearly:   return "/ year"
        case .lifetime: return "once"
        }
    }

    private var detail: String {
        switch tier {
        case .monthly:  return "Billed monthly"
        case .yearly:   return "Save 50%"
        case .lifetime: return "Pay once, own it"
        }
    }
}

#Preview {
    PaywallScreen()
        .environment(DataStore.makeMock())
        .environment(SubscriptionManager())
}
