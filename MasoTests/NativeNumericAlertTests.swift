import XCTest
import SwiftUI
import UIKit
@testable import Maso

@MainActor
final class NativeNumericAlertTests: XCTestCase {
    func testWeightAlertUsesNativeNumericKeyboardAndSelectsTheWholeWeight() async throws {
        var presented = true
        var saved: Double?
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Color.clear.background {
            NativeNumericAlert(isPresented: Binding(get: { presented }, set: { presented = $0 }),
                               title: "Weight", message: "Exercise", initialValue: 47.25,
                               range: 0.001...500, unit: "kg") { saved = $0 }
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        // Wait for the native presentation completion, where autofocus is requested.
        var dialog: UIAlertController?
        for _ in 0..<30 {
            dialog = alert(in: host)
            if let field = dialog?.textFields?.first, field.isFirstResponder,
               let selection = field.selectedTextRange,
               field.offset(from: field.beginningOfDocument, to: selection.start) == 0,
               field.offset(from: field.beginningOfDocument, to: selection.end) == (field.text ?? "").utf16.count { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let alert = try XCTUnwrap(dialog)
        let field = try XCTUnwrap(alert.textFields?.first)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.keyboardType, .decimalPad)
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 0)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.end), (field.text ?? "").utf16.count)
        XCTAssertFalse(field.delegate?.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: 5), replacementString: "50 kg") == true)
        field.text = "62.5"; field.sendActions(for: .editingChanged)
        XCTAssertTrue(try XCTUnwrap(alert.actions.last).isEnabled)
        field.text = ""; field.sendActions(for: .editingChanged)
        XCTAssertFalse(try XCTUnwrap(alert.actions.last).isEnabled)
        field.text = "9999"; field.sendActions(for: .editingChanged)
        XCTAssertFalse(try XCTUnwrap(alert.actions.last).isEnabled)
        XCTAssertNil(saved, "Typing never applies a weight before confirmation")
        alert.dismiss(animated: false)
        presented = false
    }

    private func alert(in controller: UIViewController) -> UIAlertController? {
        if let alert = controller as? UIAlertController { return alert }
        if let presented = controller.presentedViewController, let result = alert(in: presented) { return result }
        return controller.children.lazy.compactMap { self.alert(in: $0) }.first
    }
}
