//
//  LookupStructuredContentView.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 05.05.2026.
//

import AppCore
import Reader
import ReaderDictionary
import Dependencies
import OSLog
import Sharing
import SwiftUI
import WebKit

/// Renders Yomitan-format structured glossaries via a WKWebView that hosts
/// the bundled `popup.js` renderer. The web layer owns the visual shape
/// (lists, tables, links, pitch diagrams, dictionary-bundled images) — the
/// Swift side feeds it the glossary JSON, mediates tap-to-lookup, resolves
/// `image://` media URLs back to `dictionaryLookupClient.mediaFile`, and
/// sizes the view to the rendered height.
///
/// The height lives in SwiftUI state and is applied with `.frame(height:)`.
/// It used to be the web view's `intrinsicContentSize`, which a `List` row
/// doesn't re-measure when it changes: rows kept their first height, so
/// glossaries spilled over the next entry's header and buttons, or left
/// tall blank gaps when the first measurement was taken at zero width.
struct LookupStructuredContentView: View {
    let dictionary: String
    let glossaries: [DictionaryLookupGlossary]
    let dictionaryStyle: String
    let onLookupRequested: ((String) -> Void)?

    @State private var measuredHeight: CGFloat?
    @State private var width: CGFloat = 0

    /// A List rebuilds rows that scroll off and back on, which recreates
    /// this view and reloads its page. Starting each time from a 44 pt
    /// guess made rows jump while scrolling, and for a frame the old cell
    /// height left glossaries drawn over their neighbours. The height
    /// measured for this content at this width is kept app-wide instead.
    private var contentKey: Int {
        var hasher = Hasher()
        hasher.combine(dictionary)
        hasher.combine(glossaries)
        hasher.combine(dictionaryStyle)
        return hasher.finalize()
    }

    private var height: CGFloat {
        measuredHeight ?? GlossaryHeightCache.shared.height(for: contentKey, width: width) ?? 44
    }

    var body: some View {
        let key = contentKey
        StructuredGlossaryWebView(
            dictionary: dictionary,
            glossaries: glossaries,
            dictionaryStyle: dictionaryStyle,
            onLookupRequested: onLookupRequested,
            onHeightChange: { height, measuredWidth in
                let resolved = max(1, ceil(height))
                GlossaryHeightCache.shared.store(resolved, for: key, width: measuredWidth)
                if measuredHeight.map({ abs(resolved - $0) > 0.5 }) ?? true {
                    measuredHeight = resolved
                }
            }
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            // A new width reflows the page; the old measurement no longer
            // applies, so fall back to the cache until the page reports.
            if abs(newWidth - width) > 0.5 {
                width = newWidth
                measuredHeight = nil
            }
        }
    }
}

/// Rendered glossary heights, keyed by content and whole-point width.
@MainActor
final class GlossaryHeightCache {
    static let shared = GlossaryHeightCache()

    private struct Key: Hashable {
        let content: Int
        let width: Int
    }

    private var heights: [Key: CGFloat] = [:]

    func height(for content: Int, width: CGFloat) -> CGFloat? {
        guard width > 1 else { return nil }
        return heights[Key(content: content, width: Int(width.rounded()))]
    }

    func store(_ height: CGFloat, for content: Int, width: CGFloat) {
        guard width > 1 else { return }
        if heights.count > 2000 { heights.removeAll() }
        heights[Key(content: content, width: Int(width.rounded()))] = height
    }
}

private struct StructuredGlossaryWebView: UIViewRepresentable {
    let dictionary: String
    let glossaries: [DictionaryLookupGlossary]
    let dictionaryStyle: String
    let onLookupRequested: ((String) -> Void)?
    let onHeightChange: (CGFloat, CGFloat) -> Void

    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient
    @Shared(.appStorage(ReaderPreferences.Keys.dictionaryScanLength))
    private var scanLength: Int = 16

