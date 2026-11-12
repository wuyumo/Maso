import Foundation
import StoreKit
import Observation
import Security

// StoreKit 2 订阅管理器
//
// 职责:
//   1. 启动时 load 3 个 product (monthly / yearly / lifetime)
//   2. 启动后台 Task.detached 监听 Transaction.updates (跨设备 / refund / 续期 → 实时更新本机状态)
//   3. purchase(product) — 调 Product.purchase(), 校验 verification, 更新 entitlement
//   4. restore() — 调 AppStore.sync() + 重读 currentEntitlements (用户换设备 / 重装 app 后恢复)
//   5. 通过 onEntitlementChange callback 回调把 ProSubscription 写到 DataStore.settings
//
// 跟 DataStore 的关系:
//   - SubscriptionManager 是 storage-agnostic 的 — 只管 StoreKit transactions, 不直接读写
//     DataStore. MasoApp 在 init 时注入一个 callback: { sub in dataStore.settings.proSubscription = sub }.
//   - 这样 SubscriptionManager 可以单独测试, 不依赖 DataStore.
//
// Product ID 跟 SubscriptionTier 映射:
//   - com.yumowu.maso.pro.monthly  → .monthly
//   - com.yumowu.maso.pro.yearly   → .yearly
//   - com.yumowu.maso.pro.lifetime → .lifetime
@Observable
@MainActor
final class SubscriptionManager {

    // MARK: - Public state

    /// StoreKit load 出来的 3 个 product. 顺序保证: monthly, yearly, lifetime.
    /// 失败 / 还在加载时是 [], UI 用 isEmpty 判断展示 placeholder.
    var products: [Product] = []

    /// 当前订阅状态 — 从 Transaction.currentEntitlements 派生. nil = free.
    /// 跟 DataStore.settings.proSubscription 同步 (通过 onEntitlementChange callback).
    var currentSubscription: ProSubscription?

    /// load products 是否完成 (即使是空数组也算完成 — 区分 "还没尝试" vs "尝试过但拿不到").
    var hasLoadedProducts: Bool = false
    var isLoadingProducts = false
    /// Returning subscribers must be checked before a first-run upgrade prompt.
    var hasCheckedEntitlements: Bool = false

    /// 最近一次操作的错误信息 — 给 UI 弹 alert 用. 用户 dismiss 后清空.
    var lastError: String?

    // MARK: - Product IDs

    static let monthlyProductID = "com.yumowu.maso.pro.monthly"
    static let yearlyProductID = "com.yumowu.maso.pro.yearly"
    static let lifetimeProductID = "com.yumowu.maso.pro.lifetime"

    static let subscriptionProductIDs = [monthlyProductID, yearlyProductID]

    static let allProductIDs: [String] = [
        monthlyProductID, yearlyProductID, lifetimeProductID
    ]

    // MARK: - Private

    /// 后台 Transaction.updates 监听 task.
    /// @ObservationIgnored — 它不是 UI 状态 (deinit 里 cancel), 不进 Observation 追踪;
    /// 也避开 @Observable 对 mutable stored property 加 nonisolated 的限制.
    @ObservationIgnored private var updateListenerTask: Task<Void, Never>?

    /// entitlement 变化时回调 (MasoApp 注入, 写 DataStore).
    @ObservationIgnored private let productLoader: @MainActor () async throws -> [Product]
    @ObservationIgnored private var productLoadTask: Task<Void, Never>?

    private var onEntitlementChange: ((ProSubscription?) -> Void)?

    // MARK: - Init / Deinit

