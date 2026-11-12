import XCTest
import SwiftUI
import UIKit
@testable import Maso

@MainActor
final class NumericEntryTests: XCTestCase {
    func testLocalizedNumbersRoundTripWithoutTruncatingFractionalWeights() throws {
        for language in SupportedLanguage.allCases {
            let locale = Locale(identifier: language.rawValue)
            for number in [0.0, 1.25, 47.25, 137.7956] {
                let text = NumericInputRules.formatted(number, allowsDecimal: true, locale: locale)
                let parsed = try XCTUnwrap(NumericInputRules.value(text, allowsDecimal: true, locale: locale), "\(language): \(text)")
                XCTAssertEqual(parsed, number, accuracy: 0.000001, "\(language): \(text)")
            }
        }
        XCTAssertEqual(NumericInputRules.value("١٢٫٥", allowsDecimal: true, locale: Locale(identifier: "ar")), 12.5)
        XCTAssertEqual(NumericInputRules.value("１２．５", allowsDecimal: true, locale: Locale(identifier: "ja")), 12.5)
        XCTAssertEqual(NumericInputRules.value("47,25", allowsDecimal: true, locale: Locale(identifier: "de")), 47.25)
        XCTAssertEqual(NumericInputRules.value("47.25", allowsDecimal: true, locale: Locale(identifier: "de")), 47.25)
    }

    func testNumericPasteRejectsNonNumbersAndKeepsEmptyEditingState() {
        let locale = Locale(identifier: "en")
        for invalid in ["12 kg", "abc", "12🏋️", "1.2.3", "-12", "nan", "∞", "1e3", "1,000.5"] {
            XCTAssertNil(NumericInputRules.normalized(invalid, allowsDecimal: true, locale: locale), invalid)
        }
        XCTAssertEqual(NumericInputRules.normalized("", allowsDecimal: true, locale: locale), "")
        XCTAssertEqual(NumericInputRules.normalized(".", allowsDecimal: true, locale: locale), ".")
        XCTAssertNil(NumericInputRules.value(".", allowsDecimal: true, locale: locale))
        XCTAssertNil(NumericInputRules.normalized("12.5", allowsDecimal: false, locale: locale))
        XCTAssertEqual(NumericInputRules.value("١٢", allowsDecimal: false, locale: locale), 12)
    }

    func testNativeFieldFocusSelectsWholeNumberAndEditingPreservesBounds() async throws {
        var value = 47.25
        let binding = Binding<Double>(get: { value }, set: { value = $0 })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NumericValueField(value: binding, range: 0...500, autoFocus: true).padding(20))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        let field = try XCTUnwrap(findField(in: host.view))
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.keyboardType, .decimalPad)
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 0)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.end), (field.text ?? "").utf16.count)

        XCTAssertTrue(field.delegate?.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: (field.text ?? "").utf16.count), replacementString: "62.5") == true)
        field.text = "62.5"; field.sendActions(for: .editingChanged)
        XCTAssertEqual(value, 62.5, "Save can read the edited value before the keyboard closes")
        field.text = ""; field.sendActions(for: .editingChanged)
        XCTAssertEqual(value, 62.5)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(field.text, "", "Empty input must not immediately refill")
        field.text = "999"; field.sendActions(for: .editingChanged)
        XCTAssertEqual(value, 500, "An out-of-range draft cannot save an invalid parameter")
        field.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(NumericInputRules.value(field.text ?? "", allowsDecimal: true, locale: LanguageManager.currentLocale), 500)
    }

    func testIntegerFieldUsesNumberPadAndRejectsFractionalInput() async throws {
        var value = 12
        let binding = Binding<Int>(get: { value }, set: { value = $0 })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NumericValueField(value: binding, range: 1...100, autoFocus: true).padding(20))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(100))
        let field = try XCTUnwrap(findField(in: try XCTUnwrap(window.rootViewController?.view)))
        XCTAssertEqual(field.keyboardType, .numberPad)
        XCTAssertFalse(field.delegate?.textField?(field, shouldChangeCharactersIn: NSRange(location: 0, length: 2), replacementString: "2.5") == true)
        field.text = "٢٥"; field.sendActions(for: .editingChanged)
        XCTAssertEqual(value, 25)
        field.resignFirstResponder()
    }

    private func findField(in view: UIView) -> NumericInputTextField? {
        if let field = view as? NumericInputTextField { return field }
        return view.subviews.lazy.compactMap { self.findField(in: $0) }.first
    }
}
