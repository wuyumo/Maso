import SwiftUI

// Maso Pro 付费 paywall
//
// 设计思路 (参考 Strong / Hevy / Apple Fitness+ 等主流付费墙):
//   1. 顶部 logo + 标题 — 品牌识别
//   2. 价值清单 (6 条) — 让用户在 5 秒内明白买的是什么
//   3. 3 个 plan 卡片 (Monthly / Yearly / Lifetime), Yearly 默认选中 + POPULAR badge
//   4. 大 CTA (Start free trial), 跟 plan 选择联动
//   5. 底部 Restore Purchases + Terms + Privacy 小字 (App Store 合规要求)
//
// MVP 实现:
//   - 没接 StoreKit, "购买"直接写本地 mock subscription 进 settings
//   - 生产环境需要换成 Product.purchase() + Transaction listener
struct PaywallScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionTier = .yearly
    @State private var processing: Bool = false
    @State private var showConfirm: Bool = false

    var body: some View {
        ZStack {
            // 背景 — 顶部一抹 accent radial gradient, 营造 "premium" 感
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // 关闭 + 顶部留白
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MasoColor.text)
                                .frame(width: 30, height: 30)
                                .background(MasoColor.surfaceHi.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close paywall")
                    }
                    .padding(.top, 8)

                    // Hero: logo + title
                    heroSection
                        .padding(.top, 24)
                        .padding(.bottom, 28)

                    // 价值清单
                    featureList
                        .padding(.bottom, 32)

                    // 3 个 plan
                    planCards
                        .padding(.bottom, 24)

                    // CTA
                    ctaButton
                        .padding(.bottom, 16)

                    // 法律 / 恢复 链接
                    footer
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }
        }
        .preferredColorScheme(.dark)
        .alert("You're now Maso Pro!", isPresented: $showConfirm) {
            Button("Done") { dismiss() }
        } message: {
            Text("Enjoy unlimited plans, full history, and everything else. Welcome aboard.")
        }
    }

    // MARK: - sections

    private var backgroundGradient: some View {
        ZStack {
            Color.black
            // 顶部一道绿色光晕, 跟品牌 mark 呼应
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
            FeatureRow(icon: "icloud.fill", title: "Cloud sync",
                       desc: "Plans + history follow you across devices.")
        }
        .padding(.horizontal, 4)
    }

    private var planCards: some View {
        HStack(spacing: 10) {
            PlanCard(
                tier: .monthly,
                price: "$4.99",
                period: "/ month",
                detail: "Billed monthly",
                badge: nil,
                selected: selectedPlan == .monthly,
                onTap: { selectedPlan = .monthly }
            )
            PlanCard(
                tier: .yearly,
                price: "$29.99",
                period: "/ year",
                detail: "Save 50%",
                badge: "POPULAR",
                selected: selectedPlan == .yearly,
                onTap: { selectedPlan = .yearly }
            )
            PlanCard(
                tier: .lifetime,
                price: "$79.99",
                period: "once",
                detail: "Pay once, own it",
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
        .disabled(processing)
    }

    private var ctaTitle: String {
        switch selectedPlan {
        case .monthly: return "Start 7-day free trial"
        case .yearly: return "Start 7-day free trial"
        case .lifetime: return "Buy lifetime — $79.99"
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // 试用 → 转付费 时机说明 (App Store 合规)
            if selectedPlan != .lifetime {
                let priceStr = selectedPlan == .monthly ? "$4.99 / month" : "$29.99 / year"
                Text("Free for 7 days, then \(priceStr). Cancel anytime in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
                    .multilineTextAlignment(.center)
            } else {
                Text("One-time purchase. No subscription, no recurring charges.")
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                Button("Restore Purchases", action: restorePurchases)
                Button("Terms", action: {})
                Button("Privacy", action: {})
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textDim)
        }
    }

    // MARK: - actions (mock)

    private func handlePurchase() {
        processing = true
        // mock 一个 0.6s 的网络延迟, 让 CTA 上的 ProgressView 转一下, 像在交易
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let now = Date()
            let renewsAt: Date? = {
                switch selectedPlan {
                case .monthly:  return now.addingTimeInterval(86400 * 30)
                case .yearly:   return now.addingTimeInterval(86400 * 365)
                case .lifetime: return nil
                }
            }()
            data.settings.proSubscription = ProSubscription(
                tier: selectedPlan, startedAt: now, renewsAt: renewsAt
            )
            processing = false
            showConfirm = true
        }
    }

    private func restorePurchases() {
        // 生产环境: AppStore.sync() + 校验
        // MVP: 仅作为按钮存在
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
                // 包 LocalizedStringKey 让 stringVar 也走 i18n. 已经在 Localizable.strings 配过键.
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

private struct PlanCard: View {
    let tier: SubscriptionTier
    let price: String
    let period: String
    let detail: String
    let badge: String?
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // label / period / detail / badge 全部走 LocalizedStringKey.
                // price 是动态价格字符串 (e.g. "$2.99/mo"), 不走 i18n.
                Text(LocalizedStringKey(label))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(selected ? MasoColor.accent : MasoColor.textDim)
                Text(price)
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
            // POPULAR badge — 顶部 floating
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

    private var label: String {
        switch tier {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }
}

#Preview {
    PaywallScreen()
        .environment(DataStore.makeMock())
}
