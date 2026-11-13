import SwiftUI
import StoreKit

enum PaywallContext { case upgrade, welcome, aiReminder }

/// Restores Claude Code's custom layout (f0ebc0e / 83277c3), with current
/// StoreKit products, verified trial eligibility and the approved free/Pro split.
struct PaywallScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    var source: String = "unknown"
    var context: PaywallContext = .upgrade
    @State private var codeSheetShown = false
    @State private var referralSheetShown = false
    @State private var policyDetailsShown = false
    @State private var selectedPlan: SubscriptionTier = .yearly
    @State private var processing = false
    private struct Notice { let message: String; var canRetry = false }
    @State private var notice: Notice?
    @State private var eligibleTrials: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let termsURL = URL(string: "https://wuyumo.github.io/Maso/terms.html")!
    static let privacyURL = URL(string: "https://wuyumo.github.io/Maso/privacy-policy.html")!

    var body: some View {
        AppNavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                RadialGradient(colors: [MasoColor.accent.opacity(0.18), .clear],
                               center: .init(x: 0.5, y: 0.1), startRadius: 20, endRadius: 340)
                    .ignoresSafeArea().allowsHitTesting(false)
                ScrollView {
                    VStack(spacing: 12) {
                        marketingContent
                        HStack(spacing: 8) {
                            Text(String(format: NSLocalizedString("Free: %d plans and %d custom exercises", comment: ""),
                                        ProAccessPolicy.current.freeSavedPlans, ProAccessPolicy.current.freeCustomExercises))
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { policyDetailsShown = true } label: {
                                Image(systemName: "info.circle").frame(width: 44, height: 44).contentShape(Rectangle())
                            }.accessibilityLabel("Free and Pro details")
                                .accessibilityIdentifier("paywall.policy-details")
                        }
                        subscriptionOptions
                        purchaseSection
                        footer
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 10).padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).accessibilityIdentifier("paywall.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if availableProducts.isEmpty && !subscriptions.isLoadingProducts {
                            Button("Try again") { Task { await loadSubscriptionOptions() } }
                        }
                        Button("Restore web purchase") { codeSheetShown = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityIdentifier("paywall.more")
                }
            }
        }
        .preferredColorScheme(.dark).tint(MasoColor.text)
        .presentationDetents([.large])
        .accessibilityIdentifier("paywall.screen")
        .sheet(isPresented: $codeSheetShown) {
            ActivationCodeSheet { codeSheetShown = false; dismiss() }.environment(data)
        }
        .sheet(isPresented: $referralSheetShown) { ReferralCodeSheet() }
        .sheet(isPresented: $policyDetailsShown) { ProPolicyDetailsSheet() }
        .alert("Masso Pro", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }), presenting: notice) { item in
            if item.canRetry {
                Button("Try again") { Task { await loadSubscriptionOptions() } }
                Button("Not now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { item in Text(item.message) }
        .onChange(of: subscriptions.lastError) { _, error in
            if let error {
                notice = Notice(message: error)
                subscriptions.lastError = nil
            }
        }
        .onChange(of: data.settings.isPro) { _, active in if active { dismiss() } }
        .task {
            Analytics.shared.track("paywall_shown", ["source": .string(source)])
            if availableProducts.isEmpty { await loadSubscriptionOptions() }
            else { await refreshTrialEligibility() }
        }
        .task(id: subscriptions.products.map(\.id)) { await refreshTrialEligibility() }
    }

    private var marketingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 6) {
                MasoMarkIcon(color: MasoColor.accent).frame(width: 64, height: 64)
                    .accessibilityIdentifier("paywall.brand-logo")
                    .environment(\.layoutDirection, .leftToRight)
                Text("Masso Pro").font(.largeTitle.weight(.heavy))
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 12) {
                benefit("Keep adapting with AI Coach", detail: "Adjust workouts around your time and equipment.", icon: "rectangle.stack", id: "plans")
                benefit("See progress and recovery", detail: "Lift trends and per-muscle recovery estimates.", icon: "chart.xyaxis.line", id: "progress")
                benefit("More room for your training", detail: "Save more plans and create more exercises.", icon: "figure.strengthtraining.traditional", id: "recovery")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String, id: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout(alignment:.top,spacing:12))
        return layout {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(MasoColor.accent)
                .frame(width: 34, height: 34)
                .background(MasoColor.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
                    .accessibilityIdentifier("paywall.benefit." + id)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var subscriptionOptions: some View {
        if availableProducts.isEmpty {
            if subscriptions.isLoadingProducts || !subscriptions.hasLoadedProducts {
                ProgressView().accessibilityLabel("Loading price…")
            }
        } else {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                ForEach(availableProducts, id: \.id) { product in planCard(product) }
            }
        }
    }

    private var availableProducts: [Product] {
        subscriptions.products.filter { SubscriptionManager.subscriptionProductIDs.contains($0.id) }
    }

    private var selectedProduct: Product? {
        subscriptions.product(for: selectedPlan) ?? availableProducts.first
    }

    private func planCard(_ product: Product) -> some View {
        let yearly = product.id == SubscriptionManager.yearlyProductID
        let selected = product.id == selectedProduct?.id
        return Button {
            selectedPlan = yearly ? .yearly : .monthly
            Haptics.tap()
        } label: {
            ZStack(alignment: .topLeading) {
                // Reserve the same intrinsic height for every plan and eligibility state.
                ForEach(availableProducts, id: \.id) { candidate in
                    planCardContent(candidate, selected: true, hasTrial: true)
                        .hidden().accessibilityHidden(true)
                    planCardContent(candidate, selected: true, hasTrial: false)
                        .hidden().accessibilityHidden(true)
                }
                planCardContent(product, selected: selected, hasTrial: trialDays(for: product) == 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(MasoColor.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? MasoColor.accent : MasoColor.borderSoft, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(processing)
        .accessibilityIdentifier("paywall.plan.\(yearly ? "yearly" : "monthly")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func planCardContent(_ product: Product, selected: Bool, hasTrial: Bool) -> some View {
        let yearly = product.id == SubscriptionManager.yearlyProductID
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text(LocalizedStringKey(yearly ? "Yearly" : "Monthly")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 2)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? MasoColor.accent : MasoColor.textDim)
            }
            Text(product.displayPrice).font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(yearly ? "Billed yearly" : "Billed monthly"))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if selected {
                Text(disclosure(for: product, hasTrial: hasTrial)).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.renewal")
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            if let product = selectedProduct {
                Button {
                    guard !processing else { return }
                    processing = true
                    Task {
                        let purchased = await subscriptions.purchase(product)
                        processing = false
                        if purchased { dismiss() }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if processing { ProgressView().tint(.black) }
                        Text(purchaseTitle).font(.body.weight(.semibold)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(MasoColor.accent, in: Capsule()).foregroundStyle(.black)
                }
                .buttonStyle(.plain).disabled(processing)
                .accessibilityIdentifier("paywall.purchase")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { secondaryActions }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 0) { secondaryActions }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            if context == .aiReminder {
                Text("AI access on this device")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var purchaseTitle: String {
        guard let product = selectedProduct else { return NSLocalizedString(subscriptions.hasLoadedProducts ? "Subscribe" : "Loading price…", comment: "") }
        return NSLocalizedString(trialDays(for: product) == 7 ? "Start 7-day free trial" : "Subscribe", comment: "")
    }

    @ViewBuilder private var secondaryActions: some View {
        Button { referralSheetShown = true } label: {
            Text("Have a referral code?").fixedSize(horizontal:false,vertical:true).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier("paywall.referral")
        Button { dismiss() } label: {
            Text("Continue free").fixedSize(horizontal:false,vertical:true).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier("paywall.continue-free")
        Button {
            guard !processing else { return }
            processing = true
            Task { await subscriptions.restore(); processing = false; if data.settings.isPro { dismiss() } }
        } label: {
            Text("Restore Purchases").fixedSize(horizontal:false,vertical:true).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier("paywall.restore")
    }

    private var footer: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:22) { legalLinks }.fixedSize(horizontal:true,vertical:true)
            VStack(spacing:4) { legalLinks }
        }.font(.footnote).foregroundStyle(.secondary)
    }

    @ViewBuilder private var legalLinks: some View {
        Link("Terms",destination:Self.termsURL).fixedSize(horizontal:true,vertical:true).frame(minHeight:44).accessibilityIdentifier("paywall.terms")
        Link("Privacy",destination:Self.privacyURL).fixedSize(horizontal:true,vertical:true).frame(minHeight:44).accessibilityIdentifier("paywall.privacy")
    }

    private func loadSubscriptionOptions() async {
        await subscriptions.loadProducts()
        guard !Task.isCancelled else { return }
        await refreshTrialEligibility()
        guard !Task.isCancelled, !data.settings.isPro else { return }
        if availableProducts.isEmpty && notice == nil {
            notice = Notice(message: NSLocalizedString("Subscription options are unavailable right now", comment: ""), canRetry: true)
        } else if !availableProducts.isEmpty && notice?.canRetry == true {
            notice = nil
        }
    }

    private func refreshTrialEligibility() async {
        var eligible: Set<String> = []
        for tier in [SubscriptionTier.monthly, .yearly] {
            if await subscriptions.isEligibleForIntroOffer(tier), let product = subscriptions.product(for: tier) {
                eligible.insert(product.id)
            }
        }
        eligibleTrials = eligible
    }

    private func trialDays(for product: Product) -> Int? {
        guard eligibleTrials.contains(product.id), let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        switch offer.period.unit {
        case .day: return offer.period.value * offer.periodCount
        case .week: return offer.period.value * offer.periodCount * 7
        default: return nil
        }
    }

    private func disclosure(for product: Product, hasTrial: Bool) -> String {
        let yearly = product.id == SubscriptionManager.yearlyProductID
        let key: String
        if hasTrial {
            key = yearly
                ? "7 days free, then renews yearly at the price above until cancelled."
                : "7 days free, then renews monthly at the price above until cancelled."
        } else {
            key = yearly
                ? "Renews yearly at the price above until cancelled."
                : "Renews monthly at the price above until cancelled."
        }
        return NSLocalizedString(key, comment: "renewal at the main price in the same subscription card")
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

        AppNavigationStack {
            Form {
                Section {
                    TextField("XXXX-XXXX-XXXX", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.body.monospaced())
                } footer: {
                    Text("After buying on the web, your code was emailed to you (and shown on the confirmation page). Paste it here to unlock Pro on this device.")
                }
                if let error { Section { Text(error).foregroundStyle(MasoColor.negative) } }
            }.scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Activate", icon: "checkmark", loading: checking, action: activate)
                    .disabled(checking || code.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Enter your activation code").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(MasoColor.text)


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



struct ReferralCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @State private var code = ""
    @State private var loading = false
    @State private var offer: PartnerReferral.Offer?
    @State private var failed = false
    @State private var redemptionShown = false
    @State private var redemptionFailed = false
    @State private var codeCopied = false
    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    TextField("Referral code", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: code) { _, _ in offer = nil; failed = false; codeCopied = false; redemptionFailed = false }
                        .accessibilityIdentifier("referral.code")
                    Button("Check referral code") {
                        loading = true; failed = false
                        Task {
                            do { offer = try await PartnerReferral.claim(code) }
                            catch { failed = true }
                            loading = false
                        }
                    }.disabled(loading || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(MasoColor.accent)
                    .accessibilityIdentifier("referral.check")
                    if loading { ProgressView() }
                } footer: {
                    Text("Checking a code binds your referral and shares an anonymous identifier and subscription transactions with Masso for referral accounting. Your health and training data are not shared.")
                }
                if failed { Section { Text("Couldn’t check this code. It may be unavailable, already bound, or the service may be offline. Try again later.").foregroundStyle(.secondary) } }
                if let offer {
                    Section {
                        Text(offer.code).font(.headline)
                        Button("Copy code and redeem with Apple") {
                            UIPasteboard.general.string = offer.code
                            codeCopied = true
                            redemptionFailed = false
                            redemptionShown = true
                        }
                            .accessibilityIdentifier("referral.redeem")
                        if redemptionFailed {
                            Text("Apple’s redemption sheet couldn’t open. Please try again.").foregroundStyle(.secondary)
                        }
                    } footer: {
                        if codeCopied { Text("Your code is copied. Paste it into Apple’s redemption sheet if asked.") }
                        Text("Apple confirms eligibility, the actual price, trial and renewal terms. Your discount is active only after Apple confirms redemption. This offer applies to the annual subscription.")
                    }
                }
            }
            .navigationTitle("Referral code").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("referral.close") } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await subscriptions.refreshEntitlements() } }
            }
            .offerCodeRedemption(isPresented: $redemptionShown) { result in
                if case .failure(let error) = result { redemptionFailed = !PartnerReferral.isCancellation(error) }
                Task { await subscriptions.refreshEntitlements() }
            }
        }
    }
}


private struct ProPolicyDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var candidatePreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MASO_PRO_POLICY_PREVIEW"] == "1"
        #else
        false
        #endif
    }
    var body: some View {
        AppNavigationStack {
            Form {
                if candidatePreview {
                    Section {
                        Text("Preview only: the shared quota service is not connected.")
                            .foregroundStyle(.secondary).accessibilityIdentifier("paywall.policy-preview-warning")
                    }
                }
                Section("Free") {
                    Text("Complete workouts, history, basic charts and data export stay available.")
                        .accessibilityIdentifier("paywall.policy-foundation")
                    Text(String(format: NSLocalizedString("Free: %d plans and %d custom exercises", comment: ""),
                                ProAccessPolicy.current.freeSavedPlans, ProAccessPolicy.current.freeCustomExercises))
                    Text("Existing plans, exercises and acquired results remain usable after Pro expires.")
                }
                Section("More with Pro") {
                    Text("Ongoing AI adjustments, more saved plans and custom exercises, lift progress and detailed recovery estimates.")
                }
                Section("AI access") {
                    DeviceAIRulesText()
                    Text("AI access and saved results")
                }
            }
            .navigationTitle("Free and Pro details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
