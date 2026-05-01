import SwiftUI
import UIKit
import WebKit

struct RichNoteFieldEditor: View {
    @Binding var htmlText: String
    var preservesSourceHTML = false
    var onInsertPhoto: (() -> Void)? = nil
    var onInsertCameraPhoto: (() -> Void)? = nil
    var onInsertFile: (() -> Void)? = nil
    var onRecordAudio: (() -> Void)? = nil

    static func normalizedStoredHTML(_ text: String) -> String {
        LegacyRichNoteFieldTextEditor.normalizedStoredHTML(text)
    }

    var body: some View {
        Group {
            if preservesSourceHTML {
                LegacyRichNoteFieldTextEditor(
                    htmlText: $htmlText,
                    preservesSourceHTML: true,
                    onInsertPhoto: onInsertPhoto,
                    onInsertCameraPhoto: onInsertCameraPhoto,
                    onInsertFile: onInsertFile,
                    onRecordAudio: onRecordAudio
                )
            } else {
                RenderedHTMLFieldEditor(
                    htmlText: $htmlText,
                    onInsertPhoto: onInsertPhoto,
                    onInsertCameraPhoto: onInsertCameraPhoto,
                    onInsertFile: onInsertFile,
                    onRecordAudio: onRecordAudio
                )
            }
        }
        .frame(minHeight: preservesSourceHTML ? 120 : 140, maxHeight: preservesSourceHTML ? 180 : 220)
    }
}

