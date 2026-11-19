import SwiftUI
import StoreKit

enum PaywallContext { case upgrade, welcome, aiReminder }

#if DEBUG
private final class RestoreGate {
    var released = false
}

/// Off unless `MASO_RESTORE_TRACE=1`. Release builds omit it.
@Observable
final class RestoreTrace {
    static let shared = RestoreTrace()
    var text = ""
    var enabled: Bool { ProcessInfo.processInfo.environment["MASO_RESTORE_TRACE"] == "1" }
    @MainActor func mark(_ stage: String) {
        guard enabled else { return }
        let line = String(format: "%.3f %@", Date().timeIntervalSince1970, stage)
        text = text.isEmpty ? line : text + " | " + line
        print("RESTORE_TRACE \(line)")
    }
    @MainActor static func mark(_ stage: String) { shared.mark(stage) }
}
#else
enum RestoreTrace { static func mark(_ stage: String) {} }
#endif

/// Restores Claude Code's custom layout (f0ebc0e / 83277c3), with current
/// StoreKit products, verified trial eligibility and the approved free/Pro split.
struct PaywallScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    var source: String = "unknown"
    var context: PaywallContext = .upgrade
    @State private var referralSheetShown = false
    @State private var selectedPlan: SubscriptionTier = .yearly
    @State private var processing = false
    #if DEBUG
    /// Holds the real StoreKit restore until a debug test has observed the in-flight state.
    @State private var restoreGate = RestoreGate()
    #endif
    private struct Notice { let message: String; var canRetry = false }
    @State private var notice: Notice?
    @State private var eligibleTrials: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var brandTitleSize = 32

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
                        subscriptionOptions
                            .padding(.top, 24)
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
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { restoreToolbarContent }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { restoreToolbarContent }
                }
            }
        }
        .preferredColorScheme(.dark).tint(MasoColor.text)
        .presentationDetents([.large])
        .accessibilityIdentifier("paywall.screen")
        .overlay(alignment: .bottom) { restoreReleaseControl }
        #if DEBUG
        .overlay(alignment: .top) {
            if RestoreTrace.shared.enabled {
                Text(RestoreTrace.shared.text)
                    .font(.caption2)
                    .accessibilityIdentifier("paywall.restore.trace")
            }
        }
        #endif
        .sheet(isPresented: $referralSheetShown) { ReferralCodeSheet() }
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

    private var restoreToolbarContent: some View {
                    ZStack {
                        Button(action: restorePurchases) {
                            restorePurchaseLabel.opacity(processing ? 0 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(processing)
                        .accessibilityLabel(Text("Restore Purchase"))
                        .accessibilityValue(processing ? "busy" : "idle")
                        .accessibilityShowsLargeContentViewer { Text("Restore Purchase") }
                        .accessibilityIdentifier("paywall.restore")
                        if processing {
                            ProgressView()
                                .frame(minWidth: 44, minHeight: 44)
                                .allowsHitTesting(false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("paywall.restore.progress")
                                .accessibilityLabel("Restoring")
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
    }

    private var marketingContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(spacing: 6) {
                MasoMarkIcon(color: MasoColor.accent).frame(width: 64, height: 64)
                    .accessibilityIdentifier("paywall.brand-logo")
                    .environment(\.layoutDirection, .leftToRight)
                Text("Masso Pro").font(.system(size: brandTitleSize, weight: .heavy))
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
            } else {
                Button { Task { await loadSubscriptionOptions() } } label: {
                    Text("Try again")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(MasoColor.accent)
                .accessibilityIdentifier("paywall.retry")
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
                // Match the tallest visible card, including only its actual disclosure.
                ForEach(availableProducts, id: \.id) { candidate in
                    planCardContent(candidate, selected: candidate.id == selectedProduct?.id,
                                    hasTrial: trialDays(for: candidate) == 7)
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
            Button { referralSheetShown = true } label: {
                Text("Have a referral code?").fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.subheadline.weight(.semibold)).foregroundStyle(MasoColor.text)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("paywall.referral")
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

    private var restorePurchaseLabel: some View {
        Text("Restore Purchase")
            .font(.body)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .allowsTightening(true)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 150 : 210,
                   minHeight: 44, alignment: .trailing)
    }

    private func restorePurchases() {
        guard !processing else { return }
        processing = true
        #if DEBUG
        let gate = restoreGate
        gate.released = false
        #endif
        Task {
            defer {
                processing = false
                RestoreTrace.mark("paywall.processing.cleared")
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["MASO_RESTORE_HOLD"] == "1" {
                RestoreTrace.mark("paywall.gate.wait")
                while !gate.released {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                RestoreTrace.mark("paywall.gate.released")
            }
            #endif
            RestoreTrace.mark("paywall.restore.call")
            await subscriptions.restore()
            if let error = subscriptions.lastError {
                notice = Notice(message: error)
                subscriptions.lastError = nil
                RestoreTrace.mark("paywall.notice:\(error)")
            } else {
                RestoreTrace.mark("paywall.notice:none")
            }
            if data.settings.isPro {
                RestoreTrace.mark("paywall.dismiss.pro")
                dismiss()
            }
        }
    }

    @ViewBuilder private var restoreReleaseControl: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASO_RESTORE_HOLD"] == "1", processing {
            Button("Finish restore") { restoreGate.released = true }
                .accessibilityIdentifier("paywall.restore.release")
        }
        #else
        EmptyView()
        #endif
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


