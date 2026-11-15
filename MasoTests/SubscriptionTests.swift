import XCTest
import StoreKit
import StoreKitTest
import SwiftUI
@testable import Maso

@MainActor
final class SubscriptionTests: XCTestCase {
    /// Explicitly opt-in on the owner's test phone; normal test runs never hit production.
    func testLiveReferralCodeOnOwnerTestDevice() async throws {
        guard ProcessInfo.processInfo.environment["MASO_REFERRAL_LIVE_PROBE"] == "1" else {
            throw XCTSkip("Requires explicit live referral probe")
        }
        do {
            let offer = try await PartnerReferral.claim("YUMOREDEEM20")
            XCTAssertEqual(offer.code, "YUMOREDEEM20")
            XCTAssertEqual(offer.redemptionURL.host, "apps.apple.com")
            print("REFERRAL_LIVE_PROBE: claim succeeded; no redemption or purchase initiated")
        } catch {
            XCTFail("REFERRAL_LIVE_PROBE: " + PartnerReferral.diagnostic(for: error))
        }
    }

    func testReferralDiagnosticDoesNotEchoResponseOrCredentials() {
        XCTAssertEqual(PartnerReferral.diagnostic(for: URLError(.cannotFindHost)), "referral: NSURLErrorDomain -1003")
        XCTAssertEqual(PartnerReferral.diagnostic(for: PartnerReferral.Failure.keychain(-25299)), "referral: keychain -25299")
    }

    func testReferralRedemptionCancellationIsNotAServiceFailure() {
        XCTAssertTrue(PartnerReferral.isCancellation(StoreKitError.userCancelled))
        XCTAssertTrue(PartnerReferral.isCancellation(NSError(domain: SKErrorDomain, code: SKError.paymentCancelled.rawValue)))
        XCTAssertFalse(PartnerReferral.isCancellation(URLError(.notConnectedToInternet)))
        XCTAssertFalse(PartnerReferral.isCancellation(NSError(domain: SKErrorDomain, code: SKError.unknown.rawValue)))
    }

    func testFreeTierDoesNotDependOnStorefrontAndKeepsHistory() {
        for country in [nil, "USA", "CHN", "JPN", "DEU"] as [String?] {
            var settings = UserSettings()
            settings.appStoreCountry = country
            XCTAssertFalse(settings.isPro)
            XCTAssertTrue(settings.showProUpsell)
            let data = DataStore(exercises: [], plans: [], sets: [], settings: settings)
            XCTAssertTrue(data.canSaveMorePlans)
            XCTAssertEqual(DataStore.freeSavedPlansLimit, 5)
        }
    }

    func testExpiredAndLegacyEntitlements() {
        var settings = UserSettings()
        settings.proSubscription = .init(tier: .monthly, startedAt: .now, renewsAt: Date(timeIntervalSinceNow: -10))
        XCTAssertFalse(settings.isPro)
        settings.proSubscription = .init(tier: .yearly, startedAt: .now, renewsAt: Date(timeIntervalSinceNow: 3600))
        XCTAssertTrue(settings.isPro)
        settings.proSubscription = nil
        settings.polarProActive = true
        settings.polarValidatedAt = .now
        XCTAssertTrue(settings.isPro, "Earlier paid web subscribers retain access")
        settings.polarValidatedAt = Date(timeIntervalSinceNow: -PolarEntitlement.offlineGrace - 1)
        XCTAssertFalse(settings.isPro)
        settings.polarValidatedAt = .now
        settings.polarExpiresAt = Date(timeIntervalSinceNow: -1)
        XCTAssertFalse(settings.isPro)
    }

    func testStoreKitPurchaseRecreationExpiryAndRefund() async throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Maso", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let manager = SubscriptionManager()
        await manager.loadProducts()
        let monthly = try XCTUnwrap(manager.product(for: .monthly))
        XCTAssertEqual(monthly.price, Decimal(string: "4.99"))
        XCTAssertEqual(monthly.subscription?.introductoryOffer?.paymentMode, .freeTrial)
        let eligible = await manager.isEligibleForIntroOffer(.monthly)
        XCTAssertTrue(eligible)
        let purchased = await manager.purchase(monthly)
        XCTAssertTrue(purchased)
        XCTAssertEqual(manager.currentSubscription?.tier, .monthly)