    func makeCoordinator() -> Coordinator {
        Coordinator(
            dictionary: dictionary,
            glossaries: glossaries,
            dictionaryStyle: dictionaryStyle,
            scanLength: scanLength,
            onLookupRequested: onLookupRequested,
            onHeightChange: onHeightChange,
            loadMediaData: { dict, mediaPath in
                try await dictionaryLookupClient.mediaFile(dict, mediaPath)
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "image")
        configuration.userContentController.add(context.coordinator, name: "openLink")
        configuration.userContentController.add(context.coordinator, name: "lookupText")
        configuration.userContentController.add(context.coordinator, name: "contentHeight")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Never draw past the frame SwiftUI gave us, even for the moment
        // before a new height arrives.
        webView.clipsToBounds = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(context.coordinator.html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.update(
            dictionary: dictionary,
            glossaries: glossaries,
            dictionaryStyle: dictionaryStyle,
            scanLength: scanLength
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelAllSchemeTasks()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookupText")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contentHeight")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
        fileprivate var html: String = ""
        fileprivate weak var webView: WKWebView?

        private var dictionary: String
        private var glossaries: [DictionaryLookupGlossary]
        private var dictionaryStyle: String
        private var scanLength: Int
        private let onLookupRequested: ((String) -> Void)?
        fileprivate var onHeightChange: (CGFloat, CGFloat) -> Void
        /// One CSP nonce for the coordinator's life. A fresh nonce per
        /// `makeHTML` made every `update` see "new" HTML and reload the page
        /// on each SwiftUI pass, resetting its height each time.
        private let nonce = UUID().uuidString
        private let loadMediaData: @Sendable (String, String) async throws -> Data
        /// In-flight `image://` scheme tasks, keyed by task identity, so they
        /// can be cancelled when WebKit stops them or the page goes away.
        private var schemeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        init(
            dictionary: String,
            glossaries: [DictionaryLookupGlossary],
            dictionaryStyle: String,
            scanLength: Int,
            onLookupRequested: ((String) -> Void)?,
            onHeightChange: @escaping (CGFloat, CGFloat) -> Void,
            loadMediaData: @escaping @Sendable (String, String) async throws -> Data
        ) {
            self.dictionary = dictionary
            self.glossaries = glossaries
            self.dictionaryStyle = dictionaryStyle
            self.scanLength = scanLength
            self.onLookupRequested = onLookupRequested
            self.onHeightChange = onHeightChange
            self.loadMediaData = loadMediaData
            super.init()
            html = Self.makeHTML(
                dictionary: dictionary,
                glossaries: glossaries,
                dictionaryStyle: dictionaryStyle,
                scanLength: scanLength,
                nonce: nonce
            )
        }

        func update(
            dictionary: String,
            glossaries: [DictionaryLookupGlossary],
            dictionaryStyle: String,
            scanLength: Int
        ) {
            let next = Self.makeHTML(
                dictionary: dictionary,
                glossaries: glossaries,
                dictionaryStyle: dictionaryStyle,
                scanLength: scanLength,
                nonce: nonce
            )
            guard next != html else { return }
            self.dictionary = dictionary
            self.glossaries = glossaries
            self.dictionaryStyle = dictionaryStyle
            self.scanLength = scanLength
            html = next
            // Reloading abandons any asset request the old page started.
            cancelAllSchemeTasks()
            webView?.loadHTMLString(next, baseURL: nil)
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.scheme?.lowercased() == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // One measurement now, then a ResizeObserver reports every
            // subsequent change. This used to be three polls at 0, 50ms and
            // 200ms hoping layout had settled — which silently produced a
            // wrong popup height whenever it hadn't (slow device, late web
            // font, large glossary).
            updateContentHeight(for: webView)
            installHeightObserver(on: webView)
        }

        /// Installs a `ResizeObserver` on the rendered glossary that posts
        /// its height over the `contentHeight` message handler. Idempotent:
        /// re-running after a reload replaces the previous observer.
        private func installHeightObserver(on webView: WKWebView) {
            let js = """
            (function() {
              var el = document.getElementById('content');
              if (!el || typeof ResizeObserver !== 'function') { return; }
              if (window.__amgiHeightObserver) { window.__amgiHeightObserver.disconnect(); }
              window.__amgiHeightObserver = new ResizeObserver(function() {
                var h = Math.ceil(el.getBoundingClientRect().height);
                window.webkit.messageHandlers.contentHeight.postMessage(h);
              });
              window.__amgiHeightObserver.observe(el);
            })();
            """
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    Log.reader.error("height observer install failed: \(error)")
                }
            }
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "contentHeight":
                guard let height = (message.body as? NSNumber).map({ CGFloat(truncating: $0) }) else { return }
                reportHeight(height)
            case "lookupText":
                guard let payload = message.body as? [String: Any],
                      let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return }
                onLookupRequested?(text)
            case "openLink":
                guard let urlString = message.body as? String,
                      let url = URL(string: urlString),
                      ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
                UIApplication.shared.open(url)
            default:
                return
            }
        }

        // MARK: WKURLSchemeHandler — dictionary-bundled media via image://

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let requestURL = urlSchemeTask.request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
                  let dict = components.queryItems?.first(where: { $0.name == "dictionary" })?.value,
                  let mediaPath = components.queryItems?.first(where: { $0.name == "path" })?.value else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }
            let key = ObjectIdentifier(urlSchemeTask)
            schemeTasks[key] = Task { [weak self] in
                defer { self?.schemeTasks[key] = nil }
                do {
                    let data = try await self?.loadMediaData(dict, mediaPath) ?? Data()
                    // WebKit raises an uncatchable NSInternalInconsistency-
                    // Exception if a stopped task is resumed, so re-check
                    // cancellation immediately before every callback.
                    guard self?.schemeTasks[key] != nil, !Task.isCancelled else { return }
                    guard !data.isEmpty else {
                        urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                        return
                    }
                    let response = URLResponse(
                        url: requestURL,
                        mimeType: Self.mimeType(for: mediaPath),
                        expectedContentLength: data.count,
                        textEncodingName: nil
                    )
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                } catch {
                    guard self?.schemeTasks[key] != nil, !Task.isCancelled else { return }
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            let key = ObjectIdentifier(urlSchemeTask)
            schemeTasks.removeValue(forKey: key)?.cancel()
        }

        /// Cancels every in-flight scheme task. Called when the popup reloads
        /// its HTML or the view is dismantled — both leave WebKit free to
        /// stop the tasks underneath us.
        func cancelAllSchemeTasks() {
            for (_, task) in schemeTasks { task.cancel() }
            schemeTasks.removeAll()
        }
    }
}

