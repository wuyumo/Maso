import XCTest
import UIKit
@testable import Maso

@MainActor
final class HomeQuickActionTests: XCTestCase {
    func testStaticMenuMatchesTypedRoutesAndAllTwelveLocalizations() throws {
        let definitions = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
        XCTAssertEqual(definitions.count, 4)
        XCTAssertEqual(definitions.compactMap { $0["UIApplicationShortcutItemType"] as? String }, HomeQuickAction.allCases.map(\.type))
        for (entry, action) in zip(definitions, HomeQuickAction.allCases) {
            XCTAssertEqual(entry["UIApplicationShortcutItemTitle"] as? String, action.titleKey)
            XCTAssertEqual(entry["UIApplicationShortcutItemIconSymbolName"] as? String, action.symbol)
            XCTAssertNotNil(UIImage(systemName: action.symbol))
        }
        for language in SupportedLanguage.allCases {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for action in HomeQuickAction.allCases {
                XCTAssertNotEqual(bundle.localizedString(forKey: action.titleKey, value: "MISSING", table: "InfoPlist"), "MISSING", language.rawValue)
            }
        }
    }
    func testKnownItemsQueueOnceAndRepeatedActionsRemainDistinct() {
        let router = AppRouter.shared
        defer { router.pendingHomeQuickAction = nil; router.pendingWidgetDestination = nil; router.pendingWidgetDay = nil }
        router.pendingWidgetDestination = .diet
        router.pendingWidgetDay = Date()
        let item = UIApplicationShortcutItem(type: HomeQuickAction.addMeal.type, localizedTitle: "Add meal")
        XCTAssertTrue(HomeQuickAction.receive(item))
        let first = router.pendingHomeQuickAction?.id
        XCTAssertEqual(router.pendingHomeQuickAction?.action, .addMeal)
        XCTAssertNil(router.pendingWidgetDestination); XCTAssertNil(router.pendingWidgetDay)
        XCTAssertTrue(HomeQuickAction.receive(item))
        XCTAssertNotEqual(router.pendingHomeQuickAction?.id, first)
        let pending = router.pendingHomeQuickAction
        XCTAssertFalse(HomeQuickAction.receive(.init(type: "unknown", localizedTitle: "Unknown")))
        XCTAssertEqual(router.pendingHomeQuickAction, pending)
    }
    func testWarmSceneDelegateReportsHandledAndDoesNotCreateAnotherWindow() throws {
        let router = AppRouter.shared
        defer { router.pendingHomeQuickAction = nil }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let count = scene.windows.count
        var completed: Bool?
        HomeQuickActionSceneDelegate().windowScene(scene,
            performActionFor: .init(type: HomeQuickAction.coach.type, localizedTitle: "AI Coach")) { completed = $0 }
        XCTAssertEqual(completed, true)
        XCTAssertEqual(router.pendingHomeQuickAction?.action, .coach)
        XCTAssertEqual(scene.windows.count, count)
    }
}
