import SwiftUI
import UIKit

/// Native alert text entry, with the same numeric rules as parameter Form rows.
/// UIKit owns presentation, keyboard and dismissal; no custom alert chrome.
struct NativeNumericAlert: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let initialValue: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var onSubmit: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> Presenter {
        let controller = Presenter()
        controller.onAppearance = { [weak coordinator = context.coordinator, weak controller] in
            guard let controller else { return }
            coordinator?.presentIfNeeded(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        context.coordinator.parent = self
        context.coordinator.presentIfNeeded(from: controller)
    }

    final class Presenter: UIViewController {
        var onAppearance: (() -> Void)?
        override func loadView() { view = UIView(); view.backgroundColor = .clear }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAppearance?()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeNumericAlert
        private weak var alert: UIAlertController?
        private weak var applyAction: UIAlertAction?
        private let locale = LanguageManager.currentLocale
        init(_ parent: NativeNumericAlert) { self.parent = parent }

        func presentIfNeeded(from controller: UIViewController) {
            guard parent.isPresented else {
                if let alert, !alert.isBeingDismissed { alert.dismiss(animated: true) }
                return
            }
            guard alert == nil, controller.viewIfLoaded?.window != nil else { return }
            let dialog = UIAlertController(title: parent.title, message: parent.message, preferredStyle: .alert)
            dialog.view.tintColor = .label
            dialog.addTextField { [weak self] field in
                guard let self else { return }
                field.text = NumericInputRules.formatted(self.parent.initialValue, allowsDecimal: true, locale: self.locale)
                field.keyboardType = .decimalPad
                field.delegate = self
                field.autocorrectionType = .no
                field.spellCheckingType = .no
                field.accessibilityLabel = NSLocalizedString("Weight", comment: "") + " " + self.parent.unit
                field.addTarget(self, action: #selector(self.changed(_:)), for: .editingChanged)
                let tap = UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:)))
                tap.cancelsTouchesInView = false
                field.addGestureRecognizer(tap)
                if !self.parent.unit.isEmpty {
                    let suffix = UILabel()
                    suffix.text = " " + self.parent.unit
                    suffix.font = .preferredFont(forTextStyle: .body)
                    suffix.textColor = .secondaryLabel
                    suffix.sizeToFit()
                    field.rightView = suffix
                    field.rightViewMode = .always
                }
            }
            dialog.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
                self?.parent.isPresented = false
            })
            let apply = UIAlertAction(title: NSLocalizedString("Apply", comment: ""), style: .default) { [weak self, weak dialog] _ in
                guard let self else { return }
                let value = self.validValue(dialog?.textFields?.first?.text ?? "")
                self.parent.isPresented = false
                if let value { self.parent.onSubmit(value) }
            }
            dialog.addAction(apply)
            applyAction = apply
            alert = dialog
            if let field = dialog.textFields?.first { changed(field) }
            controller.present(dialog, animated: true) { [weak self, weak dialog] in
                guard let field = dialog?.textFields?.first else { return }
                field.becomeFirstResponder()
                // UIAlertController may set its insertion caret during the final presentation
                // layout. Select after that layout, as the shared numeric Form field does.
                DispatchQueue.main.async { self?.selectAll(field) }
            }
        }

        func validValue(_ text: String) -> Double? {
            guard let value = NumericInputRules.value(text, allowsDecimal: true, locale: locale),
                  parent.range.contains(value) else { return nil }
            return value
        }

        @objc private func changed(_ field: UITextField) {
            applyAction?.isEnabled = validValue(field.text ?? "") != nil
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard let field = gesture.view as? UITextField else { return }
            field.becomeFirstResponder()
            DispatchQueue.main.async { [weak self, weak field] in
                if let field { self?.selectAll(field) }
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let text = textField.text, let selection = Range(range, in: text) else { return false }
            return NumericInputRules.normalized(text.replacingCharacters(in: selection, with: string),
                                                allowsDecimal: true, locale: locale) != nil
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self, weak textField] in
                if let textField { self?.selectAll(textField) }
            }
        }

        private func selectAll(_ field: UITextField) {
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
        }
    }
}
