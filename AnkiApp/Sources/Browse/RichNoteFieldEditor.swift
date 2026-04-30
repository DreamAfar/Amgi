import SwiftUI
import UIKit

/// A note field editor that can switch between rendered rich text editing and
/// raw HTML/source editing.
///
/// Amgi stores field values as HTML fragments. In rendered mode, this editor
/// maps a conservative subset of HTML to attributed text for inline editing.
/// In source mode, it preserves the raw stored HTML.
struct RichNoteFieldEditor: UIViewRepresentable {
    @Binding var htmlText: String
    var preservesSourceHTML = false

    static func normalizedStoredHTML(_ text: String) -> String {
        Coordinator.normalizedStoredHTML(from: text)
    }

    private let doneButtonTitle = L("common_done")
    private let boldTitle = L("rich_text_action_bold")
    private let italicTitle = L("rich_text_action_italic")
    private let underlineTitle = L("rich_text_action_underline")
    private let strikeTitle = L("rich_text_action_strikethrough")
    private let superscriptTitle = L("rich_text_action_superscript")
    private let subscriptTitle = L("rich_text_action_subscript")
    private let colorTitle = L("rich_text_action_color")
    private let highlightTitle = L("rich_text_action_highlight")
    private let mathJaxTitle = L("rich_text_action_mathjax")
    private let mathJaxInlineTitle = L("rich_text_action_mathjax_inline")
    private let mathJaxBlockTitle = L("rich_text_action_mathjax_block")
    private let mathJaxChemistryTitle = L("rich_text_action_mathjax_chemistry")
    private let clearFormatTitle = L("rich_text_action_clear_format")

