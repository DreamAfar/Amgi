import SwiftUI
import UIKit

struct RichNoteFieldEditor: UIViewRepresentable {
    @Binding var htmlText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(htmlText: $htmlText)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.typingAttributes = Coordinator.defaultTypingAttributes

        let attr = Coordinator.attributedFromHTML(htmlText)
        textView.attributedText = attr
        context.coordinator.lastSerializedHTML = Coordinator.htmlFromAttributed(attr)
        context.coordinator.currentTextView = textView
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.currentTextView = uiView
        if context.coordinator.isProgrammaticUpdate {
            return
        }

        if htmlText != context.coordinator.lastSerializedHTML {
            context.coordinator.isProgrammaticUpdate = true
            let selected = uiView.selectedRange
            let attr = Coordinator.attributedFromHTML(htmlText)
            uiView.attributedText = attr
            let maxLoc = max(0, min(selected.location, attr.length))
            uiView.selectedRange = NSRange(location: maxLoc, length: 0)
            context.coordinator.lastSerializedHTML = Coordinator.htmlFromAttributed(attr)
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIColorPickerViewControllerDelegate {
        static let defaultFont = UIFont.preferredFont(forTextStyle: .body)
        static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: UIColor.label,
        ]

        @Binding var htmlText: String
        var isProgrammaticUpdate = false
        var lastSerializedHTML: String = ""
        weak var currentTextView: UITextView?
        private var colorPickerSelectionRange: NSRange = NSRange(location: 0, length: 0)

        init(htmlText: Binding<String>) {
            self._htmlText = htmlText
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            let serialized = Self.htmlFromAttributed(textView.attributedText)
            lastSerializedHTML = serialized
            htmlText = serialized
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            currentTextView = textView
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else {
                return UIMenu(children: suggestedActions)
            }

            let formatMenu = UIMenu(
                title: L("rich_text_menu_title"),
                options: .displayInline,
                children: [
                    UIAction(title: L("rich_text_action_bold")) { [weak self, weak textView] _ in
                        guard let self, let textView else { return }
                        self.toggleBold(in: textView)
                    },
                    UIAction(title: L("rich_text_action_italic")) { [weak self, weak textView] _ in
                        guard let self, let textView else { return }
                        self.toggleItalic(in: textView)
                    },
                    UIAction(title: L("rich_text_action_underline")) { [weak self, weak textView] _ in
                        guard let self, let textView else { return }
                        self.toggleUnderline(in: textView)
                    },
                    UIAction(title: L("rich_text_action_strikethrough")) { [weak self, weak textView] _ in
                        guard let self, let textView else { return }
                        self.toggleStrikethrough(in: textView)
                    },
                    UIMenu(
                        title: L("rich_text_action_color"),
                        children: [
                            UIAction(title: L("rich_text_color_red")) { [weak self, weak textView] _ in
                                guard let self, let textView else { return }
                                self.applyColor(.systemRed, in: textView)
                            },
                            UIAction(title: L("rich_text_color_blue")) { [weak self, weak textView] _ in
                                guard let self, let textView else { return }
                                self.applyColor(.systemBlue, in: textView)
                            },
                            UIAction(title: L("rich_text_color_green")) { [weak self, weak textView] _ in
                                guard let self, let textView else { return }
                                self.applyColor(.systemGreen, in: textView)
                            },
                            UIAction(title: L("rich_text_color_default")) { [weak self, weak textView] _ in
                                guard let self, let textView else { return }
                                self.applyColor(.label, in: textView)
                            },
                            UIAction(title: L("rich_text_color_custom")) { [weak self, weak textView] _ in
                                guard let self, let textView else { return }
                                self.presentColorPicker(for: textView)
                            },
                        ]
                    ),
                    UIAction(title: L("rich_text_action_clear_format")) { [weak self, weak textView] _ in
                        guard let self, let textView else { return }
                        self.clearFormatting(in: textView)
                    },
                ]
            )

            return UIMenu(children: suggestedActions + [formatMenu])
        }

        private func toggleBold(in textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            applyFontTrait(in: textView, range: range, trait: .traitBold)
        }

        private func toggleItalic(in textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            applyFontTrait(in: textView, range: range, trait: .traitItalic)
        }

        private func toggleUnderline(in textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            toggleAttribute(
                key: .underlineStyle,
                enabledValue: NSUnderlineStyle.single.rawValue,
                in: textView,
                range: range
            )
        }

        private func toggleStrikethrough(in textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            toggleAttribute(
                key: .strikethroughStyle,
                enabledValue: NSUnderlineStyle.single.rawValue,
                in: textView,
                range: range
            )
        }

        private func applyFontTrait(in textView: UITextView, range: NSRange, trait: UIFontDescriptor.SymbolicTraits) {
            let storage = textView.textStorage
            let shouldRemove = selectionHasTrait(in: storage, range: range, trait: trait)
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let current = (value as? UIFont) ?? Self.defaultFont
                var traits = current.fontDescriptor.symbolicTraits
                if shouldRemove {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }
                let descriptor = current.fontDescriptor.withSymbolicTraits(traits) ?? current.fontDescriptor
                let updated = UIFont(descriptor: descriptor, size: current.pointSize)
                storage.addAttribute(.font, value: updated, range: subRange)
            }
            storage.endEditing()
            textView.selectedRange = range
            textViewDidChange(textView)
        }