    init(productLoader: @escaping @MainActor () async throws -> [Product] = {
        try await Product.products(for: SubscriptionManager.allProductIDs)
    }) {
        self.productLoader = productLoader
        // 立刻起监听 — Transaction.updates 是 AsyncSequence, 后台 task 持续消费.
        updateListenerTask = listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Configuration

    /// MasoApp init 后调一次, 注入 entitlement 变化的 callback (写 DataStore).
    /// 立即触发一次 refresh, 把当前 StoreKit 状态同步到 DataStore.
    func configure(onChange: @escaping (ProSubscription?) -> Void) {
        self.onEntitlementChange = onChange
        Task {
            // Entitlements must not wait for a product-network request.
            await refreshEntitlements()
            await loadProducts()
        }
    }

    // MARK: - Product loading

    /// App startup and paywall share one in-flight request. Loading failures are
    /// presented by the paywall, never as a stale purchase/restore error.
    func loadProducts() async {
        if let productLoadTask { await productLoadTask.value; return }
        let task = Task { @MainActor in
            isLoadingProducts = true
            defer { isLoadingProducts = false; hasLoadedProducts = true }
            do {
                let fetched = try await productLoader()
#if DEBUG
                print("[Masso StoreKit] requested=\(Self.allProductIDs.joined(separator: ",")) returned=\(fetched.map(\.id).joined(separator: ","))")
                if fetched.isEmpty && ProcessInfo.processInfo.arguments.contains("--diagnose-live-storekit") {
                    let storefront = await Storefront.current
                    print("[Masso StoreKit] storefront=\(storefront?.countryCode ?? "unavailable")")
                    for identifier in Self.subscriptionProductIDs {
                        do {
                            let result = try await Product.products(for: [identifier])
                            print("[Masso StoreKit] independent=\(identifier) returned=\(result.map(\.id).joined(separator: ","))")
                        } catch {
                            let failure = error as NSError
                            print("[Masso StoreKit] independent=\(identifier) error=\(failure.domain):\(failure.code)")
                        }
                    }
                }
#endif
                let order = Dictionary(uniqueKeysWithValues: Self.allProductIDs.enumerated().map { ($1, $0) })
                products = fetched.sorted { (order[$0.id] ?? 99) < (order[$1.id] ?? 99) }
            } catch {
#if DEBUG
                let failure = error as NSError
                print("[Masso StoreKit] product load failed domain=\(failure.domain) code=\(failure.code) description=\(failure.localizedDescription)")
#endif
                // Preserve previously fetched products; an empty result is handled
                // by the visible paywall with a retryable system notice.
            }
        }
        productLoadTask = task
        await task.value
        productLoadTask = nil
    }

    func product(for tier: SubscriptionTier) -> Product? {
        let id: String = {
            switch tier {
            case .monthly:  return Self.monthlyProductID
            case .yearly:   return Self.yearlyProductID
            case .lifetime: return Self.lifetimeProductID
            }
        }()
        return products.first(where: { $0.id == id })
    }

    /// 该 tier 当前用户是否还有资格领取 introductory offer (7 天试用).
    /// 关键: introductoryOffer != nil 只说明"产品配了试用", 不代表"此人能领" —— 续订/已用过
    /// 试用的用户领不到, 给他们看"免费试用"会被立即扣费 (2.3.2/3.1.2 拒审 + 退款投诉).
    /// 非订阅 (lifetime) / 无试用配置 / 无网 → false.
    func isEligibleForIntroOffer(_ tier: SubscriptionTier) async -> Bool {
        guard tier != .lifetime,
              let sub = product(for: tier)?.subscription,
              sub.introductoryOffer != nil else { return false }
        return await sub.isEligibleForIntroOffer
    }

    // MARK: - Purchase

    /// 购买入口 — 返回 true 表示成功且已写 entitlement; false 表示用户取消 / pending / 失败.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let options: Set<Product.PurchaseOption> = PartnerReferral.appAccountToken.map { [.appAccountToken($0)] } ?? []
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                // verification 用 .verified / .unverified 区分受信任的 transaction.
                // 不受信任的不要写 entitlement (可能是越狱 / Cydia tweak 伪造的 receipt).
                let transaction = try checkVerified(verification)
                PartnerReferral.report(verification)
                await refreshEntitlements()
                await transaction.finish()
                return currentSubscription != nil
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy / SCA 等异步流程 — Transaction.updates 后续会推
                lastError = NSLocalizedString("Purchase pending approval.", comment: "")
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore

    /// "Restore Purchases" — 用户换设备 / 重装 app 后点这个把之前买过的 entitlement 拉回来.
    /// AppStore.sync() 是 force-refresh, 比单纯 currentEntitlements 强 — 会跟 server 对账.
    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if currentSubscription == nil {
                lastError = NSLocalizedString("No active subscription found", comment: "")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Entitlement refresh

    /// 扫所有 currentEntitlements, 选出最有利的一个 (lifetime > yearly > monthly), 更新本机状态.
    func refreshEntitlements() async {
        var best: ProSubscription? = nil
        for await result in Transaction.currentEntitlements {
            PartnerReferral.report(result)
            guard case .verified(let transaction) = result else { continue }
            // 过期 transaction 跳过 — currentEntitlements 通常已经过滤, 但保险起见再 check.
            var validUntil = transaction.expirationDate
            if let expiration = validUntil, expiration <= Date() {
                guard let group = transaction.subscriptionGroupID,
                      let statuses = try? await Product.SubscriptionInfo.status(for: group),
                      let grace = statuses.compactMap({ status -> Date? in
                          guard status.state == .inGracePeriod,
                                case .verified(let info) = status.renewalInfo,
                                case .verified(let entitled) = status.transaction,
                                entitled.originalID == transaction.originalID,
                                entitled.revocationDate == nil else { return nil }
                          return info.gracePeriodExpirationDate
                      }).filter({ $0 > Date() }).max() else { continue }
                validUntil = grace
            }
            // 退款 / 撤销 的 transaction 跳过.
            if transaction.revocationDate != nil || transaction.isUpgraded { continue }

            let tier: SubscriptionTier
            switch transaction.productID {
            case Self.monthlyProductID:  tier = .monthly
            case Self.yearlyProductID:   tier = .yearly
            case Self.lifetimeProductID: tier = .lifetime
            default: continue
            }

            let candidate = ProSubscription(
                tier: tier,
                startedAt: transaction.originalPurchaseDate,
                renewsAt: validUntil  // includes verified billing grace; lifetime = nil
            )
            best = pickBetter(best, candidate)
        }
        currentSubscription = best
        onEntitlementChange?(best)
        hasCheckedEntitlements = true
    }

    /// 选优 — lifetime > yearly > monthly. 同 tier 取 renewsAt 更晚的.
    private func pickBetter(_ a: ProSubscription?, _ b: ProSubscription) -> ProSubscription {
        guard let a else { return b }
        let aRank = tierRank(a.tier)
        let bRank = tierRank(b.tier)
        if bRank > aRank { return b }
        if bRank < aRank { return a }
        // 同 tier — 取 renewsAt 更晚的 (覆盖更长). lifetime 是 nil, 视作 +∞.
        let aDate = a.renewsAt ?? Date.distantFuture
        let bDate = b.renewsAt ?? Date.distantFuture
        return bDate > aDate ? b : a
    }

    private func tierRank(_ t: SubscriptionTier) -> Int {
        switch t {
        case .monthly:  return 1
        case .yearly:   return 2
        case .lifetime: return 3
        }
    }

    // MARK: - Verification helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Transaction listener

    /// 后台监听 Transaction.updates — 跨设备购买 / 自动续费 / refund / family share 等场景的 push.
    /// 一旦收到, 校验后 refresh entitlements (顺手 finish 掉 transaction).
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await PartnerReferral.report(result)
                await self?.refreshEntitlements()
                await transaction.finish()
            }
        }
    }
}

