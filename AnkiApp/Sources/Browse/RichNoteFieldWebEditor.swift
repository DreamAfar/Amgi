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
                SourceHTMLFieldEditor(htmlText: $htmlText)
            } else {
                RenderedHTMLFieldEditor(htmlText: $htmlText)
            }
        }
        .frame(minHeight: preservesSourceHTML ? 120 : 140, maxHeight: preservesSourceHTML ? 180 : 220)
    }
}

private struct SourceHTMLFieldEditor: UIViewRepresentable {
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
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.text = RichNoteFieldEditor.normalizedStoredHTML(htmlText)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let normalized = RichNoteFieldEditor.normalizedStoredHTML(htmlText)
        guard context.coordinator.isEditing == false else { return }
        guard uiView.text != normalized else { return }
        uiView.text = normalized
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var htmlText: String
        var isEditing = false

        init(htmlText: Binding<String>) {
            self._htmlText = htmlText
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            htmlText = RichNoteFieldEditor.normalizedStoredHTML(textView.text ?? "")
        }

        func textViewDidChange(_ textView: UITextView) {
            htmlText = RichNoteFieldEditor.normalizedStoredHTML(textView.text ?? "")
        }
    }
}

private struct RenderedHTMLFieldEditor: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var htmlText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(htmlText: $htmlText)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.alwaysBounceVertical = true
        context.coordinator.webView = webView
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "amgiNoteFieldChanged"

        @Binding var htmlText: String
        weak var webView: WKWebView?
        var lastDocument = ""
        var lastKnownHTML = ""
        var pendingHTMLAfterLoad = ""

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
