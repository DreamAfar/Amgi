//
//  ChapterWebView.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 20.08.2026.
//

import Reader
import Theme
import AppCore
import AppShared
import Sharing
import SwiftUI
import WebKit

struct ChapterWebView: UIViewRepresentable {
    let html: String
    /// 0..1 fraction to scroll to once the page finishes loading. Read once
    /// per appearance — set to nil after the initial restore.
    let initialProgress: Double?
    @Binding var progress: Double
    /// Called with a tapped phrase (the engine does its own deinflection
    /// and word-segmentation, so we forward a generous chunk starting at
    /// the tap point rather than a pre-extracted word — handles CJK,
    /// where word boundaries don't exist at the DOM level). nil disables
    /// the tap gesture entirely (controlled by the user pref).
    let onTapLookup: ((String) -> Void)?
    /// Called with the user's current text selection when the toolbar
    /// "make note" button fires the `.amgiReaderRequestSelection`
    /// notification. nil ignores the request.
    let onSelectionForNote: ((String) -> Void)?
    /// How many characters a tap hands the dictionary.
    var scanLength = 16
    /// The span the dictionary matched for the last tap, highlighted in
    /// the page until the popup closes.
    var lookupHighlight = LookupHighlight()

    func makeCoordinator() -> Coordinator {
        Coordinator(
            progress: $progress,
            onTapLookup: onTapLookup,
            onSelectionForNote: onSelectionForNote
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        if onTapLookup != nil {
            userContent.add(context.coordinator, name: "amgiLookup")
            userContent.addUserScript(WKUserScript(
                source: LookupExtractionScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
            userContent.addUserScript(WKUserScript(
                source: tapScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        config.userContentController = userContent
        config.setURLSchemeHandler(ReaderFontScheme(), forURLScheme: ReaderCustomFonts.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        webView.isOpaque = false
        context.coordinator.attach(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingInitialProgress = initialProgress
        context.coordinator.apply(scanLength: scanLength, highlight: lookupHighlight)
        // The host builds the HTML in a `.task`, so the very first update
        // arrives empty. Loading it would flash a blank document before the
        // real one lands one runloop later.
        guard !html.isEmpty else { return }
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            context.coordinator.didFinishLoad = false
            context.coordinator.didApplyInitialProgress = false
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            // The saved progress now resolves asynchronously, so it can
            // land after `didFinish` — apply it late, once per load.
            context.coordinator.applyPendingInitialProgressIfLoaded()
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Single tap → the shared lookup extractor (the one the EPUB reader
    /// and the reviewer use) takes the text from the tapped character
    /// forward — expanding back to the word start in scripts with spaces —
    /// and remembers exactly which characters it took, so the span the
    /// dictionary matched can be highlighted once the popup reports it.
    /// Long-press still gives WebKit's own selection for copy/paste, and a
    /// tap that only dismisses a selection doesn't look anything up.
    private var tapScript: String {
        """
        document.addEventListener('click', function(e) {
          const sel = window.getSelection();
          if (sel && sel.toString().length > 0) { return; }
          if (!window.amgiLookup) { return; }
          const payload = window.amgiLookup.payloadAt(e.clientX, e.clientY, window.__amgiLookupScanLength || 16);
          if (!payload || !payload.text) {
            window.amgiLookup.clearHighlight();
            return;
          }
          window.webkit.messageHandlers.amgiLookup.postMessage(payload.text);
        }, true);
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, WKScriptMessageHandler {
        var pendingInitialProgress: Double?
        var loadedHTML: String?
        var didFinishLoad = false
        var didApplyInitialProgress = false
        private var scanLength = 16
        private var highlightGeneration = 0
        @Binding var progress: Double
        let onTapLookup: ((String) -> Void)?
        let onSelectionForNote: ((String) -> Void)?
        private weak var webView: WKWebView?
        private var selectionObserver: (any NSObjectProtocol)?
        /// Live while waiting for the page to report a real content size.
        private var contentSizeObservation: NSKeyValueObservation?

        init(
            progress: Binding<Double>,
            onTapLookup: ((String) -> Void)?,
            onSelectionForNote: ((String) -> Void)?
        ) {
            self._progress = progress
            self.onTapLookup = onTapLookup
            self.onSelectionForNote = onSelectionForNote
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            selectionObserver = NotificationCenter.default.addObserver(
                forName: .amgiReaderRequestSelection,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Delivered on the main queue, so assumeIsolated is safe and
                // keeps fetchSelection() synchronous.
                MainActor.assumeIsolated { self?.fetchSelection() }
            }
        }

        func detach() {
            if let observer = selectionObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            selectionObserver = nil
            contentSizeObservation = nil
            webView = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.scheme?.lowercased() == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            webView.evaluateJavaScript("window.__amgiLookupScanLength = \(scanLength);")
            applyPendingInitialProgressIfLoaded()
        }

        /// Pushes the scan length and, when it changed, the lookup
        /// highlight into the page.
        func apply(scanLength: Int, highlight: LookupHighlight) {
            if scanLength != self.scanLength {
                self.scanLength = scanLength
                webView?.evaluateJavaScript("window.__amgiLookupScanLength = \(scanLength);")
            }
            guard highlight.generation != highlightGeneration else { return }
            highlightGeneration = highlight.generation
            let call = highlight.utf16Length > 0
                ? "highlightMatched(\(highlight.utf16Length))"
                : "clearHighlight()"
            webView?.evaluateJavaScript("window.amgiLookup && window.amgiLookup.\(call);")
        }

        /// Restore prior scroll position once the page reports a real
        /// content size; without this the scrollView height is still
        /// the initial frame size and our offset would be clamped.
        /// One-shot per HTML load — the flag stops later view updates
        /// from yanking the user back to the saved position.
        func applyPendingInitialProgressIfLoaded() {
            guard didFinishLoad, !didApplyInitialProgress,
                  let target = pendingInitialProgress else { return }
            didApplyInitialProgress = true
            pendingInitialProgress = nil
            guard target > 0, let scrollView = webView?.scrollView else { return }

            // Observe contentSize rather than sleeping 50ms and hoping. On a
            // slow device or a long chapter the old delay fired while
            // contentSize was still the initial frame height, so the offset
            // clamped to ~0 and the reader silently reopened at the top.
            if scrollView.contentSize.height > scrollView.bounds.height {
                Self.applyProgress(target, to: scrollView)
                return
            }
            // `change.newValue` is a CGSize, so nothing main-actor-isolated
            // is captured by the Sendable observation closure; the scroll
            // view is re-resolved inside the isolated block. contentSize is
            // mutated on the main thread, so assumeIsolated holds.
            contentSizeObservation = scrollView.observe(
                \.contentSize, options: [.new]
            ) { [weak self] _, change in
                guard let newSize = change.newValue else { return }
                MainActor.assumeIsolated {
                    guard let self, let scrollView = self.webView?.scrollView,
                          newSize.height > scrollView.bounds.height else { return }
                    Self.applyProgress(target, to: scrollView)
                    self.contentSizeObservation = nil
                }
            }
        }

        private static func applyProgress(_ target: Double, to scrollView: UIScrollView) {
            let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.contentOffset.y = maxOffset * CGFloat(target)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let usable = scrollView.contentSize.height - scrollView.bounds.height
            guard usable > 1 else {
                progress = 0
                return
            }
            let fraction = min(max(scrollView.contentOffset.y / usable, 0), 1)
            progress = Double(fraction)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "amgiLookup",
                  let phrase = message.body as? String,
                  !phrase.isEmpty else { return }
            onTapLookup?(phrase)
        }
    }
}

extension ChapterWebView.Coordinator {
    func fetchSelection() {
        guard let webView, let onSelectionForNote else { return }
        // window.getSelection() — current text selection in the page.
        // Empty string when nothing's selected; we just no-op then.
        webView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            guard let text = result as? String else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSelectionForNote(trimmed)
        }
    }
}