enum SubscriptionError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return NSLocalizedString("Purchase verification failed. Try again or contact support.", comment: "")
        }
    }
}

// Referral accounting is optional and never gates StoreKit delivery or legacy rights.
@MainActor
enum PartnerReferral {
    static func isCancellation(_ error: Error) -> Bool {
        if let error = error as? StoreKitError, case .userCancelled = error { return true }
        let error = error as NSError
        return error.domain == SKErrorDomain && error.code == SKError.paymentCancelled.rawValue
    }

    private static let base = URL(string: "https://ai.replai.sh/partners/api/app/")!
    private static let service = "com.yumowu.maso.partner-referral"
    private static let account = "installation"
    private static var sent = Set<String>()
    private static var registration: Task<String, Error>?

    struct Offer: Decodable {
        let code: String
        let offer: String
        let redemptionURL: URL
    }
    enum Failure: Error {
        case unavailable, identity
        case keychain(OSStatus)
        case service(Int, String)
    }

    /// Diagnostics contain only a stage/status, never credentials, codes or response bodies.
    static func diagnostic(for error: Error) -> String {
        if let failure = error as? Failure {
            switch failure {
            case .unavailable: return "referral: unavailable"
            case .identity: return "referral: missing installation identity"
            case .keychain(let status): return "referral: keychain \(status)"
            case .service(let status, let code): return "referral: HTTP \(status) \(code)"
            }
        }
        let value = error as NSError
        return "referral: \(value.domain) \(value.code)"
    }