        // A new manager must restore from verified StoreKit history, not app JSON.
        let recreated = SubscriptionManager()
        await recreated.refreshEntitlements()
        XCTAssertEqual(recreated.currentSubscription?.tier, .monthly)
        await recreated.restore()
        XCTAssertNil(recreated.lastError)
        XCTAssertEqual(recreated.currentSubscription?.tier, .monthly,
                       "Restore Purchases must recover the verified subscription")
        try session.expireSubscription(productIdentifier: SubscriptionManager.monthlyProductID)
        let expired = try await waitForEntitlement(recreated) { $0 == nil }
        XCTAssertTrue(expired)
        XCTAssertNil(recreated.currentSubscription)

        let yearly = try XCTUnwrap(manager.product(for: .yearly))
        XCTAssertEqual(yearly.price, Decimal(string: "29.99"))
        let boughtYearly = await manager.purchase(yearly)
        XCTAssertTrue(boughtYearly)
        let yearlyTransaction = try XCTUnwrap(session.allTransactions().last(where: { $0.productIdentifier == SubscriptionManager.yearlyProductID }))
        try session.refundTransaction(identifier: yearlyTransaction.identifier)
        let refunded = try await waitForEntitlement(recreated) { $0 == nil }
        XCTAssertTrue(refunded)
        XCTAssertNil(recreated.currentSubscription)
    }

    func testRestoreWithoutSubscriptionReportsTheExistingFailure() async throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Maso", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let manager = SubscriptionManager()
        await manager.restore()
        XCTAssertNil(manager.currentSubscription)
        XCTAssertEqual(manager.lastError, "No active subscription found")
    }

    func testStoreKitCancelledAndFailedPurchasesDoNotUnlock() async throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Maso", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.resetToDefaultState(); session.clearTransactions() }
        let manager = SubscriptionManager()
        await manager.loadProducts()
        let monthly = try XCTUnwrap(manager.product(for: .monthly))

        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let cancelled = await manager.purchase(monthly)
        XCTAssertFalse(cancelled)
        XCTAssertNil(manager.currentSubscription)
        XCTAssertNil(manager.lastError, "A cancelled purchase must not display a failure alert")

        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        let failed = await manager.purchase(monthly)
        XCTAssertFalse(failed)
        XCTAssertNil(manager.currentSubscription)
        XCTAssertNotNil(manager.lastError)
    }

    func testStoreKitPendingApprovalRenewalAndCancellation() async throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Maso", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.disableDialogs = true
        session.askToBuyEnabled = true
        session.clearTransactions()
        defer { session.resetToDefaultState(); session.clearTransactions() }
        let manager = SubscriptionManager()
        await manager.loadProducts()
        let monthly = try XCTUnwrap(manager.product(for: .monthly))
        let pending = await manager.purchase(monthly)
        XCTAssertFalse(pending)
        XCTAssertNil(manager.currentSubscription, "Ask to Buy cannot unlock before approval")
        XCTAssertNotNil(manager.lastError)
        let deferred = try XCTUnwrap(session.allTransactions().last(where: { $0.pendingAskToBuyConfirmation }))
        try session.approveAskToBuyTransaction(identifier: deferred.identifier)

        // Exercise Transaction.updates, without explicitly refreshing entitlements.
        for _ in 0..<100 where manager.currentSubscription == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(manager.currentSubscription?.tier, .monthly)
        let originalExpiry = try XCTUnwrap(manager.currentSubscription?.renewsAt)
        try session.forceRenewalOfSubscription(productIdentifier: SubscriptionManager.monthlyProductID)
        let renewed = try await waitForEntitlement(manager) { ($0?.renewsAt ?? .distantPast) > originalExpiry }
        XCTAssertTrue(renewed)
        XCTAssertGreaterThan(try XCTUnwrap(manager.currentSubscription?.renewsAt), originalExpiry)

        let active = try XCTUnwrap(session.allTransactions().last(where: { $0.productIdentifier == SubscriptionManager.monthlyProductID }))
        try session.disableAutoRenewForTransaction(identifier: active.identifier)
        await manager.refreshEntitlements()
        XCTAssertEqual(manager.currentSubscription?.tier, .monthly, "Cancelling renewal must preserve access until expiry")
        try session.expireSubscription(productIdentifier: SubscriptionManager.monthlyProductID)
        let expired = try await waitForEntitlement(manager) { $0 == nil }
        XCTAssertTrue(expired)
        XCTAssertNil(manager.currentSubscription)
    }

    /// StoreKit's test service publishes mutations asynchronously, after the
    /// SKTestSession command returns. Wait for observable verified entitlements.
    private func waitForEntitlement(_ manager: SubscriptionManager,
                                    matching predicate: (ProSubscription?) -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            await manager.refreshEntitlements()
            if predicate(manager.currentSubscription) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
