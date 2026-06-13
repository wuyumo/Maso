import Foundation
import StoreKit
import Observation

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

    /// 最近一次操作的错误信息 — 给 UI 弹 alert 用. 用户 dismiss 后清空.
    var lastError: String?

    // MARK: - Product IDs

    static let monthlyProductID = "com.yumowu.maso.pro.monthly"
    static let yearlyProductID = "com.yumowu.maso.pro.yearly"
    static let lifetimeProductID = "com.yumowu.maso.pro.lifetime"

    static let allProductIDs: [String] = [
        monthlyProductID, yearlyProductID, lifetimeProductID
    ]

    // MARK: - Private

    /// 后台 Transaction.updates 监听 task.
    /// nonisolated(unsafe) — SubscriptionManager 整个 app lifetime 都活着 (MasoApp @State),
    /// deinit 实际上跑不到, 这个标记只是让编译器不抓 deinit / 非 isolated 上下文里的访问.
    private nonisolated(unsafe) var updateListenerTask: Task<Void, Never>?

    /// entitlement 变化时回调 (MasoApp 注入, 写 DataStore).
    private var onEntitlementChange: ((ProSubscription?) -> Void)?

    // MARK: - Init / Deinit

    init() {
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
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Product loading

    /// 从 StoreKit 拉 3 个 product. 失败不抛 — UI 用 hasLoadedProducts + products.isEmpty 判断.
    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            // 按 monthly → yearly → lifetime 排序, 保证 UI 顺序稳定 (StoreKit 返回顺序不保证).
            let order: [String: Int] = [
                Self.monthlyProductID: 0,
                Self.yearlyProductID: 1,
                Self.lifetimeProductID: 2,
            ]
            self.products = fetched.sorted { (order[$0.id] ?? 99) < (order[$1.id] ?? 99) }
            self.hasLoadedProducts = true
        } catch {
            self.hasLoadedProducts = true
            self.lastError = NSLocalizedString("Couldn't load subscription options. Try again later.", comment: "")
        }
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
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // verification 用 .verified / .unverified 区分受信任的 transaction.
                // 不受信任的不要写 entitlement (可能是越狱 / Cydia tweak 伪造的 receipt).
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return true
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
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Entitlement refresh

    /// 扫所有 currentEntitlements, 选出最有利的一个 (lifetime > yearly > monthly), 更新本机状态.
    func refreshEntitlements() async {
        var best: ProSubscription? = nil
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // 过期 transaction 跳过 — currentEntitlements 通常已经过滤, 但保险起见再 check.
            if let exp = transaction.expirationDate, exp < Date() { continue }
            // 退款 / 撤销 的 transaction 跳过.
            if transaction.revocationDate != nil { continue }

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
                renewsAt: transaction.expirationDate  // lifetime = nil
            )
            best = pickBetter(best, candidate)
        }
        currentSubscription = best
        onEntitlementChange?(best)
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
                await transaction.finish()
                await self?.refreshEntitlements()
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
