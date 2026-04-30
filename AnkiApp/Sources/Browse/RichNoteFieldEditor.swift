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
        let container = ToolbarContainerView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        container.backgroundColor = .secondarySystemBackground
        container.clipsToBounds = false

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        container.addSubview(divider)

        let bubble = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .systemBackground
        bubble.layer.cornerRadius = 18
        bubble.layer.shadowColor = UIColor.black.withAlphaComponent(0.16).cgColor
        bubble.layer.shadowOpacity = 1
        bubble.layer.shadowRadius = 14
        bubble.layer.shadowOffset = CGSize(width: 0, height: 8)
        bubble.layer.borderWidth = 1
        bubble.layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
        bubble.isHidden = true
        bubble.alpha = 0
        container.addSubview(bubble)

        let bubbleScrollView = UIScrollView()
        bubbleScrollView.translatesAutoresizingMaskIntoConstraints = false
        bubbleScrollView.showsHorizontalScrollIndicator = false
        bubbleScrollView.showsVerticalScrollIndicator = false
        bubbleScrollView.alwaysBounceHorizontal = true
        bubbleScrollView.alwaysBounceVertical = false
        bubble.addSubview(bubbleScrollView)

        let bubbleStackView = UIStackView()
        bubbleStackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleStackView.axis = .horizontal
        bubbleStackView.alignment = .center
        bubbleStackView.spacing = 10
        bubbleScrollView.addSubview(bubbleStackView)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        container.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        scrollView.addSubview(stackView)

        var activeInlineMenu: String?
        let dismissInlineMenu: () -> Void = {
            activeInlineMenu = nil
            UIView.animate(withDuration: 0.18) {
                bubble.alpha = 0
            } completion: { _ in
                bubble.isHidden = true
            }
        }

        func showInlineMenu(key: String, views: [UIView]) {
            if activeInlineMenu == key, bubble.isHidden == false {
                dismissInlineMenu()
                return
            }

            activeInlineMenu = key
            bubbleStackView.arrangedSubviews.forEach { subview in
                bubbleStackView.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }
            views.forEach { bubbleStackView.addArrangedSubview($0) }
            bubble.isHidden = false
            bubble.alpha = 0
            UIView.animate(withDuration: 0.18) {
                bubble.alpha = 1
            }
        }

        stackView.addArrangedSubview(
            makeSymbolButton(systemName: "arrow.uturn.backward") {
                dismissInlineMenu()
                coordinator.performUndo()
            }
        )
        stackView.addArrangedSubview(
            makeSymbolButton(systemName: "arrow.uturn.forward") {
                dismissInlineMenu()
                coordinator.performRedo()
            }
        )

        stackView.addArrangedSubview(
            makeFormatButton(systemName: "bold", title: boldTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<b>", suffix: "</b>")
                } else {
                    coordinator.toggleBold()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "italic", title: italicTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<i>", suffix: "</i>")
                } else {
                    coordinator.toggleItalic()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "underline", title: underlineTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<u>", suffix: "</u>")
                } else {
                    coordinator.toggleUnderline()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "strikethrough", title: strikeTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<s>", suffix: "</s>")
                } else {
                    coordinator.toggleStrikethrough()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "textformat.superscript", title: superscriptTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<sup>", suffix: "</sup>")
                } else {
                    coordinator.applySuperscript()
                }
            }
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "textformat.subscript", title: subscriptTitle) {
                dismissInlineMenu()
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
                tintColor: .systemBlue
            ) {
                showInlineMenu(
                    key: "foreground",
                    views: makeColorPaletteViews(
                        customActionTitle: colorTitle,
                        colors: [
                            .label,
                            .systemYellow,
                            .systemPurple,
                            .systemRed,
                            .systemOrange,
                            .systemGreen,
                            .systemBlue,
                            .black,
                        ],
                        coordinator: coordinator,
                        applyColor: { selectedColor in
                            coordinator.applyForegroundColor(selectedColor)
                            dismissInlineMenu()
                        },
                        applyCustom: {
                            dismissInlineMenu()
                            coordinator.presentForegroundColorPicker()
                        }
                    )
                )
            )
        )
        stackView.addArrangedSubview(
            makeMenuButton(
                systemName: "highlighter",
                title: highlightTitle,
                tintColor: .systemYellow
            ) {
                showInlineMenu(
                    key: "highlight",
                    views: makeColorPaletteViews(
                        customActionTitle: highlightTitle,
                        colors: [
                            UIColor.systemGray3,
                            UIColor.systemYellow.withAlphaComponent(0.35),
                            UIColor.systemPurple.withAlphaComponent(0.25),
                            UIColor.systemRed.withAlphaComponent(0.25),
                            UIColor.systemOrange.withAlphaComponent(0.25),
                            UIColor.systemGreen.withAlphaComponent(0.35),
                            UIColor.systemBlue.withAlphaComponent(0.25),
                            UIColor.clear,
                        ],
                        coordinator: coordinator,
                        applyColor: { selectedColor in
                            if selectedColor == .clear {
                                coordinator.applyHighlightColorStyle("transparent")
                            } else {
                                coordinator.applyHighlightColor(selectedColor)
                            }
                            dismissInlineMenu()
                        },
                        applyCustom: {
                            dismissInlineMenu()
                            coordinator.presentHighlightColorPicker()
                        }
                    )
                )
            )
        )
        stackView.addArrangedSubview(
            makeMenuButton(
                systemName: "function",
                title: mathJaxTitle,
                tintColor: .systemTeal
            ) {
                showInlineMenu(
                    key: "mathjax",
                    views: makeMathPaletteViews(
                        coordinator: coordinator,
                        dismissMenu: dismissInlineMenu
                    )
                )
            )
        )
        stackView.addArrangedSubview(
            makeFormatButton(systemName: "textformat", title: clearFormatTitle) {
                dismissInlineMenu()
                coordinator.clearFormattingInSelection()
            }
        )

        stackView.addArrangedSubview(
            makeTextButton(title: doneButtonTitle) {
                dismissInlineMenu()
                textView.resignFirstResponder()
            }
        )

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            bubble.bottomAnchor.constraint(equalTo: container.topAnchor, constant: -8),
            bubble.heightAnchor.constraint(equalToConstant: 52),

            bubbleScrollView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            bubbleScrollView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            bubbleScrollView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6),
            bubbleScrollView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),

            bubbleStackView.leadingAnchor.constraint(equalTo: bubbleScrollView.contentLayoutGuide.leadingAnchor),
            bubbleStackView.trailingAnchor.constraint(equalTo: bubbleScrollView.contentLayoutGuide.trailingAnchor),
            bubbleStackView.topAnchor.constraint(equalTo: bubbleScrollView.contentLayoutGuide.topAnchor),
            bubbleStackView.bottomAnchor.constraint(equalTo: bubbleScrollView.contentLayoutGuide.bottomAnchor),
            bubbleStackView.heightAnchor.constraint(equalTo: bubbleScrollView.frameLayoutGuide.heightAnchor),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -12)
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
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = tintColor
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

    private func makeColorPaletteViews(
        customActionTitle: String,
        colors: [UIColor],
        coordinator: Coordinator,
        applyColor: @escaping (UIColor) -> Void,
        applyCustom: @escaping () -> Void
    ) -> [UIView] {
        colors.enumerated().map { index, color in
            makePaletteSwatchButton(
                color: color,
                accessibilityLabel: index == colors.count - 1 && color == .clear
                    ? L("rich_text_color_default")
                    : customActionTitle
            ) {
                applyColor(color)
                coordinator.textView?.becomeFirstResponder()
            }
        } + [
            makePaletteActionButton(
                title: nil,
                systemName: "plus",
                tintColor: .label
            ) {
                applyCustom()
            }
        ]
    }

    private func makeMathPaletteViews(
        coordinator: Coordinator,
        dismissMenu: @escaping () -> Void
    ) -> [UIView] {
        [
            makePaletteActionButton(title: "f(x)", tintColor: .systemTeal) {
                coordinator.wrapSelection(prefix: #"\("#, suffix: #"\)"#)
                dismissMenu()
            },
            makePaletteActionButton(title: "[x]", tintColor: .systemTeal) {
                coordinator.wrapSelection(prefix: #"\["#, suffix: #"\]"#)
                dismissMenu()
            },
            makePaletteActionButton(title: "ce{}", tintColor: .systemTeal) {
                coordinator.wrapSelection(prefix: #"\(\ce{"#, suffix: #"}\)"#)
                dismissMenu()
            },
        ]
    }

    private func makePaletteSwatchButton(
        color: UIColor,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel
        button.backgroundColor = color == .clear ? .secondarySystemFill : color
        button.layer.cornerRadius = 16
        button.layer.borderWidth = color == .clear ? 1 : 0
        button.layer.borderColor = UIColor.separator.cgColor
        if color == .clear {
            button.setImage(UIImage(systemName: "slash.circle"), for: .normal)
            button.tintColor = .secondaryLabel
        }
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makePaletteActionButton(
        title: String?,
        systemName: String? = nil,
        tintColor: UIColor,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = tintColor
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 16
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        if let title {
            button.setTitle(title, for: .normal)
            button.setTitleColor(tintColor, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        } else if let systemName {
            button.setImage(UIImage(systemName: systemName), for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        }
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
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
            finalizeMarkedTextIfNeeded()
            textView.replace(range, withText: string)
            commitCurrentValue()
        }

        func wrapSelection(prefix: String, suffix: String) {
            guard let textView else { return }
            finalizeMarkedTextIfNeeded()
            guard preservesSourceHTML else {
                let selected = textView.selectedRange
                let selectedText = selected.length > 0
                    ? textView.attributedText.attributedSubstring(from: selected).string
                    : ""
                let replacement = "\(prefix)\(selectedText)\(suffix)"
                let cursorOffset = selected.length > 0 ? replacement.count : prefix.count
                insertRichText(replacement, cursorOffset: cursorOffset)
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
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                Self.updatedFontAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    trait: .traitBold
                )
            }
        }

        func toggleItalic() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                Self.updatedFontAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    trait: .traitItalic
                )
            }
        }

        func toggleUnderline() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                var updated = attributes
                updated[.underlineStyle] = NSUnderlineStyle.single.rawValue
                return updated
            }
        }

        func toggleStrikethrough() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                var updated = attributes
                updated[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                return updated
            }
        }

        func applySuperscript() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                Self.updatedBaselineAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    baselineOffset: 6
                )
            }
        }

        func applySubscript() {
            finalizeMarkedTextIfNeeded()
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
            finalizeMarkedTextIfNeeded()
            Self.storeColor(color, forKey: Self.lastForegroundColorKey)
            applyForegroundColorStyle(Self.hexString(from: color))
        }

        func applyForegroundColorStyle(_ styleValue: String) {
            finalizeMarkedTextIfNeeded()
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
            finalizeMarkedTextIfNeeded()
            Self.storeColor(color, forKey: Self.lastHighlightColorKey)
            applyHighlightColorStyle(Self.cssColorString(from: color))
        }

        func applyHighlightColorStyle(_ styleValue: String) {
            finalizeMarkedTextIfNeeded()
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
            finalizeMarkedTextIfNeeded()
            if textView.selectedRange.length == 0 {
                presentClearAllFormattingConfirmation()
                return
            }

            clearFormatting(in: textView, range: textView.selectedRange)
        }

        func performUndo() {
            guard let textView else { return }
            finalizeMarkedTextIfNeeded()
            textView.undoManager?.undo()
            commitCurrentValue()
        }

        func performRedo() {
            guard let textView else { return }
            finalizeMarkedTextIfNeeded()
            textView.undoManager?.redo()
            commitCurrentValue()
        }

        private func finalizeMarkedTextIfNeeded() {
            guard let textView, textView.markedTextRange != nil else { return }
            textView.unmarkText()
            commitCurrentValue()
        }

        private func presentClearAllFormattingConfirmation() {
            guard let presenter = topPresenter() else { return }

            let alert = UIAlertController(
                title: L("rich_text_clear_all_title"),
                message: L("rich_text_clear_all_message"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L("common_cancel"), style: .cancel))
            alert.addAction(
                UIAlertAction(
                    title: L("rich_text_clear_all_confirm"),
                    style: .destructive
                ) { [weak self] _ in
                    guard let self, let textView = self.textView else { return }
                    self.clearFormatting(in: textView, range: nil)
                }
            )
            presenter.present(alert, animated: true)
        }

        private func clearFormatting(in textView: UITextView, range: NSRange?) {
            guard preservesSourceHTML else {
                clearAttributedFormatting(in: textView, range: range)
                return
            }

            let original = textView.text ?? ""
            let source = original as NSString

            let targetRange: NSRange
            if let range {
                targetRange = range
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

        private func clearAttributedFormatting(in textView: UITextView, range: NSRange?) {
            let selected = textView.selectedRange
            let targetRange = range
                ?? NSRange(location: 0, length: textView.attributedText.length)

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

            return normalizedStoredHTML(from: mutable as String)
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

private final class ToolbarContainerView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }

        for subview in subviews where !subview.isHidden && subview.alpha > 0.01 {
            let converted = subview.convert(point, from: self)
            if subview.point(inside: converted, with: event) {
                return true
            }
        }
        return false
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
