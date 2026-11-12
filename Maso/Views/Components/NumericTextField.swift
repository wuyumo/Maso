import SwiftUI
import UIKit

/// Numeric editing rules shared by parameter rows, body data and meal amounts.
/// Keep the user's unfinished string while editing; only presentation is localized.
enum NumericInputRules {
    static func normalized(_ input: String, allowsDecimal: Bool, locale: Locale) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = Set([locale.decimalSeparator ?? ".", ".", ",", "٫", "．"])
        var result = ""
        var hasSeparator = false
        for character in trimmed {
            if character.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .decimalNumber }),
               let digit = character.wholeNumberValue, (0...9).contains(digit) {
                result.append(String(digit))
            } else if allowsDecimal, separators.contains(String(character)), !hasSeparator {
                result.append(".")
                hasSeparator = true
            } else {
                // Reject invalid paste rather than silently changing its meaning.
                return nil
            }
        }
        return result
    }

    static func value(_ input: String, allowsDecimal: Bool, locale: Locale) -> Double? {
        guard let normalized = normalized(input, allowsDecimal: allowsDecimal, locale: locale),
              let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    static func formatted(_ value: Double, allowsDecimal: Bool, locale: Locale) -> String {
        guard value.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        // Preserve manually entered fractional weights (e.g. 1.25), not just one decimal.
        formatter.maximumFractionDigits = allowsDecimal ? 6 : 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Plain native field: tap once to replace the full number, including when already focused.
/// Its containing Form/Stepper supplies the current native iOS row appearance.
struct NumericTextField: UIViewRepresentable {
    @Binding var text: String
    var allowsDecimal = false
    var autoFocus = false
    var placeholder = "0"
    var textAlignment: NSTextAlignment = .right
    var font = UIFont.preferredFont(forTextStyle: .body)
    var textColor = UIColor.label
    var locale = LanguageManager.currentLocale
    var accessibilityLabel: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> NumericInputTextField {
        let field = NumericInputTextField()
        field.delegate = context.coordinator
        field.keyboardType = allowsDecimal ? .decimalPad : .numberPad
        field.borderStyle = .none
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .done
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        field.addGestureRecognizer(tap)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.tintColor = .label
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: NSLocalizedString("Done", comment: ""), style: .plain,
                            target: field, action: #selector(UIResponder.resignFirstResponder))
        ]
        field.inputAccessoryView = toolbar
        field.onAttached = { [weak field, weak coordinator = context.coordinator] in
            guard let field, let coordinator else { return }
            coordinator.requestInitialFocus(field)
        }
        return field
    }

    func updateUIView(_ field: NumericInputTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        let keyboard: UIKeyboardType = allowsDecimal ? .decimalPad : .numberPad
        if field.keyboardType != keyboard {
            field.keyboardType = keyboard
            if field.isFirstResponder { field.reloadInputViews() }
        }
        field.placeholder = placeholder
        field.textAlignment = textAlignment
        field.font = font
        field.textColor = textColor
        field.accessibilityLabel = accessibilityLabel
        context.coordinator.requestInitialFocus(field)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NumericInputTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: max(22, uiView.font?.lineHeight ?? 22))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericTextField
        private var didAutofocus = false
        init(_ parent: NumericTextField) { self.parent = parent }

        func requestInitialFocus(_ field: UITextField) {
            guard parent.autoFocus, !didAutofocus, field.window != nil else { return }
            didAutofocus = true
            DispatchQueue.main.async { [weak field] in field?.becomeFirstResponder() }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let current = textField.text, let selection = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: selection, with: string)
            return NumericInputRules.normalized(proposed, allowsDecimal: parent.allowsDecimal, locale: parent.locale) != nil
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged(true)
            selectAllAfterTap(textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged(false)
            parent.onCommit()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        @objc func changed(_ textField: UITextField) { parent.text = textField.text ?? "" }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let field = gesture.view as? UITextField else { return }
            field.becomeFirstResponder()
            selectAllAfterTap(field)
        }

        private func selectAllAfterTap(_ field: UITextField) {
            // UIKit places the insertion caret after didBeginEditing; select on the next turn.
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isFirstResponder else { return }
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
        }
    }
}