private struct RenderedHTMLFieldEditor: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var htmlText: String
    var onInsertPhoto: (() -> Void)?
    var onInsertCameraPhoto: (() -> Void)?
    var onInsertFile: (() -> Void)?
    var onRecordAudio: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(htmlText: $htmlText)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let webView = AccessoryWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.alwaysBounceVertical = true
        context.coordinator.webView = webView
        webView.accessoryView = makeInputToolbar(for: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = htmlDocument(colorScheme: colorScheme)
        if context.coordinator.lastDocument != document {
            context.coordinator.lastDocument = document
            context.coordinator.pendingHTMLAfterLoad = RichNoteFieldEditor.normalizedStoredHTML(htmlText)
            webView.loadHTMLString(document, baseURL: CardAssetPath.mediaBaseURL)
            return
        }

        let normalized = RichNoteFieldEditor.normalizedStoredHTML(htmlText)
        context.coordinator.pushHTMLIfNeeded(normalized)
    }

    private func htmlDocument(colorScheme: ColorScheme) -> String {
        let textColor = colorScheme == .dark ? "#F2F4F8" : "#17212F"
        let linkColor = colorScheme == .dark ? "#8FB8FF" : "#1E5BB8"
        let selectionColor = colorScheme == .dark ? "rgba(143,184,255,0.26)" : "rgba(30,91,184,0.18)"

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">
        \(CardAssetPath.mediaBaseTag())
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(textColor);
            font: -apple-system-body;
            overflow-wrap: anywhere;
            -webkit-text-size-adjust: 100%;
        }
        body {
            padding: 8px 0;
        }
        #editor {
            min-height: 108px;
            outline: none;
            caret-color: \(textColor);
            white-space: normal;
        }
        #editor:empty:before {
            content: '';
        }
        *::selection {
            background: \(selectionColor);
        }
        img, svg, video {
            display: block;
            max-width: 100%;
            height: auto;
            margin: 0 auto;
        }
        audio {
            width: 100%;
            max-width: 100%;
        }
        p {
            margin: 0 0 0.6em 0;
        }
        a {
            color: \(linkColor);
        }
        pre {
            white-space: pre-wrap;
        }
        </style>
        </head>
        <body>
            <div id=\"editor\" contenteditable=\"true\" spellcheck=\"false\" autocapitalize=\"off\" autocomplete=\"off\" autocorrect=\"off\"></div>
        <script>
        const editor = document.getElementById('editor');
        let isSyncingFromSwift = false;
        let lastSentHTML = '';

        function focusEditor() {
            editor.focus();
        }

        function unwrapNode(node) {
            const parent = node.parentNode;
            if (!parent) { return; }
            while (node.firstChild) {
                parent.insertBefore(node.firstChild, node);
            }
            parent.removeChild(node);
        }

        function stripFormatting(container) {
            const inlineTags = new Set(['B', 'STRONG', 'I', 'EM', 'U', 'S', 'STRIKE', 'DEL', 'SPAN', 'FONT', 'MARK', 'SUB', 'SUP']);
            const elements = Array.from(container.querySelectorAll('*'));
            for (const element of elements) {
                element.removeAttribute('style');
                element.removeAttribute('class');
            }
            for (let index = elements.length - 1; index >= 0; index -= 1) {
                const element = elements[index];
                if (inlineTags.has(element.tagName)) {
                    unwrapNode(element);
                }
            }
        }

        function normalizedHTML() {
            return editor.innerHTML;
        }

        function sendHTMLIfNeeded() {
            if (isSyncingFromSwift) { return; }
            const html = normalizedHTML();
            if (html === lastSentHTML) { return; }
            lastSentHTML = html;
            window.webkit.messageHandlers.\(Coordinator.messageHandlerName).postMessage({
                type: 'htmlChanged',
                html: html
            });
        }

        window.amgiNoteField = {
            setHTML(html) {
                isSyncingFromSwift = true;
                editor.innerHTML = html || '';
                lastSentHTML = normalizedHTML();
                isSyncingFromSwift = false;
            },
            focus() {
                focusEditor();
            },
            exec(command, value) {
                focusEditor();
                document.execCommand(command, false, value ?? null);
                sendHTMLIfNeeded();
            },
            insertHTML(html) {
                focusEditor();
                document.execCommand('insertHTML', false, html || '');
                sendHTMLIfNeeded();
            },
            wrapSelection(prefix, suffix) {
                focusEditor();
                const selection = window.getSelection();
                if (!selection || selection.rangeCount === 0) {
                    document.execCommand('insertHTML', false, prefix + suffix);
                    sendHTMLIfNeeded();
                    return;
                }
                const text = selection.toString() || '';
                document.execCommand('insertHTML', false, prefix + text + suffix);
                sendHTMLIfNeeded();
            },
            hasSelection() {
                const selection = window.getSelection();
                return !!selection && selection.rangeCount > 0 && selection.isCollapsed === false;
            },
            clearSelectionFormatting() {
                focusEditor();
                document.execCommand('removeFormat', false, null);
                document.execCommand('unlink', false, null);
                sendHTMLIfNeeded();
            },
            clearAllFormatting() {
                stripFormatting(editor);
                sendHTMLIfNeeded();
            },
            blur() {
                editor.blur();
            }
        };

        editor.addEventListener('input', sendHTMLIfNeeded);
        editor.addEventListener('blur', sendHTMLIfNeeded);
        </script>
        </body>
        </html>
        """
    }

    private func makeInputToolbar(for webView: WKWebView, coordinator: Coordinator) -> UIView {
        let container = WebToolbarContainerView(frame: CGRect(x: 0, y: 0, width: 0, height: 68))
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
            makeFormatButton(systemName: "bold", title: L("rich_text_action_bold")) {
                dismissInlineMenu()
                coordinator.exec("bold")
            },
            makeFormatButton(systemName: "italic", title: L("rich_text_action_italic")) {
                dismissInlineMenu()
                coordinator.exec("italic")
            },
            makeFormatButton(systemName: "underline", title: L("rich_text_action_underline")) {
                dismissInlineMenu()
                coordinator.exec("underline")
            },
            makeFormatButton(systemName: "strikethrough", title: L("rich_text_action_strikethrough")) {
                dismissInlineMenu()
                coordinator.exec("strikeThrough")
            },
            makeFormatButton(systemName: "textformat.superscript", title: L("rich_text_action_superscript")) {
                dismissInlineMenu()
                coordinator.exec("superscript")
            },
            makeFormatButton(systemName: "textformat.subscript", title: L("rich_text_action_subscript")) {
                dismissInlineMenu()
                coordinator.exec("subscript")
            },
            makeMenuButton(systemName: "paintpalette", title: L("rich_text_action_color"), tintColor: .systemBlue) {
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
                        applyColor: { color in
                            coordinator.applyForegroundColor(color)
                            dismissInlineMenu()
                        },
                        applyCustom: {
                            dismissInlineMenu()
                            coordinator.presentForegroundColorPicker()
                        }
                    )
                )
            },
            makeMenuButton(systemName: "highlighter", title: L("rich_text_action_highlight"), tintColor: .systemYellow) {
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
                        ],
                        applyColor: { color in
                            coordinator.applyHighlightColor(color)
                            dismissInlineMenu()
                        },
                        applyCustom: {
                            dismissInlineMenu()
                            coordinator.presentHighlightColorPicker()
                        }
                    )
                )
            },
            makeFormatButton(systemName: "textformat", title: L("rich_text_action_clear_format")) {
                dismissInlineMenu()
                coordinator.clearFormatting()
            }
        ]

        let secondRowButtons: [UIView] = [
            makeFormatButton(systemName: "list.bullet", title: L("rich_text_action_bullet_list")) {
                dismissInlineMenu()
                coordinator.exec("insertUnorderedList")
            },
            makeFormatButton(systemName: "list.number", title: L("rich_text_action_numbered_list")) {
                dismissInlineMenu()
                coordinator.exec("insertOrderedList")
            },
            makeMenuButton(systemName: "text.alignleft", title: L("rich_text_action_alignment"), tintColor: .systemBlue) {
                showInlineMenu(
                    key: "alignment",
                    views: [
                        makePaletteActionButton(title: L("rich_text_action_align_left"), tintColor: .systemBlue) {
                            coordinator.exec("justifyLeft")
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(title: L("rich_text_action_align_center"), tintColor: .systemBlue) {
                            coordinator.exec("justifyCenter")
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(title: L("rich_text_action_align_right"), tintColor: .systemBlue) {
                            coordinator.exec("justifyRight")
                            dismissInlineMenu()
                        }
                    ]
                )
            },
            makeMenuButton(systemName: "function", title: L("rich_text_action_mathjax"), tintColor: .systemTeal) {
                showInlineMenu(
                    key: "mathjax",
                    views: [
                        makePaletteActionButton(title: "f(x)", tintColor: .systemTeal) {
                            coordinator.wrapSelection(prefix: #"\("#, suffix: #"\)"#)
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(title: "[x]", tintColor: .systemTeal) {
                            coordinator.wrapSelection(prefix: #"\["#, suffix: #"\]"#)
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(title: "ce{}", tintColor: .systemTeal) {
                            coordinator.wrapSelection(prefix: #"\(\ce{"#, suffix: #"}\)"#)
                            dismissInlineMenu()
                        }
                    ]
                )
            },
            makeMenuButton(systemName: "paperclip", title: L("rich_text_action_attachment"), tintColor: .systemBlue) {
                showInlineMenu(
                    key: "attachment",
                    views: [
                        makePaletteActionButton(title: L("note_editor_media_import_photo"), tintColor: .systemBlue) {
                            dismissInlineMenu()
                            coordinator.blur()
                            onInsertPhoto?()
                        },
                        makePaletteActionButton(title: L("note_editor_media_import_camera"), tintColor: .systemBlue) {
                            dismissInlineMenu()
                            coordinator.blur()
                            onInsertCameraPhoto?()
                        },
                        makePaletteActionButton(title: L("note_editor_media_import_file"), tintColor: .systemBlue) {
                            dismissInlineMenu()
                            coordinator.blur()
                            onInsertFile?()
                        }
                    ]
                )
            },
            makeFormatButton(systemName: "mic.fill", title: L("rich_text_action_record_audio")) {
                dismissInlineMenu()
                coordinator.blur()
                onRecordAudio?()
            },
            makeSymbolButton(systemName: "arrow.uturn.backward", title: L("common_undo")) {
                dismissInlineMenu()
                coordinator.exec("undo")
            },
            makeSymbolButton(systemName: "arrow.uturn.forward", title: L("common_redo")) {
                dismissInlineMenu()
                coordinator.exec("redo")
            },
            makeSymbolButton(systemName: "keyboard.chevron.compact.down", title: L("common_done")) {
                dismissInlineMenu()
                coordinator.blur()
                webView.endEditing(true)
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

    private func makeMenuButton(systemName: String, title: String, tintColor: UIColor, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = tintColor
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

    private func makeColorPaletteViews(
        choices: [(displayColor: UIColor, appliedColor: UIColor)],
        applyColor: @escaping (UIColor) -> Void,
        applyCustom: @escaping () -> Void
    ) -> [UIView] {
        choices.map { choice in
            makePaletteSwatchButton(color: choice.displayColor, action: { applyColor(choice.appliedColor) })
        } + [
            makePaletteActionButton(title: nil, systemName: "plus", tintColor: .label, action: applyCustom)
        ]
    }

    private func makePaletteSwatchButton(color: UIColor, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = color
        button.layer.cornerRadius = 16
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "amgiNoteFieldChanged"

        @Binding var htmlText: String
        weak var webView: WKWebView?
        var lastDocument = ""
        var lastKnownHTML = ""
        var pendingHTMLAfterLoad = ""
        private var colorSelectionHandler: ((UIColor) -> Void)?

        init(htmlText: Binding<String>) {
            self._htmlText = htmlText
            self.lastKnownHTML = RichNoteFieldEditor.normalizedStoredHTML(htmlText.wrappedValue)
        }

        func pushHTMLIfNeeded(_ html: String) {
            guard html != lastKnownHTML else { return }
            lastKnownHTML = html
            let script = "window.amgiNoteField && window.amgiNoteField.setHTML(\(html.javaScriptStringLiteral()));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func exec(_ command: String, value: String? = nil) {
            let resolvedValue = value?.javaScriptStringLiteral() ?? "null"
            let script = "window.amgiNoteField && window.amgiNoteField.exec('\(command)', \(resolvedValue));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func wrapSelection(prefix: String, suffix: String) {
            let script = "window.amgiNoteField && window.amgiNoteField.wrapSelection(\(prefix.javaScriptStringLiteral()), \(suffix.javaScriptStringLiteral()));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func blur() {
            webView?.evaluateJavaScript("window.amgiNoteField && window.amgiNoteField.blur();", completionHandler: nil)
        }

        func focus() {
            webView?.evaluateJavaScript("window.amgiNoteField && window.amgiNoteField.focus();", completionHandler: nil)
        }

        func applyForegroundColor(_ color: UIColor) {
            exec("foreColor", value: Self.hexString(from: color))
        }

        func applyHighlightColor(_ color: UIColor) {
            exec("hiliteColor", value: Self.cssColorString(from: color))
        }

        func presentForegroundColorPicker() {
            presentColorPicker(initialColor: .systemBlue) { [weak self] color in
                self?.applyForegroundColor(color)
            }
        }

        func presentHighlightColorPicker() {
            presentColorPicker(initialColor: .systemYellow) { [weak self] color in
                self?.applyHighlightColor(color.withAlphaComponent(0.35))
            }
        }

        func clearFormatting() {
            webView?.evaluateJavaScript("window.amgiNoteField && window.amgiNoteField.hasSelection();") { [weak self] result, _ in
                guard let self else { return }
                if (result as? Bool) == true {
                    self.webView?.evaluateJavaScript(
                        "window.amgiNoteField && window.amgiNoteField.clearSelectionFormatting();",
                        completionHandler: nil
                    )
                } else {
                    self.presentClearAllFormattingConfirmation()
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let html = pendingHTMLAfterLoad.isEmpty ? lastKnownHTML : pendingHTMLAfterLoad
            pendingHTMLAfterLoad = ""
            pushHTMLIfNeeded(html)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }
            if type == "htmlChanged" {
                let html = RichNoteFieldEditor.normalizedStoredHTML((body["html"] as? String) ?? "")
                lastKnownHTML = html
                htmlText = html
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
                    self?.webView?.evaluateJavaScript(
                        "window.amgiNoteField && window.amgiNoteField.clearAllFormatting();",
                        completionHandler: nil
                    )
                }
            )
            presenter.present(alert, animated: true)
        }

        private func topPresenter() -> UIViewController? {
            var controller = webView?.window?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
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

extension RenderedHTMLFieldEditor.Coordinator: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        colorSelectionHandler?(viewController.selectedColor)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        colorSelectionHandler = nil
        focus()
    }
}

private final class WebToolbarContainerView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }

        for subview in subviews where subview.isHidden == false && subview.alpha > 0.01 {
            let convertedPoint = subview.convert(point, from: self)
            if subview.point(inside: convertedPoint, with: event) {
                return true
            }
        }
        return false
    }
}

private final class AccessoryWKWebView: WKWebView {
    var accessoryView: UIView?

    override var inputAccessoryView: UIView? {
        accessoryView
    }
}

private extension String {
    func javaScriptStringLiteral() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [self]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2
        else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }
}
