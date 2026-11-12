import XCTest
import UIKit
@testable import Maso

@MainActor
final class CoachPromptInputTests: XCTestCase {
    private let locales = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]

    func testEveryUseCaseInEveryLanguageSelectsItsEditableContent() throws {
        for locale in locales {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"), locale)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for useCase in CoachUseCase.allCases {
                let prompt = bundle.localizedString(forKey: useCase.promptKey, value: nil, table: nil)
                let ranges = CoachTemplates.editablePlaceholderRanges(in: prompt)
                if useCase == .physiqueGoal {
                    XCTAssertTrue(ranges.isEmpty, "\(locale): photo flow does not need a text blank")
                    continue
                }
                XCTAssertEqual(ranges.count, 1, "\(locale): \(useCase)")
                let range = try XCTUnwrap(ranges.first, "\(locale): \(useCase)")
                XCTAssertFalse(prompt[range].isEmpty)
                let blank = CoachPromptBlank(range: NSRange(range, in: prompt))
                let view = CoachPromptTextView()
                view.install(text: prompt, blanks: [blank], selection: blank.range)
                XCTAssertEqual(view.selectedRange, blank.range, "\(locale): \(useCase)")
                XCTAssertEqual((view.text as NSString).substring(with: view.selectedRange), String(prompt[range]))
                // A caret elsewhere must still be able to select the entire green blank.
                view.selectedRange = NSRange(location: 0, length: 0)
                XCTAssertTrue(view.selectBlank(atUTF16Offset: blank.range.location))
                XCTAssertEqual(view.selectedRange, blank.range)
                XCTAssertEqual(view.textStorage.attribute(.foregroundColor, at: blank.range.location, effectiveRange: nil) as? UIColor,
                               UIColor(MasoColor.accent))
                let replacement = "腿🦵"
                XCTAssertTrue(view.textView(view, shouldChangeTextIn: blank.range, replacementText: replacement))
                view.text = (prompt as NSString).replacingCharacters(in: blank.range, with: replacement)
                view.textViewDidChange(view)
                XCTAssertTrue(view.blanks.isEmpty)
                XCTAssertEqual(view.textStorage.attribute(.foregroundColor, at: blank.range.location, effectiveRange: nil) as? UIColor,
                               UIColor(MasoColor.text))
                XCTAssertFalse(view.selectBlank(atUTF16Offset: blank.range.location))
            }
        }
    }

    func testKeyboardActivationPreservesLongChineseSelections() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let view = CoachPromptTextView()
        view.frame = CGRect(x: 20, y: 150, width: 250, height: 150)
        controller.view.addSubview(view)
        for prompt in ["我想更多训练「肩部和背部」，请据此调整训练计划，同时保持整体均衡。", "我在家用「哑铃和弹力带」训练，请按现有器械调整计划。"] {
            let target = NSRange(try XCTUnwrap(CoachTemplates.editablePlaceholderRanges(in: prompt).first), in: prompt)
            view.resignFirstResponder()
            view.install(text: prompt, blanks: [CoachPromptBlank(range: target)], selection: target)
            view.activate(selecting: target)
            XCTAssertTrue(view.isFirstResponder)
            await Task.yield()
            XCTAssertEqual(view.selectedRange, target)
        }
    }

    func testMultipleBlanksMoveAfterUnicodePrefixEditsAndOnlyEditedBlankResolves() {
        let text = "🙂 Train [chest] with [dumbbells]"
        let blanks = CoachTemplates.editablePlaceholderRanges(in: text).map { CoachPromptBlank(range: NSRange($0, in: text)) }
        let moved = CoachPromptBlank.applyingEdit(NSRange(location: 0, length: 0), replacementLength: 3, to: blanks)
        XCTAssertEqual(moved.map(\.range.location), blanks.map { $0.range.location + 3 })
        let remaining = CoachPromptBlank.applyingEdit(blanks[0].range, replacementLength: 4, to: blanks)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].range.location, blanks[1].range.location - 1)
    }

    func testQuoteStylesAndSelectionDoNotIncludeDelimiters() {
        for text in ["练「肩部和背部」", "练『肩部』", "练【背部】", "Train [shoulders]", "Train “back”", "Train «épaules»", "Train \"arms\""] {
            let ranges = CoachTemplates.editablePlaceholderRanges(in: text)
            XCTAssertEqual(ranges.count, 1, text)
            if let range = ranges.first {
                XCTAssertFalse(String(text[range]).contains("「"))
                XCTAssertFalse(String(text[range]).contains("["))
                XCTAssertFalse(String(text[range]).contains("\""))
            }
        }
    }
    func testNewPromptRejectsStaleOutOfBoundsSelectionAndRanges() {
        let view = CoachPromptTextView()
        view.install(text: "short", blanks: [CoachPromptBlank(range: NSRange(location: 12, length: 4))],
                     selection: NSRange(location: 12, length: 4))
        XCTAssertTrue(view.blanks.isEmpty)
        XCTAssertLessThanOrEqual(NSMaxRange(view.selectedRange), 5)
    }
}
