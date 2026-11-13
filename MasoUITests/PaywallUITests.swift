import XCTest
import StoreKitTest

@MainActor
final class PaywallUITests: XCTestCase {
    private var store: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Maso", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: url)
        store.disableDialogs = true
        store.clearTransactions()
    }

    override func tearDownWithError() throws { store.clearTransactions(); store = nil }

    func testWelcomeCanBeClosedAndDoesNotRepeatWhenRootReappears() throws {
        let app = launch("welcome")
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 15))
        capture(app, "welcome-top")
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.staticTexts["paywall.test.welcome-state"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["paywall.test.welcome-state"].label, "seen")
        app.buttons["paywall.test.recreate"].tap()
        XCTAssertFalse(app.buttons["paywall.close"].exists)
    }

    func testNativeDeviceImageAllowancePersistsResultAndSecondTaskGates() throws {
        for language in ["en", "zh-Hans"] {
            let app = launch("device-quota", language: language)
            let run = app.buttons["quota.fixture.run"]
            XCTAssertTrue(run.waitForExistence(timeout: 15))
            run.tap()
            let calls = app.staticTexts["quota.fixture.calls"]
            let one = NSPredicate(format: "label == '1'")
            expectation(for: one, evaluatedWith: calls); waitForExpectations(timeout: 10)
            run.tap()
            XCTAssertEqual(calls.label, "1", "Denied second image must not execute the model closure")
            capture(app, language + "-device-image-gate")
            app.terminate()
        }
    }

    func testNativeExistingUserNoticeIsReachableWithLargeText() throws {
        let app = launch("device-notice",language:"zh-Hans",largeType:true,narrow:true)
        XCTAssertTrue(app.staticTexts["ai.policy.test.basic-content"].waitForExistence(timeout:10))
        app.buttons["ai.policy.notice.details"].tap()
        XCTAssertTrue(app.staticTexts["ai.policy.device-scope"].waitForExistence(timeout:10))
        capture(app,"zh-50-device-details-large")
    }

    func testDeviceNoticeAndDetailsContrastMatrixNeverBlocksBasicApp() throws {
        for language in ["en","zh-Hans"] {
            for light in [false,true] {
                for large in [false,true] {
                    let app = launch("device-notice",language:language,largeType:large,narrow:large,light:light,increasedContrast:large)
                    let name = language + (light ? "-light" : "-dark") + (large ? "-large-increased" : "-normal")
                    XCTAssertTrue(app.staticTexts["ai.policy.test.basic-content"].waitForExistence(timeout:10))
                    let details = app.buttons["ai.policy.notice.details"]; XCTAssertTrue(details.isHittable); XCTAssertGreaterThanOrEqual(details.frame.height + 0.001,44)
                    let close = app.buttons["ai.policy.notice.dismiss"]; XCTAssertGreaterThanOrEqual(close.frame.height + 0.001,44)
                    capture(app,name + "-50-notice")
                    details.tap()
                    XCTAssertTrue(app.staticTexts["ai.policy.device-scope"].waitForExistence(timeout:10))
                    capture(app,name + "-50-details")
                    app.buttons["ai.policy.details.close"].tap()
                    app.buttons["ai.policy.notice.dismiss"].tap()
                    XCTAssertTrue(app.staticTexts["ai.policy.test.dismissed"].waitForExistence(timeout:5))
                    XCTAssertFalse(app.buttons["ai.policy.notice.details"].exists)
                    capture(app,name + "-50-dismissed")
                    app.terminate()
                }
            }
        }
    }

    func testArabicPaywallActionsHaveRealNativeAndStoreKitFixtureOutcomes() throws {
        var app = launch("welcome",language:"ar",largeType:true,narrow:true)
        let free = app.buttons["paywall.continue-free"]; try reveal(free,app:app); free.tap()
        let seen = app.staticTexts["paywall.test.welcome-state"]
        XCTAssertTrue(seen.waitForExistence(timeout:10)); XCTAssertEqual(seen.label,"seen")
        capture(app,"ar-50-continue-free-closed-welcome")
        app.terminate()
        app = launch("upgrade",language:"ar",largeType:true,narrow:true)
        let referral = app.buttons["paywall.referral"]; try reveal(referral,app:app); referral.tap()
        XCTAssertTrue(app.textFields["referral.code"].waitForExistence(timeout:10))
        capture(app,"ar-50-referral-sheet-open"); app.buttons["referral.close"].tap()
        let purchase = app.buttons["paywall.purchase"]; try reveal(purchase,app:app); purchase.tap()
        let bought = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in !self.store.allTransactions().isEmpty },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[bought],timeout:15),.completed)
        let transactions = Set(store.allTransactions().map { String($0.identifier) })
        XCTAssertFalse(transactions.isEmpty); capture(app,"ar-50-purchased-storekit-fixture")
        let restore = app.buttons["paywall.restore"]; try reveal(restore,app:app); restore.tap()
        XCTAssertEqual(Set(store.allTransactions().map { String($0.identifier) }),transactions,"Restore must not buy again")
        capture(app,"ar-50-restore-after-native-tap")
        let proof = XCTAttachment(string:"Real native AX taps: Continue free closed welcome; referral opened text field; CTA created verified StoreKit-test transaction(s) " + transactions.sorted().joined(separator:",") + "; restore tap retained transaction identity. All SKTestSession fixtures, no real charge.")
        proof.name = "ar-50-action-outcome-proof"; proof.lifetime = .keepAlways; add(proof)
        app.terminate()
    }

    // Requires the real OS simctl content_size setting documented in this release receipt.
    func testDetailsAtActualSystemAccessibilitySizeCanScrollAndClose() throws {
        for language in ["en","zh-Hans"] {
            for light in [false,true] {
                let app = launch("device-notice",language:language,largeType:true,narrow:true,light:light,increasedContrast:true)
                XCTAssertTrue(app.buttons["ai.policy.notice.details"].waitForExistence(timeout:10))
                app.buttons["ai.policy.notice.details"].tap()
                let name = language + (light ? "-light" : "-dark") + "-50-system-AX"
                XCTAssertTrue(app.staticTexts["ai.policy.device-scope"].waitForExistence(timeout:10))
                capture(app,name + "-0-top")
                let limits = app.staticTexts["ai.sources.limits"]
                for page in 1...18 {
                    if limits.exists && limits.isHittable && limits.frame.height > 0 && limits.frame.maxY <= app.frame.maxY - 20 { break }
                    app.swipeUp(); capture(app,name + "-" + String(page))
                }
                XCTAssertTrue(limits.exists && limits.isHittable)
                XCTAssertLessThanOrEqual(limits.frame.maxY,app.frame.maxY - 20)
                app.buttons["ai.policy.details.close"].tap()
                app.buttons["ai.policy.notice.dismiss"].tap()
                XCTAssertTrue(app.staticTexts["ai.policy.test.basic-content"].exists)
                XCTAssertTrue(app.staticTexts["ai.policy.test.dismissed"].exists)
                capture(app,name + "-dismissed")
                app.terminate()
            }
        }
    }

    func testProAIHasNoReminderAndFourthCustomCreationRequiresPro() throws {
        var app = launch("pro")
        XCTAssertTrue(app.buttons["paywall.test.run-ai"].waitForExistence(timeout: 10))
        app.buttons["paywall.test.run-ai"].tap()
        XCTAssertEqual(app.staticTexts["paywall.test.calls"].label, "1")
        XCTAssertFalse(app.buttons["paywall.close"].exists)
        app.terminate()
        app = launch("custom-full")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10))
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.textFields.element(boundBy: 0).waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields.element(boundBy: 0).value as? String, "My test exercise")
    }

    func testRealPricesTrialAndFourLanguageLayouts() throws {
        for language in ["en", "zh-Hans", "de", "ar"] {
            let app = launch("upgrade", language: language)
            XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10))
            capture(app, language + "-top")
            let yearly = app.buttons["paywall.plan.yearly"]
            try reveal(yearly, app: app)
            XCTAssertTrue(yearly.label.contains("29.99") || yearly.label.contains("29,99"))
            capture(app, language + "-plans")
            let free = app.buttons["paywall.continue-free"]
            try reveal(free, app: app)
            XCTAssertTrue(app.buttons["paywall.purchase"].exists)
            XCTAssertTrue(app.staticTexts["paywall.renewal"].exists)
            if language == "en" {
                let trial = NSPredicate(format: "label == %@", "Start 7-day free trial")
                expectation(for: trial, evaluatedWith: app.buttons["paywall.purchase"])
                waitForExpectations(timeout: 10)
                XCTAssertTrue(app.staticTexts["paywall.renewal"].label.contains("7 days free, then"))
            }
            capture(app, language + "-purchase")
            app.terminate()
        }
    }

    func testAccessibleTypeKeepsPurchaseRestoreAndFreeExitReachable() throws {
        let app = launch("upgrade", language: "de", largeType: true)
        try reveal(app.buttons["paywall.plan.yearly"], app: app)
        capture(app, "de-accessibility-plans")
        try reveal(app.buttons["paywall.restore"], app: app)
        XCTAssertTrue(app.buttons["paywall.continue-free"].exists)
        capture(app, "de-accessibility-footer")
    }

    func testFullScrollGermanAndArabicAccessibilityLayoutShowsAllSections() throws {
        for language in ["de","ar"] {
            let app = launch("upgrade",language:language,largeType:true,narrow:true)
            XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout:15))
            capture(app,language + "-49-fullscroll-0-top")
            for index in 1...14 {
                if app.buttons["paywall.restore"].isHittable { break }
                app.swipeUp(); capture(app,language + "-49-fullscroll-" + String(index))
            }
            for id in ["purchase","referral","continue-free","restore"] {
                let button = app.buttons["paywall." + id]
                try reveal(button,app:app); XCTAssertGreaterThanOrEqual(button.frame.height,44)
                capture(app,language + "-49-reachable-" + id)
            }
            app.swipeUp(); capture(app,language + "-49-terms-footer")
            app.terminate()
        }
    }
    func testSourceLinkHelpIsHonestAndReachableInEnglishChineseAndArabicLargeType() throws {
        for language in ["en","zh-Hans","zh-Hant","de","fr","es","it","pt-BR","ru","ja","ko","ar"] {
            let app = launch("device-usage",language:language,largeType:language == "ar",narrow:language == "ar")
            let intro = app.staticTexts["ai.sources.intro"]; try reveal(intro,app:app)
            capture(app,language + "-source-help-intro")
            if language == "ar" { app.swipeUp(); capture(app,language + "-source-help-middle") }
            let hosts = app.staticTexts["ai.sources.hosts"]; try reveal(hosts,app:app)
            for host in ["strongerbyscience.com","muscleandstrength.com","strengthlog.com","hevyapp.com","exrx.net"] { XCTAssertTrue(hosts.label.contains(host)) }
            let video = app.staticTexts["ai.sources.video-limit"]; try reveal(video,app:app)
            XCTAssertTrue(video.label.contains("YouTube")); XCTAssertTrue(video.label.contains("Bilibili"))
            if language == "ar" { app.swipeUp(); capture(app,language + "-source-help-video-scroll") }
            let limits = app.staticTexts["ai.sources.limits"]; try reveal(limits,app:app)
            XCTAssertTrue(limits.label.contains("HTTPS")); XCTAssertTrue(limits.label.contains("120"))
            for _ in 0..<4 where limits.frame.maxY > app.frame.maxY - 20 { app.swipeUp() }
            XCTAssertLessThanOrEqual(limits.frame.maxY,app.frame.maxY - 20,"Complete final disclosure must be reachable above the bottom safe area")
            capture(app,language + "-source-help-limits")
            app.terminate()
        }
    }
    func testNativeRecoverySnapshotAndFullAcquiredTextAreReadable() throws {
        for language in ["en","zh-Hans"] {
            let app = launch("device-usage",language:language)
            let result = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Synthetic saved text result")).firstMatch
            try reveal(result,app:app); result.tap()
            let details = app.buttons["ai.result.details"]
            XCTAssertTrue(details.waitForExistence(timeout:10)); details.tap()
            let payload = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Entire acquired text fixture")).firstMatch
            capture(app,language + "-49-saved-result-details-open")
            if !payload.waitForExistence(timeout:5) { print("SYNTHETIC REPLAY DEBUG: " + app.debugDescription) }
            XCTAssertTrue(payload.exists); XCTAssertTrue(payload.label.contains("Entire acquired text fixture"))
            capture(app,language + "-49-full-saved-result")
            app.navigationBars.buttons.element(boundBy:0).tap()
            for _ in 0..<3 { app.swipeDown() }
            let snapshot = app.buttons["recovery.snapshot.preview"]
            try reveal(snapshot,app:app); snapshot.tap()
            XCTAssertTrue(app.staticTexts["recovery.snapshot.timestamp"].waitForExistence(timeout:10))
            capture(app,language + "-49-recovery-snapshot")
            app.terminate()
        }
    }

    func testReferralSheetReachabilityAndCancellationInThreeLanguages() throws {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("upgrade", language: language)
            let entry = app.buttons["paywall.referral"]
            try reveal(entry, app: app)
            entry.tap()
            let code = app.textFields["referral.code"]
            XCTAssertTrue(code.waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["referral.check"].isEnabled)
            code.tap(); code.typeText("ALEX20")
            XCTAssertTrue(app.buttons["referral.check"].isEnabled)
            XCTAssertFalse(app.buttons["referral.redeem"].exists)
            capture(app, language + "-referral")
            app.buttons["referral.close"].tap()
            XCTAssertTrue(app.buttons["paywall.referral"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testReferralFromHomeSettingsKeepsParentNavigationInThreeLanguages() throws {
        for language in ["en", "zh-Hans", "ar"] {
            let app = launch("banner", language: language)
            let settings = app.buttons["home.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            settings.tap()
            let entry = app.buttons["settings.referral"]
            for _ in 0..<2 {
                XCTAssertTrue(entry.waitForExistence(timeout: 8))
                entry.tap()
                XCTAssertTrue(app.textFields["referral.code"].waitForExistence(timeout: 8))
                capture(app, language + "-settings-referral")
                app.buttons["referral.close"].tap()
                XCTAssertTrue(entry.waitForExistence(timeout: 5))
                XCTAssertTrue(entry.isHittable)
                XCTAssertFalse(settings.isHittable)
            }
            app.terminate()
        }
    }

    func testFreeProDetailsAreHonestAboutCurrentlyEffectiveAIAndPreservedData() throws {
        for language in ["en", "zh-Hans", "de", "ar"] {
            let app = launch("upgrade", language: language)
            let details = app.buttons["paywall.policy-details"]
            try reveal(details, app: app)
            details.tap()
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["paywall.policy-preview-warning"].exists)
            XCTAssertTrue(app.staticTexts["paywall.policy-foundation"].exists)
            XCTAssertTrue(app.staticTexts["ai.policy.device-scope"].exists)
            capture(app, language + "-effective-rights-details")
            app.terminate()
        }
    }

    func testCompactBenefitsAndGroupedActionsInEnglishAndChinese() throws {
        for language in ["en", "zh-Hans"] {
            let app = launch("upgrade", language: language)
            XCTAssertTrue(app.buttons["paywall.plan.yearly"].waitForExistence(timeout: 15))
            for id in ["plans", "progress", "recovery"] {
                XCTAssertEqual(app.staticTexts.matching(identifier: "paywall.benefit." + id).count, 1)
            }
            capture(app, language + "-compact-yearly")
            let monthly = app.buttons["paywall.plan.monthly"]
            try reveal(monthly, app: app)
            monthly.tap()
            XCTAssertTrue(monthly.isSelected)
            XCTAssertFalse(app.buttons["paywall.plan.yearly"].isSelected)
            XCTAssertTrue(monthly.label.lowercased().contains(language == "en" ? "renews" : "自动"))
            XCTAssertFalse(app.buttons["paywall.plan.yearly"].label.lowercased().contains(language == "en" ? "renews" : "自动"))
            capture(app, language + "-compact-monthly")
            for id in ["referral", "continue-free", "restore"] {
                let button = app.buttons["paywall." + id]
                try reveal(button, app: app)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            }
            capture(app, language + "-compact-actions")
            app.terminate()
        }
    }

    func testCompactNarrowLargeTypeKeepsDisclosuresAndActionsReachable() throws {
        for language in ["en", "zh-Hans", "de", "ar"] {
            let app = launch("upgrade", language: language, largeType: true, narrow: true)
            let yearly = app.buttons["paywall.plan.yearly"]
            try reveal(yearly, app: app)
            XCTAssertTrue(yearly.label.contains("29.99") || yearly.label.contains("29,99"))
            capture(app, language + "-compact-narrow-large-plan")
            for id in ["purchase", "referral", "continue-free", "restore"] {
                try reveal(app.buttons["paywall." + id], app: app)
            }
            if language == "ar" { XCTAssertEqual(app.buttons["paywall.restore"].label, "استعادة المشتريات") }
            capture(app, language + "-compact-narrow-large-actions")
            app.terminate()
        }
    }

    func testSelectedPlanDisclosureWithoutTrialEligibility() throws {
        _ = try store.buyProduct(productIdentifier: "com.yumowu.maso.pro.yearly")
        try store.expireSubscription(productIdentifier: "com.yumowu.maso.pro.yearly")
        let app = launch("upgrade")
        let yearly = app.buttons["paywall.plan.yearly"]
        try reveal(yearly, app: app)
        let subscribe = NSPredicate(format: "label == %@", "Subscribe")
        expectation(for: subscribe, evaluatedWith: app.buttons["paywall.purchase"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(yearly.label.lowercased().contains("renews"))
        XCTAssertFalse(yearly.label.contains("7 days free"))
        capture(app, "en-compact-no-trial")
    }

    func testPlanCardsKeepEqualHeightAndSinglePriceAcrossSelections() throws {
        let variants: [(String, Bool, Bool)] = [
            ("en", false, false), ("zh-Hans", false, false),
            ("de", false, false), ("ar", false, false),
            ("en", false, true), ("zh-Hans", true, true),
            ("de", true, true), ("ar", true, true)
        ]
        for (language, large, narrow) in variants {
            let app = launch("upgrade", language: language, largeType: large, narrow: narrow)
            let monthly = app.buttons["paywall.plan.monthly"]
            let yearly = app.buttons["paywall.plan.yearly"]
            XCTAssertTrue(yearly.waitForExistence(timeout: 15))
            let originalMonthly = monthly.frame.height
            let originalYearly = yearly.frame.height
            XCTAssertGreaterThan(originalMonthly, 44)
            XCTAssertEqual(originalMonthly, originalYearly, accuracy: 0.5)
            if !large { XCTAssertEqual(monthly.frame.minY, yearly.frame.minY, accuracy: 0.5) }
            let name = language + (large ? "-large" : "-normal") + (narrow ? "-320pt" : "")
            capture(app, name + "-equal-yearly")
            try reveal(monthly, app: app)
            monthly.tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: monthly)], timeout: 5) == .completed, "Monthly card selection must complete")
            XCTAssertEqual(monthly.frame.height, originalMonthly, accuracy: 0.5)
            XCTAssertEqual(yearly.frame.height, originalYearly, accuracy: 0.5)
            XCTAssertEqual(app.staticTexts.matching(identifier: "paywall.renewal").count, 1)
            capture(app, name + "-equal-monthly")
            try reveal(yearly, app: app)
            yearly.tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: yearly)], timeout: 5) == .completed, "Yearly card selection must complete")
            XCTAssertEqual(monthly.frame.height, originalMonthly, accuracy: 0.5)
            XCTAssertEqual(yearly.frame.height, originalYearly, accuracy: 0.5)
            for (card, dot, comma) in [(yearly, "29.99", "29,99"), (monthly, "4.99", "4,99")] {
                let price = card.label.contains(dot) ? dot : comma
                XCTAssertEqual(card.label.components(separatedBy: price).count - 1, 1, "Main price must appear exactly once per card")
            }
            let metrics: [String: Any] = ["variant": name,
                "monthlyHeight": originalMonthly, "yearlyHeight": originalYearly,
                "monthlyAfterSwitch": monthly.frame.height, "yearlyAfterSwitch": yearly.frame.height,
                "amountOccurrencesPerCard": 1]
            let encoded = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
            let text = String(decoding: encoded, as: UTF8.self)
            print("PAYWALL_CARD_METRICS " + text)
            let attachment = XCTAttachment(string: text)
            attachment.name = "card-metrics-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }


    func testRestorePurchaseIsTheOnlyTrailingStoreKitAction() throws {
        let labels = [
            "en": "Restore Purchase", "zh-Hans": "恢复购买", "zh-Hant": "恢復購買",
            "de": "Käufe wiederherstellen", "fr": "Restaurer les achats",
            "es": "Restaurar las compras", "it": "Ripristinare gli acquisti",
            "pt-BR": "Restaurar compras", "ru": "Восстановить покупки",
            "ja": "購入を復元する", "ko": "구매 복원", "ar": "استعادة المشتريات",
        ]
        let webLabels = [
            "en": "Restore web purchase", "zh-Hans": "恢复网页购买", "zh-Hant": "恢復網頁購買",
            "de": "Webkauf wiederherstellen", "fr": "Restaurer un achat web",
            "es": "Restaurar compra web", "it": "Ripristina acquisto web",
            "pt-BR": "Restaurar compra na web", "ru": "Восстановить покупку на сайте",
            "ja": "ウェブ購入を復元", "ko": "웹 구매 복원", "ar": "استعادة شراء الويب",
        ]
        for language in ["en", "zh-Hans", "zh-Hant", "de", "fr", "es", "it", "pt-BR", "ru", "ja", "ko", "ar"] {
            let crowded = ["de", "fr", "es", "it", "pt-BR", "ru", "ar"].contains(language)
            let app = launch("upgrade", language: language, largeType: crowded, narrow: crowded)
            let restore = app.buttons["paywall.restore"]
            let close = app.buttons["paywall.close"]
            XCTAssertTrue(restore.waitForExistence(timeout: 15))
            XCTAssertTrue(close.exists)
            XCTAssertEqual(app.buttons.matching(identifier: "paywall.restore").count, 1)
            XCTAssertEqual(restore.label, try XCTUnwrap(labels[language]))
            XCTAssertFalse(app.buttons["paywall.more"].exists)
            let webLabel = try XCTUnwrap(webLabels[language])
            XCTAssertFalse(app.buttons[webLabel].exists)
            XCTAssertFalse(app.staticTexts[webLabel].exists)
            XCTAssertFalse(app.staticTexts["Enter your activation code"].exists)
            XCTAssertFalse(app.textFields["XXXX-XXXX-XXXX"].exists)
            if language == "en" { XCTAssertFalse(app.buttons["Restore Purchases"].exists) }
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(bar.exists)
            XCTAssertLessThanOrEqual(restore.frame.maxY, bar.frame.maxY + 1)
            XCTAssertGreaterThanOrEqual(restore.frame.height, 44)
            let separation = language == "ar" ? close.frame.minX - restore.frame.maxX : restore.frame.minX - close.frame.maxX
            XCTAssertGreaterThan(separation, 0, "Restore Purchase must stay clear of Close in \(language)")
            if language == "ar" {
                XCTAssertLessThan(restore.frame.midX, close.frame.midX)
            } else {
                XCTAssertGreaterThan(restore.frame.midX, close.frame.midX)
            }
            try reveal(app.buttons["paywall.continue-free"], app: app)
            XCTAssertTrue(app.buttons["paywall.referral"].exists)
            XCTAssertTrue(app.buttons["paywall.terms"].exists)
            XCTAssertTrue(app.buttons["paywall.privacy"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "paywall.restore").count, 1)
            app.terminate()
        }
    }

    func testRestorePurchaseShowsLoadingThenStoreKitResultWithoutAnotherPurchase() throws {
        let app = launch("upgrade", restoreHold: true)
        let restore = app.buttons["paywall.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 15))
        XCTAssertEqual(restore.label, "Restore Purchase")
        XCTAssertTrue(restore.isEnabled)
        restore.tap()
        let release = app.buttons["paywall.restore.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 2), "Restore stays busy while the request is in flight")
        XCTAssertTrue(app.descendants(matching: .any)["paywall.restore.progress"].exists)
        XCTAssertFalse(app.alerts["Masso Pro"].exists)
        release.tap()
        let alert = app.alerts["Masso Pro"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["No active subscription found"].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 2))
        XCTAssertTrue(restore.isEnabled)

        let purchase = app.buttons["paywall.purchase"]
        try reveal(purchase, app: app)
        purchase.tap()
        let bought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.store.allTransactions().isEmpty }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [bought], timeout: 15), .completed)
        let transactions = Set(store.allTransactions().map { String($0.identifier) })
        XCTAssertFalse(transactions.isEmpty)
        restore.tap()
        let releaseAgain = app.buttons["paywall.restore.release"]
        XCTAssertTrue(releaseAgain.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["paywall.restore.progress"].exists)
        releaseAgain.tap()
        XCTAssertTrue(releaseAgain.waitForNonExistence(timeout: 5))
        XCTAssertEqual(Set(store.allTransactions().map { String($0.identifier) }), transactions, "Restore must call StoreKit without buying again")
        XCTAssertFalse(app.alerts["Masso Pro"].exists)
    }

    func testEnlargedBrandKeeps17ProInitialSubscribeVisibleWithoutScrolling() throws {
        for language in ["en","zh-Hans","de","ar"] {
            // Production Masso enforces dark appearance. A light-only Debug host is not the default product screen.
            let app = launch("upgrade",language:language)
            let yearly = app.buttons["paywall.plan.yearly"]
            XCTAssertTrue(yearly.waitForExistence(timeout:15))
            let purchase = app.buttons["paywall.purchase"]
            for selection in ["yearly","monthly","yearly"] {
                let card = app.buttons["paywall.plan." + selection]
                XCTAssertTrue(card.isHittable)
                card.tap()
                XCTAssertTrue(purchase.isHittable,"CTA must be hittable without scrolling")
                XCTAssertGreaterThanOrEqual(purchase.frame.minY, app.navigationBars.firstMatch.frame.maxY)
                XCTAssertLessThanOrEqual(purchase.frame.maxY,app.frame.maxY - 34,"Entire CTA above bottom safe area")
                capture(app,"51-" + language + "-initial-" + selection)
                print("PAYWALL51_CTA " + language + " " + selection + " " + String(describing: purchase.frame))
            }
            app.terminate()
        }
    }

    private func launch(_ scene: String, language: String = "en", largeType: Bool = false, narrow: Bool = false, light: Bool = false, increasedContrast: Bool = false, restoreHold: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.terminate()
        var environment = ["MASO_PAYWALL_UI_TEST_SCENE": scene,
                           "MASO_PAYWALL_LARGE_TYPE": largeType ? "1" : "0",
                           "MASO_PAYWALL_NARROW": narrow ? "1" : "0",
                           "MASO_UI_LIGHT": light ? "1" : "0", "MASO_UI_CONTRAST": increasedContrast ? "1" : "0"]
        if restoreHold { environment["MASO_RESTORE_HOLD"] = "1" }
        app.launchEnvironment = environment
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Missing reachable control: \(element.identifier)")
        if !element.exists { throw FixtureError.missingControl }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "paywall-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum FixtureError: Error { case missingControl }
}

