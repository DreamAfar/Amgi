import SwiftUI
import UIKit

/// A note field editor that can switch between rendered rich text editing and
/// raw HTML/source editing.
///
/// Amgi stores field values as HTML fragments. In rendered mode, this editor
/// maps a conservative subset of HTML to attributed text for inline editing.
/// In source mode, it preserves the raw stored HTML.
struct LegacyRichNoteFieldTextEditor: UIViewRepresentable {
    @Binding var htmlText: String
    var preservesSourceHTML = false
    var onInsertPhoto: (() -> Void)?
    var onInsertCameraPhoto: (() -> Void)?
    var onInsertFile: (() -> Void)?
    var onRecordAudio: (() -> Void)?

    static func normalizedStoredHTML(_ text: String) -> String {
        Coordinator.normalizedStoredHTML(from: text)
    }

    private let boldTitle = L("rich_text_action_bold")
    private let italicTitle = L("rich_text_action_italic")
    private let underlineTitle = L("rich_text_action_underline")
    private let strikeTitle = L("rich_text_action_strikethrough")
    private let superscriptTitle = L("rich_text_action_superscript")
    private let subscriptTitle = L("rich_text_action_subscript")
    private let colorTitle = L("rich_text_action_color")
    private let highlightTitle = L("rich_text_action_highlight")
    private let mathJaxTitle = L("rich_text_action_mathjax")
    private let bulletListTitle = L("rich_text_action_bullet_list")
    private let numberedListTitle = L("rich_text_action_numbered_list")
    private let alignmentTitle = L("rich_text_action_alignment")
    private let insertAttachmentTitle = L("rich_text_action_attachment")
    private let recordAudioTitle = L("rich_text_action_record_audio")
    private let choosePhotoTitle = L("note_editor_media_import_photo")
    private let takePhotoTitle = L("note_editor_media_import_camera")
    private let chooseFileTitle = L("note_editor_media_import_file")
    private let alignLeftTitle = L("rich_text_action_align_left")
    private let alignCenterTitle = L("rich_text_action_align_center")
    private let alignRightTitle = L("rich_text_action_align_right")
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
        let modeChanged = context.coordinator.preservesSourceHTML != preservesSourceHTML
        context.coordinator.preservesSourceHTML = preservesSourceHTML
        if modeChanged {
            let selected = uiView.selectedRange
            context.coordinator.render(html: htmlText, in: uiView)
            let maxLoc = max(0, min(selected.location, uiView.attributedText.length))
            uiView.selectedRange = NSRange(location: maxLoc, length: 0)
            return
        }

