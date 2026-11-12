import XCTest
import SwiftUI
import UIKit
@testable import Maso

@MainActor
final class ParameterSheetTests: XCTestCase {
    private struct PresentedEditor: View {
        let exercise: Exercise
        let onSave: (Int, Int?, Double?, Int?, [Int?]?, [Double?]?) -> Void
        @State private var presented = false
        var body: some View {
            Color.black
                .sheet(isPresented: $presented) {
                    EditCurrentStepSheet(exercise: exercise, initialSets: 3, initialReps: 10,
                                         initialWeight: 47.25, initialDuration: nil, onSave: onSave,
                                         onReplace: {})
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
                .task { presented = true }
        }
    }

    /// Exercise the real editor in its native sheet, not an isolated numeric-field preview.
    func testTrainingParameterSheetSelectsWeightAndSavesCurrentInputWithKeyboardOpen() async throws {
        let originalUnit = WeightUnitProvider.current
        WeightUnitProvider.current = .kg
        defer { WeightUnitProvider.current = originalUnit }
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById.values.first {
            $0.category == .strength && $0.name.localizedCaseInsensitiveContains("bench press")
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        var saved: (sets: Int, reps: Int?, weight: Double?)?
        let host = UIHostingController(rootView: PresentedEditor(exercise: exercise, onSave: { sets, reps, weight, _, _, _ in
            saved = (sets, reps, weight)
        }).preferredColorScheme(.dark)
            .environment(\.locale, LanguageManager.currentLocale)
            .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(650))
        let sheet = try XCTUnwrap(host.presentedViewController)
        let presentation = try XCTUnwrap(sheet.sheetPresentationController)
        // UIKit leaves selectedDetentIdentifier nil when the sole detent was selected
        // implicitly. Verify both its allowed detents and the real displayed height.
        XCTAssertEqual(presentation.detents.first?.identifier, .medium)
        XCTAssertEqual(presentation.detents.count, 1)
        XCTAssertLessThan(sheet.view.bounds.height, window.bounds.height * 0.7)
        XCTAssertGreaterThan(sheet.view.bounds.height, window.bounds.height * 0.35)
        try capture(scene: scene, reference: window, name: "training-parameters-medium.png")

        let field = try XCTUnwrap(fields(in: sheet.view).first {
            NumericInputRules.value($0.text ?? "", allowsDecimal: true, locale: LanguageManager.currentLocale) == 47.25
        })
        XCTAssertEqual(field.keyboardType, .decimalPad)
        XCTAssertTrue(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(400))
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 0)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.end), (field.text ?? "").utf16.count)
        print("PARAMETER_SHEET_KEYBOARD_READY")
        try capture(scene: scene, reference: window, name: "training-parameters-keyboard.png")

        let replacement = NumericInputRules.formatted(62.5, allowsDecimal: true, locale: LanguageManager.currentLocale)
        XCTAssertTrue(field.delegate?.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: (field.text ?? "").utf16.count), replacementString: replacement) == true)
        field.text = replacement
        field.sendActions(for: .editingChanged)
        // Let SwiftUI update the real sheet's state while the field remains focused.
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertNil(saved)
        XCTAssertTrue(activateSave(in: sheet), "The real navigation Save action must be reachable")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(saved?.sets, 3)
        XCTAssertEqual(saved?.reps, 10)
        XCTAssertEqual(try XCTUnwrap(saved?.weight), 62.5, accuracy: 0.000001,
                       "Save must use the edited weight without requiring keyboard Done")
    }

    private func fields(in view: UIView) -> [NumericInputTextField] {
        (view as? NumericInputTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
    }

    private func activateSave(in controller: UIViewController) -> Bool {
        let title = NSLocalizedString("Save", comment: "")
        if let navigation = controller as? UINavigationController {
            let navigationItem = navigation.topViewController?.navigationItem ?? navigation.navigationBar.topItem
            let items = (navigationItem?.rightBarButtonItems ?? []) + (navigationItem?.leftBarButtonItems ?? [])
                + (navigationItem?.leadingItemGroups ?? []).flatMap(\.barButtonItems)
                + (navigationItem?.trailingItemGroups ?? []).flatMap(\.barButtonItems)
            for item in items where item.title == title || item.accessibilityLabel == title {
                if let action = item.primaryAction {
                    // Native Liquid Glass toolbar groups may expose UIAction rather
                    // than a selector. Dispatch the same action through a public control.
                    let sender = UIControl()
                    sender.addAction(action, for: .primaryActionTriggered)
                    sender.sendActions(for: .primaryActionTriggered)
                    return true
                }
                if let action = item.action {
                    return UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
                }
            }
        }
        for child in controller.children where activateSave(in: child) { return true }
        return activateSave(in: controller.view, title: title)
    }

    private func activateSave(in view: UIView, title: String) -> Bool {
        if let control = view as? UIControl,
           control.accessibilityLabel == title || (control as? UIButton)?.title(for: .normal) == title {
            let events: UIControl.Event = control.allControlEvents.contains(.primaryActionTriggered) ? .primaryActionTriggered : .touchUpInside
            control.sendActions(for: events)
            return true
        }
        for element in view.accessibilityElements ?? [] {
            if let accessible = element as? NSObject, accessible.accessibilityLabel == title,
               accessible.accessibilityActivate() { return true }
        }
        for child in view.subviews where activateSave(in: child, title: title) { return true }
        return false
    }

    private func capture(scene: UIWindowScene, reference: UIWindow, name: String) throws {
        let image = UIGraphicsImageRenderer(bounds: reference.bounds).image { _ in
            for window in scene.windows.filter({ !$0.isHidden }).sorted(by: { $0.windowLevel.rawValue < $1.windowLevel.rawValue }) {
                window.drawHierarchy(in: window.convert(window.bounds, to: reference), afterScreenUpdates: true)
            }
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try XCTUnwrap(image.pngData()).write(to: url)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