/// Focused integration checks for the shared compact banner and recoverable
/// StoreKit product-loading failures, in real navigation and paywall sheets.
@MainActor
final class ProBannerUITests: XCTestCase {
    private var store: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Maso", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: url)
        store.disableDialogs = true
        store.clearTransactions()
    }

    override func tearDownWithError() throws { store.clearTransactions(); store = nil }

    func testBannerInHomeAndSettingsAcrossLanguages() throws {
        for language in ["en", "zh-Hans", "de", "ar"] {
            let app = launch("banner", language: language)
            let banner = app.buttons["pro.banner"]
            try reveal(banner, app: app)
            if ["en", "zh-Hans"].contains(language) { XCTAssertLessThan(banner.frame.height, 145) }
            capture(app, language + "-home")
            banner.tap()
            XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10))
            app.buttons["paywall.close"].tap()
            let settings = app.buttons["home.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
            try reveal(banner, app: app)
            capture(app, language + "-settings")
            banner.tap()
            XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10))
            app.buttons["paywall.close"].tap()
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testFailedProductLoadUsesSystemNoticeAndVisibleRetryRecovers() throws {
        try verifyUnavailableProducts(scene: "unavailable")
    }

    func testEmptyProductResponseAlsoUsesSystemNoticeAndRetryRecovers() throws {
        try verifyUnavailableProducts(scene: "empty")
    }

    private func verifyUnavailableProducts(scene: String) throws {
        let app = launch(scene)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["Subscription options are unavailable right now"].exists)
        capture(app, scene + "-system-notice")
        alert.buttons["Not now"].tap()
        XCTAssertFalse(app.buttons["paywall.purchase"].exists)
        XCTAssertFalse(app.buttons["paywall.more"].exists)
        XCTAssertFalse(app.staticTexts["Subscription options are unavailable right now"].exists)
        try reveal(app.buttons["paywall.continue-free"], app: app)
        XCTAssertEqual(app.buttons.matching(identifier: "paywall.restore").count, 1)
        capture(app, scene + "-free-exit")
        let retry = app.buttons["paywall.retry"]
        try reveal(retry, app: app)
        retry.tap()
        let yearly = app.buttons["paywall.plan.yearly"]
        try reveal(yearly, app: app)
        XCTAssertTrue(yearly.label.contains("29.99") || yearly.label.contains("29,99"))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        try reveal(app.buttons["paywall.purchase"], app: app)
        XCTAssertTrue(app.buttons["paywall.purchase"].isEnabled)
        XCTAssertTrue(app.staticTexts["paywall.renewal"].exists)
        capture(app, scene + "-recovered")
        app.terminate()
    }

    func testBannerMarkAtActualSystemContrastInLightAndDark() throws {
        for light in [false,true] {
            let app = launch("banner",language:"en",light:light)
            let banner = app.buttons["pro.banner"]
            try reveal(banner,app:app)
            XCTAssertTrue(banner.isHittable)
            capture(app,light ? "51-system-contrast-light":"51-system-contrast-dark")
            print("BANNER51_RECT " + String(describing:banner.frame))
            app.terminate()
        }
    }

    private func launch(_ scene: String, language: String = "en", light: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.yumowu.maso")
        app.launchEnvironment = ["MASO_PAYWALL_UI_TEST_SCENE": scene, "MASO_UI_LIGHT": light ? "1":"0"]
        app.launchArguments = ["-maso.selectedLanguage", language, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<16 {
            if element.waitForExistence(timeout: 0.5) && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Missing reachable control: \(element.identifier)")
        throw NSError(domain: "ProBannerUITests", code: 1)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "pro-banner-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