        private func selectionHasTrait(
            in storage: NSTextStorage,
            range: NSRange,
            trait: UIFontDescriptor.SymbolicTraits
        ) -> Bool {
            var hasTraitEverywhere = true
            storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
                let font = (value as? UIFont) ?? Self.defaultFont
                if !font.fontDescriptor.symbolicTraits.contains(trait) {
                    hasTraitEverywhere = false
                    stop.pointee = true
                }
            }
            return hasTraitEverywhere
        }

        private func applyColor(_ color: UIColor, in textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            textView.textStorage.addAttribute(.foregroundColor, value: color, range: range)
            textView.selectedRange = range
            textViewDidChange(textView)
        }

        private func toggleAttribute(
            key: NSAttributedString.Key,
            enabledValue: Int,
            in textView: UITextView,
            range: NSRange
        ) {
            let storage = textView.textStorage
            let shouldRemove = selectionHasAttributeValue(
                in: storage,
                range: range,
                key: key,
                expected: enabledValue
            )
            storage.beginEditing()
            if shouldRemove {
                storage.removeAttribute(key, range: range)
            } else {
                storage.addAttribute(key, value: enabledValue, range: range)
            }
            storage.endEditing()
            textView.selectedRange = range
            textViewDidChange(textView)
        }

        private func selectionHasAttributeValue(
            in storage: NSTextStorage,
            range: NSRange,
            key: NSAttributedString.Key,
            expected: Int
        ) -> Bool {
            var hasValueEverywhere = true
            storage.enumerateAttribute(key, in: range, options: []) { value, _, stop in
                guard let number = value as? NSNumber, number.intValue == expected else {
                    hasValueEverywhere = false
                    stop.pointee = true
                    return
                }
            }
            return hasValueEverywhere
        }

        private func presentColorPicker(for textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }
            colorPickerSelectionRange = range
            currentTextView = textView

            let picker = UIColorPickerViewController()
            picker.delegate = self
            picker.selectedColor = .label
            picker.supportsAlpha = false

            guard let presenter = topViewController() else { return }
            presenter.present(picker, animated: true)
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            guard let textView = currentTextView else { return }
            applyColor(viewController.selectedColor, in: textView, range: colorPickerSelectionRange)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            guard let textView = currentTextView else { return }
            applyColor(viewController.selectedColor, in: textView, range: colorPickerSelectionRange)
        }

        private func applyColor(_ color: UIColor, in textView: UITextView, range: NSRange) {
            guard range.length > 0 else { return }
            textView.textStorage.addAttribute(.foregroundColor, value: color, range: range)
            textView.selectedRange = range
            textViewDidChange(textView)
        }

        private func topViewController(
            from controller: UIViewController? = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \ .isKeyWindow)?.rootViewController
        ) -> UIViewController? {
            if let nav = controller as? UINavigationController {
                return topViewController(from: nav.visibleViewController)
            }
            if let tab = controller as? UITabBarController {
                return topViewController(from: tab.selectedViewController)
            }
            if let presented = controller?.presentedViewController {
                return topViewController(from: presented)
            }
            return controller
        }

        private func clearFormatting(in textView: UITextView) {
            let range = textView.selectedRange
            guard range.length > 0 else { return }

            let plain = textView.textStorage.attributedSubstring(from: range).string
            let reset = NSAttributedString(string: plain, attributes: Self.defaultTypingAttributes)

            textView.textStorage.beginEditing()
            textView.textStorage.replaceCharacters(in: range, with: reset)
            textView.textStorage.endEditing()
            textView.selectedRange = NSRange(location: range.location, length: plain.utf16.count)
            textViewDidChange(textView)
        }

        static func attributedFromHTML(_ html: String) -> NSAttributedString {
            guard !html.isEmpty else { return NSAttributedString(string: "", attributes: defaultTypingAttributes) }

            if let data = html.data(using: .utf8),
               let attributed = try? NSMutableAttributedString(
                   data: data,
                   options: [
                       .documentType: NSAttributedString.DocumentType.html,
                       .characterEncoding: String.Encoding.utf8.rawValue,
                   ],
                   documentAttributes: nil
               ) {
                normalizeFonts(in: attributed)
                return attributed
            }

            return NSAttributedString(string: html, attributes: defaultTypingAttributes)
        }

        static func htmlFromAttributed(_ attributed: NSAttributedString) -> String {
            let mutable = NSMutableAttributedString(attributedString: attributed)
            normalizeFonts(in: mutable)
            let range = NSRange(location: 0, length: mutable.length)
            if let data = try? mutable.data(
                from: range,
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ]
            ), let html = String(data: data, encoding: .utf8) {
                return html
            }
            return attributed.string
        }

        private static func normalizeFonts(in attributed: NSMutableAttributedString) {
            let full = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
                let font = (value as? UIFont) ?? defaultFont
                let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits)
                    ?? font.fontDescriptor
                let normalized = UIFont(descriptor: descriptor, size: defaultFont.pointSize)
                attributed.addAttribute(.font, value: normalized, range: range)
            }
        }
    }
}
