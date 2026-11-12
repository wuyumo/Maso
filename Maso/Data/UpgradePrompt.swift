import Foundation
import Observation

/// A reminder authorizes one pending user action after the sheet has fully closed.
/// Subscription-only features use their existing entitlement gate instead.
@MainActor @Observable
final class UpgradePrompt {
    var isPresented = false
    private(set) var source = "ai"
    @ObservationIgnored private var pendingAction: (() -> Void)?

    func requestAI(isPro: Bool, source: String, action: @escaping () -> Void) {
        // Semantic device policy is enforced before real work; no dismiss-to-bypass reminder.
        action()
    }

    func didDismiss() {
        let action = pendingAction
        pendingAction = nil
        isPresented = false
        action?()
    }
}

enum WelcomePaywallPolicy {
    /// Existing installations finish their old onboarding without a new launch
    /// interruption. Fresh installations see the offer before onboarding begins.
    static func shouldPresent(hasSeen: Bool?, onboardingCompleted: Bool, isPro: Bool) -> Bool {
        !isPro && hasSeen != true && !onboardingCompleted
    }
}

/// Existing profiles (nil) never receive a new first-run prompt retroactively.
enum CoachIntroTipPolicy {
    static func shouldOffer(pending: Bool?, onboardingCompleted: Bool, homeAvailable: Bool, reopened: Bool = true) -> Bool {
        pending == true && onboardingCompleted && homeAvailable && reopened
    }
    static func shouldOfferPhoto(seen: Bool?, onboardingCompleted: Bool, homeAvailable: Bool,
                                 reopened: Bool, shownThisSession: Bool, workoutCount: Int) -> Bool {
        seen != true && onboardingCompleted && homeAvailable && reopened && !shownThisSession && workoutCount >= 3
    }
}