private extension StructuredGlossaryWebView.Coordinator {
    func updateContentHeight(for webView: WKWebView) {
        let script = """
        Math.ceil(document.getElementById('content')?.getBoundingClientRect().height || 0)
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let n = value as? NSNumber else { return }
            self?.reportHeight(CGFloat(truncating: n))
        }
    }

    /// Forwards a measured height unless the page hasn't been laid out at
    /// a real width yet: at zero width every character wraps onto its own
    /// line, and that height is what left the large blank gaps.
    func reportHeight(_ height: CGFloat) {
        guard let webView, webView.bounds.width > 1, height > 0 else { return }
        onHeightChange(height, webView.bounds.width)
    }

    // MARK: HTML

    static func scriptLiteral(_ value: some Encodable, fallback: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return fallback }
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }

    static func makeHTML(
        dictionary: String,
        glossaries: [DictionaryLookupGlossary],
        dictionaryStyle: String,
        scanLength: Int,
        nonce: String
    ) -> String {
        let dictionaryData = scriptLiteral(glossaries, fallback: "[]")
        let dictionaryName = scriptLiteral(dictionary, fallback: "\"\"")
        let dictionaryCSS = scriptLiteral(dictionaryStyle, fallback: "\"\"")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src image: data: blob:; media-src audio: data: blob:; connect-src audio: image:; style-src 'unsafe-inline'; script-src 'nonce-\(nonce)'">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>\(ReaderLookupStructuredContentResources.popupCSS)</style>
        <script nonce="\(nonce)">\(ReaderLookupStructuredContentResources.popupJS)</script>
        <style>
        body { padding: 0; margin: 0; }
        #content { padding: 0; }
        .glossary-content { padding: 0; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script nonce="\(nonce)">
        (function() {
            const dictName = \(dictionaryName);
            const glossaryItems = \(dictionaryData);
            document.getElementById('content').dataset.dictionary = dictName;
            window.dictionaryStyles = { [dictName]: \(dictionaryCSS) };
            window.compactGlossaries = false;
            window.lookupScanLength = \(max(1, scanLength));

            const contentRoot = document.getElementById('content');
            const dictStyle = window.dictionaryStyles?.[dictName] ?? '';
            if (dictStyle) {
                const style = document.createElement('style');
                style.textContent = constructDictCss(dictStyle, dictName);
                document.head.appendChild(style);
            }

            const termTags = [...new Set(parseTags(glossaryItems[0]?.termTags))];
            const termTagsRow = createGlossaryTags(termTags);
            if (termTagsRow) {
                contentRoot.appendChild(termTagsRow);
            }

            const renderContent = (parent, content) => {
                try {
                    renderStructuredContent(parent, JSON.parse(content), null, dictName);
                } catch {
                    renderStructuredContent(parent, content, null, dictName);
                }
            };

            if (glossaryItems.length > 1) {
                const ol = el('ol');
                glossaryItems.forEach((item) => {
                    const li = el('li');
                    const parsedTags = parseTags(item.definitionTags).filter(tag => !NUMERIC_TAG.test(tag));
                    const tags = createGlossaryTags(parsedTags);
                    if (tags) li.appendChild(tags);
                    const wrapper = el('div', { className: 'glossary-content' });
                    renderContent(wrapper, item.content);
                    li.appendChild(wrapper);
                    ol.appendChild(li);
                });
                contentRoot.appendChild(ol);
            } else {
                glossaryItems.forEach((item, index) => {
                    const wrapper = el('div');
                    const tags = createGlossaryTags(parseTags(item.definitionTags).filter(tag => !NUMERIC_TAG.test(tag)));
                    if (tags) wrapper.appendChild(tags);
                    const content = el('div', { className: 'glossary-content' });
                    renderContent(content, item.content);
                    wrapper.appendChild(content);
                    if (index > 0) contentRoot.appendChild(document.createElement('hr'));
                    contentRoot.appendChild(wrapper);
                });
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    static func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    // The bundled popup.js renderer drives layout; the @Dependency resolves
    // to its preview value (no media is referenced by these plain glossaries).
    LookupStructuredContentView(
        dictionary: "JMdict",
        glossaries: [
            DictionaryLookupGlossary(
                dictionary: "JMdict",
                content: "to go; to move; to proceed",
                definitionTags: "v5k-s, vi"
            ),
            DictionaryLookupGlossary(
                dictionary: "JMdict",
                content: "to pass; to elapse"
            ),
        ],
        dictionaryStyle: "",
        onLookupRequested: nil
    )
    .padding()
}
#endif