        if context.coordinator.isEditing {
            context.coordinator.trackExternalHTMLUpdateWhileEditing(htmlText)
            return
        }
        guard htmlText != context.coordinator.lastRenderedValue else { return }
        let selected = uiView.selectedRange
        context.coordinator.render(html: htmlText, in: uiView)
        let maxLoc = max(0, min(selected.location, uiView.attributedText.length))
        uiView.selectedRange = NSRange(location: maxLoc, length: 0)
    }

    // MARK: - Toolbar

    private func makeInputToolbar(for textView: UITextView, coordinator: Coordinator) -> UIView {
        let container = ToolbarContainerView(frame: CGRect(x: 0, y: 0, width: 0, height: 68))
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

        let toolbarStack = UIStackView()
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.axis = .vertical
        toolbarStack.alignment = .fill
        toolbarStack.distribution = .fillEqually
        toolbarStack.spacing = 4
        container.addSubview(toolbarStack)

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

        func makeRow(_ views: [UIView]) -> UIStackView {
            let row = UIStackView(arrangedSubviews: views)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 4
            return row
        }

        let firstRowButtons: [UIView] = [
            makeFormatButton(systemName: "bold", title: boldTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<b>", suffix: "</b>")
                } else {
                    coordinator.toggleBold()
                }
            },
            makeFormatButton(systemName: "italic", title: italicTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<i>", suffix: "</i>")
                } else {
                    coordinator.toggleItalic()
                }
            },
            makeFormatButton(systemName: "underline", title: underlineTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<u>", suffix: "</u>")
                } else {
                    coordinator.toggleUnderline()
                }
            },
            makeFormatButton(systemName: "strikethrough", title: strikeTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<s>", suffix: "</s>")
                } else {
                    coordinator.toggleStrikethrough()
                }
            },
            makeFormatButton(systemName: "textformat.superscript", title: superscriptTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<sup>", suffix: "</sup>")
                } else {
                    coordinator.applySuperscript()
                }
            },
            makeFormatButton(systemName: "textformat.subscript", title: subscriptTitle) {
                dismissInlineMenu()
                if coordinator.preservesSourceHTML {
                    coordinator.wrapSelection(prefix: "<sub>", suffix: "</sub>")
                } else {
                    coordinator.applySubscript()
                }
            },
            makeMenuButton(systemName: "paintpalette", title: colorTitle, tintColor: .systemBlue) {
                showInlineMenu(
                    key: "foreground",
                    views: makeColorPaletteViews(
                        choices: [
                            (.label, .label),
                            (.systemYellow, .systemYellow),
                            (.systemPurple, .systemPurple),
                            (.systemRed, .systemRed),
                            (.systemOrange, .systemOrange),
                            (.systemGreen, .systemGreen),
                            (.systemBlue, .systemBlue),
                        ],
                        customActionTitle: colorTitle,
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
            },
            makeMenuButton(systemName: "highlighter", title: highlightTitle, tintColor: .systemYellow) {
                showInlineMenu(
                    key: "highlight",
                    views: makeColorPaletteViews(
                        choices: [
                            (.systemYellow, UIColor.systemYellow.withAlphaComponent(0.35)),
                            (.systemPurple, UIColor.systemPurple.withAlphaComponent(0.25)),
                            (.systemRed, UIColor.systemRed.withAlphaComponent(0.25)),
                            (.systemOrange, UIColor.systemOrange.withAlphaComponent(0.25)),
                            (.systemGreen, UIColor.systemGreen.withAlphaComponent(0.35)),
                            (.systemBlue, UIColor.systemBlue.withAlphaComponent(0.25)),
                            (.systemGray3, .clear),
                        ],
                        customActionTitle: highlightTitle,
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
            },
            makeFormatButton(systemName: "textformat", title: clearFormatTitle) {
                dismissInlineMenu()
                coordinator.clearFormattingInSelection()
            }
        ]

        let secondRowButtons: [UIView] = [
            makeFormatButton(systemName: "list.bullet", title: bulletListTitle) {
                dismissInlineMenu()
                coordinator.toggleBulletList()
            },
            makeFormatButton(systemName: "list.number", title: numberedListTitle) {
                dismissInlineMenu()
                coordinator.toggleNumberedList()
            },
            makeMenuButton(systemName: "text.alignleft", title: alignmentTitle, tintColor: .systemBlue) {
                showInlineMenu(
                    key: "alignment",
                    views: makeAlignmentPaletteViews(
                        coordinator: coordinator,
                        dismissMenu: dismissInlineMenu
                    )
                )
            },
            makeMenuButton(systemName: "function", title: mathJaxTitle, tintColor: .systemTeal) {
                showInlineMenu(
                    key: "mathjax",
                    views: makeMathPaletteViews(
                        coordinator: coordinator,
                        dismissMenu: dismissInlineMenu
                    )
                )
            },
            makeMenuButton(systemName: "paperclip", title: insertAttachmentTitle, tintColor: .systemBlue) {
                showInlineMenu(
                    key: "attachment",
                    views: makeAttachmentPaletteViews(
                        dismissMenu: dismissInlineMenu,
                        textView: textView
                    )
                )
            },
            makeFormatButton(systemName: "mic.fill", title: recordAudioTitle) {
                dismissInlineMenu()
                textView.resignFirstResponder()
                onRecordAudio?()
            },
            makeSymbolButton(systemName: "arrow.uturn.backward", title: L("common_undo")) {
                dismissInlineMenu()
                coordinator.performUndo()
            },
            makeSymbolButton(systemName: "arrow.uturn.forward", title: L("common_redo")) {
                dismissInlineMenu()
                coordinator.performRedo()
            },
            makeSymbolButton(systemName: "keyboard.chevron.compact.down", title: L("common_done")) {
                dismissInlineMenu()
                textView.resignFirstResponder()
            }
        ]

        toolbarStack.addArrangedSubview(makeRow(firstRowButtons))
        toolbarStack.addArrangedSubview(makeRow(secondRowButtons))

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0),

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

            toolbarStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            toolbarStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            toolbarStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            toolbarStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        return container
    }

    private func makeSymbolButton(systemName: String, title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeFormatButton(systemName: String, title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeColorPaletteViews(
        choices: [(displayColor: UIColor, appliedColor: UIColor)],
        customActionTitle: String,
        applyColor: @escaping (UIColor) -> Void,
        applyCustom: @escaping () -> Void
    ) -> [UIView] {
        choices.enumerated().map { index, choice in
            makePaletteSwatchButton(
                color: choice.displayColor,
                accessibilityLabel: index == choices.count - 1 && choice.appliedColor == .clear
                    ? L("rich_text_color_default")
                    : customActionTitle
            ) {
                applyColor(choice.appliedColor)
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

    private func makeAlignmentPaletteViews(
        coordinator: Coordinator,
        dismissMenu: @escaping () -> Void
    ) -> [UIView] {
        [
            makePaletteActionButton(title: alignLeftTitle, tintColor: .systemBlue) {
                coordinator.applyTextAlignment(.left)
                dismissMenu()
            },
            makePaletteActionButton(title: alignCenterTitle, tintColor: .systemBlue) {
                coordinator.applyTextAlignment(.center)
                dismissMenu()
            },
            makePaletteActionButton(title: alignRightTitle, tintColor: .systemBlue) {
                coordinator.applyTextAlignment(.right)
                dismissMenu()
            },
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

    private func makeAttachmentPaletteViews(
        dismissMenu: @escaping () -> Void,
        textView: UITextView
    ) -> [UIView] {
        [
            makePaletteActionButton(title: choosePhotoTitle, tintColor: .systemBlue) {
                dismissMenu()
                textView.resignFirstResponder()
                onInsertPhoto?()
            },
            makePaletteActionButton(title: takePhotoTitle, tintColor: .systemBlue) {
                dismissMenu()
                textView.resignFirstResponder()
                onInsertCameraPhoto?()
            },
            makePaletteActionButton(title: chooseFileTitle, tintColor: .systemBlue) {
                dismissMenu()
                textView.resignFirstResponder()
                onInsertFile?()
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

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIColorPickerViewControllerDelegate {
        @Binding var htmlText: String
        private static let lastForegroundColorKey = "amgi.rich_text.last_foreground_color"
        private static let lastHighlightColorKey = "amgi.rich_text.last_highlight_color"
        var preservesSourceHTML: Bool

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

        func trackExternalHTMLUpdateWhileEditing(_ html: String) {
            let normalized = Self.normalizedStoredHTML(from: html)
            guard normalized != lastRenderedValue else { return }
            guard Self.containsEmbeddedMediaMarkup(normalized) else { return }
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
                let renderedSnapshot = Self.renderedAttributedString(
                    from: lastRenderedValue,
                    baseFont: baseFont
                ).string
                if Self.containsEmbeddedMediaMarkup(lastRenderedValue),
                   textView.attributedText.string == renderedSnapshot {
                    normalized = lastRenderedValue
                } else {
                    normalized = Self.serializedHTML(
                        from: textView.attributedText,
                        baseFont: baseFont
                    )
                }
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
                Self.toggledFontAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    trait: .traitBold
                )
            }
        }

        func toggleItalic() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                Self.toggledFontAttributes(
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
                if (attributes[.underlineStyle] as? Int ?? 0) != 0 {
                    updated.removeValue(forKey: .underlineStyle)
                } else {
                    updated[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                return updated
            }
        }

        func toggleStrikethrough() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                var updated = attributes
                if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 {
                    updated.removeValue(forKey: .strikethroughStyle)
                } else {
                    updated[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                return updated
            }
        }

        func applySuperscript() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                Self.toggledBaselineAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    baselineOffset: 6,
                    direction: .superscript
                )
            }
        }

        func applySubscript() {
            finalizeMarkedTextIfNeeded()
            applyAttributedTransformation { attributes in
                Self.toggledBaselineAttributes(
                    from: attributes,
                    baseFont: baseFont,
                    baselineOffset: -4,
                    direction: .subscripted
                )
            }
        }

        private func toggleListMarkers(ordered: Bool) {
            guard let textView else { return }
            finalizeMarkedTextIfNeeded()

            let targetRange = Self.paragraphRange(for: textView.selectedRange, in: textView.text ?? "")
            let sourceText = preservesSourceHTML ? (textView.text ?? "") : textView.attributedText.string
            let source = sourceText as NSString
            let original = source.substring(with: targetRange)
            let lines = original.components(separatedBy: "\n")
            let allMarked = lines.allSatisfy { line in
                ordered ? Self.isNumberedListLine(line) : Self.isBulletListLine(line)
            }

            let updatedLines = lines.enumerated().map { index, line in
                if ordered {
                    return allMarked
                        ? Self.removingNumberMarker(from: line)
                        : Self.appendingNumberMarker(to: line, number: index + 1)
                }
                return allMarked
                    ? Self.removingBulletMarker(from: line)
                    : Self.appendingBulletMarker(to: line)
            }

            let updated = updatedLines.joined(separator: "\n")
            replacePlainText(in: targetRange, with: updated)
        }

        private func replacePlainText(in range: NSRange, with string: String) {
            guard let textView else { return }
            if preservesSourceHTML {
                let source = (textView.text ?? "") as NSString
                textView.text = source.replacingCharacters(in: range, with: string)
                let cursor = range.location + (string as NSString).length
                textView.selectedRange = NSRange(location: cursor, length: 0)
                commitCurrentValue()
                return
            }

            let typingAttributes = textView.typingAttributes
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let replacement = NSAttributedString(string: string, attributes: typingAttributes)
            mutable.replaceCharacters(in: range, with: replacement)
            textView.attributedText = mutable
            let cursor = range.location + replacement.length
            textView.selectedRange = NSRange(location: cursor, length: 0)
            textView.typingAttributes = Self.typingAttributes(
                from: mutable,
                at: cursor,
                baseFont: baseFont
            )
            commitCurrentValue()
        }

        func toggleBulletList() {
            toggleListMarkers(ordered: false)
        }

        func toggleNumberedList() {
            toggleListMarkers(ordered: true)
        }

        func applyTextAlignment(_ alignment: NSTextAlignment) {
            finalizeMarkedTextIfNeeded()
            if preservesSourceHTML {
                let cssValue = Self.cssTextAlignmentValue(for: alignment)
                wrapSelection(
                    prefix: #"<div style="text-align: \#(cssValue);">"#,
                    suffix: "</div>"
                )
                return
            }

            guard let textView else { return }
            let selected = textView.selectedRange
            if selected.length == 0 {
                let currentStyle = (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                currentStyle.alignment = currentStyle.alignment == alignment ? .natural : alignment
                var updated = textView.typingAttributes
                if currentStyle.alignment == .natural {
                    updated.removeValue(forKey: .paragraphStyle)
                } else {
                    updated[.paragraphStyle] = currentStyle
                }
                textView.typingAttributes = updated
                return
            }

            let targetRange = Self.paragraphRange(for: selected, in: textView.attributedText.string)
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.enumerateAttributes(in: targetRange, options: []) { attributes, range, _ in
                var updated = attributes
                let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.alignment = style.alignment == alignment ? .natural : alignment
                if style.alignment == .natural {
                    updated.removeValue(forKey: .paragraphStyle)
                } else {
                    updated[.paragraphStyle] = style
                }
                mutable.setAttributes(updated, range: range)
            }
            textView.attributedText = mutable
            textView.selectedRange = selected
            commitCurrentValue()
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

        static func paragraphRange(for range: NSRange, in text: String) -> NSRange {
            let source = text as NSString
            guard source.length > 0 else { return NSRange(location: 0, length: 0) }
            let location = min(range.location, max(source.length - 1, 0))
            let start = source.paragraphRange(for: NSRange(location: location, length: 0)).location
            let endLocation = min(range.location + max(range.length - 1, 0), max(source.length - 1, 0))
            let endRange = source.paragraphRange(for: NSRange(location: endLocation, length: 0))
            return NSRange(location: start, length: endRange.location + endRange.length - start)
        }

        static func cssTextAlignmentValue(for alignment: NSTextAlignment) -> String? {
            switch alignment {
            case .center:
                return "center"
            case .right:
                return "right"
            case .justified:
                return "justify"
            case .left, .natural:
                return "left"
            @unknown default:
                return nil
            }
        }

        static func isBulletListLine(_ line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix("• ")
        }

        static func isNumberedListLine(_ line: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: #"^\s*\d+\.\s"#) else { return false }
            let range = NSRange(location: 0, length: (line as NSString).length)
            return regex.firstMatch(in: line, range: range) != nil
        }

        static func appendingBulletMarker(to line: String) -> String {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else { return line }
            return "• \(line)"
        }

        static func removingBulletMarker(from line: String) -> String {
            line.replacingOccurrences(of: #"^\s*•\s"#, with: "", options: .regularExpression)
        }

        static func appendingNumberMarker(to line: String, number: Int) -> String {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else { return line }
            return "\(number). \(line)"
        }

        static func removingNumberMarker(from line: String) -> String {
            line.replacingOccurrences(of: #"^\s*\d+\.\s"#, with: "", options: .regularExpression)
        }

        static func toggledFontAttributes(
            from attributes: [NSAttributedString.Key: Any],
            baseFont: UIFont,
            trait: UIFontDescriptor.SymbolicTraits
        ) -> [NSAttributedString.Key: Any] {
            var updated = attributes
            let font = (attributes[.font] as? UIFont) ?? baseFont
            var traits = font.fontDescriptor.symbolicTraits
            let hasItalicObliqueness = ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) != 0
            let isEnabled = traits.contains(trait) || (trait == .traitItalic && hasItalicObliqueness)
            if isEnabled {
                traits.remove(trait)
            } else {
                traits.insert(trait)
            }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                ?? font.fontDescriptor
            updated[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            if trait == .traitItalic {
                if isEnabled {
                    updated.removeValue(forKey: .obliqueness)
                } else {
                    updated[.obliqueness] = 0
                }
            }
            return updated
        }

        enum BaselineDirection {
            case superscript
            case subscripted
        }

        static func toggledBaselineAttributes(
            from attributes: [NSAttributedString.Key: Any],
            baseFont: UIFont,
            baselineOffset: CGFloat,
            direction: BaselineDirection
        ) -> [NSAttributedString.Key: Any] {
            var updated = attributes
            let font = (attributes[.font] as? UIFont) ?? baseFont
            let currentBaseline = (attributes[.baselineOffset] as? NSNumber)?.doubleValue
                ?? Double(attributes[.baselineOffset] as? CGFloat ?? 0)
            let isSameDirection = direction == .superscript ? currentBaseline > 0 : currentBaseline < 0

            if isSameDirection {
                updated[.font] = font.withSize(max(font.pointSize / 0.8, baseFont.pointSize))
                updated.removeValue(forKey: .baselineOffset)
            } else {
                updated[.font] = font.withSize(max(font.pointSize * 0.8, 12))
                updated[.baselineOffset] = baselineOffset
            }
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
                if traits.contains(.traitItalic) {
                    updated[.obliqueness] = 0
                }

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
            if traits.contains(.traitItalic)
                || ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) != 0 {
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
            if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle,
               let cssAlignment = cssTextAlignmentValue(for: paragraphStyle.alignment),
               cssAlignment != "left" {
                styleRules.append("text-align: \(cssAlignment);")
            }
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

        private static func containsEmbeddedMediaMarkup(_ text: String) -> Bool {
            let lowercasedText = text.lowercased()
            return lowercasedText.contains("<img")
                || lowercasedText.contains("<svg")
                || lowercasedText.contains("<audio")
                || lowercasedText.contains("<video")
                || lowercasedText.contains("[sound:")
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
