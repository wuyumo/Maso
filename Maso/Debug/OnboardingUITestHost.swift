#if DEBUG
import SwiftUI

/// Exercises the real first-run view with a fresh, isolated in-memory profile.
struct OnboardingUITestHost: View {
    @State private var data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: UserSettings())
    @State private var subscriptions = SubscriptionManager()
    @State private var session = TrainingSessionStore()
    @State private var completed = false
    @State private var selectedPlan: Plan?

    var body: some View {
        Group {
            if completed {
                VStack {
                    Text("Completed").accessibilityIdentifier("onboarding.test.completed")
                    Text("\(data.plans.count)").accessibilityIdentifier("onboarding.test.savedCount")
                    Text(selectedPlan?.steps.first?.exerciseId ?? "").accessibilityIdentifier("onboarding.test.startedPlan")
                }
            } else {
                OnboardingScreen(previewOnly: ProcessInfo.processInfo.environment["MASO_ONBOARDING_PREVIEW_ONLY"] == "1") { plan in
                    data.settings.onboardingCompleted = true
                    selectedPlan = plan
                    completed = true
                }
            }
        }
        .environment(data).environment(subscriptions).environment(session)
        .environment(\.locale, LanguageManager.currentLocale)
        .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["MASO_ONBOARDING_LARGE_TYPE"] == "1" ? .accessibility3 : .large)
        .preferredColorScheme(.dark).tint(MasoColor.text)
    }
}
#endif
