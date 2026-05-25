import SwiftUI
import WebKit

struct NoteFieldHTMLPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var measuredHeight: CGFloat = 180

    let html: String

    var body: some View {
        NoteFieldHTMLPreviewWebView(
            html: html,
            colorScheme: colorScheme,
            measuredHeight: $measuredHeight
        )
        .frame(height: measuredHeight)
    }
}

private struct NoteFieldHTMLPreviewWebView: UIViewRepresentable {
    let html: String
    let colorScheme: ColorScheme
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(measuredHeight: $measuredHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = htmlDocument(for: html)
        if document != context.coordinator.lastHTML {
            context.coordinator.lastHTML = document
            webView.loadHTMLString(document, baseURL: CardAssetPath.mediaBaseURL)
        }

        DispatchQueue.main.async {
            context.coordinator.measureHeight(in: webView)
        }
    }

    private func htmlDocument(for fragment: String) -> String {
        let textColor = colorScheme == .dark ? "#F2F4F8" : "#17212F"
        let linkColor = colorScheme == .dark ? "#8FB8FF" : "#1E5BB8"

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
        }
        body {
            padding: 10px 12px;
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
        </style>
        </head>
        <body>\(fragment)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""
        private var measuredHeight: Binding<CGFloat>

        init(measuredHeight: Binding<CGFloat>) {
            self.measuredHeight = measuredHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(in: webView)
        }

        func measureHeight(in webView: WKWebView) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { result, _ in
                guard let value = result as? NSNumber else { return }
                let nextHeight = max(180, ceil(value.doubleValue))
                guard abs(self.measuredHeight.wrappedValue - nextHeight) > 0.5 else { return }
                self.measuredHeight.wrappedValue = nextHeight
            }
        }
    }
}