final class NumericInputTextField: UITextField {
    var onAttached: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onAttached?() }
    }
}

/// A bounded numeric model with an independent editing buffer, shared across numeric UI.
/// Valid edits update immediately so tapping a sheet's Save uses the latest number;
/// clearing the field temporarily never forces a zero or a minimum back into the buffer.
struct NumericValueField: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let allowsDecimal: Bool
    var autoFocus = false
    var font = UIFont.preferredFont(forTextStyle: .body)
    var textColor = UIColor.label
    var accessibilityLabel: String? = nil
    var showsUnknown = false
    @State private var text: String
    @State private var isEditing = false
    @State private var lastWrittenValue: Double? = nil

    init(value: Binding<Double>, range: ClosedRange<Double>, allowsDecimal: Bool = true,
         autoFocus: Bool = false, font: UIFont = .preferredFont(forTextStyle: .body),
         textColor: UIColor = .label, accessibilityLabel: String? = nil, showsUnknown: Bool = false) {
        self._value = value
        self.range = range
        self.allowsDecimal = allowsDecimal
        self.autoFocus = autoFocus
        self.font = font
        self.textColor = textColor
        self.accessibilityLabel = accessibilityLabel
        self.showsUnknown = showsUnknown
        self._text = State(initialValue: showsUnknown ? "" : NumericInputRules.formatted(value.wrappedValue, allowsDecimal: allowsDecimal,
                                                                   locale: LanguageManager.currentLocale))
    }

    init(value: Binding<Int>, range: ClosedRange<Int>, autoFocus: Bool = false,
         font: UIFont = .preferredFont(forTextStyle: .body), textColor: UIColor = .label,
         accessibilityLabel: String? = nil) {
        self.init(value: Binding<Double>(get: { Double(value.wrappedValue) },
                                        set: { value.wrappedValue = Int($0.rounded()) }),
                  range: Double(range.lowerBound)...Double(range.upperBound), allowsDecimal: false,
                  autoFocus: autoFocus, font: font, textColor: textColor, accessibilityLabel: accessibilityLabel)
    }

    var body: some View {
        NumericTextField(text: Binding(get: { text }, set: { text = $0; writeValid($0) }),
                         allowsDecimal: allowsDecimal, autoFocus: autoFocus, placeholder: showsUnknown ? "—" : "0", font: font,
                         textColor: textColor, accessibilityLabel: accessibilityLabel,
                         onEditingChanged: { isEditing = $0 }, onCommit: commit)
            .onChange(of: showsUnknown) { _, unknown in
                if !isEditing { text = unknown ? "" : format(value) }
            }
            .onChange(of: value) { _, newValue in
                // A Stepper or parent edit must update even while the keyboard remains open.
                let wasWrittenHere = lastWrittenValue.map {
                    abs(newValue - $0) <= max(1, abs(newValue)) * 1e-10
                } ?? false
                if !isEditing || !wasWrittenHere { text = format(newValue) }
            }
            .onChange(of: LanguageManager.currentLocale.identifier) { _, _ in
                if !isEditing { text = format(value) }
            }
    }

    private func writeValid(_ input: String) {
        guard let parsed = NumericInputRules.value(input, allowsDecimal: allowsDecimal,
                                                  locale: LanguageManager.currentLocale) else { return }
        let bounded = min(range.upperBound, max(range.lowerBound, parsed))
        lastWrittenValue = bounded
        value = bounded
    }

    private func commit() {
        writeValid(text)
        text = showsUnknown ? "" : format(value)
    }

    private func format(_ value: Double) -> String {
        NumericInputRules.formatted(value, allowsDecimal: allowsDecimal, locale: LanguageManager.currentLocale)
    }
}