    func makeCoordinator() -> Coordinator {
        Coordinator(
            htmlText: $htmlText,
            preservesSourceHTML: preservesSourceHTML
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = 0
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.textColor = .label
        context.coordinator.attach(textView: textView)
        textView.inputAccessoryView = makeInputToolbar(for: textView, coordinator: context.coordinator)
        context.coordinator.render(html: htmlText, in: textView)
        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = min(max(32, fit.height), 160)
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        guard htmlText != context.coordinator.lastRenderedValue else { return }
        let selected = uiView.selectedRange
        context.coordinator.render(html: htmlText, in: uiView)
        let maxLoc = max(0, min(selected.location, uiView.attributedText.length))
        uiView.selectedRange = NSRange(location: maxLoc, length: 0)
    }

    // MARK: - Toolbar

    private func makeInputToolbar(for textView: UITextView, coordinator: Coordinator) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        container.backgroundColor = .secondarySystemBackground

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        container.addSubview(divider)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        container.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        scrollView.addSubview(stackView)

        stackView.addArrangedSubview(
            makeSymbolButton(systemName: "arrow.uturn.backward") {
                textView.undoManager?.undo()
            }
        )
        stackView.addArrangedSubview(
            makeSymbolButton(systemName: "arrow.uturn.forward") {
                textView.undoManager?.redo()
            }
        )

        stackView.addArrangedSubview(
            makeFormatButton(systemName: "bold", title: boldTitle) {
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<b>", suffix: "</b>")
                } else {
                    coordinator.toggleBold()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "italic", title: italicTitle) {
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<i>", suffix: "</i>")
                } else {
                    coordinator.toggleItalic()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "underline", title: underlineTitle) {
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<u>", suffix: "</u>")
                } else {
                    coordinator.toggleUnderline()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "strikethrough", title: strikeTitle) {
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<s>", suffix: "</s>")
                } else {
                    coordinator.toggleStrikethrough()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "textformat.superscript", title: superscriptTitle) {
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<sup>", suffix: "</sup>")
                } else {
                    coordinator.applySuperscript()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "textformat.subscript", title: subscriptTitle) {
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<sub>", suffix: "</sub>")
                } else {
                    coordinator.applySubscript()
                }
            }
        )
        stackView.addArrangedSubview(
            makeMenuButton(
                systemName: "paintpalette",
                title: colorTitle,
                tintColor: .systemBlue,
                menu: makeTextColorMenu(coordinator: coordinator)
            )
        )
        stackView.addArrangedSubview(
            makeMenuButton(
                systemName: "highlighter",
                title: highlightTitle,
                tintColor: .systemYellow,
                menu: makeHighlightMenu(coordinator: coordinator)
            )
        )
        stackView.addArrangedSubview(
            makeMenuButton(
                systemName: "function",
                title: mathJaxTitle,
                tintColor: .systemTeal,
                menu: makeMathJaxMenu(coordinator: coordinator)
            )
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "textformat", title: clearFormatTitle) {
                coordinator.clearFormattingInSelection()
            }
        )

        stackView.addArrangedSubview(
            makeTextButton(title: doneButtonTitle) {
                textView.resignFirstResponder()
            }
        )

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -12),
        ])

        return container
    }

    private func makeSymbolButton(systemName: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 8
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .tertiarySystemFill
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeFormatButton(systemName: String, title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .tertiarySystemFill
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeMenuButton(
        systemName: String,
        title: String,
        tintColor: UIColor,
        menu: UIMenu
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = tintColor
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .tertiarySystemFill
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return button
    }

    private func makeTextColorMenu(coordinator: Coordinator) -> UIMenu {
        UIMenu(title: colorTitle, children: [
            UIAction(title: L("rich_text_color_red")) { _ in
                coordinator.applyForegroundColor(.systemRed)
            },
            UIAction(title: L("rich_text_color_blue")) { _ in
                coordinator.applyForegroundColor(.systemBlue)
            },
            UIAction(title: L("rich_text_color_green")) { _ in
                coordinator.applyForegroundColor(.systemGreen)
            },
            UIAction(title: L("rich_text_color_default")) { _ in
                coordinator.applyForegroundColorStyle("inherit")
            },
            UIAction(title: L("rich_text_color_custom")) { _ in
                coordinator.presentForegroundColorPicker()
            }
        ])
    }

    private func makeHighlightMenu(coordinator: Coordinator) -> UIMenu {
        UIMenu(title: highlightTitle, children: [
            UIAction(title: L("rich_text_color_yellow")) { _ in
                coordinator.applyHighlightColor(.systemYellow.withAlphaComponent(0.35))
            },
            UIAction(title: L("rich_text_color_green")) { _ in
                coordinator.applyHighlightColor(.systemGreen.withAlphaComponent(0.35))
            },
            UIAction(title: L("rich_text_color_blue")) { _ in
                coordinator.applyHighlightColor(.systemBlue.withAlphaComponent(0.25))
            },
            UIAction(title: L("rich_text_color_default")) { _ in
                coordinator.applyHighlightColorStyle("transparent")
            },
            UIAction(title: L("rich_text_color_custom")) { _ in
                coordinator.presentHighlightColorPicker()
            }
        ])
    }

    private func makeMathJaxMenu(coordinator: Coordinator) -> UIMenu {
        UIMenu(title: mathJaxTitle, children: [
            UIAction(title: mathJaxInlineTitle) { _ in
                coordinator.wrapSelection(prefix: #"\("#, suffix: #"\)"#)
            },
            UIAction(title: mathJaxBlockTitle) { _ in
                coordinator.wrapSelection(prefix: #"\["#, suffix: #"\]"#)
            },
            UIAction(title: mathJaxChemistryTitle) { _ in
                coordinator.wrapSelection(prefix: #"\(\ce{"#, suffix: #"}\)"#)
            }
        ])
    }

    private func makeTextButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.titleLabel?.numberOfLines = 1
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .tertiarySystemFill
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIColorPickerViewControllerDelegate {
        @Binding var htmlText: String
        private static let lastForegroundColorKey = "amgi.rich_text.last_foreground_color"
        private static let lastHighlightColorKey = "amgi.rich_text.last_highlight_color"
        let preservesSourceHTML: Bool

        weak var textView: UITextView?
        var lastRenderedValue: String = ""
        var isEditing = false
        private var colorSelectionHandler: ((UIColor) -> Void)?
        private let baseFont = UIFont.preferredFont(forTextStyle: .body)

        init(htmlText: Binding<String>, preservesSourceHTML: Bool) {
            self._htmlText = htmlText
            self.preservesSourceHTML = preservesSourceHTML
        }

        func attach(textView: UITextView) {
            self.textView = textView
        }

        func render(html: String, in textView: UITextView) {
            let normalized = Self.normalizedStoredHTML(from: html)
            if preservesSourceHTML {
                textView.text = normalized
                textView.font = baseFont
                textView.textColor = .label
                textView.typingAttributes = Self.baseTypingAttributes(font: baseFont)
            } else {
                let attributed = Self.renderedAttributedString(
                    from: normalized,
                    baseFont: baseFont
                )
                textView.attributedText = attributed
                textView.typingAttributes = Self.typingAttributes(
                    from: attributed,
                    at: min(textView.selectedRange.location, attributed.length),
                    baseFont: baseFont
                )
            }
            lastRenderedValue = normalized
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            guard preservesSourceHTML == false else { return }
            textView.typingAttributes = Self.typingAttributes(
                from: textView.attributedText,
                at: textView.selectedRange.location,
                baseFont: baseFont
            )
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            commitCurrentValue()
        }

        func textViewDidChange(_ textView: UITextView) {
            commitCurrentValue()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard preservesSourceHTML == false else { return }
            textView.typingAttributes = Self.typingAttributes(
                from: textView.attributedText,
                at: textView.selectedRange.location,
                baseFont: baseFont
            )
        }

        private func commitCurrentValue() {
            guard let textView else { return }
            let normalized: String
            if preservesSourceHTML {
                normalized = Self.normalizedStoredHTML(from: textView.text ?? "")
            } else {
                normalized = Self.serializedHTML(
                    from: textView.attributedText,
                    baseFont: baseFont
                )
            }
            lastRenderedValue = normalized
            htmlText = normalized
        }

        func insert(_ string: String) {
            guard let textView, let range = textView.selectedTextRange else { return }
            textView.replace(range, withText: string)
            commitCurrentValue()
        }

        func wrapSelection(prefix: String, suffix: String) {
            guard let textView else { return }
            guard preservesSourceHTML else {
                insertRichText(prefix + suffix, cursorOffset: prefix.count)
                return
            }
            let selected = textView.selectedRange
            let original = textView.text ?? ""
            let source = original as NSString
            let selectedText = source.substring(with: selected)
            let replacement = "\(prefix)\(selectedText)\(suffix)"
            let updated = source.replacingCharacters(in: selected, with: replacement)
            textView.text = updated

            if selected.length == 0 {
                let cursor = selected.location + (prefix as NSString).length
                textView.selectedRange = NSRange(location: cursor, length: 0)
            } else {
                let rangeStart = selected.location + (prefix as NSString).length
                textView.selectedRange = NSRange(location: rangeStart, length: selected.length)
            }

            commitCurrentValue()
        }

        func toggleBold() {
            applyAttributedTransformation { attributes in
                Self.updatedFontAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    trait: .traitBold
                )
            }
        }

        func toggleItalic() {
            applyAttributedTransformation { attributes in
                Self.updatedFontAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    trait: .traitItalic
                )
            }
        }

        func toggleUnderline() {
            applyAttributedTransformation { attributes in
                var updated = attributes
                updated[.underlineStyle] = NSUnderlineStyle.single.rawValue
                return updated
            }
        }

        func toggleStrikethrough() {
            applyAttributedTransformation { attributes in
                var updated = attributes
                updated[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                return updated
            }
        }

        func applySuperscript() {
            applyAttributedTransformation { attributes in
                Self.updatedBaselineAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    baselineOffset: 6
                )
            }
        }

        func applySubscript() {
            applyAttributedTransformation { attributes in
                Self.updatedBaselineAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    baselineOffset: -4
                )
            }
        }

        private func insertRichText(_ string: String, cursorOffset: Int? = nil) {
            guard let textView else { return }
            let selected = textView.selectedRange
            let replacement = NSAttributedString(
                string: string,
                attributes: textView.typingAttributes
            )
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.replaceCharacters(in: selected, with: replacement)
            textView.attributedText = mutable
            let offset = cursorOffset ?? string.count
            textView.selectedRange = NSRange(
                location: selected.location + offset,
                length: 0
            )
            textView.typingAttributes = Self.typingAttributes(
                from: mutable,
                at: textView.selectedRange.location,
                baseFont: baseFont
            )
            commitCurrentValue()
        }

        private func applyAttributedTransformation(
            _ transform: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]
        ) {
            guard preservesSourceHTML == false, let textView else { return }
            let selected = textView.selectedRange

            if selected.length == 0 {
                textView.typingAttributes = transform(textView.typingAttributes)
                return
            }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttributes(in: selected, options: []) { attributes, range, _ in
                let updated = transform(attributes)
                mutable.setAttributes(updated, range: range)
            }

            textView.attributedText = mutable
            textView.selectedRange = selected
            textView.typingAttributes = Self.typingAttributes(
                from: mutable,
                at: selected.location + selected.length,
                baseFont: baseFont
            )
            commitCurrentValue()
        }

        func applyForegroundColor(_ color: UIColor) {
            Self.storeColor(color, forKey: Self.lastForegroundColorKey)
            applyForegroundColorStyle(Self.hexString(from: color))
        }

        func applyForegroundColorStyle(_ styleValue: String) {
            if preservesSourceHTML {
                wrapSelection(
                    prefix: #"<span style="color: \#(styleValue);">"#,
                    suffix: "</span>"
                )
            } else {
                let color = styleValue == "inherit" ? UIColor.label : (UIColor(hex: styleValue) ?? .label)
                applyAttributedTransformation { attributes in
                    var updated = attributes
                    updated[.foregroundColor] = color
                    return updated
                }
            }
        }

        func applyHighlightColor(_ color: UIColor) {
            Self.storeColor(color, forKey: Self.lastHighlightColorKey)
            applyHighlightColorStyle(Self.cssColorString(from: color))
        }

        func applyHighlightColorStyle(_ styleValue: String) {
            if preservesSourceHTML {
                wrapSelection(
                    prefix: #"<span style="background-color: \#(styleValue);">"#,
                    suffix: "</span>"
                )
            } else {
                let color = styleValue == "transparent"
                    ? UIColor.clear
                    : (Self.color(fromCSS: styleValue) ?? UIColor.clear)
                applyAttributedTransformation { attributes in
                    var updated = attributes
                    updated[.backgroundColor] = color
                    return updated
                }
            }
        }

        func presentForegroundColorPicker() {
            presentColorPicker(
                initialColor: Self.loadColor(
                    forKey: Self.lastForegroundColorKey,
                    fallback: .systemBlue
                )
            ) { [weak self] color in
                self?.applyForegroundColor(color)
            }
        }

        func presentHighlightColorPicker() {
            presentColorPicker(
                initialColor: Self.loadColor(
                    forKey: Self.lastHighlightColorKey,
                    fallback: .systemYellow
                )
            ) { [weak self] color in
                self?.applyHighlightColor(color.withAlphaComponent(0.35))
            }
        }

        private func presentColorPicker(
            initialColor: UIColor,
            onPick: @escaping (UIColor) -> Void
        ) {
            guard let presenter = topPresenter() else { return }

            let picker = UIColorPickerViewController()
            picker.supportsAlpha = false
            picker.selectedColor = initialColor
            picker.delegate = self
            colorSelectionHandler = onPick
            presenter.present(picker, animated: true)
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            colorSelectionHandler?(viewController.selectedColor)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            colorSelectionHandler = nil
            textView?.becomeFirstResponder()
        }

        private func topPresenter() -> UIViewController? {
            var controller = textView?.window?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }

        func clearFormattingInSelection() {
            guard let textView else { return }
            guard preservesSourceHTML else {
                clearAttributedFormatting(in: textView)
                return
            }
            let selected = textView.selectedRange
            let original = textView.text ?? ""
            let source = original as NSString

            let targetRange: NSRange
            if selected.length > 0 {
                targetRange = selected
            } else {
                targetRange = NSRange(location: 0, length: source.length)
            }

            let target = source.substring(with: targetRange)
            let cleaned = Self.removeInlineHTMLFormatting(from: target)
            let updated = source.replacingCharacters(in: targetRange, with: cleaned)
            textView.text = updated

            let cursor = targetRange.location + (cleaned as NSString).length
            textView.selectedRange = NSRange(location: cursor, length: 0)
            commitCurrentValue()
        }

        private func clearAttributedFormatting(in textView: UITextView) {
            let selected = textView.selectedRange
            let targetRange = selected.length > 0
                ? selected
                : NSRange(location: 0, length: textView.attributedText.length)

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttributes(in: targetRange, options: []) { attributes, range, _ in
                var updated = attributes
                updated[.font] = baseFont
                updated[.foregroundColor] = UIColor.label
                updated.removeValue(forKey: .backgroundColor)
                updated.removeValue(forKey: .underlineStyle)
                updated.removeValue(forKey: .strikethroughStyle)
                updated.removeValue(forKey: .baselineOffset)
                mutable.setAttributes(updated, range: range)
            }

            textView.attributedText = mutable
            textView.selectedRange = selected
            textView.typingAttributes = Self.baseTypingAttributes(font: baseFont)
            commitCurrentValue()
        }

        // MARK: - HTML strip

        static func renderedAttributedString(
            from html: String,
            baseFont: UIFont
        ) -> NSAttributedString {
            guard html.isEmpty == false else {
                return NSAttributedString(
                    string: "",
                    attributes: baseTypingAttributes(font: baseFont)
                )
            }

            guard isLikelyHTML(html) else {
                return NSAttributedString(
                    string: html,
                    attributes: baseTypingAttributes(font: baseFont)
                )
            }

            let document = """
            <html>
            <head>
            <meta charset="utf-8">
            <style>
            body { font: -apple-system-body; color: #000000; }
            </style>
            </head>
            <body>\(html)</body>
            </html>
            """

            guard
                let data = document.data(using: .utf8),
                let imported = try? NSMutableAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue,
                    ],
                    documentAttributes: nil
                )
            else {
                return NSAttributedString(
                    string: plainText(from: html),
                    attributes: baseTypingAttributes(font: baseFont)
                )
            }

            normalizeImportedAttributes(imported, baseFont: baseFont)
            return imported
        }

        static func serializedHTML(
            from attributedText: NSAttributedString,
            baseFont: UIFont
        ) -> String {
            guard attributedText.length > 0 else { return "" }

            let mutable = NSMutableString()
            attributedText.enumerateAttributes(
                in: NSRange(location: 0, length: attributedText.length),
                options: []
            ) { attributes, range, _ in
                let text = attributedText.attributedSubstring(from: range).string
                let wrappers = wrappers(for: attributes, baseFont: baseFont)
                wrappers.prefix.forEach { mutable.append($0) }
                for character in text {
                    if character == "\n" {
                        mutable.append("<br>")
                    } else {
                        mutable.append(escapeHTML(String(character)))
                    }
                }
                wrappers.suffix.forEach { mutable.append($0) }
            }

            return normalizedStoredHTML(mutable as String)
        }

        static func baseTypingAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .foregroundColor: UIColor.label,
            ]
        }

        static func typingAttributes(
            from attributedText: NSAttributedString,
            at location: Int,
            baseFont: UIFont
        ) -> [NSAttributedString.Key: Any] {
            guard attributedText.length > 0 else {
                return baseTypingAttributes(font: baseFont)
            }

            let clampedLocation = max(0, min(location, attributedText.length - 1))
            var attributes = attributedText.attributes(
                at: clampedLocation,
                effectiveRange: nil
            )
            if attributes[.font] == nil {
                attributes[.font] = baseFont
            }
            if attributes[.foregroundColor] == nil {
                attributes[.foregroundColor] = UIColor.label
            }
            return attributes
        }

        static func updatedFontAttributes(
            from attributes: [NSAttributedString.Key: Any],
            baseFont: UIFont,
            trait: UIFontDescriptor.SymbolicTraits
        ) -> [NSAttributedString.Key: Any] {
            var updated = attributes
            let font = (attributes[.font] as? UIFont) ?? baseFont
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(trait)
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                ?? font.fontDescriptor
            updated[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            return updated
        }

        static func updatedBaselineAttributes(
            from attributes: [NSAttributedString.Key: Any],
            baseFont: UIFont,
            baselineOffset: CGFloat
        ) -> [NSAttributedString.Key: Any] {
            var updated = attributes
            let font = (attributes[.font] as? UIFont) ?? baseFont
            updated[.font] = font.withSize(max(font.pointSize * 0.8, 12))
            updated[.baselineOffset] = baselineOffset
            return updated
        }

        private static func normalizeImportedAttributes(
            _ attributed: NSMutableAttributedString,
            baseFont: UIFont
        ) {
            let fullRange = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                var updated = attributes
                let importedFont = (attributes[.font] as? UIFont) ?? baseFont
                let traits = importedFont.fontDescriptor.symbolicTraits
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
                    ?? baseFont.fontDescriptor
                let size = importedFont.pointSize < baseFont.pointSize ? importedFont.pointSize : baseFont.pointSize
                updated[.font] = UIFont(descriptor: descriptor, size: size)

                if let color = attributes[.foregroundColor] as? UIColor,
                   isDefaultForegroundColor(color) {
                    updated.removeValue(forKey: .foregroundColor)
                }
                if let background = attributes[.backgroundColor] as? UIColor,
                   resolvedComponents(for: background)?.alpha == 0 {
                    updated.removeValue(forKey: .backgroundColor)
                }
                attributed.setAttributes(updated, range: range)
            }
        }

        private static func wrappers(
            for attributes: [NSAttributedString.Key: Any],
            baseFont: UIFont
        ) -> (prefix: [String], suffix: [String]) {
            var prefix: [String] = []
            var suffix: [String] = []

            let font = (attributes[.font] as? UIFont) ?? baseFont
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) {
                prefix.append("<b>")
                suffix.insert("</b>", at: 0)
            }
            if traits.contains(.traitItalic) {
                prefix.append("<i>")
                suffix.insert("</i>", at: 0)
            }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 {
                prefix.append("<u>")
                suffix.insert("</u>", at: 0)
            }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 {
                prefix.append("<s>")
                suffix.insert("</s>", at: 0)
            }
            if let baseline = attributes[.baselineOffset] as? CGFloat {
                if baseline > 0 {
                    prefix.append("<sup>")
                    suffix.insert("</sup>", at: 0)
                } else if baseline < 0 {
                    prefix.append("<sub>")
                    suffix.insert("</sub>", at: 0)
                }
            } else if let baseline = attributes[.baselineOffset] as? NSNumber {
                if baseline.doubleValue > 0 {
                    prefix.append("<sup>")
                    suffix.insert("</sup>", at: 0)
                } else if baseline.doubleValue < 0 {
                    prefix.append("<sub>")
                    suffix.insert("</sub>", at: 0)
                }
            }

            var styleRules: [String] = []
            if let color = attributes[.foregroundColor] as? UIColor,
               isDefaultForegroundColor(color) == false {
                styleRules.append("color: \(hexString(from: color));")
            }
            if let background = attributes[.backgroundColor] as? UIColor,
               let components = resolvedComponents(for: background),
               components.alpha > 0 {
                styleRules.append("background-color: \(cssColorString(from: background));")
            }
            if styleRules.isEmpty == false {
                prefix.append(#"<span style="\#(styleRules.joined(separator: " "))">"#)
                suffix.insert("</span>", at: 0)
            }

            return (prefix, suffix)
        }

        private static func escapeHTML(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        /// Strips HTML tags and decodes common entities to produce editable plain text.
        static func plainText(from html: String) -> String {
            guard !html.isEmpty else { return "" }
            guard isLikelyHTML(html) else { return html }

            var result = ""
            result.reserveCapacity(html.count)
            var inTag = false
            for ch in html.unicodeScalars {
                switch ch {
                case "<": inTag = true
                case ">": inTag = false
                default:
                    if !inTag { result.unicodeScalars.append(ch) }
                }
            }

            result = result
                .replacingOccurrences(of: "&amp;",  with: "&")
                .replacingOccurrences(of: "&lt;",   with: "<")
                .replacingOccurrences(of: "&gt;",   with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;",  with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")

            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func normalizedStoredHTML(from text: String) -> String {
            guard text.localizedCaseInsensitiveContains("anki-mathjax") else { return text }
            let pattern = #"<anki-mathjax(?:[^>]*?block=\"(.*?)\")?[^>]*?>(.*?)</anki-mathjax>"#
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else {
                return text
            }

            let source = text as NSString
            var output = ""
            var currentLocation = 0

            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                let fullRange = match.range(at: 0)
                output += source.substring(with: NSRange(location: currentLocation, length: fullRange.location - currentLocation))

                let blockValue: String? = {
                    let range = match.range(at: 1)
                    guard range.location != NSNotFound else { return nil }
                    return source.substring(with: range)
                }()

                let innerText: String = {
                    let range = match.range(at: 2)
                    guard range.location != NSNotFound else { return "" }
                    return source.substring(with: range)
                }()

                let trimmed = trimMathJaxBreaks(in: innerText)
                if let blockValue, !blockValue.isEmpty, blockValue.caseInsensitiveCompare("false") != .orderedSame {
                    output += #"\["# + trimmed + #"\]"#
                } else {
                    output += #"\("# + trimmed + #"\)"#
                }

                currentLocation = fullRange.location + fullRange.length
            }

            output += source.substring(from: currentLocation)
            return output
        }

        private static func isLikelyHTML(_ text: String) -> Bool {
            text.contains("<") && text.contains(">")
        }

        private static func trimMathJaxBreaks(in text: String) -> String {
            text
                .replacingOccurrences(
                    of: #"<br[ ]*/?>"#,
                    with: "\n",
                    options: [.regularExpression, .caseInsensitive]
                )
                .replacingOccurrences(of: #"^\n*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n*$"#, with: "", options: .regularExpression)
        }

        private static func removeInlineHTMLFormatting(from text: String) -> String {
            var output = text
            let patterns = [
                "(?i)</?(b|strong|i|em|u|s|strike|del|sup|sub)>",
                "(?i)</?font[^>]*>",
                "(?i)</?span[^>]*>"
            ]
            for pattern in patterns {
                output = output.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
            return output
        }

        private static func loadColor(forKey key: String, fallback: UIColor) -> UIColor {
            guard let hex = UserDefaults.standard.string(forKey: key) else {
                return fallback
            }
            return UIColor(hex: hex) ?? fallback
        }

        private static func color(fromCSS cssValue: String) -> UIColor? {
            if cssValue.hasPrefix("#") {
                return UIColor(hex: cssValue)
            }

            let pattern = #"rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([0-9.]+))?\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let nsValue = cssValue as NSString
            guard let match = regex.firstMatch(
                in: cssValue,
                range: NSRange(location: 0, length: nsValue.length)
            ) else {
                return nil
            }

            let red = CGFloat(Int(nsValue.substring(with: match.range(at: 1))) ?? 0) / 255
            let green = CGFloat(Int(nsValue.substring(with: match.range(at: 2))) ?? 0) / 255
            let blue = CGFloat(Int(nsValue.substring(with: match.range(at: 3))) ?? 0) / 255
            let alpha: CGFloat
            if match.range(at: 4).location != NSNotFound {
                alpha = CGFloat(Double(nsValue.substring(with: match.range(at: 4))) ?? 1)
            } else {
                alpha = 1
            }
            return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        private static func storeColor(_ color: UIColor, forKey key: String) {
            UserDefaults.standard.set(hexString(from: color), forKey: key)
        }

        private static func hexString(from color: UIColor) -> String {
            guard let components = resolvedComponents(for: color) else {
                return "#000000"
            }
            return String(
                format: "#%02X%02X%02X",
                Int(components.red * 255),
                Int(components.green * 255),
                Int(components.blue * 255)
            )
        }

        private static func cssColorString(from color: UIColor) -> String {
            guard let components = resolvedComponents(for: color) else {
                return "rgba(0, 0, 0, 1.00)"
            }
            return String(
                format: "rgba(%d, %d, %d, %.2f)",
                Int(components.red * 255),
                Int(components.green * 255),
                Int(components.blue * 255),
                components.alpha
            )
        }

        private static func isDefaultForegroundColor(_ color: UIColor) -> Bool {
            color.isApproximatelyEqual(to: .black)
                || color.isApproximatelyEqual(to: .label)
        }

        private static func resolvedComponents(
            for color: UIColor
        ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
            let resolved = color.resolvedColor(with: UITraitCollection.current)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                return nil
            }
            return (red, green, blue, alpha)
        }
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func isApproximatelyEqual(to other: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        let resolvedSelf = resolvedColor(with: UITraitCollection.current)
        let resolvedOther = other.resolvedColor(with: UITraitCollection.current)

        var red1: CGFloat = 0
        var green1: CGFloat = 0
        var blue1: CGFloat = 0
        var alpha1: CGFloat = 0
        var red2: CGFloat = 0
        var green2: CGFloat = 0
        var blue2: CGFloat = 0
        var alpha2: CGFloat = 0

        guard resolvedSelf.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1),
              resolvedOther.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2)
        else { return false }

        return abs(red1 - red2) <= tolerance
            && abs(green1 - green2) <= tolerance
            && abs(blue1 - blue2) <= tolerance
            && abs(alpha1 - alpha2) <= tolerance
    }
}