    private static func credential() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let bytes = item as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
    static var appAccountToken: UUID? {
        guard UserDefaults.standard.bool(forKey: "maso.referral.bound") else { return nil }
        return credential()?.split(separator: ".").first.flatMap { UUID(uuidString: String($0)) }
    }
    private static func register() async throws -> String {
        if let saved = credential() { return saved }
        if let registration { return try await registration.value }
        let task = Task { @MainActor () async throws -> String in
            let bytes = try await request("register", payload: [:], authenticated: false)
            struct Identity: Decodable { let credential: String }
            let value = try JSONDecoder().decode(Identity.self, from: bytes).credential
            guard let first = value.split(separator: ".").first, UUID(uuidString: String(first)) != nil else { throw Failure.identity }
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData as String: Data(value.utf8)]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw Failure.keychain(status) }
            return value
        }
        registration = task
        defer { registration = nil }
        return try await task.value
    }
    private static func request(_ path: String, payload: [String: String], authenticated: Bool = true) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token = credential() else { throw Failure.identity }
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (bytes, response) = try await URLSession.shared.data(for: req)
        guard let response = response as? HTTPURLResponse else { throw Failure.unavailable }
        guard response.statusCode == 200 else {
            let known = ["invalid_code", "code_unavailable", "unauthorized", "referral_already_bound", "referral_expired", "rate_limited"]
            let code = (try? JSONSerialization.jsonObject(with: bytes) as? [String: String])?["error"]
            throw Failure.service(response.statusCode, code.flatMap { known.contains($0) ? $0 : nil } ?? "service_unavailable")
        }
        return bytes
    }
    static func claim(_ code: String) async throws -> Offer {
        _ = try await register()
        let bytes = try await request("claim", payload: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
        let offer = try JSONDecoder().decode(Offer.self, from: bytes)
        guard offer.redemptionURL.scheme == "https", offer.redemptionURL.host == "apps.apple.com",
              offer.redemptionURL.path == "/redeem" else { throw Failure.unavailable }
        UserDefaults.standard.set(true, forKey: "maso.referral.bound")
        return offer
    }
    static func report(_ result: VerificationResult<StoreKit.Transaction>) {
        guard UserDefaults.standard.bool(forKey: "maso.referral.bound"), credential() != nil, case .verified(let transaction) = result,
              SubscriptionManager.subscriptionProductIDs.contains(transaction.productID) else { return }
        let key = "\(transaction.id):\(transaction.revocationDate?.timeIntervalSince1970 ?? 0)"
        guard !sent.contains(key) else { return }
        // A failed upload is retried when StoreKit refreshes on foreground/restore.
        sent.insert(key)
        Task { @MainActor in
            do {
                var payload = ["signedTransaction": result.jwsRepresentation,
                    "environment": transaction.environment == .sandbox ? "Sandbox" : "Production"]
                if let group = transaction.subscriptionGroupID,
                   let statuses = try? await Product.SubscriptionInfo.status(for: group),
                   let status = statuses.first(where: { status in
                       guard case .verified(let current) = status.transaction else { return false }
                       return current.originalID == transaction.originalID
                   }), case .verified = status.renewalInfo {
                    payload["signedRenewal"] = status.renewalInfo.jwsRepresentation
                }
                let bytes = try await request("transaction", payload: payload)
                struct Report: Decodable { let attributed: Bool }
                if try JSONDecoder().decode(Report.self, from: bytes).attributed == false { sent.remove(key) }
            } catch { sent.remove(key) }
        }
    }
}
