import SwiftUI
import UIKit

/// The static menu is available immediately after installation, before the first App launch.
enum HomeQuickAction: String, CaseIterable, Sendable {
    case workout, addMeal, freeWorkout, coach
    static let prefix = "com.yumowu.maso.quickAction."
    var type: String { Self.prefix + rawValue }
    var titleKey: String {
        switch self { case .workout: "Start workout"; case .addMeal: "Add meal"; case .freeWorkout: "Free workout"; case .coach: "AI Coach" }
    }
    var symbol: String {
        switch self { case .workout: "play.fill"; case .addMeal: "fork.knife"; case .freeWorkout: "figure.strengthtraining.traditional"; case .coach: "bubble.left.and.bubble.right" }
    }
    init?(type: String) {
        guard type.hasPrefix(Self.prefix), let value = Self(rawValue: String(type.dropFirst(Self.prefix.count))) else { return nil }
        self = value
    }
    struct Request: Equatable { let id = UUID(); let action: HomeQuickAction }
    @MainActor @discardableResult
    static func receive(_ item: UIApplicationShortcutItem, router suppliedRouter: AppRouter? = nil) -> Bool {
        guard let action = Self(type: item.type) else { return false }
        let router = suppliedRouter ?? AppRouter.shared
        router.pendingWidgetDestination = nil; router.pendingWidgetDay = nil
        router.pendingHomeQuickAction = .init(action: action)
        return true
    }
}

/// SwiftUI still owns all windows. These delegates only forward UIKit quick-action events.
@MainActor
final class HomeQuickActionAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication { configuration.delegateClass = HomeQuickActionSceneDelegate.self }
        return configuration
    }
}

@MainActor
final class HomeQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let item = options.shortcutItem { HomeQuickAction.receive(item) }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(HomeQuickAction.receive(shortcutItem))
    }
}
