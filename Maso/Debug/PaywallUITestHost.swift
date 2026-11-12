#if DEBUG
import SwiftUI
import StoreKit

/// Only reachable through the explicit UI-test launch environment, never Release.
struct PaywallUITestHost: View {
    let scene: String
    @State private var data: DataStore
    @State private var subscriptions: SubscriptionManager
    @State private var session = TrainingSessionStore()
    @State private var prompt = UpgradePrompt()
    @State private var calls = 0
    @State private var rootVersion = 0

    init(scene: String) {
        self.scene = scene
        var settings = UserSettings()
        settings.debugProUnlock = scene == "pro"
        if scene == "banner" {
            settings.onboardingCompleted = true
            settings.hasSeenWelcomePaywall = true
        }
        var loadCount = 0
        _subscriptions = State(initialValue: SubscriptionManager(productLoader: {
            loadCount += 1
            if loadCount == 1 {
                if scene == "unavailable" { throw URLError(.notConnectedToInternet) }
                if scene == "empty" { return [] }
            }
            return try await Product.products(for: SubscriptionManager.allProductIDs)
        }))
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: settings)
        if scene == "device-usage", let exercise = data.exById["bench_press_barbell"] {
            data.sets = (0..<7).map { index in
                SetRecord(id:"snapshot-fixture-" + String(index),exerciseId:exercise.id,exerciseName:exercise.name,category:exercise.category,weight:60,reps:8,duration:nil,performedAt:Date().addingTimeInterval(index == 0 ? -15*86400 : -3600),planId:nil)
            }
        }
        if scene == "device-notice" { data.aiAccess = DeviceAIQuota(legacy: true, acknowledged: false) }
        if scene == "banner" { data.aiTodayPlanEditedAt = .now } // No background AI during UI checks.
        if scene == "custom-full", let original = ExerciseLibrary.all.first {
            for index in 0..<3 {
                if let encoded = try? JSONEncoder().encode(original),
                   var payload = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] {
                    payload["id"] = "custom-fixture-\(index)"
                    if let json = try? JSONSerialization.data(withJSONObject: payload),
                       let exercise = try? JSONDecoder().decode(Exercise.self, from: json) {
                        _ = data.addCustomExercise(exercise)
                    }
                }
            }
        }
        _data = State(initialValue: data)
    }

    var body: some View {
        Group {
            if scene == "device-quota" { DeviceAIQuotaUITestView() }
            else if scene == "device-usage" { AppNavigationStack { DeviceAIUsageView() } }
            else if scene == "device-notice" {
                VStack {
                    DeviceAIChangeNotice()
                    Text("Basic app content remains available").accessibilityIdentifier("ai.policy.test.basic-content")
                    if !data.aiAccess.needsDisclosure { Text("Notice dismissed").accessibilityIdentifier("ai.policy.test.dismissed") }
                }
            }
            else if scene == "welcome" {
                RootView().id(rootVersion)
                    .overlay(alignment: .topTrailing) {
                        VStack {
                            Text(data.settings.hasSeenWelcomePaywall == true ? "seen" : "unseen")
                                .accessibilityIdentifier("paywall.test.welcome-state")
                            Button("Recreate root") { rootVersion += 1 }
                                .accessibilityIdentifier("paywall.test.recreate")
                        }
                    }
            } else if scene == "banner" {
                RootView()
            } else if ["upgrade", "unavailable", "empty"].contains(scene) {
                PaywallScreen(source: "ui_test")
            } else if ["custom", "custom-full"].contains(scene) {
                CustomExerciseFormSheet(initialName: "My test exercise")
            } else {
                AppNavigationStack {
                    VStack(spacing: 24) {
                        Text(String(calls)).accessibilityIdentifier("paywall.test.calls")
                        Button("Run AI request") {
                            prompt.requestAI(isPro: data.settings.isPro, source: "ui_test_ai") { calls += 1 }
                        }.accessibilityIdentifier("paywall.test.run-ai")
                    }
                }.aiUpgradeReminder(prompt)
            }
        }
        .frame(maxWidth: ProcessInfo.processInfo.environment["MASO_PAYWALL_NARROW"] == "1" ? 320 : .infinity)
        .environment(data).environment(subscriptions).environment(session)
        .environment(\.locale, LanguageManager.currentLocale)
        .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["MASO_PAYWALL_LARGE_TYPE"] == "1" ? .accessibility3 : .large)
        .preferredColorScheme(ProcessInfo.processInfo.environment["MASO_UI_LIGHT"] == "1" ? .light : .dark).tint(MasoColor.text)
        .task {
            if scene == "device-usage" {
                let _:String? = try? await data.aiAccess.perform(kind:.sourceImport,isPro:false,valid:{ !$0.isEmpty },summary:{ _ in "Synthetic saved text result" }) { "Entire acquired text fixture: sets 3, reps 8, rest 90. Reopened without any model request." }
            }
            if ["unavailable", "empty"].contains(scene) { await subscriptions.refreshEntitlements() }
            else { subscriptions.configure { data.settings.proSubscription = $0 } }
        }
    }
}
#endif
