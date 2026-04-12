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
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.typingAttributes = Coordinator.defaultTypingAttributes
        textView.inputAccessoryView = context.coordinator.makeAccessoryToolbar(for: textView)

        let attr = Coordinator.attributedFromHTML(htmlText)
        textView.attributedText = attr
        context.coordinator.lastRenderedHTML = htmlText
        context.coordinator.lastSerializedHTML = Coordinator.htmlFromAttributed(attr)
        context.coordinator.currentTextView = textView
        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let height = min(max(56, fit.height), 220)
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.currentTextView = uiView
        if context.coordinator.isProgrammaticUpdate {
            return
        }

        if htmlText != context.coordinator.lastRenderedHTML {
            context.coordinator.isProgrammaticUpdate = true
            let selected = uiView.selectedRange
            let attr = Coordinator.attributedFromHTML(htmlText)
            uiView.attributedText = attr
            let maxLoc = max(0, min(selected.location, attr.length))
            uiView.selectedRange = NSRange(location: maxLoc, length: 0)
            context.coordinator.lastRenderedHTML = htmlText
            context.coordinator.lastSerializedHTML = Coordinator.htmlFromAttributed(attr)
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIColorPickerViewControllerDelegate {
        static let defaultFont = UIFont.preferredFont(forTextStyle: .body)
        static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: UIColor.label,
        ]

        @Binding var htmlText: String
        var isProgrammaticUpdate = false
        var lastRenderedHTML: String = ""
        var lastSerializedHTML: String = ""
        weak var currentTextView: UITextView?
        private var colorPickerSelectionRange: NSRange = NSRange(location: 0, length: 0)

        init(htmlText: Binding<String>) {
            self._htmlText = htmlText
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            let serialized = Self.htmlFromAttributed(textView.attributedText)
            lastRenderedHTML = serialized
            lastSerializedHTML = serialized
            htmlText = serialized
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            currentTextView = textView
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
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

        func makeAccessoryToolbar(for textView: UITextView) -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.items = [
                UIBarButtonItem(
                    image: UIImage(systemName: "textformat"),
                    menu: formattingMenu(for: textView)
                ),
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(
                    systemItem: .done,
                    primaryAction: UIAction { [weak textView] _ in
                        textView?.resignFirstResponder()
                    }
                ),
            ]
            toolbar.sizeToFit()
            return toolbar
        }

        private func formattingMenu(for textView: UITextView) -> UIMenu {
            UIMenu(
                title: L("rich_text_menu_title"),
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
                .first(where: \.isKeyWindow)?.rootViewController
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

            guard isLikelyHTML(html) else {
                return NSAttributedString(string: html, attributes: defaultTypingAttributes)
            }

            let normalizedHTML = sanitizeHTMLForEditing(wrapHTMLFragmentIfNeeded(html))

            if let data = normalizedHTML.data(using: .utf8),
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
            // Keep plain text as plain text to avoid writing full HTML wrappers unnecessarily.
            if attributed.length == 0 {
                return ""
            }

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
                if let body = extractHTMLBodyFragment(html) {
                    return body
                }
                return html
            }
            return attributed.string
        }

        private static func isLikelyHTML(_ text: String) -> Bool {
            text.range(of: "</?[A-Za-z][^>]*>", options: .regularExpression) != nil
            || text.range(of: "&(?:[A-Za-z]+|#[0-9]+|#x[0-9A-Fa-f]+);", options: .regularExpression) != nil
        }

        private static func wrapHTMLFragmentIfNeeded(_ html: String) -> String {
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return html }

            if trimmed.range(of: "<html[\\s>]", options: .regularExpression) != nil {
                return trimmed
            }

            return "<html><head><meta charset=\"utf-8\"></head><body>\(trimmed)</body></html>"
        }

        private static func sanitizeHTMLForEditing(_ html: String) -> String {
            var sanitized = html
            let patterns = [
                #"<script\b[^>]*>[\s\S]*?</script>"#,
                #"<style\b[^>]*>[\s\S]*?</style>"#,
                #"<iframe\b[^>]*>[\s\S]*?</iframe>"#,
                #"<audio\b[^>]*>[\s\S]*?</audio>"#,
                #"<video\b[^>]*>[\s\S]*?</video>"#,
                #"<source\b[^>]*>"#,
                #"<track\b[^>]*>"#,
                #"<img\b[^>]*>"#,
            ]

            for pattern in patterns {
                sanitized = sanitized.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }

            return sanitized
        }

        private static func extractHTMLBodyFragment(_ html: String) -> String? {
            guard
                let open = html.range(of: "<body[^>]*>", options: .regularExpression),
                let close = html.range(of: "</body>", options: [.caseInsensitive, .backwards]),
                open.upperBound <= close.lowerBound
            else {
                return nil
            }

            let fragment = String(html[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return fragment.isEmpty ? nil : fragment
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
