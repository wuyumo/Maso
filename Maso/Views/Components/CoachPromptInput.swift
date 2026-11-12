import SwiftUI
import UIKit

struct CoachPromptBlank: Equatable {
    var range: NSRange

    /// Only untouched template contents remain interactive. Edits before a blank
    /// move its UTF-16 range; edits inside it resolve it permanently.
    static func applyingEdit(_ edit: NSRange, replacementLength: Int, to blanks: [Self]) -> [Self] {
        blanks.compactMap { blank in
            let touched = edit.length == 0
                ? edit.location >= blank.range.location && edit.location <= NSMaxRange(blank.range)
                : NSIntersectionRange(edit, blank.range).length > 0
            guard !touched else { return nil }
            var moved = blank
            if NSMaxRange(edit) <= blank.range.location {
                moved.range.location += replacementLength - edit.length
            }
            return moved
        }
    }
}

/// UITextView owns the actual selection instead of racing TextField's focus updates.
struct CoachPromptInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var blanks: [CoachPromptBlank]
    @Binding var selection: NSRange?
    @Binding var isFocused: Bool
    let placeholder: String
    @ScaledMetric(relativeTo:.body) private var textSize = 16.0

    func makeUIView(context: Context) -> CoachPromptTextView {
        let view = CoachPromptTextView()
        view.onEdit = { text, blanks, selection in
            context.coordinator.parent.text = text
            context.coordinator.parent.blanks = blanks
            context.coordinator.parent.selection = selection
        }
        view.onSelection = { context.coordinator.parent.selection = $0 }
        view.onFocus = { context.coordinator.parent.isFocused = $0 }
        return view
    }

    func updateUIView(_ view: CoachPromptTextView, context: Context) {
        context.coordinator.parent = self
        view.font = .systemFont(ofSize:textSize)
        view.placeholderLabel.font = view.font
        view.placeholderLabel.text = placeholder
        view.accessibilityLabel = placeholder
        view.install(text: text, blanks: blanks, selection: selection)
        if isFocused && !view.isFirstResponder {
            let expectedText = text
            let target = selection
            // Wait for attachment, not arbitrary keyboard-duration retries. Text and
            // selection are guarded so a stale request cannot overwrite user edits.
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window != nil, view.text == expectedText,
                      context.coordinator.parent.isFocused else { return }
                let requestedSelection = context.coordinator.parent.selection == target ? target : nil
                view.activate(selecting: requestedSelection)
            }
        } else if !isFocused && view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CoachPromptTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let natural = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let line = uiView.font?.lineHeight ?? 20
        let maximumLines = context.environment.dynamicTypeSize.isAccessibilitySize ? 3.0 : 6.0
        let height = min(max(line * 2 + 16, natural), line * maximumLines + 16)
        uiView.isScrollEnabled = natural > height
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator {
        var parent: CoachPromptInput
        init(_ parent: CoachPromptInput) { self.parent = parent }
    }
}

final class CoachPromptTextView: UITextView, UITextViewDelegate, UIGestureRecognizerDelegate {
    let placeholderLabel = UILabel()
    private(set) var blanks: [CoachPromptBlank] = []
    private var applyingUpdate = false
    var onEdit: ((String, [CoachPromptBlank], NSRange) -> Void)?
    var onSelection: ((NSRange) -> Void)?
    var onFocus: ((Bool) -> Void)?
    private var normalColor: UIColor { UIColor(MasoColor.text) }
    private var blankColor: UIColor { UIColor(MasoColor.accent) }

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        backgroundColor = .clear
        font = .systemFont(ofSize: 16)
        textColor = normalColor
        tintColor = blankColor
        textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textContainer.lineFragmentPadding = 0
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        isScrollEnabled = false
        accessibilityIdentifier = "coachPromptInput"
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            placeholderLabel.widthAnchor.constraint(equalTo: widthAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedBlank(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(text newText: String, blanks newBlanks: [CoachPromptBlank], selection: NSRange?) {
        applyingUpdate = true
        if text != newText { text = newText }
        blanks = newBlanks.filter { $0.range.length > 0 && NSMaxRange($0.range) <= (newText as NSString).length }
        refreshColors()
        if let selection, selection.location != NSNotFound, NSMaxRange(selection) <= (newText as NSString).length,
           selectedRange != selection {
            selectedRange = selection
        }
        applyingUpdate = false
    }

    private func refreshColors() {
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttributes([.font: font ?? UIFont.systemFont(ofSize: 16), .foregroundColor: normalColor], range: range)
        for blank in blanks where NSMaxRange(blank.range) <= textStorage.length {
            textStorage.addAttribute(.foregroundColor, value: blankColor, range: blank.range)
        }
        typingAttributes = [.font: font ?? UIFont.systemFont(ofSize: 16), .foregroundColor: normalColor]
        placeholderLabel.isHidden = !text.isEmpty
    }

    /// Keyboard activation may emit a caret update. Suppress that intermediate
    /// update so it cannot replace the requested template selection in SwiftUI.
    func activate(selecting range: NSRange?) {
        applyingUpdate = true
        becomeFirstResponder()
        if let range, range.location != NSNotFound, NSMaxRange(range) <= textStorage.length {
            selectedRange = range
            scrollRangeToVisible(range)
        }
        applyingUpdate = false
        onSelection?(selectedRange)
    }

    func selectContents(_ range: NSRange) {
        guard range.location != NSNotFound, NSMaxRange(range) <= textStorage.length else { return }
        selectedRange = range
        scrollRangeToVisible(range)
        onSelection?(range)
    }

    @discardableResult
    func selectBlank(atUTF16Offset offset: Int) -> Bool {
        guard let blank = blanks.first(where: { NSLocationInRange(offset, $0.range) }) else { return false }
        becomeFirstResponder()
        selectContents(blank.range)
        return true
    }

    @objc private func tappedBlank(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        let containerPoint = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -3, dy: -3).contains(containerPoint) else { return }
        let offset = layoutManager.characterIndexForGlyph(at: glyph)
        guard let blank = blanks.first(where: { NSLocationInRange(offset, $0.range) }) else { return }
        // Run after the native tap has placed its caret, then replace that caret
        // with the complete untouched blank. Normal text keeps native editing.
        let expected = text
        DispatchQueue.main.async { [weak self] in
            guard let self, self.text == expected, self.blanks.contains(blank) else { return }
            self.becomeFirstResponder()
            self.selectContents(blank.range)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        blanks = CoachPromptBlank.applyingEdit(range, replacementLength: (text as NSString).length, to: blanks)
        return true
    }
    func textViewDidChange(_ textView: UITextView) {
        applyingUpdate = true
        refreshColors()
        applyingUpdate = false
        onEdit?(text, blanks, selectedRange)
        invalidateIntrinsicContentSize()
    }
    func textViewDidChangeSelection(_ textView: UITextView) {
        if !applyingUpdate { onSelection?(selectedRange) }
    }
    func textViewDidBeginEditing(_ textView: UITextView) { onFocus?(true) }
    func textViewDidEndEditing(_ textView: UITextView) { onFocus?(false) }
}
