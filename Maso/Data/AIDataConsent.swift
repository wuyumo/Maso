import SwiftUI
import UIKit

/// A versioned, explicit choice before any personal-content AI request.
/// Present above the active sheet so Diet/Coach never hide the consent UI.
@MainActor @Observable
final class AIDataConsent {
    static let shared = AIDataConsent()
    // v2 names the verified primary provider and optional Bailian route, and explains screenshots.
    // A Qwen-only v1 grant must not silently authorize this expanded disclosure.
    private static let key = "masso.aiDataSharingConsent.v2"
    private(set) var isGranted = UserDefaults.standard.bool(forKey: key)
    @ObservationIgnored private var waiters: [CheckedContinuation<Bool, Never>] = []

    func revoke() {
        isGranted = false
        UserDefaults.standard.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: "masso.aiDataSharingConsent.v1")
    }

    func requirePermission() async throws {
        try Task.checkCancellation()
        guard !isGranted else { return }
        let accepted = await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard waiters.count == 1 else { return }
            guard UIApplication.shared.applicationState == .active,
                  var presenter = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .windows.first(where: \.isKeyWindow)?.rootViewController else {
                resolve(false)
                return
            }
            while let presented = presenter.presentedViewController { presenter = presented }
            let alert = UIAlertController(
                title: NSLocalizedString("AI data sharing", comment: ""),
                message: NSLocalizedString("ai.dataSharing.explanation", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Not now", comment: ""), style: .cancel) { [weak self] _ in self?.resolve(false) })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Allow", comment: ""), style: .default) { [weak self] _ in self?.resolve(true) })
            presenter.present(alert, animated: true)
        }
        guard accepted else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func resolve(_ accepted: Bool) {
        isGranted = accepted
        UserDefaults.standard.set(accepted, forKey: Self.key)
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: accepted) }
    }
}
