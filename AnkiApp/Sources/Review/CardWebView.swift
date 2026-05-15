import SwiftUI
import WebKit
import Foundation
import UIKit
import AnkiProto

struct CardWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    enum ReplayMode: String {
        case question
        case answerOnly
        case answerWithQuestion
    }

    enum ContentAlignment: String {
        case top
        case center
    }

    let html: String
    let cardCSS: String
    let autoplayEnabled: Bool
    let isAnswerSide: Bool
    let questionAVTags: [Anki_CardRendering_AVTag]
    let answerAVTags: [Anki_CardRendering_AVTag]
    let cardOrdinal: UInt32
    let replayRequestID: Int
    let stopAudioRequestID: Int
    let typedAnswerRequestID: Int
    let replayMode: ReplayMode
    let playAudioInSilentMode: Bool
    let showInlineAudioReplayButtons: Bool
    let openLinksExternally: Bool
    let lookupPopupEnabled: Bool
    let prefetchHTML: String?
    let contentAlignment: ContentAlignment
    let bottomContentInset: CGFloat
    let onTypedAnswerSubmitted: ((String?) -> Void)?
    let onAudioStateChange: ((Bool) -> Void)?
    let onCardBackgroundColorChange: ((UIColor, Bool) -> Void)?
    let onLookupRequested: ((String?, String?, CGPoint) -> Void)?

    init(
        html: String,
        cardCSS: String = "",
        autoplayEnabled: Bool = true,
        isAnswerSide: Bool = false,
        questionAVTags: [Anki_CardRendering_AVTag] = [],
        answerAVTags: [Anki_CardRendering_AVTag] = [],
        cardOrdinal: UInt32 = 0,
        replayRequestID: Int = 0,
        stopAudioRequestID: Int = 0,
        typedAnswerRequestID: Int = 0,
        replayMode: ReplayMode = .question,
        playAudioInSilentMode: Bool = false,
        showInlineAudioReplayButtons: Bool = true,
        openLinksExternally: Bool = true,
        lookupPopupEnabled: Bool = true,
        prefetchHTML: String? = nil,
        contentAlignment: ContentAlignment = .center,
        bottomContentInset: CGFloat = 0,
        onTypedAnswerSubmitted: ((String?) -> Void)? = nil,
        onAudioStateChange: ((Bool) -> Void)? = nil,
        onCardBackgroundColorChange: ((UIColor, Bool) -> Void)? = nil,
        onLookupRequested: ((String?, String?, CGPoint) -> Void)? = nil
    ) {
        self.html = html
        self.cardCSS = cardCSS
        self.autoplayEnabled = autoplayEnabled
        self.isAnswerSide = isAnswerSide
        self.questionAVTags = questionAVTags
        self.answerAVTags = answerAVTags
        self.cardOrdinal = cardOrdinal
        self.replayRequestID = replayRequestID
        self.stopAudioRequestID = stopAudioRequestID
        self.typedAnswerRequestID = typedAnswerRequestID
        self.replayMode = replayMode
        self.playAudioInSilentMode = playAudioInSilentMode
        self.showInlineAudioReplayButtons = showInlineAudioReplayButtons
        self.openLinksExternally = openLinksExternally
        self.lookupPopupEnabled = lookupPopupEnabled
        self.prefetchHTML = prefetchHTML
        self.contentAlignment = contentAlignment
        self.bottomContentInset = bottomContentInset
        self.onTypedAnswerSubmitted = onTypedAnswerSubmitted
        self.onAudioStateChange = onAudioStateChange
        self.onCardBackgroundColorChange = onCardBackgroundColorChange
        self.onLookupRequested = onLookupRequested
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTypedAnswerSubmitted: onTypedAnswerSubmitted,
            onAudioStateChange: onAudioStateChange,
            onCardBackgroundColorChange: onCardBackgroundColorChange,
            onLookupRequested: onLookupRequested
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)
        config.userContentController.add(context.coordinator, name: "amgiAudioState")
        config.userContentController.add(context.coordinator, name: "amgiOpenLink")
        config.userContentController.add(context.coordinator, name: "amgiSpeakTts")
        config.userContentController.add(context.coordinator, name: "amgiStopTts")
        config.userContentController.add(context.coordinator, name: "amgiSubmitTypedAnswer")
        config.userContentController.add(context.coordinator, name: "amgiCardTheme")
        config.userContentController.add(context.coordinator, name: "amgiLookupText")
        
        // Enable media playback without user interaction
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiAudioState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiOpenLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiSpeakTts")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiStopTts")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiSubmitTypedAnswer")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiCardTheme")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiLookupText")
        coordinator.stopTTS()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let isDarkMode = colorScheme == .dark
        let processedHTML = Self.processReviewHTML(
            html,
            questionAVTags: questionAVTags,
            answerAVTags: answerAVTags,
            isDarkMode: isDarkMode,
            showReplayButtons: showInlineAudioReplayButtons
        )
        let processedPrefetchHTML = prefetchHTML.map {
            Self.processReviewHTML(
                $0,
                questionAVTags: questionAVTags,
                answerAVTags: answerAVTags,
                isDarkMode: isDarkMode,
                showReplayButtons: showInlineAudioReplayButtons
            )
        }
        let hasTypedAnswerInput = !isAnswerSide && processedHTML.contains("id=\"typeans\"")
        let bodyPaddingBottom = hasTypedAnswerInput ? 148 : 16
        let cardPaddingBottom = hasTypedAnswerInput ? 96 : 0
        let alignTop = hasTypedAnswerInput || contentAlignment == .top
        let bodyClass = Self.bodyClasses(cardOrdinal: cardOrdinal, isDarkMode: isDarkMode)
        let pageSignature = "\(isDarkMode)"
        let cssSignature = "\(cardCSS.hashValue)"
        let contentSignature = "\(autoplayEnabled)|\(isAnswerSide)|\(lookupPopupEnabled)|\(replayMode.rawValue)|\(cardOrdinal)|\(alignTop)|\(bodyPaddingBottom)|\(cardPaddingBottom)|\(cssSignature)|\(processedHTML.hashValue)|\(processedPrefetchHTML?.hashValue ?? 0)"
        context.coordinator.openLinksExternally = openLinksExternally
        context.coordinator.playAudioInSilentMode = playAudioInSilentMode
        context.coordinator.currentWebView = webView
        webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light

        // Build the JS call that shows the card – passed via evaluateJavaScript so
        // HTML content never lives inside a <script> literal in the page source.
        let showCardScript = Self.showCardScript(
            processedHTML: processedHTML,
            prefetchHTML: processedPrefetchHTML,
            cardCSS: cardCSS,
            isAnswerSide: isAnswerSide,
            lookupPopupEnabled: lookupPopupEnabled,
            bodyClass: bodyClass,
            autoplayEnabled: autoplayEnabled,
            replayMode: replayMode.rawValue,
            alignTop: alignTop,
            bodyPaddingBottom: bodyPaddingBottom,
            cardPaddingBottom: cardPaddingBottom,
            questionAVTags: questionAVTags,
            answerAVTags: answerAVTags
        )

        if context.coordinator.lastPageSignature != pageSignature {
            context.coordinator.stopTTS()
            context.coordinator.lastPageSignature = pageSignature
            context.coordinator.lastContentSignature = contentSignature
            context.coordinator.isPageLoaded = false
            context.coordinator.pendingUpdateScript = nil
            let htmlClass = Self.htmlClasses(isDarkMode: isDarkMode)
            let playIconHTML = Self.audioButtonIconHTML(systemName: "play.circle", alt: "Play", isDarkMode: isDarkMode)
            let pauseIconHTML = Self.audioButtonIconHTML(systemName: "pause.circle", alt: "Pause", isDarkMode: isDarkMode)
            let missingImageIconHTML = Self.missingMediaIconHTML(systemName: "photo.badge.exclamationmark", alt: "Missing image", isDarkMode: isDarkMode)
            let missingAudioIconHTML = Self.missingMediaIconHTML(systemName: "speaker.badge.exclamationmark", alt: "Missing audio", isDarkMode: isDarkMode)
            let baseTag = CardAssetPath.mediaBaseTag()
            // Stash the show-card call so we can run it once the page finishes loading.
            context.coordinator.pendingUpdateScript = showCardScript

            let styledHTML = Self.buildFrameHTML(
                htmlClass: htmlClass,
                isDarkMode: isDarkMode,
                playIconHTML: playIconHTML,
                pauseIconHTML: pauseIconHTML,
                missingImageIconHTML: missingImageIconHTML,
                missingAudioIconHTML: missingAudioIconHTML,
                baseTag: baseTag
            )

            // Use cardBaseURL so that MathJax, fonts, and other resources load correctly.
            // The CardAssetScheme handler processes amgi-asset:// URLs.
            webView.loadHTMLString(styledHTML, baseURL: CardAssetPath.cardBaseURL)
        } else if context.coordinator.lastContentSignature != contentSignature {
            context.coordinator.stopTTS()
            context.coordinator.lastContentSignature = contentSignature
            if context.coordinator.isPageLoaded {
                webView.evaluateJavaScript(showCardScript, completionHandler: nil)
            } else {
                context.coordinator.pendingUpdateScript = showCardScript
            }
        }
        if replayRequestID != context.coordinator.lastReplayRequestID {
            context.coordinator.lastReplayRequestID = replayRequestID
            webView.evaluateJavaScript("window.amgiReplayAll && window.amgiReplayAll('" + replayMode.rawValue + "');", completionHandler: nil)
        }

        if stopAudioRequestID != context.coordinator.lastStopAudioRequestID {
            context.coordinator.lastStopAudioRequestID = stopAudioRequestID
            webView.evaluateJavaScript("window.amgiStopAllAudio && window.amgiStopAllAudio();", completionHandler: nil)
        }

        if typedAnswerRequestID != context.coordinator.lastTypedAnswerRequestID {
            context.coordinator.lastTypedAnswerRequestID = typedAnswerRequestID
            webView.evaluateJavaScript("window.amgiGetTypedAnswer ? window.amgiGetTypedAnswer() : null") { value, _ in
                let typedAnswer: String?
                if let string = value as? String {
                    typedAnswer = string
                } else {
                    typedAnswer = nil
                }
                context.coordinator.onTypedAnswerSubmitted?(typedAnswer)
            }
        }

        // Force bottom content inset so card content can always scroll above the floating
        // action bar. WKWebView does not reliably inherit SwiftUI safeAreaInset changes,
        // so we set it explicitly via DispatchQueue.main.async to override any WebKit-internal
        // layout pass that might run after updateUIView.
        let targetInset = bottomContentInset
        DispatchQueue.main.async {
            webView.scrollView.contentInset.bottom = targetInset
            webView.scrollView.scrollIndicatorInsets.bottom = targetInset
        }
    }

    // MARK: - Helpers

    /// Builds the static HTML frame page (no card content). Card HTML is injected
    /// later via evaluateJavaScript(_showQuestion/_showAnswer) so that arbitrary
    /// HTML never lives inside a <script> literal in the page source.
    private static func buildFrameHTML(
        htmlClass: String,
        isDarkMode: Bool,
        playIconHTML: String,
        pauseIconHTML: String,
        missingImageIconHTML: String,
        missingAudioIconHTML: String,
        baseTag: String
    ) -> String {
        let colorScheme = isDarkMode ? "dark" : "light"
        // Keep the frame background transparent in both light and dark modes.
        // The review toolbar/bottom chrome must sample the rendered card template
        // background; reintroducing a dark-only fallback here makes the wrapper
        // background win over the template color and breaks auto-match again.
        let defaultCardBackground = "transparent"
        let textColor = isDarkMode ? "#f5f5f5" : "#1a1a1a"
        let hrColor = isDarkMode ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.2)"
        let typeBorderColor = isDarkMode ? "rgba(255,255,255,0.28)" : "rgba(0,0,0,0.22)"
        let typeBgColor = isDarkMode ? "rgba(255,255,255,0.08)" : "rgba(255,255,255,0.9)"
        let typeFocusBorder = isDarkMode ? "rgba(143,184,255,0.9)" : "rgba(0,122,255,0.9)"
        let typeFocusShadow = isDarkMode ? "rgba(143,184,255,0.18)" : "rgba(0,122,255,0.15)"
        let typeCodeBg = isDarkMode ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.05)"
        let missingMediaColor = isDarkMode ? "rgba(255,100,100,0.9)" : "rgba(200,40,40,0.8)"
        let playIconLiteral = jsStringLiteral(playIconHTML)
        let pauseIconLiteral = jsStringLiteral(pauseIconHTML)
        let missingImageIconLiteral = jsStringLiteral(missingImageIconHTML)
        let missingAudioIconLiteral = jsStringLiteral(missingAudioIconHTML)
        let mathJaxConfigScriptURL = jsStringLiteral(CardAssetPath.mathJaxConfigScriptURLString)
        let mathJaxCoreScriptURL = jsStringLiteral(CardAssetPath.mathJaxCoreScriptURLString)
        let mathJaxBootstrapScriptTags = Self.mathJaxBootstrapScriptTags()

        return """
        <!DOCTYPE html>
        <html class="\(htmlClass)" data-bs-theme="\(colorScheme)">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        \(baseTag)
        <style>
            :root {
                color-scheme: \(colorScheme);
                --amgi-default-card-bg: \(defaultCardBackground);
                --amgi-default-card-fg: \(textColor);
            }
            html, body {
                background: transparent;
                overflow-x: hidden;
                -webkit-text-size-adjust: 100%;
                text-size-adjust: 100%;
            }
            body {
                font-family: -apple-system, system-ui;
                font-size: 18px; line-height: 1.5;
                color: var(--amgi-default-card-fg); background: var(--amgi-default-card-bg);
                padding: 0 0 var(--amgi-body-padding-bottom, 16px);
                margin: 20px; min-height: calc(100vh - 40px); box-sizing: border-box; text-align: center;
                overflow-wrap: break-word;
                background-size: cover;
                background-repeat: no-repeat;
                background-position: top;
                background-attachment: fixed;
            }
            body.amgi-centered { display: flex; align-items: center; justify-content: center; min-height: calc(100vh - 40px); }
            .card-frame {
                width: 100%; box-sizing: border-box;
                padding-bottom: var(--amgi-card-padding-bottom, 0px);
            }
            hr { border: none; border-top: 1px solid \(hrColor); margin: 16px 0; }
            ruby {
                ruby-position: over;
                line-height: normal;
            }
            ruby rt {
                font-size: 0.58em;
                line-height: 1;
            }
            img { max-width: 100%; max-height: 95vh; height: auto; border-radius: 8px; }
            li { text-align: start; }
            pre { text-align: left; }
            .sound-btn { display: inline-flex; align-items: center; justify-content: center; margin: 4px; }
            .sound-btn audio { display: none; }
            #typeans {
                width: 100%; box-sizing: border-box; line-height: 1.75;
                padding: 10px 12px; border-radius: 10px;
                border: 1px solid \(typeBorderColor); background: \(typeBgColor);
                color: inherit; outline: none;
            }
            #typeans:focus {
                border-color: \(typeFocusBorder);
                box-shadow: 0 0 0 3px \(typeFocusShadow);
            }
            code#typeans {
                display: inline-block; white-space: pre-wrap;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                font-size: 0.95em; line-height: 1.75; padding: 10px 12px;
                font-variant-ligatures: none;
                border-radius: 10px; background: \(typeCodeBg);
            }
            .typeGood { background: #afa; color: black; }
            .typeBad { color: black; background: #faa; }
            .typeMissed { color: black; background: #ccc; }
            #typearrow { opacity: 0.7; }
            .replay-button {
                text-decoration: none; display: inline-flex; vertical-align: middle; margin: 3px;
            }
            .replay-btn {
                background: transparent; border: none; color: inherit; padding: 0;
                line-height: 0; cursor: pointer; display: inline-flex;
                align-items: center; justify-content: center;
                flex: 0 0 auto; min-width: 48px; min-height: 48px;
                box-shadow: none; outline: none;
                -webkit-tap-highlight-color: transparent; appearance: none;
            }
            .replay-btn:active { opacity: 0.7; }
            .replay-btn .amgi-inline-icon {
                width: 34px; height: 34px; display: block;
                max-width: none; max-height: none;
                margin: 0; padding: 0;
                border: 0 !important; border-radius: 0 !important;
                background: transparent !important; box-shadow: none !important;
                object-fit: contain;
            }
            #toggle,
            .toggle {
                min-width: 48px;
                min-height: 34px;
                padding: 4px 10px;
                margin-top: 12px;
                border: 1px solid \(typeBorderColor);
                border-radius: 18px;
                background: \(typeBgColor);
                color: inherit;
                font: inherit;
                font-size: 15px;
                line-height: 1.2;
                cursor: pointer;
                -webkit-appearance: none;
                appearance: none;
            }
            #toggle:active,
            .toggle:active {
                opacity: 0.78;
            }
            video { max-width: 100%; height: auto; border-radius: 8px; margin: 8px 0; }
            .drawing { zoom: 50%; }
            .cloze:not([data-shape]) { display: inline !important; font-weight: 600; color: #1565c0; }
            .cloze-inactive:not([data-shape]),
            .cloze-highlight:not([data-shape]) { display: inline !important; }
            .cloze[data-shape], .cloze-inactive[data-shape], .cloze-highlight[data-shape] { display: none; }
            #image-occlusion-container { position: relative; display: inline-block; line-height: 0; }
            #image-occlusion-canvas {
                position: absolute; top: 0; left: 0;
                pointer-events: auto; cursor: pointer; border-radius: 8px;
            }
            .missing-media {
                display: inline-flex; align-items: center; justify-content: center;
                width: 28px; height: 28px; margin: 4px;
                color: \(missingMediaColor); vertical-align: middle;
            }
            .missing-media .amgi-inline-icon {
                width: 20px; height: 20px; display: block;
                max-width: none; max-height: none;
                margin: 0; padding: 0;
                border: 0 !important; border-radius: 0 !important;
                background: transparent !important; box-shadow: none !important;
                object-fit: contain;
            }
            body.nightMode,
            body.night_mode,
            .nightMode.card,
            .night_mode.card,
            .nightMode .card,
            .night_mode .card {
                color: #f5f5f5;
                background-color: #111111;
            }
            .nightMode .latex, .night_mode .latex { filter: invert(100%); }
            .nightMode img.drawing, .night_mode img.drawing { filter: invert(1) hue-rotate(180deg); }
            .nightMode .cloze:not([data-shape]) { color: #8fb8ff; }
            .night_mode .cloze:not([data-shape]) { color: #8fb8ff; }
            .nightMode a, .nightMode a:visited, .nightMode a:active { color: #8fb8ff; }
            .night_mode a, .night_mode a:visited, .night_mode a:active { color: #8fb8ff; }
        </style>
        <style id="amgi-card-css"></style>
        \(mathJaxBootstrapScriptTags)
        <script>
        // ── Globals ──────────────────────────────────────────────────────────
        var PLAY_ICON_HTML = \(playIconLiteral);
        var PAUSE_ICON_HTML = \(pauseIconLiteral);
        var MISSING_IMAGE_ICON_HTML = \(missingImageIconLiteral);
        var MISSING_AUDIO_ICON_HTML = \(missingAudioIconLiteral);
        var MATHJAX_CONFIG_SCRIPT_URL = \(mathJaxConfigScriptURL);
        var MATHJAX_CORE_SCRIPT_URL = \(mathJaxCoreScriptURL);
        window.__amgiAudioPlaying = false;
        window.onUpdateHook = [];
        window.onShownHook = [];
        window.__amgiUpdateQueue = Promise.resolve();
        window.__amgiMathJaxLoadPromise = null;
        var amgiPreloadTemplate = document.createElement('template');
        var amgiPreloadDoc = document.implementation.createHTMLDocument('');
        var amgiFontURLPattern = /url\\s*\\(\\s*(["']?)(\\S.*?)\\1\\s*\\)/g;
        var amgiCachedFonts = new Set();

        // ── Card state ──────────────────────────────────────────────────────
        window.__amgiCardState = {};

        function amgiCardState() { return window.__amgiCardState || {}; }
        function amgiAutoplayEnabled() { return !!(amgiCardState().autoplayEnabled); }
        function amgiIsAnswerSide() { return !!(amgiCardState().isAnswerSide); }
        function amgiLookupPopupEnabled() { return !!(amgiCardState().lookupPopupEnabled); }
        function amgiReplayModeValue() { return amgiCardState().replayMode || 'question'; }
        function amgiPrefetchHTMLValue() { return amgiCardState().prefetchHTML || ''; }
        function amgiIsLookupFuriganaNode(node) {
            var element = node && node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
            return !!(element && element.closest('rt, rp'));
        }
        function amgiLookupContainerForNode(node) {
            var element = node && node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
            return (element && element.closest('p, li, div, section, article, td, th')) || document.getElementById('qa') || document.body;
        }
        function amgiLookupTextWalker(root) {
            return document.createTreeWalker(root || document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                    return amgiIsLookupFuriganaNode(node) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
                }
            });
        }
        function amgiPointInRange(range, x, y) {
            var rects = range.getClientRects ? Array.from(range.getClientRects()) : [];
            if (!rects.length) rects = [range.getBoundingClientRect()];
            return rects.some(function(rect) {
                return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
            });
        }
        function amgiLookupCharacterAtPoint(x, y) {
            var range = document.caretRangeFromPoint ? document.caretRangeFromPoint(x, y) : null;
            if (!range && document.caretPositionFromPoint) {
                var position = document.caretPositionFromPoint(x, y);
                if (position) {
                    range = document.createRange();
                    range.setStart(position.offsetNode, position.offset);
                }
            }
            var node = range && range.startContainer;
            if (!node || node.nodeType !== Node.TEXT_NODE || amgiIsLookupFuriganaNode(node)) return null;

            var text = node.textContent || '';
            for (var i = 0, offsets = [range.startOffset, range.startOffset - 1, range.startOffset + 1]; i < offsets.length; i++) {
                var offset = offsets[i];
                if (offset < 0 || offset >= text.length) continue;
                var charRange = document.createRange();
                charRange.setStart(node, offset);
                charRange.setEnd(node, offset + 1);
                if (amgiPointInRange(charRange, x, y)) {
                    return { node: node, offset: offset };
                }
            }
            return null;
        }
        function amgiLookupNodesInContainer(root, hitNode) {
            var walker = amgiLookupTextWalker(root);
            var nodes = [];
            var hitIndex = -1;
            var node;
            while (node = walker.nextNode()) {
                if (node === hitNode) hitIndex = nodes.length;
                nodes.push(node);
            }
            return { nodes: nodes, hitIndex: hitIndex };
        }
        function amgiIsLatinLookupChar(character) {
            return /^[A-Za-z0-9]$/.test(character || '');
        }
        function amgiFlattenedLookupItems(root) {
            var walker = amgiLookupTextWalker(root);
            var items = [];
            var node;
            while (node = walker.nextNode()) {
                var content = node.textContent || '';
                for (var index = 0; index < content.length; index++) {
                    items.push({ node: node, offset: index, character: content[index] });
                }
            }
            return items;
        }
        function amgiLatinWordPayloadAt(nodeInfo, hit, maxLength) {
            var items = amgiFlattenedLookupItems(amgiLookupContainerForNode(hit.node));
            var hitIndex = -1;
            for (var i = 0; i < items.length; i++) {
                if (items[i].node === hit.node && items[i].offset === hit.offset) {
                    hitIndex = i;
                    break;
                }
            }
            if (hitIndex < 0) return '';

            var start = hitIndex;
            var end = hitIndex;
            while (start > 0 && end - (start - 1) + 1 <= maxLength && amgiIsLatinLookupChar(items[start - 1].character)) {
                start--;
            }
            while (end + 1 < items.length && (end + 1) - start + 1 <= maxLength && amgiIsLatinLookupChar(items[end + 1].character)) {
                end++;
            }

            return items.slice(start, end + 1).map(function(item) { return item.character; }).join('').trim();
        }
        function amgiLookupRangeRect(node, start, end) {
            var range = document.createRange();
            range.setStart(node, start);
            range.setEnd(node, end);
            var rects = range.getClientRects ? Array.from(range.getClientRects()).filter(function(rect) {
                return rect.width > 0 && rect.height > 0;
            }) : [];
            return rects[0] || null;
        }
        function amgiSameVisualLine(rect, reference) {
            var rectMidY = rect.top + rect.height / 2;
            var referenceMidY = reference.top + reference.height / 2;
            return Math.abs(rectMidY - referenceMidY) <= Math.max(rect.height, reference.height) * 0.65;
        }
        function amgiVisualLatinWordPayloadAt(nodeInfo, hit, maxLength) {
            var chars = [];

            for (var nodeIndex = 0; nodeIndex < nodeInfo.nodes.length; nodeIndex++) {
                var node = nodeInfo.nodes[nodeIndex];
                var content = node.textContent || '';
                for (var index = 0; index < content.length; index++) {
                    var character = content[index];
                    if (!amgiIsLatinLookupChar(character)) continue;
                    var rect = amgiLookupRangeRect(node, index, index + 1);
                    if (!rect) continue;
                    chars.push({ node: node, offset: index, character: character, rect: rect });
                }
            }

            var hitIndex = -1;
            for (var i = 0; i < chars.length; i++) {
                if (chars[i].node === hit.node && chars[i].offset === hit.offset) {
                    hitIndex = i;
                    break;
                }
            }
            if (hitIndex < 0) return '';

            var reference = chars[hitIndex].rect;
            var maxGap = Math.max(6, Math.min(18, reference.width * 1.4));
            var start = hitIndex;
            var end = hitIndex;

            for (var beforeIndex = hitIndex - 1; beforeIndex >= 0 && end - beforeIndex + 1 <= maxLength; beforeIndex--) {
                var currentBefore = chars[beforeIndex];
                var next = chars[beforeIndex + 1];
                if (!amgiSameVisualLine(currentBefore.rect, reference)) break;
                if (next.rect.left - currentBefore.rect.right > maxGap) break;
                start = beforeIndex;
            }

            for (var afterIndex = hitIndex + 1; afterIndex < chars.length && afterIndex - start + 1 <= maxLength; afterIndex++) {
                var currentAfter = chars[afterIndex];
                var previous = chars[afterIndex - 1];
                if (!amgiSameVisualLine(currentAfter.rect, reference)) break;
                if (currentAfter.rect.left - previous.rect.right > maxGap) break;
                end = afterIndex;
            }

            return chars.slice(start, end + 1).map(function(item) { return item.character; }).join('');
        }
        function amgiForwardLookupTextAt(nodeInfo, hit, maxLength, delimiters) {
            var selected = '';

            for (var forwardIndex = nodeInfo.hitIndex; forwardIndex < nodeInfo.nodes.length && selected.length < maxLength; forwardIndex++) {
                var forwardText = nodeInfo.nodes[forwardIndex].textContent || '';
                var forwardOffset = forwardIndex === nodeInfo.hitIndex ? hit.offset : 0;
                for (var f = forwardOffset; f < forwardText.length && selected.length < maxLength; f++) {
                    var forwardChar = forwardText[f];
                    if (delimiters.indexOf(forwardChar) !== -1) {
                        forwardIndex = nodeInfo.nodes.length;
                        break;
                    }
                    selected += forwardChar;
                }
            }

            return selected.trim();
        }

        function amgiApplyCardState(state) {
            window.__amgiCardState = Object.assign({}, window.__amgiCardState || {}, state || {});
            var s = amgiCardState();
            var qa = document.getElementById('qa');
            document.body.className = s.bodyClass || document.body.className;
            document.body.style.setProperty('--amgi-body-padding-bottom', (s.bodyPaddingBottom || 16) + 'px');
            document.body.classList.toggle('amgi-centered', !s.alignTop);
            if (qa) qa.style.setProperty('--amgi-card-padding-bottom', (s.cardPaddingBottom || 0) + 'px');
        }

        function amgiCardLookupPayloadAt(x, y, scanLength) {
            if (!amgiLookupPopupEnabled()) return null;
            var target = document.elementFromPoint(x, y);
            if (!target) return null;
            if (target.closest('a, button, input, textarea, select, option, [contenteditable], .replay-button, .replay-btn, .sound-btn, #image-occlusion-canvas')) {
                return null;
            }
            if (target.closest('rt, rp')) return null;

            var hit = amgiLookupCharacterAtPoint(x, y);
            if (!hit) return null;

            var maxLength = Math.max(1, scanLength || 16);
            var delimiters = ' \\t\\n\\r。、！？…‥「」『』（）()【】〈〉《》〔〕｛｝{}［］[]・：；:;，,.─';
            var container = amgiLookupContainerForNode(hit.node);
            var nodeInfo = amgiLookupNodesInContainer(container, hit.node);
            if (nodeInfo.hitIndex < 0) return null;

            var hitText = hit.node.textContent || '';
            var hitChar = hitText[hit.offset] || '';
            var selected = amgiIsLatinLookupChar(hitChar)
                ? amgiLatinWordPayloadAt(nodeInfo, hit, maxLength)
                : amgiForwardLookupTextAt(nodeInfo, hit, maxLength, delimiters);
            if (amgiIsLatinLookupChar(hitChar) && selected.length === 1) {
                var bodyNodeInfo = amgiLookupNodesInContainer(document.body, hit.node);
                selected = amgiVisualLatinWordPayloadAt(nodeInfo, hit, maxLength)
                    || (bodyNodeInfo.hitIndex >= 0 ? amgiVisualLatinWordPayloadAt(bodyNodeInfo, hit, maxLength) : '')
                    || selected;
            }
            if (!selected) return null;
            return {
                text: selected,
                sentence: (container.textContent || '').trim(),
                x: x,
                y: y
            };
        }

        document.addEventListener('click', function(event) {
            var state = amgiCardState();
            if (state.renderedAt && Date.now() - state.renderedAt < 300) return;
            var payload = amgiCardLookupPayloadAt(event.clientX, event.clientY, 16);
            if (!payload) return;
            window.webkit.messageHandlers.amgiLookupText.postMessage(payload);
        }, false);

        function amgiSetCardCSS(cssText) {
            var style = document.getElementById('amgi-card-css');
            if (!style) return;
            var next = cssText || '';
            if (style.textContent === next) return;
            style.textContent = next;
        }

        // ── Resource preloading ──────────────────────────────────────────────
        function amgiLoadPreloadResource(element) {
            return new Promise(function(resolve) {
                function finish() { resolve(); if (element.parentNode) element.parentNode.removeChild(element); }
                element.addEventListener('load', finish);
                element.addEventListener('error', finish);
                document.head.appendChild(element);
            });
        }
        function amgiCreatePreloadLink(href, asType) {
            var link = document.createElement('link');
            link.rel = 'preload'; link.href = href; link.as = asType;
            if (asType === 'font') link.crossOrigin = '';
            return link;
        }
        function amgiPreloadImage(img) {
            if (!img.getAttribute('decoding')) img.decoding = 'async';
            return img.complete ? Promise.resolve() : new Promise(function(resolve) {
                img.addEventListener('load', function() { resolve(); });
                img.addEventListener('error', function() { resolve(); });
            });
        }
        function amgiPreloadImages(fragment) {
            return Array.from(fragment.querySelectorAll('img[src]')).map(function(existing) {
                try {
                    var img = new Image();
                    img.src = new URL(existing.getAttribute('src') || '', document.baseURI).toString();
                    return amgiPreloadImage(img);
                } catch(e) { return Promise.resolve(); }
            });
        }
        function amgiAllImagesLoaded() {
            return Promise.all(Array.from(document.getElementsByTagName('img')).map(amgiPreloadImage));
        }
        function amgiPreloadStyleSheets(fragment) {
            return Array.from(fragment.querySelectorAll('style, link')).filter(function(css) {
                return (css.tagName === 'STYLE' && (css.innerHTML || '').includes('@import'))
                    || (css.tagName === 'LINK' && css.rel === 'stylesheet');
            }).map(function(css) { css.media = 'print'; return amgiLoadPreloadResource(css); });
        }
        function amgiExtractFontURLs(style) {
            amgiPreloadDoc.head.innerHTML = '';
            amgiPreloadDoc.head.appendChild(style);
            var urls = [];
            try {
                if (style.sheet) {
                    Array.from(style.sheet.cssRules || []).forEach(function(rule) {
                        if (typeof CSSFontFaceRule !== 'undefined' && rule instanceof CSSFontFaceRule) {
                            var src = rule.style.getPropertyValue('src');
                            var matches = src.matchAll(amgiFontURLPattern);
                            for (var m of matches) { if (m[2]) urls.push(m[2]); }
                        }
                    });
                }
            } catch(e) {}
            return urls;
        }
        function amgiPreloadFonts(fragment) {
            var fontURLs = [];
            Array.from(fragment.querySelectorAll('style')).forEach(function(s) {
                fontURLs.push.apply(fontURLs, amgiExtractFontURLs(s));
            });
            return fontURLs.filter(function(url) {
                if (!url || amgiCachedFonts.has(url)) return false;
                amgiCachedFonts.add(url);
                return true;
            }).map(function(url) { return amgiLoadPreloadResource(amgiCreatePreloadLink(url, 'font')); });
        }
        async function amgiPreloadResources(html) {
            try {
                amgiPreloadTemplate.innerHTML = html || '';
                var fragment = amgiPreloadTemplate.content;
                var styleSheets = amgiPreloadStyleSheets(fragment.cloneNode(true));
                var images = amgiPreloadImages(fragment.cloneNode(true));
                var fonts = amgiPreloadFonts(fragment.cloneNode(true));
                var timeout = fonts.length ? 800 : styleSheets.length ? 500 : images.length ? 200 : 0;
                if (!timeout) return;
                await Promise.race([
                    Promise.all(styleSheets.concat(images, fonts)),
                    new Promise(function(resolve) { window.setTimeout(resolve, timeout); })
                ]);
            } catch(e) { console.error('Preload failed', e); }
        }

        function amgiTrimMathJaxText(text) {
            return (text || '')
                .replace(/<br[ ]*\\/?>/gi, '\\n')
                .replace(/^\\n*/, '')
                .replace(/\\n*$/, '');
        }

        function amgiNormalizeMathJaxMarkup(html) {
            return (html || '').replace(
                /<anki-mathjax(?:[^>]*?block="(.*?)")?[^>]*?>([\\s\\S]*?)<\\/anki-mathjax>/gi,
                function(_match, block, text) {
                    var trimmed = amgiTrimMathJaxText(text);
                    return (typeof block === 'string' && block !== 'false')
                        ? '\\[' + trimmed + '\\]'
                        : '\\(' + trimmed + '\\)';
                }
            );
        }

        function amgiContainsMathJaxMarkup(html) {
            var source = html || '';
            return source.includes('\\\\(') || source.includes('\\\\[');
        }

        function amgiLoadMathJaxScript(kind, src) {
            return new Promise(function(resolve) {
                var existing = document.querySelector('script[data-amgi-mathjax="' + kind + '"]');
                if (existing) {
                    if (existing.dataset.amgiLoaded === '1') {
                        resolve();
                        return;
                    }
                    var finishExisting = function() {
                        existing.dataset.amgiLoaded = existing.dataset.amgiLoaded || '1';
                        resolve();
                    };
                    existing.addEventListener('load', function() {
                        finishExisting();
                    }, { once: true });
                    existing.addEventListener('error', function() {
                        resolve();
                    }, { once: true });
                    window.setTimeout(finishExisting, 50);
                    return;
                }

                var script = document.createElement('script');
                script.src = src;
                script.async = false;
                script.setAttribute('data-amgi-mathjax', kind);
                script.addEventListener('load', function() {
                    script.dataset.amgiLoaded = '1';
                    resolve();
                }, { once: true });
                script.addEventListener('error', function() {
                    resolve();
                }, { once: true });
                document.head.appendChild(script);
            });
        }

        async function amgiWaitForMathJax(timeout) {
            var deadline = Date.now() + (timeout || 0);
            while (Date.now() <= deadline) {
                var mathJax = window.MathJax;
                if (mathJax
                    && mathJax.startup
                    && mathJax.startup.promise
                    && typeof mathJax.typesetPromise === 'function') {
                    try {
                        await mathJax.startup.promise;
                    } catch (error) {
                        console.error('MathJax startup failed', error);
                        return null;
                    }
                    return mathJax;
                }
                await new Promise(function(resolve) { window.setTimeout(resolve, 25); });
            }
            return null;
        }

        async function amgiEnsureMathJaxReady(timeout) {
            var readyMathJax = await amgiWaitForMathJax(0);
            if (readyMathJax) {
                return readyMathJax;
            }

            if (!window.__amgiMathJaxLoadPromise) {
                window.__amgiMathJaxLoadPromise = (async function() {
                    await amgiLoadMathJaxScript('config', MATHJAX_CONFIG_SCRIPT_URL);
                    await amgiLoadMathJaxScript('core', MATHJAX_CORE_SCRIPT_URL);
                    return await amgiWaitForMathJax(timeout || 1500);
                })().catch(function(error) {
                    console.error('MathJax load failed', error);
                    window.__amgiMathJaxLoadPromise = null;
                    return null;
                });
            }

            return await window.__amgiMathJaxLoadPromise;
        }

        void amgiEnsureMathJaxReady(4000);

        // ── Hooks ────────────────────────────────────────────────────────────
        function amgiRunHooks(hooks) {
            if (!Array.isArray(hooks)) return Promise.resolve([]);
            var promises = [];
            hooks.forEach(function(hook) {
                try { if (typeof hook === 'function') promises.push(hook()); }
                catch(e) { console.error('Hook failed', e); }
            });
            return Promise.allSettled(promises);
        }

        // Read the visible card/template background first. Do not add an
        // isDarkMode-only DOM background fallback before this function runs,
        // or the reported chrome color will come from the wrapper instead of
        // the card template itself.
        function amgiResolveCardBackground() {
            var candidates = [
                document.querySelector('.card'),
                document.getElementById('qa'),
                document.body,
                document.documentElement,
            ];
            for (var i = 0; i < candidates.length; i++) {
                var el = candidates[i];
                if (!el) continue;
                var bg = window.getComputedStyle(el).backgroundColor;
                if (bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)') {
                    return bg;
                }
            }
            return window.getComputedStyle(document.body).backgroundColor || 'rgba(0, 0, 0, 0)';
        }

        function amgiParseCssColor(color) {
            if (!color) return null;
            var rgba = color.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/i);
            if (!rgba) return null;
            return {
                r: parseInt(rgba[1], 10) || 0,
                g: parseInt(rgba[2], 10) || 0,
                b: parseInt(rgba[3], 10) || 0,
                a: rgba[4] == null ? 1 : (parseFloat(rgba[4]) || 0),
            };
        }

        function amgiReportCardTheme() {
            try {
                var bg = amgiResolveCardBackground();
                var parsed = amgiParseCssColor(bg);
                // Transparent cards have no explicit surface color to sample, so
                // keep the toolbar scheme aligned with the current page theme.
                var isDark = document.documentElement.getAttribute('data-bs-theme') === 'dark';
                if (parsed && parsed.a > 0) {
                    var r = parsed.r || 0;
                    var g = parsed.g || 0;
                    var b = parsed.b || 0;
                    var luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
                    isDark = luminance < 0.55;
                }
                window.webkit.messageHandlers.amgiCardTheme.postMessage({
                    backgroundColor: bg,
                    isDark: isDark,
                });
            } catch(e) {
                console.error('Theme report failed', e);
            }
        }

        function amgiScheduleCardThemeReport() {
            amgiReportCardTheme();
            window.requestAnimationFrame(function() {
                amgiReportCardTheme();
            });
            window.setTimeout(function() {
                amgiReportCardTheme();
            }, 120);
            amgiAllImagesLoaded().then(function() {
                window.requestAnimationFrame(function() {
                    amgiReportCardTheme();
                });
            });
        }

        // ── Script re-execution (mirrors upstream replaceScript) ─────────────
        function amgiReplaceScript(oldScript) {
            return new Promise(function(resolve) {
                var newScript = document.createElement('script');
                var mustWaitForNetwork = !!oldScript.getAttribute('src');
                oldScript.getAttributeNames().forEach(function(name) {
                    if (name === 'type' || name === 'data-amgi-card-script') return;
                    var v = oldScript.getAttribute(name);
                    if (v !== null) newScript.setAttribute(name, v);
                });
                newScript.addEventListener('load', function() { resolve(); });
                newScript.addEventListener('error', function() { resolve(); });
                newScript.appendChild(document.createTextNode(oldScript.textContent || ''));
                oldScript.replaceWith(newScript);
                if (!mustWaitForNetwork) resolve();
            });
        }
        function amgiClearDynamicHeadResources() {
            document.head.querySelectorAll('[data-amgi-card-head-resource="1"]').forEach(function(node) {
                node.remove();
            });
        }
        function amgiHoistDynamicHeadResources(element) {
            amgiClearDynamicHeadResources();
            Array.from(element.querySelectorAll('style, link[rel~="stylesheet"]')).forEach(function(resource) {
                var clone = resource.cloneNode(true);
                clone.setAttribute('data-amgi-card-head-resource', '1');
                document.head.appendChild(clone);
                resource.remove();
            });
        }
        async function amgiSetInnerHTML(element, html) {
            // Pause & drain video elements first (mirrors upstream setInnerHTML)
            Array.from(element.getElementsByTagName('video')).forEach(function(v) {
                v.pause();
                while (v.firstChild) v.removeChild(v.firstChild);
                v.load();
            });
            element.innerHTML = html;
            amgiHoistDynamicHeadResources(element);
            for (var script of Array.from(element.getElementsByTagName('script'))) {
                await amgiReplaceScript(script);
            }
        }

        // ── Audio / Video / TTS ───────────────────────────────────────────────
        function setAudioButtonState(btn, state) {
            if (!btn) return;
            btn.innerHTML = state === 'pause' ? PAUSE_ICON_HTML : PLAY_ICON_HTML;
        }
        function notifyAudioState(isPlaying) {
            isPlaying = !!isPlaying;
            if (window.__amgiAudioPlaying === isPlaying) return;
            window.__amgiAudioPlaying = isPlaying;
            try { window.webkit.messageHandlers.amgiAudioState.postMessage(window.__amgiAudioPlaying); } catch(e) {}
        }
        function amgiStopTts() {
            try { window.webkit.messageHandlers.amgiStopTts.postMessage(null); } catch(e) {}
        }
        window.amgiStopTts = amgiStopTts;
        function amgiQueuePlayerHost() {
            var host = document.getElementById('amgi-media-queue-host');
            if (host) return host;
            host = document.createElement('div');
            host.id = 'amgi-media-queue-host';
            host.style.position = 'fixed';
            host.style.inset = '12px';
            host.style.display = 'none';
            host.style.alignItems = 'center';
            host.style.justifyContent = 'center';
            host.style.background = 'rgba(0,0,0,0.76)';
            host.style.zIndex = '2147483647';
            host.addEventListener('click', function(event) {
                if (event.target === host) {
                    stopAllSystemAudio();
                }
            });
            document.body.appendChild(host);
            return host;
        }
        function amgiQueuePlayer() {
            var player = document.getElementById('amgi-media-queue-player');
            if (player) return player;
            player = document.createElement('video');
            player.id = 'amgi-media-queue-player';
            player.preload = 'auto';
            player.playsInline = true;
            player.controls = true;
            player.style.maxWidth = '100%';
            player.style.maxHeight = '100%';
            player.style.width = 'min(100%, 960px)';
            player.style.background = '#000';
            player.style.borderRadius = '12px';
            player.style.display = 'none';
            amgiQueuePlayerHost().appendChild(player);
            return player;
        }
        function amgiConfigureQueuePlayer(kind) {
            var host = amgiQueuePlayerHost();
            var player = amgiQueuePlayer();
            var isVideo = kind === 'video';
            host.style.display = isVideo ? 'flex' : 'none';
            player.controls = isVideo;
            player.style.display = isVideo ? 'block' : 'none';
        }
        function amgiResetQueuePlayer() {
            var player = document.getElementById('amgi-media-queue-player');
            var host = document.getElementById('amgi-media-queue-host');
            if (!player) {
                if (host) host.style.display = 'none';
                return;
            }
            player.pause();
            player.currentTime = 0;
            player.onended = null;
            player.onerror = null;
            player.removeAttribute('src');
            player.load();
            player.style.display = 'none';
            if (host) host.style.display = 'none';
        }
        function amgiManagedRawMediaElements() {
            return Array.from(document.querySelectorAll('audio:not(#amgi-media-queue-player), video:not(#amgi-media-queue-player)'));
        }
        function amgiMediaButtonForElement(media) {
            var wrapper = media && media.closest ? media.closest('.sound-btn') : null;
            return wrapper ? wrapper.querySelector('.replay-button, .replay-btn') : null;
        }
        function amgiTtsPayloadForDataset(dataset) {
            dataset = dataset || {};
            return {
                text: dataset.ttsText || '',
                lang: dataset.ttsLang || '',
                voices: dataset.ttsVoices || '',
                speed: dataset.ttsSpeed || ''
            };
        }
        function amgiTtsPayloadForButton(btn) {
            return amgiTtsPayloadForDataset(btn && btn.dataset ? btn.dataset : null);
        }
        function amgiTtsSignature(payload) {
            return [
                payload.text || '',
                payload.lang || '',
                payload.voices || '',
                payload.speed || ''
            ].join('|');
        }
        function amgiStructuredAVTags(side) {
            return side === 'a' ? (window.__amgiAnswerAVTags || []) : (window.__amgiQuestionAVTags || []);
        }
        function amgiStructuredAVButton(side, index) {
            var selector = '[data-av-side="' + side + '"][data-av-index="' + index + '"]';
            return document.querySelector('.tts-btn' + selector)
                || document.querySelector('.sound-btn' + selector + ' .replay-button')
                || document.querySelector('.sound-btn' + selector + ' .replay-btn');
        }
        function amgiStructuredItemFromNode(node) {
            if (!node) return null;
            var carrier = node.closest ? (node.closest('.sound-btn, .tts-btn, .amgi-av-tag') || node) : node;
            var data = carrier.dataset || {};
            var kind = data.avKind || '';
            if (!kind) return null;
            var side = data.avSide || 'q';
            var index = parseInt(data.avIndex || '-1', 10);
            if (kind === 'tts') {
                return {
                    kind: 'tts',
                    side: side,
                    index: index,
                    button: carrier.classList && carrier.classList.contains('tts-btn') ? carrier : null,
                    payload: amgiTtsPayloadForDataset(data)
                };
            }
            return {
                kind: 'structured',
                mediaType: kind,
                side: side,
                index: index,
                src: data.avSrc || '',
                button: carrier.querySelector ? carrier.querySelector('.replay-button, .replay-btn') : null
            };
        }
        function amgiStructuredMediaItemBySideIndex(side, index) {
            var tags = amgiStructuredAVTags(side);
            for (var i = 0; i < tags.length; i++) {
                var tag = tags[i];
                if (parseInt(tag.index, 10) !== index) continue;
                if (tag.kind === 'tts') {
                    return {
                        kind: 'tts',
                        side: side,
                        index: index,
                        button: amgiStructuredAVButton(side, index),
                        payload: {
                            text: tag.text || '',
                            lang: tag.lang || '',
                            voices: Array.isArray(tag.voices) ? tag.voices.join(',') : (tag.voices || ''),
                            speed: tag.speed == null ? '' : String(tag.speed)
                        }
                    };
                }
                return {
                    kind: 'structured',
                    mediaType: tag.kind || 'audio',
                    side: side,
                    index: index,
                    src: tag.src || '',
                    button: amgiStructuredAVButton(side, index)
                };
            }
            return null;
        }
        function amgiStructuredMediaItems(side) {
            return amgiStructuredAVTags(side).map(function(tag) {
                return amgiStructuredMediaItemBySideIndex(side, parseInt(tag.index, 10));
            }).filter(Boolean);
        }
        function amgiTtsButtonItems(root) {
            return Array.from((root || document).querySelectorAll('.tts-btn')).map(function(button) {
                return {
                    kind: 'tts',
                    button: button,
                    payload: amgiTtsPayloadForButton(button)
                };
            });
        }
        function amgiRawMediaItems(elements) {
            return (elements || []).map(function(element) {
                return {
                    kind: 'raw',
                    mediaType: element.tagName.toLowerCase(),
                    element: element,
                    media: element,
                    button: amgiMediaButtonForElement(element)
                };
            });
        }
        function amgiMediaItemSignature(item) {
            if (!item) return '';
            if (item.kind === 'tts') {
                return 'tts|' + amgiTtsSignature(item.payload || {});
            }
            function normalizedMediaSource(src) {
                if (!src) return '';
                var raw = String(src).trim();
                if (!raw) return '';
                try {
                    var url = new URL(raw, document.baseURI);
                    var path = decodeURIComponent(url.pathname || '');
                    var parts = path.split('/').filter(Boolean);
                    return parts.length ? parts[parts.length - 1] : decodeURIComponent(url.href);
                } catch (error) {
                    return raw;
                }
            }
            var src = '';
            if (item.kind === 'structured') {
                src = item.src || '';
            } else {
                var media = item.media;
                src = media ? (media.currentSrc || media.getAttribute('src') || media.src || '') : '';
            }
            return (item.mediaType || item.kind || 'media') + '|' + normalizedMediaSource(src);
        }
        function amgiDedupedMediaItems(items, options) {
            options = options || {};
            var seen = new Set();
            var list = items || [];
            if (options.preferLast) {
                var reversed = [];
                for (var i = list.length - 1; i >= 0; i--) {
                    var item = list[i];
                    var signature = amgiMediaItemSignature(item);
                    if (!signature || seen.has(signature)) continue;
                    seen.add(signature);
                    reversed.push(item);
                }
                reversed.reverse();
                return reversed;
            }
            return list.filter(function(item) {
                var signature = amgiMediaItemSignature(item);
                if (!signature || seen.has(signature)) return false;
                seen.add(signature);
                return true;
            });
        }
        function amgiSplitRawMediaQueue() {
            var all = amgiRawMediaItems(amgiManagedRawMediaElements());
            var marker = document.getElementById('answer');
            if (!marker) return { all: all, question: all, answer: all };
            var answer = all.filter(function(item) {
                return !!(marker.compareDocumentPosition(item.element) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            var question = all.filter(function(item) {
                return !(marker.compareDocumentPosition(item.element) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            return {
                all: all,
                question: question.length ? question : all,
                answer: answer.length ? answer : all
            };
        }
        function amgiSplitTtsQueue() {
            var all = amgiTtsButtonItems(document);
            var marker = document.getElementById('answer');
            if (!marker) return { all: all, question: all, answer: all };
            var answer = all.filter(function(item) {
                return !!(marker.compareDocumentPosition(item.button) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            var question = all.filter(function(item) {
                return !(marker.compareDocumentPosition(item.button) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            return {
                all: all,
                question: question.length ? question : all,
                answer: answer.length ? answer : all
            };
        }
        function amgiCollectMediaQueue(mode) {
            var rawQueues = amgiSplitRawMediaQueue();
            var ttsQueues = amgiSplitTtsQueue();
            var question = amgiStructuredMediaItems('q').concat(ttsQueues.question, rawQueues.question);
            var answer = amgiStructuredMediaItems('a').concat(ttsQueues.answer, rawQueues.answer);
            if (mode === 'question') return amgiDedupedMediaItems(question);
            if (mode === 'answerWithQuestion') {
                return amgiDedupedMediaItems(question.concat(answer), { preferLast: true });
            }
            return amgiDedupedMediaItems(answer);
        }
        function amgiAnyManagedMediaPlaying() {
            var queuePlayer = document.getElementById('amgi-media-queue-player');
            var queuePlaying = !!(queuePlayer && !queuePlayer.paused && !queuePlayer.ended && (queuePlayer.currentSrc || queuePlayer.src));
            var elementPlaying = amgiManagedRawMediaElements().some(function(media) {
                return !!media && !media.paused && !media.ended;
            });
            return queuePlaying || elementPlaying || !!window.__amgiTtsPlaying;
        }
        function amgiHandleManagedMediaPause(media) {
            setAudioButtonState(amgiMediaButtonForElement(media), 'play');
            if (!amgiAnyManagedMediaPlaying()) {
                notifyAudioState(false);
            }
        }
        function amgiSetupManagedMediaElement(media) {
            if (!media || media.dataset.amgiManaged === '1') return;
            media.dataset.amgiManaged = '1';
            if (!media.preload) {
                media.preload = 'auto';
            }
            media.playsInline = true;
            media.addEventListener('play', function() {
                stopAllSystemAudio({ exceptMedia: media, preserveReplayRun: true });
                setAudioButtonState(amgiMediaButtonForElement(media), 'pause');
                notifyAudioState(true);
            });
            media.addEventListener('click', function() {
                if (media.controls || !media.paused) return;
                stopAllSystemAudio({ exceptMedia: media, preserveReplayRun: true });
                media.play().catch(function() {});
            });
            media.addEventListener('pause', function() {
                amgiHandleManagedMediaPause(media);
            });
            media.addEventListener('ended', function() {
                amgiHandleManagedMediaPause(media);
            });
            media.addEventListener('error', function() {
                amgiHandleManagedMediaPause(media);
            });
        }
        function amgiSetupManagedMedia() {
            amgiManagedRawMediaElements().forEach(amgiSetupManagedMediaElement);
        }
        window.__amgiTtsPlaying = false;
        window.__amgiTtsResolvers = {};
        window.__amgiReplayRunID = 0;
        function amgiSpeakTtsPayload(payload, onComplete) {
            var token = 'tts-' + Date.now() + '-' + Math.random().toString(36).slice(2);
            if (typeof onComplete === 'function') {
                window.__amgiTtsResolvers[token] = onComplete;
            }
            try {
                window.webkit.messageHandlers.amgiSpeakTts.postMessage({
                    text: payload.text || '',
                    lang: payload.lang || '',
                    voices: payload.voices || '',
                    speed: payload.speed || '',
                    token: token
                });
                return token;
            } catch(e) {
                if (window.__amgiTtsResolvers[token]) {
                    delete window.__amgiTtsResolvers[token];
                }
                return null;
            }
        }
        function amgiHandleTtsEvent(payload) {
            payload = payload || {};
            var token = payload.token || '';
            var state = payload.state || '';
            if (state === 'start') {
                window.__amgiTtsPlaying = true;
                return;
            }
            window.__amgiTtsPlaying = false;
            var resolver = token ? window.__amgiTtsResolvers[token] : null;
            if (resolver) {
                delete window.__amgiTtsResolvers[token];
                resolver(state);
            }
            if (!amgiAnyManagedMediaPlaying()) {
                notifyAudioState(false);
            }
        }
        window.amgiHandleTtsEvent = amgiHandleTtsEvent;
        function stopAllSystemAudio(options) {
            options = options || {};
            var exceptMedia = options.exceptMedia || null;
            if (!options.preserveReplayRun) {
                window.__amgiReplayRunID = (window.__amgiReplayRunID || 0) + 1;
            }
            window.__amgiTtsPlaying = false;
            amgiStopTts();
            document.querySelectorAll('.tts-btn, .sound-btn .replay-button, .sound-btn .replay-btn').forEach(function(btn) {
                setAudioButtonState(btn, 'play');
            });
            amgiManagedRawMediaElements().forEach(function(media) {
                if (exceptMedia && media === exceptMedia) return;
                if (!media.paused) media.pause();
                media.currentTime = 0;
                setAudioButtonState(amgiMediaButtonForElement(media), 'play');
                media.onended = null;
                media.onerror = null;
            });
            amgiResetQueuePlayer();
            notifyAudioState(false);
        }
        window.amgiStopAllAudio = stopAllSystemAudio;
        function amgiPlayStructuredNode(node) {
            return amgiPlayMediaItem(amgiStructuredItemFromNode(node));
        }
        window.amgiPlayStructuredNode = amgiPlayStructuredNode;
        function amgiPlayStructuredSoundItem(item, options) {
            options = options || {};
            if (!item || !item.src) {
                if (typeof options.onComplete === 'function') options.onComplete('error');
                return false;
            }
            stopAllSystemAudio({ preserveReplayRun: !!options.preserveReplayRun });
            var player = amgiQueuePlayer();
            amgiConfigureQueuePlayer(item.mediaType);
            player.src = item.src;
            player.currentTime = 0;
            setAudioButtonState(item.button, 'pause');
            notifyAudioState(true);
            player.onended = function() {
                amgiResetQueuePlayer();
                setAudioButtonState(item.button, 'play');
                if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                if (typeof options.onComplete === 'function') options.onComplete('ended');
            };
            player.onerror = function() {
                amgiResetQueuePlayer();
                setAudioButtonState(item.button, 'play');
                if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                if (typeof options.onComplete === 'function') options.onComplete('error');
            };
            player.play().catch(function() {
                amgiResetQueuePlayer();
                setAudioButtonState(item.button, 'play');
                if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                if (typeof options.onComplete === 'function') options.onComplete('error');
            });
            return false;
        }
        function amgiPlayMediaElement(media, options) {
            options = options || {};
            if (!media) {
                if (typeof options.onComplete === 'function') options.onComplete('error');
                return false;
            }
            stopAllSystemAudio({ exceptMedia: media, preserveReplayRun: !!options.preserveReplayRun });
            var btn = amgiMediaButtonForElement(media);
            media.currentTime = 0;
            media.onended = function() {
                setAudioButtonState(btn, 'play');
                if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                if (typeof options.onComplete === 'function') options.onComplete('ended');
            };
            media.onerror = function() {
                setAudioButtonState(btn, 'play');
                if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                if (typeof options.onComplete === 'function') options.onComplete('error');
            };
            setAudioButtonState(btn, 'pause');
            notifyAudioState(true);
            media.play().catch(function() {
                setAudioButtonState(btn, 'play');
                if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                if (typeof options.onComplete === 'function') options.onComplete('error');
            });
            return false;
        }
        function amgiPlayMediaItem(item, options) {
            options = options || {};
            if (!item) {
                if (typeof options.onComplete === 'function') options.onComplete('error');
                return false;
            }
            if (item.kind === 'tts') {
                stopAllSystemAudio({ preserveReplayRun: !!options.preserveReplayRun });
                if (item.button) {
                    setAudioButtonState(item.button, 'pause');
                }
                var token = amgiSpeakTtsPayload(item.payload || {}, function() {
                    setAudioButtonState(item.button, 'play');
                    if (typeof options.onComplete === 'function') options.onComplete('ended');
                });
                if (!token) {
                    setAudioButtonState(item.button, 'play');
                    if (typeof options.onComplete === 'function') options.onComplete('error');
                } else {
                    notifyAudioState(true);
                }
                return false;
            }
            if (item.kind === 'structured') {
                return amgiPlayStructuredSoundItem(item, options);
            }
            return amgiPlayMediaElement(item.media, options);
        }
        function replaySequential(queue) {
            stopAllSystemAudio();
            if (!queue || !queue.length) return;
            var idx = 0;
            var runID = window.__amgiReplayRunID;
            function isCurrentRun() {
                return window.__amgiReplayRunID === runID;
            }
            function playNext() {
                if (!isCurrentRun()) return;
                if (idx >= queue.length) {
                    if (!amgiAnyManagedMediaPlaying()) notifyAudioState(false);
                    return;
                }
                var item = queue[idx++];
                amgiPlayMediaItem(item, {
                    preserveReplayRun: true,
                    onComplete: function() {
                        if (!isCurrentRun()) return;
                        playNext();
                    }
                });
            }
            playNext();
        }
        function amgiReplayAll(mode) {
            replaySequential(amgiCollectMediaQueue(mode));
        }
        window.amgiReplayAll = amgiReplayAll;
        function playSound(btn) {
            var structuredItem = amgiStructuredItemFromNode(btn);
            if (structuredItem) return amgiPlayMediaItem(structuredItem);
            return amgiPlayMediaElement(btn ? btn.previousElementSibling : null);
        }
        window.playSound = playSound; globalThis.playSound = playSound;

        // ── pycmd (compat shim) ──────────────────────────────────────────────
        function pycmd(command) {
            if (!command || typeof command !== 'string') return false;
            if (command === 'replay') { amgiReplayAll(amgiReplayModeValue()); return false; }
            if (command.startsWith('play:')) {
                var parts = command.split(':');
                var side = parts[1];
                var index = parseInt(parts[2] || '0', 10);
                if (Number.isNaN(index) || index < 0) return false;
                var structuredItem = amgiStructuredMediaItemBySideIndex(side, index);
                if (structuredItem) return amgiPlayMediaItem(structuredItem);
                var queues = amgiSplitRawMediaQueue();
                return amgiPlayMediaItem((side === 'a' ? queues.answer : queues.question)[index]);
            }
            return false;
        }
        globalThis.pycmd = pycmd; window.pycmd = pycmd;

        // ── Link handling ────────────────────────────────────────────────────
        function postOpenLink(rawHref) {
            if (!rawHref) return;
            var resolved = rawHref;
            try { resolved = new URL(rawHref, document.baseURI).toString(); } catch(e) {}
            try { window.webkit.messageHandlers.amgiOpenLink.postMessage(resolved); } catch(e) {}
        }
        document.addEventListener('click', function(event) {
            var anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            if (!anchor) return;
            var href = anchor.getAttribute('href');
            if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;
            event.preventDefault();
            postOpenLink(anchor.href || href);
        });
        window.open = function(url) { postOpenLink(url); return null; };

        // ── TTS ──────────────────────────────────────────────────────────────
        function amgiSpeakTts(btn) {
            if (!btn) return false;
            stopAllSystemAudio();
            setAudioButtonState(btn, 'pause');
            var token = amgiSpeakTtsPayload(amgiTtsPayloadForButton(btn), function() {
                setAudioButtonState(btn, 'play');
            });
            if (!token) {
                setAudioButtonState(btn, 'play');
            }
            return false;
        }
        window.amgiSpeakTts = amgiSpeakTts; globalThis.amgiSpeakTts = amgiSpeakTts;

        // ── Typed answer ─────────────────────────────────────────────────────
        function amgiGetTypedAnswer() {
            var input = document.getElementById('typeans');
            return input ? input.value : null;
        }
        window.amgiGetTypedAnswer = amgiGetTypedAnswer;
        window.getTypedAnswer = amgiGetTypedAnswer;
        globalThis.getTypedAnswer = amgiGetTypedAnswer;
        function amgiSubmitTypedAnswer() {
            try { window.webkit.messageHandlers.amgiSubmitTypedAnswer.postMessage(amgiGetTypedAnswer()); } catch(e) {}
        }
        window.amgiSubmitTypedAnswer = amgiSubmitTypedAnswer;
        function amgiEnsureTypedAnswerVisible() {
            var input = document.getElementById('typeans');
            if (!input) return;
            try { input.scrollIntoView({ block: 'center', inline: 'nearest' }); }
            catch(e) { input.scrollIntoView(); }
        }
        window.amgiEnsureTypedAnswerVisible = amgiEnsureTypedAnswerVisible;
        window.amgiHandleTypeAnswerKey = function(e) {
            e = e || window.event || null;
            if (e && e.key === 'Enter') { e.preventDefault(); amgiSubmitTypedAnswer(); return false; }
            return true;
        };
        window._typeAnsPress = window.amgiHandleTypeAnswerKey;
        globalThis.amgiHandleTypeAnswerKey = window.amgiHandleTypeAnswerKey;
        globalThis._typeAnsPress = window._typeAnsPress;

        // ── Browser classes ──────────────────────────────────────────────────
        function amgiAddBrowserClasses() {
            var ua = navigator.userAgent.toLowerCase();
            function add(c) { if (c) document.documentElement.classList.add(c); }
            if (/ipad/.test(ua)) add('ipad');
            else if (/iphone/.test(ua)) add('iphone');
            else if (/android/.test(ua)) add('android');
            if (/ipad|iphone|ipod/.test(ua)) add('ios');
            if (/ipad|iphone|ipod|android/.test(ua)) add('mobile');
            else if (/linux/.test(ua)) add('linux');
            else if (/windows/.test(ua)) add('win');
            else if (/mac/.test(ua)) add('mac');
            if (/firefox\\//.test(ua)) add('firefox');
            else if (/chrome\\//.test(ua)) add('chrome');
            else if (/safari\\//.test(ua)) add('safari');
        }
        window.ankiPlatform = /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) ? 'ios' : 'other';
        globalThis.ankiPlatform = window.ankiPlatform;

        // ── Image Occlusion ──────────────────────────────────────────────────
        function amgiExtractIOShapes(selector) {
            return Array.from(document.querySelectorAll(selector)).map(function(el) {
                var pointsRaw = el.dataset.points;
                var points = null;
                if (pointsRaw) {
                    var nums = pointsRaw.trim().split(/[\\s,]+/).map(Number).filter(function(v) { return !Number.isNaN(v); });
                    points = [];
                    for (var i = 0; i + 1 < nums.length; i += 2) points.push({ x: nums[i], y: nums[i+1] });
                }
                return {
                    type: el.dataset.shape,
                    ordinal: parseInt(el.dataset.ordinal||'0'),
                    left: parseFloat(el.dataset.left||'0'), top: parseFloat(el.dataset.top||'0'),
                    width: parseFloat(el.dataset.width||'0'), height: parseFloat(el.dataset.height||'0'),
                    rx: parseFloat(el.dataset.rx||'0'), ry: parseFloat(el.dataset.ry||'0'),
                    angle: parseFloat(el.dataset.angle||'0'),
                    text: el.dataset.text||'',
                    scale: parseFloat(el.dataset.scale||'1'),
                    fontSize: parseFloat(el.dataset.fontSize||'0'),
                    fill: el.dataset.fill||'#000000',
                    occludeInactive: (el.dataset.occludeInactive||el.dataset.occludeinactive||'')==='1',
                    points: points
                };
            });
        }
        function amgiDrawIOShape(ctx, shape, size, fill, stroke) {
            if (shape.type === 'text') {
                var fontSize = shape.fontSize > 0 ? shape.fontSize * size.height : 40;
                var scale = shape.scale > 0 ? shape.scale : 1;
                ctx.save(); ctx.font = fontSize + 'px Arial'; ctx.textBaseline = 'top'; ctx.scale(scale, scale);
                var lines = (shape.text || '').split('\\n');
                var bm = ctx.measureText('M');
                var fh = bm.actualBoundingBoxAscent + bm.actualBoundingBoxDescent;
                var lh = 1.5 * fh; var maxW = 0;
                var sl = shape.left * size.width / scale, st = shape.top * size.height / scale;
                var angle = shape.angle * Math.PI / 180;
                lines.forEach(function(l) { var w = ctx.measureText(l).width; if (w > maxW) maxW = w; });
                if (angle) { ctx.translate(sl, st); ctx.rotate(angle); ctx.translate(-sl, -st); }
                ctx.fillStyle = '#ffffff';
                ctx.fillRect(sl, st, maxW + 5, lines.length * lh + 5);
                ctx.fillStyle = shape.fill || '#000000';
                lines.forEach(function(l, i) { ctx.fillText(l, sl, st + i * lh); });
                ctx.restore(); return;
            }
            if (shape.type === 'polygon' && shape.points && shape.points.length >= 2) {
                ctx.save(); ctx.beginPath();
                ctx.moveTo(shape.points[0].x * size.width, shape.points[0].y * size.height);
                for (var pi = 1; pi < shape.points.length; pi++)
                    ctx.lineTo(shape.points[pi].x * size.width, shape.points[pi].y * size.height);
                ctx.closePath(); ctx.fillStyle = fill; ctx.fill();
                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.stroke(); }
                ctx.restore(); return;
            }
            var left = shape.left * size.width, top = shape.top * size.height;
            var angle = shape.angle * Math.PI / 180;
            ctx.save(); ctx.translate(left, top); ctx.rotate(angle);
            if (shape.type === 'rect') {
                var sw = shape.width * size.width, sh = shape.height * size.height;
                ctx.fillStyle = fill; ctx.fillRect(0, 0, sw, sh);
                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.strokeRect(0, 0, sw, sh); }
            } else if (shape.type === 'ellipse') {
                var rx = shape.rx * size.width, ry = shape.ry * size.height;
                ctx.beginPath(); ctx.ellipse(rx, ry, rx, ry, 0, 0, 2 * Math.PI);
                ctx.fillStyle = fill; ctx.fill();
                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.stroke(); }
            }
            ctx.restore();
        }
        function amgiHitTestShape(shape, px, py, size) {
            if (shape.type === 'polygon' && shape.points && shape.points.length >= 3) {
                var inside = false;
                for (var i = 0, j = shape.points.length - 1; i < shape.points.length; j = i++) {
                    var xi = shape.points[i].x * size.width, yi = shape.points[i].y * size.height;
                    var xj = shape.points[j].x * size.width, yj = shape.points[j].y * size.height;
                    if (((yi > py) !== (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) inside = !inside;
                }
                return inside;
            }
            var angle = shape.angle * Math.PI / 180;
            var ox = shape.left * size.width, oy = shape.top * size.height;
            var dx = px - ox, dy = py - oy;
            var lx = dx * Math.cos(-angle) - dy * Math.sin(-angle);
            var ly = dx * Math.sin(-angle) + dy * Math.cos(-angle);
            if (shape.type === 'rect') {
                return lx >= 0 && lx <= shape.width * size.width && ly >= 0 && ly <= shape.height * size.height;
            } else if (shape.type === 'ellipse') {
                var rx = shape.rx * size.width, ry = shape.ry * size.height;
                var ex = lx - rx, ey = ly - ry;
                return (rx > 0 && ry > 0) ? ((ex*ex)/(rx*rx) + (ey*ey)/(ry*ry)) <= 1 : false;
            }
            return false;
        }
        var amgiIOOneTimeSetupDone = false;
        function amgiSetupImageOcclusion() {
            var container = document.getElementById('image-occlusion-container');
            if (!container) return;
            var img = container.querySelector('img');
            if (!img) {
                if (!container.dataset.amgiNoImageShown) {
                    container.textContent = 'No image to show.';
                    container.dataset.amgiNoImageShown = '1';
                }
                return;
            }
            var canvas = document.getElementById('image-occlusion-canvas');
            if (!canvas) {
                canvas = document.createElement('canvas');
                canvas.id = 'image-occlusion-canvas';
                container.appendChild(canvas);
            }
            if (!amgiIOOneTimeSetupDone) {
                window.addEventListener('resize', function() { window.requestAnimationFrame(amgiSetupImageOcclusion); });
                window.addEventListener('keydown', function(event) {
                    var toggleBtn = document.getElementById('toggle') || document.querySelector('.toggle');
                    if (event.key !== 'M' || !toggleBtn || toggleBtn.style.display === 'none') return;
                    var currentContainer = document.getElementById('image-occlusion-container');
                    if (currentContainer && currentContainer._amgiToggleMasks) {
                        currentContainer._amgiToggleMasks(event);
                    }
                });
                amgiIOOneTimeSetupDone = true;
            }
            container.dataset.amgiNoImageShown = '';
            function waitForImg(cb) {
                if (!img || img.complete) { cb(); return; }
                var fn = function() { img.removeEventListener('load', fn); img.removeEventListener('error', fn); cb(); };
                img.addEventListener('load', fn); img.addEventListener('error', fn);
            }
            function optimumCanvasPixelSize(imageSize, containerSize) {
                var dpr = window.devicePixelRatio || 1;
                var targetWidth = containerSize.width * dpr;
                var targetHeight = containerSize.height * dpr;
                var containerScale = Math.min(targetWidth / imageSize.width, targetHeight / imageSize.height);
                var width = imageSize.width * containerScale;
                var height = imageSize.height * containerScale;
                var maximumPixels = 4096 * 4096;
                var requiredPixels = width * height;
                if (requiredPixels > maximumPixels) {
                    var shrinkScale = Math.sqrt(maximumPixels / requiredPixels);
                    width *= shrinkScale;
                    height *= shrinkScale;
                }
                return {
                    width: Math.max(1, Math.floor(width)),
                    height: Math.max(1, Math.floor(height))
                };
            }
            waitForImg(function() {
                window.requestAnimationFrame(function() {
                    var canvasRef = document.getElementById('image-occlusion-canvas');
                    if (!canvasRef) return;
                    var dpr = window.devicePixelRatio || 1;
                    var width = img.offsetWidth, height = img.offsetHeight;
                    if (!width || !height) return;
                    if (img.naturalWidth && img.naturalHeight) {
                        if (CSS.supports && CSS.supports('aspect-ratio: 1')) {
                            container.style.aspectRatio = String(img.naturalWidth / img.naturalHeight);
                        } else {
                            container.style.width = width + 'px';
                            container.style.height = height + 'px';
                        }
                    }
                    canvasRef.style.width = width + 'px'; canvasRef.style.height = height + 'px';
                    var pixelSize = optimumCanvasPixelSize(
                        { width: img.naturalWidth || width, height: img.naturalHeight || height },
                        { width: width, height: height }
                    );
                    canvasRef.width = pixelSize.width;
                    canvasRef.height = pixelSize.height;
                    function collectShapes() {
                        var shapes = [];
                        ['cloze-inactive','cloze','cloze-highlight'].forEach(function(cls) {
                            amgiExtractIOShapes('.' + cls + '[data-shape]').forEach(function(s) {
                                s._cls = cls; s._revealed = false; shapes.push(s);
                            });
                        });
                        container._amgiIOShapes = shapes;
                    }
                    function isAlwaysVisibleAnnotation(shape) {
                        return shape.type === 'text' && shape.ordinal === 0;
                    }
                    function visibleShapes() {
                        return (container._amgiIOShapes || []).filter(function(s) {
                            if (!isAlwaysVisibleAnnotation(s) && s._revealed) return false;
                            if (container._amgiMasksHidden && !isAlwaysVisibleAnnotation(s)) return false;
                            if (s._cls === 'cloze-inactive' && !isAlwaysVisibleAnnotation(s)) return !!s.occludeInactive;
                            return true;
                        });
                    }
                    function redraw() {
                        var ctx = canvasRef.getContext('2d');
                        if (!ctx) return;
                        ctx.setTransform(1, 0, 0, 1, 0, 0);
                        ctx.clearRect(0, 0, canvasRef.width, canvasRef.height);
                        ctx.scale(canvasRef.width / width, canvasRef.height / height);
                        var masksHidden = !!container._amgiMasksHidden;
                        canvasRef.style.pointerEvents = amgiIsAnswerSide() && !masksHidden ? 'auto' : 'none';
                        canvasRef.style.cursor = amgiIsAnswerSide() && !masksHidden ? 'pointer' : 'default';
                        var style = getComputedStyle(document.documentElement);
                        var inactiveColor = style.getPropertyValue('--inactive-shape-color').trim() || '#ffeba2';
                        var activeColor = style.getPropertyValue('--active-shape-color').trim() || '#ff8e8e';
                        var highlightColor = style.getPropertyValue('--highlight-shape-color').trim() || 'rgba(255,142,142,0)';
                        var border = '#212121';
                        var size = { width: width, height: height };
                        visibleShapes().forEach(function(s) {
                            var fill = s._cls === 'cloze-inactive' ? inactiveColor : s._cls === 'cloze' ? activeColor : highlightColor;
                            amgiDrawIOShape(ctx, s, size, fill, border);
                        });
                    }
                    container._amgiRedrawIO = redraw;
                    collectShapes();
                    if (!canvasRef.dataset.amgiRevealBound) {
                        canvasRef.addEventListener('click', function(event) {
                            if (!amgiIsAnswerSide() || container._amgiMasksHidden) return;
                            var rect = canvasRef.getBoundingClientRect();
                            var px = event.clientX - rect.left, py = event.clientY - rect.top;
                            var size = { width: img.offsetWidth, height: img.offsetHeight };
                            var shapes = container._amgiIOShapes || [];
                            for (var i = shapes.length - 1; i >= 0; i--) {
                                if (amgiHitTestShape(shapes[i], px, py, size)) {
                                    shapes[i]._revealed = !shapes[i]._revealed;
                                    redraw(); break;
                                }
                            }
                        });
                        canvasRef.dataset.amgiRevealBound = '1';
                    }
                    var toggleBtn = document.getElementById('toggle') || document.querySelector('.toggle');
                    var hasInactiveMasks = !!document.querySelector('[data-occludeinactive="1"], [data-occludeInactive="1"]');
                    container._amgiToggleMasks = function(event) {
                        if (event) { event.preventDefault(); event.stopPropagation(); }
                        container._amgiMasksHidden = !container._amgiMasksHidden;
                        if (!container._amgiMasksHidden)
                            (container._amgiIOShapes || []).forEach(function(s) { s._revealed = false; });
                        if (toggleBtn) toggleBtn.setAttribute('aria-pressed', container._amgiMasksHidden ? 'true' : 'false');
                        redraw();
                    };
                    if (toggleBtn) {
                        toggleBtn.type = 'button';
                        toggleBtn.setAttribute('aria-pressed', container._amgiMasksHidden ? 'true' : 'false');
                        if (!amgiIsAnswerSide() || !hasInactiveMasks) { toggleBtn.style.display = 'none'; }
                        else {
                            toggleBtn.style.display = '';
                            if (!toggleBtn.dataset.amgiToggleBound) {
                                toggleBtn.addEventListener('click', function(e) { if (container._amgiToggleMasks) container._amgiToggleMasks(e); });
                                toggleBtn.dataset.amgiToggleBound = '1';
                            }
                        }
                    }
                    redraw();
                });
            });
        }
        window.amgiSetupImageOcclusion = amgiSetupImageOcclusion;

        // anki.imageOcclusion / anki.setupImageCloze compat shims
        var anki = globalThis.anki || {};
        globalThis.anki = anki; window.anki = anki;
        anki.addBrowserClasses = amgiAddBrowserClasses;
        anki.imageOcclusion = anki.imageOcclusion || {};
        anki.imageOcclusion.setup = amgiSetupImageOcclusion;
        anki.imageOcclusion.drawShape = amgiDrawIOShape;
        anki.imageOcclusion.Shape = anki.imageOcclusion.Shape || function Shape() {};
        anki.imageOcclusion.Text = anki.imageOcclusion.Text || function Text() {};
        anki.imageOcclusion.Rectangle = anki.imageOcclusion.Rectangle || function Rectangle() {};
        anki.imageOcclusion.Ellipse = anki.imageOcclusion.Ellipse || function Ellipse() {};
        anki.imageOcclusion.Polygon = anki.imageOcclusion.Polygon || function Polygon() {};
        anki.setupImageCloze = function() { amgiSetupImageOcclusion(); };
        amgiAddBrowserClasses();

        // ── Core QA update (mirrors upstream _updateQA) ──────────────────────
        async function amgiUpdateQA(html, state, onupdate, onshown) {
            window.onUpdateHook = [];
            window.onShownHook = [];
            if (typeof onupdate === 'function') window.onUpdateHook.push(onupdate);
            if (typeof onshown === 'function') window.onShownHook.push(onshown);

            var qa = document.getElementById('qa');
            if (!qa) return;

            stopAllSystemAudio();
            var normalizedHTML = amgiNormalizeMathJaxMarkup(html || '');
            var needsMathJax = amgiContainsMathJaxMarkup(normalizedHTML);
            var preloadPromise = amgiPreloadResources(normalizedHTML);
            var mathJaxPromise = needsMathJax ? amgiEnsureMathJaxReady(1500) : Promise.resolve(null);

            try {
                await preloadPromise;
                // Keep the previous card visible while resources warm, and only
                // hide right before swapping the DOM to avoid blank-frame flashes.
                qa.style.transition = 'none';
                qa.style.opacity = '0';
                amgiApplyCardState(state || {});

                try { await amgiSetInnerHTML(qa, normalizedHTML); }
                catch(e) { qa.innerHTML = '<div>Error: ' + String(e).replace(/\\n/g,'<br>') + '</div>'; }

                await amgiRunHooks(window.onUpdateHook);

                if (needsMathJax) {
                    try {
                        var mathJax = await mathJaxPromise;
                        if (mathJax) {
                            if (typeof mathJax.typesetClear === 'function') {
                                mathJax.typesetClear();
                            }
                            await mathJax.typesetPromise([qa])
                                .catch(function(error) { console.error('MathJax failed', error); });
                        }
                    } catch (error) {
                        console.error('MathJax unavailable', error);
                    }
                }

                // Detect missing media
                document.querySelectorAll('img').forEach(function(img) {
                    img.onerror = function() {
                        var hint = document.createElement('span');
                        hint.className = 'missing-media';
                        hint.innerHTML = MISSING_IMAGE_ICON_HTML;
                        img.replaceWith(hint);
                    };
                    if (img.complete && img.naturalWidth === 0 && img.src) img.onerror();
                });
                document.querySelectorAll('.sound-btn').forEach(function(span) {
                    var media = span.querySelector('audio, video');
                    if (!media) return;
                    media.onerror = function() {
                        var hint = document.createElement('span');
                        hint.className = 'missing-media';
                        hint.innerHTML = MISSING_AUDIO_ICON_HTML;
                        span.replaceWith(hint);
                    };
                });
                amgiSetupManagedMedia();

                var typeInput = document.getElementById('typeans');
        if (typeInput) {
            var ensureVisible = function() { window.setTimeout(amgiEnsureTypedAnswerVisible, 180); };
            typeInput.addEventListener('focus', ensureVisible);
            typeInput.addEventListener('click', ensureVisible);
            typeInput.addEventListener('input', ensureVisible);
            typeInput.addEventListener('keydown', window.amgiHandleTypeAnswerKey);
            typeInput.focus(); ensureVisible();
        }

                amgiSetupImageOcclusion();
                await amgiRunHooks(window.onShownHook);
            } finally {
                // Avoid a forced fade-in on every flip/next-card update; it reads
                // as a content reload once MathJax and scripts are involved.
                qa.style.transition = 'none';
                qa.style.opacity = '1';
                amgiScheduleCardThemeReport();
            }
        }

        // ── Serial queue (mirrors upstream _queueAction) ─────────────────────
        function amgiQueueAction(action) {
            window.__amgiUpdateQueue = (window.__amgiUpdateQueue || Promise.resolve()).then(action);
        }

        // ── Public API called from Swift via evaluateJavaScript ───────────────
        function _showQuestion(html, prefetchHTML, bodyclass, autoplay, replayMode, alignTop, bodyPaddingBottom, cardPaddingBottom, lookupPopupEnabled) {
            amgiQueueAction(function() {
                return amgiUpdateQA(
                    html,
                    {
                        isAnswerSide: false,
                        lookupPopupEnabled: !!lookupPopupEnabled,
                        bodyClass: bodyclass,
                        autoplayEnabled: !!autoplay,
                        replayMode: replayMode || 'question',
                        alignTop: !!alignTop,
                        bodyPaddingBottom: bodyPaddingBottom || 16,
                        cardPaddingBottom: cardPaddingBottom || 0,
                        renderedAt: Date.now(),
                        prefetchHTML: prefetchHTML || ''
                    },
                    function() {
                        window.scrollTo(0, 0);
                    },
                    function() {
                        var typeans = document.getElementById('typeans');
                        if (typeans) typeans.focus();
                        if (amgiAutoplayEnabled()) amgiReplayAll(amgiReplayModeValue());
                        var ph = amgiPrefetchHTMLValue();
                        if (amgiContainsMathJaxMarkup(html || '') || amgiContainsMathJaxMarkup(ph || '')) {
                            void amgiEnsureMathJaxReady(1500);
                        }
                        if (ph) amgiAllImagesLoaded().then(function() { return amgiPreloadResources(ph); });
                    }
                );
            });
        }

        function _showAnswer(html, bodyclass, autoplay, replayMode, alignTop, bodyPaddingBottom, cardPaddingBottom, lookupPopupEnabled) {
            amgiQueueAction(function() {
                return amgiUpdateQA(
                    html,
                    {
                        isAnswerSide: true,
                        lookupPopupEnabled: !!lookupPopupEnabled,
                        bodyClass: bodyclass,
                        autoplayEnabled: !!autoplay,
                        replayMode: replayMode || 'answerOnly',
                        alignTop: !!alignTop,
                        bodyPaddingBottom: bodyPaddingBottom || 16,
                        cardPaddingBottom: cardPaddingBottom || 0,
                        renderedAt: Date.now(),
                        prefetchHTML: ''
                    },
                    function() {
                        // scroll to answer after images load
                        amgiAllImagesLoaded().then(function() {
                            var marker = document.getElementById('answer');
                            if (marker) marker.scrollIntoView();
                        });
                    },
                    function() {
                        if (amgiAutoplayEnabled()) amgiReplayAll(amgiReplayModeValue());
                    }
                );
            });
        }

        window._showQuestion = _showQuestion;
        window._showAnswer = _showAnswer;
        </script>
        </head>
        <body><div id="qa" class="card-frame"></div></body>
        </html>
        """
    }

    /// Builds the evaluateJavaScript call that shows the card.
    /// HTML content is passed as JS string arguments – never embedded inside
    /// a <script> tag in the page source – eliminating </script> injection risk.
    private static func showCardScript(
        processedHTML: String,
        prefetchHTML: String?,
        cardCSS: String,
        isAnswerSide: Bool,
        lookupPopupEnabled: Bool,
        bodyClass: String,
        autoplayEnabled: Bool,
        replayMode: String,
        alignTop: Bool,
        bodyPaddingBottom: Int,
        cardPaddingBottom: Int,
        questionAVTags: [Anki_CardRendering_AVTag],
        answerAVTags: [Anki_CardRendering_AVTag]
    ) -> String {
        let htmlLit = jsStringLiteral(processedHTML)
        let cssLit = jsStringLiteral(normalizeCardCSS(cardCSS))
        let autoplay = autoplayEnabled ? "true" : "false"
        let lookupEnabled = lookupPopupEnabled ? "true" : "false"
        let alignTopStr = alignTop ? "true" : "false"
        let applyCSS = "amgiSetCardCSS(\(cssLit));"
        let questionTagsLit = jsObjectLiteral(managedAVTagDescriptors(questionAVTags, side: "q"), fallback: "[]")
        let answerTagsLit = jsObjectLiteral(managedAVTagDescriptors(answerAVTags, side: "a"), fallback: "[]")
        let applyAVTags = "window.__amgiQuestionAVTags = \(questionTagsLit);window.__amgiAnswerAVTags = \(answerTagsLit);"

        if isAnswerSide {
            return applyCSS + applyAVTags + "_showAnswer(\(htmlLit),\(jsStringLiteral(bodyClass)),\(autoplay),\(jsStringLiteral(replayMode)),\(alignTopStr),\(bodyPaddingBottom),\(cardPaddingBottom),\(lookupEnabled)" + ");"
        } else {
            let prefetchLit = jsStringLiteral(prefetchHTML ?? "")
            return applyCSS + applyAVTags + "_showQuestion(\(htmlLit),\(prefetchLit),\(jsStringLiteral(bodyClass)),\(autoplay),\(jsStringLiteral(replayMode)),\(alignTopStr),\(bodyPaddingBottom),\(cardPaddingBottom),\(lookupEnabled)" + ");"
        }
    }

    static func mathJaxBootstrapScriptTags() -> String {
        """
        <script src="\(CardAssetPath.mathJaxConfigScriptURLString)" data-amgi-mathjax="config" onload="this.dataset.amgiLoaded='1'"></script>
        <script src="\(CardAssetPath.mathJaxCoreScriptURLString)" data-amgi-mathjax="core" onload="this.dataset.amgiLoaded='1'"></script>
        """
    }

    private struct ManagedAVTagDescriptor: Encodable {
        let side: String
        let index: Int
        let kind: String
        let src: String?
        let text: String?
        let lang: String?
        let voices: [String]
        let speed: Float?
    }

    private static let audioFileExtensions: Set<String> = [
        "3gp", "flac", "m4a", "mp3", "oga", "ogg", "opus", "spx", "wav"
    ]

    private static func processReviewHTML(
        _ html: String,
        questionAVTags: [Anki_CardRendering_AVTag],
        answerAVTags: [Anki_CardRendering_AVTag],
        isDarkMode: Bool,
        showReplayButtons: Bool
    ) -> String {
        deferCardScripts(in:
            expandTTSTags(
                in: expandSoundTags(
                    expandPlayTags(
                        in: html,
                        questionAVTags: questionAVTags,
                        answerAVTags: answerAVTags,
                        isDarkMode: isDarkMode,
                        showReplayButtons: showReplayButtons
                    ),
                    isDarkMode: isDarkMode,
                    showReplayButtons: showReplayButtons
                ),
                isDarkMode: isDarkMode,
                showReplayButtons: showReplayButtons
            )
        )
    }

    static func expandPlayTags(
        in html: String,
        questionAVTags: [Anki_CardRendering_AVTag],
        answerAVTags: [Anki_CardRendering_AVTag],
        isDarkMode: Bool,
        showReplayButtons: Bool
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[anki:play:([qa]):(\d+)\]"#,
            options: [.caseInsensitive]
        ) else { return html }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var result = html

        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let sideRange = Range(match.range(at: 1), in: result),
                  let indexRange = Range(match.range(at: 2), in: result) else { continue }
            let side = String(result[sideRange]).lowercased()
            let index = Int(String(result[indexRange])) ?? -1
            let tags = side == "a" ? answerAVTags : questionAVTags
            guard tags.indices.contains(index) else {
                result.replaceSubrange(matchRange, with: "")
                continue
            }

            let replacement = markup(
                for: tags[index],
                side: side,
                index: index,
                isDarkMode: isDarkMode,
                showReplayButtons: showReplayButtons
            )
            result.replaceSubrange(matchRange, with: replacement)
        }

        return result
    }

    /// Converts legacy `[sound:filename.ext]` markers to managed replay markup.
    static func expandSoundTags(
        _ html: String,
        isDarkMode: Bool,
        showReplayButtons: Bool
    ) -> String {
        // Pattern: [sound:anything_without_closing_bracket]
        guard let regex = try? NSRegularExpression(
            pattern: #"\[sound:([^\]]+)\]"#, options: []
        ) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var result = html
        // Process in reverse order to preserve character indices
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let filenameRange = Range(match.range(at: 1), in: result) else { continue }
            let filename = String(result[filenameRange])
            var tag = Anki_CardRendering_AVTag()
            tag.soundOrVideo = filename
            let replacement = markup(
                for: tag,
                side: "q",
                index: -1,
                isDarkMode: isDarkMode,
                showReplayButtons: showReplayButtons
            )
            result.replaceSubrange(matchRange, with: replacement)
        }
        return result
    }

    static func expandTTSTags(
        in html: String,
        isDarkMode: Bool,
        showReplayButtons: Bool
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[anki:tts([^\]]*)\](.*?)\[/anki:tts\]"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return html }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var result = html

        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let attrsRange = Range(match.range(at: 1), in: result),
                  let textRange = Range(match.range(at: 2), in: result) else { continue }

            let options = parseTTSAttributes(String(result[attrsRange]))
            let spokenText = String(result[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lang = options["lang"] ?? ""
            let voices = options["voices"] ?? ""
            let speed = options["speed"] ?? ""

            let replacement: String
            if showReplayButtons {
                let iconHTML = audioButtonIconHTML(systemName: "play.circle", alt: "Speak", isDarkMode: isDarkMode)
                replacement = "<a class=\"replay-button replay-btn tts-btn\" href=\"#\" draggable=\"false\" data-tts-text=\"\(htmlAttributeEscaped(spokenText))\" data-tts-lang=\"\(htmlAttributeEscaped(lang))\" data-tts-voices=\"\(htmlAttributeEscaped(voices))\" data-tts-speed=\"\(htmlAttributeEscaped(speed))\" onclick=\"return amgiSpeakTts(this)\">\(iconHTML)</a>"
            } else {
                replacement = ""
            }

            result.replaceSubrange(matchRange, with: replacement)
        }

        return result
    }

    private static func markup(
        for tag: Anki_CardRendering_AVTag,
        side: String,
        index: Int,
        isDarkMode: Bool,
        showReplayButtons: Bool
    ) -> String {
        let sideAttr = htmlAttributeEscaped(side)
        let indexAttr = String(index)

        switch tag.value {
        case .soundOrVideo(let resource):
            let encodedSrc = htmlAttributeEscaped(encodedMediaSource(resource))
            let kind = mediaKind(for: resource)
            if kind == "video" {
                return """
                <video class="amgi-inline-video" controls playsinline preload="metadata" data-av-side="\(sideAttr)" data-av-index="\(indexAttr)" data-av-kind="video" data-av-src="\(encodedSrc)" src="\(encodedSrc)"></video>
                """
            }
            let iconHTML = audioButtonIconHTML(systemName: "play.circle", alt: "Play", isDarkMode: isDarkMode)
            let hiddenMarker = "<span class=\"amgi-av-tag sound-tag\" data-av-side=\"\(sideAttr)\" data-av-index=\"\(indexAttr)\" data-av-kind=\"audio\" data-av-src=\"\(encodedSrc)\"></span>"
            guard showReplayButtons else {
                return hiddenMarker
            }
            return "<span class=\"sound-btn soundLink\" data-av-side=\"\(sideAttr)\" data-av-index=\"\(indexAttr)\" data-av-kind=\"audio\" data-av-src=\"\(encodedSrc)\">\(hiddenMarker)<a class=\"replay-button replay-btn\" href=\"#\" draggable=\"false\" onclick=\"return amgiPlayStructuredNode(this)\">\(iconHTML)</a></span>"

        case .tts(let ttsTag):
            let spokenText = htmlAttributeEscaped(ttsTag.fieldText.trimmingCharacters(in: .whitespacesAndNewlines))
            let lang = htmlAttributeEscaped(ttsTag.lang)
            let voices = htmlAttributeEscaped(ttsTag.voices.joined(separator: ","))
            let speed = ttsTag.speed > 0 ? htmlAttributeEscaped(String(ttsTag.speed)) : ""
            let hiddenMarker = "<span class=\"amgi-av-tag tts-tag\" data-av-side=\"\(sideAttr)\" data-av-index=\"\(indexAttr)\" data-av-kind=\"tts\" data-tts-text=\"\(spokenText)\" data-tts-lang=\"\(lang)\" data-tts-voices=\"\(voices)\" data-tts-speed=\"\(speed)\"></span>"
            guard showReplayButtons else {
                return hiddenMarker
            }
            let iconHTML = audioButtonIconHTML(systemName: "play.circle", alt: "Speak", isDarkMode: isDarkMode)
            return "<a class=\"replay-button replay-btn tts-btn\" href=\"#\" draggable=\"false\" data-av-side=\"\(sideAttr)\" data-av-index=\"\(indexAttr)\" data-av-kind=\"tts\" data-tts-text=\"\(spokenText)\" data-tts-lang=\"\(lang)\" data-tts-voices=\"\(voices)\" data-tts-speed=\"\(speed)\" onclick=\"return amgiPlayStructuredNode(this)\">\(iconHTML)</a>"

        case .none:
            return ""
        }
    }

    private static func managedAVTagDescriptors(
        _ tags: [Anki_CardRendering_AVTag],
        side: String
    ) -> [ManagedAVTagDescriptor] {
        tags.enumerated().compactMap { index, tag in
            managedAVTagDescriptor(tag, side: side, index: index)
        }
    }

    private static func managedAVTagDescriptor(
        _ tag: Anki_CardRendering_AVTag,
        side: String,
        index: Int
    ) -> ManagedAVTagDescriptor? {
        switch tag.value {
        case .soundOrVideo(let resource):
            guard isAudioResource(resource) else {
                return nil
            }
            return ManagedAVTagDescriptor(
                side: side,
                index: index,
                kind: "audio",
                src: encodedMediaSource(resource),
                text: nil,
                lang: nil,
                voices: [],
                speed: nil
            )
        case .tts(let ttsTag):
            return ManagedAVTagDescriptor(
                side: side,
                index: index,
                kind: "tts",
                src: nil,
                text: ttsTag.fieldText,
                lang: ttsTag.lang,
                voices: ttsTag.voices,
                speed: ttsTag.speed > 0 ? ttsTag.speed : nil
            )
        case .none:
            return nil
        }
    }

    private static func mediaKind(for resource: String) -> String {
        isAudioResource(resource) ? "audio" : "video"
    }

    private static func isAudioResource(_ resource: String) -> Bool {
        let pathExtension = URL(string: resource)?.pathExtension.lowercased()
            ?? URL(fileURLWithPath: resource).pathExtension.lowercased()
        return audioFileExtensions.contains(pathExtension)
    }

    private static func encodedMediaSource(_ resource: String) -> String {
        let trimmed = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return trimmed
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "#?")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private static func deferCardScripts(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) else { return html }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var result = html

        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let attrsRange = Range(match.range(at: 1), in: result) else { continue }

            let attrs = String(result[attrsRange])
            let withoutQuotedType = attrs.replacingOccurrences(
                of: #"\stype\s*=\s*(["']).*?\1"#,
                with: "",
                options: .regularExpression
            )
            let cleanedAttrs = withoutQuotedType.replacingOccurrences(
                of: #"\stype\s*=\s*[^\s>]+"#,
                with: "",
                options: .regularExpression
            )

            let replacement = "<script type=\"application/x-amgi-card-script\" data-amgi-card-script=\"1\"\(cleanedAttrs)>"
            result.replaceSubrange(matchRange, with: replacement)
        }

        return result
    }

    private static func parseTTSAttributes(_ raw: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_]+)=([^\s\]]+)"#,
            options: []
        ) else { return [:] }

        let range = NSRange(raw.startIndex..., in: raw)
        let matches = regex.matches(in: raw, range: range)
        var result: [String: String] = [:]
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: raw),
                  let valueRange = Range(match.range(at: 2), in: raw) else { continue }
            result[String(raw[keyRange]).lowercased()] = String(raw[valueRange])
        }
        return result
    }

    private static func htmlAttributeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func audioButtonIconHTML(systemName: String, alt: String, isDarkMode: Bool) -> String {
        symbolIconHTML(
            systemName: systemName,
            alt: alt,
            isDarkMode: isDarkMode,
            pointSize: 24
        )
    }

    private static func missingMediaIconHTML(systemName: String, alt: String, isDarkMode: Bool) -> String {
        symbolIconHTML(
            systemName: systemName,
            alt: alt,
            isDarkMode: isDarkMode,
            pointSize: 20
        )
    }

    private static func symbolIconHTML(
        systemName: String,
        alt: String,
        isDarkMode: Bool,
        pointSize: CGFloat
    ) -> String {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
        let tint = isDarkMode ? UIColor.white : UIColor(red: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 1)
        guard let baseImage = UIImage(systemName: systemName, withConfiguration: configuration) else {
            return alt
        }

        let image = baseImage.withTintColor(tint, renderingMode: .alwaysOriginal)
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let rendered = renderer.image { _ in
            image.draw(at: .zero)
        }

        guard let data = rendered.pngData() else {
            return alt
        }

        return "<img class=\"amgi-inline-icon\" src=\"data:image/png;base64,\(data.base64EncodedString())\" alt=\"\(alt)\" draggable=\"false\" style=\"width:28px;height:28px;max-width:none;display:block;flex:none;\" />"
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            // Escape </script> so it doesn't prematurely close the enclosing <script> block
            .replacingOccurrences(of: "</script>", with: "<\\/script>", options: .caseInsensitive)
        return "'\(escaped)'"
    }

    private static func jsObjectLiteral<T: Encodable>(_ value: T, fallback: String) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return string
    }

    private static func rewriteRelativeMediaURLs(in css: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"url\(\s*(['"]?)([^'")]+)\1\s*\)"#,
            options: [.caseInsensitive]
        ) else {
            return css
        }

        let nsRange = NSRange(css.startIndex..., in: css)
        let matches = regex.matches(in: css, range: nsRange)
        guard !matches.isEmpty else {
            return css
        }

        var rewritten = css
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: rewritten),
                  let quoteRange = Range(match.range(at: 1), in: rewritten),
                  let urlRange = Range(match.range(at: 2), in: rewritten) else {
                continue
            }

            let quote = String(rewritten[quoteRange])
            let rawURL = String(rewritten[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard shouldRewriteMediaURL(rawURL),
                  let absoluteURL = URL(string: rawURL, relativeTo: CardAssetPath.mediaBaseURL)?.absoluteString else {
                continue
            }

            rewritten.replaceSubrange(fullRange, with: "url(\(quote)\(absoluteURL)\(quote))")
        }

        return rewritten
    }

    private static func normalizeCardCSS(_ css: String) -> String {
        rewriteRelativeMediaURLs(in: sanitizeCardCSS(css))
    }

    private static func sanitizeCardCSS(_ css: String) -> String {
        var sanitized = css

        if let styleTagRegex = try? NSRegularExpression(
            pattern: #"</?style\b[^>]*>"#,
            options: [.caseInsensitive]
        ) {
            sanitized = styleTagRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: ""
            )
        }

        if let htmlCommentRegex = try? NSRegularExpression(
            pattern: #"<!--([\s\S]*?)-->"#,
            options: []
        ) {
            sanitized = htmlCommentRegex.stringByReplacingMatches(
                in: sanitized,
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: "/*$1*/"
            )
        }

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldRewriteMediaURL(_ rawURL: String) -> Bool {
        guard !rawURL.isEmpty else {
            return false
        }

        let lowercased = rawURL.lowercased()
        if rawURL.hasPrefix("/") || rawURL.hasPrefix("#") || rawURL.hasPrefix("//") {
            return false
        }

        let blockedSchemes = [
            "data:",
            "http:",
            "https:",
            "file:",
            "blob:",
            "about:",
            "amgi-asset:",
        ]

        return !blockedSchemes.contains { lowercased.hasPrefix($0) }
    }

    private static func bodyClasses(cardOrdinal: UInt32, isDarkMode: Bool) -> String {
        var classes = ["card", "card\(Int(cardOrdinal) + 1)"]
        if isDarkMode {
            classes.append("nightMode")
            classes.append("night_mode")
        }
        return classes.joined(separator: " ")
    }

    private static func htmlClasses(isDarkMode: Bool) -> String {
        var classes: [String] = []

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            classes.append("ios")
            classes.append("ipad")
            classes.append("mobile")
        case .phone:
            classes.append("ios")
            classes.append("iphone")
            classes.append("mobile")
        default:
            break
        }

        if isDarkMode {
            classes.append("nightMode")
            classes.append("night_mode")
        }

        return classes.joined(separator: " ")
    }

    // MARK: - Navigation Delegate

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastPageSignature: String?
        var lastContentSignature: String?
        var lastReplayRequestID: Int = 0
        var lastStopAudioRequestID: Int = 0
        var lastTypedAnswerRequestID: Int = 0
        var isPageLoaded = false
        var pendingUpdateScript: String?
        var openLinksExternally: Bool = true
        var playAudioInSilentMode: Bool = false
        weak var currentWebView: WKWebView?
        let onTypedAnswerSubmitted: ((String?) -> Void)?
        private let onAudioStateChange: ((Bool) -> Void)?
        private let onCardBackgroundColorChange: ((UIColor, Bool) -> Void)?
        private let onLookupRequested: ((String?, String?, CGPoint) -> Void)?
        private var lastThemePayload: String?
        private let ttsPlayer = CardTTSPlayer()

        init(
            onTypedAnswerSubmitted: ((String?) -> Void)? = nil,
            onAudioStateChange: ((Bool) -> Void)? = nil,
            onCardBackgroundColorChange: ((UIColor, Bool) -> Void)? = nil,
            onLookupRequested: ((String?, String?, CGPoint) -> Void)? = nil
        ) {
            self.onTypedAnswerSubmitted = onTypedAnswerSubmitted
            self.onAudioStateChange = onAudioStateChange
            self.onCardBackgroundColorChange = onCardBackgroundColorChange
            self.onLookupRequested = onLookupRequested
            super.init()
            ttsPlayer.onEvent = { [weak self] state, token in
                self?.handleTTSEvent(state: state, token: token)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "amgiAudioState" {
                if let isPlaying = message.body as? Bool {
                    onAudioStateChange?(isPlaying)
                } else if let number = message.body as? NSNumber {
                    onAudioStateChange?(number.boolValue)
                }
                return
            }

            if message.name == "amgiStopTts" {
                stopTTS()
                return
            }

            if message.name == "amgiSpeakTts" {
                ttsPlayer.speak(messageBody: message.body, playAudioInSilentMode: playAudioInSilentMode)
                return
            }

            if message.name == "amgiSubmitTypedAnswer" {
                if let string = message.body as? String {
                    onTypedAnswerSubmitted?(string)
                } else if message.body is NSNull {
                    onTypedAnswerSubmitted?(nil)
                } else {
                    onTypedAnswerSubmitted?(nil)
                }
                return
            }

            if message.name == "amgiCardTheme" {
                guard let body = message.body as? [String: Any] else { return }
                let colorString = body["backgroundColor"] as? String ?? ""
                let isDark = (body["isDark"] as? Bool) ?? false
                let payload = colorString + "|" + String(isDark)
                guard payload != lastThemePayload else { return }
                lastThemePayload = payload
                guard let color = Self.parseCSSColor(colorString) else { return }
                onCardBackgroundColorChange?(color, isDark)
                return
            }

            if message.name == "amgiLookupText" {
                guard let body = message.body as? [String: Any] else { return }
                let text = body["text"] as? String
                let sentence = body["sentence"] as? String
                let x = (body["x"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
                let y = (body["y"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
                onLookupRequested?(text, sentence, CGPoint(x: x, y: y))
                return
            }

            guard message.name == "amgiOpenLink" else { return }
            let href: String?
            if let string = message.body as? String {
                href = string
            } else {
                href = nil
            }

            guard let href, !href.isEmpty else { return }
            openLink(href)
        }

        func stopTTS() {
            ttsPlayer.stop()
        }

        private static func parseCSSColor(_ cssColor: String) -> UIColor? {
            let trimmed = cssColor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("#") {
                return parseHexColor(trimmed)
            }

            if trimmed.hasPrefix("rgb(") || trimmed.hasPrefix("rgba(") {
                let pattern = #"rgba?\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\)"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { return nil }

                func component(_ idx: Int) -> CGFloat {
                    guard let r = Range(match.range(at: idx), in: trimmed) else { return 0 }
                    let value = Double(trimmed[r]) ?? 0
                    return CGFloat(max(0, min(255, value)) / 255.0)
                }

                var alpha: CGFloat = 1
                if match.range(at: 4).location != NSNotFound,
                   let r = Range(match.range(at: 4), in: trimmed) {
                    let value = Double(trimmed[r]) ?? 1
                    alpha = CGFloat(max(0, min(1, value)))
                }

                return UIColor(red: component(1), green: component(2), blue: component(3), alpha: alpha)
            }

            if trimmed == "transparent" {
                return UIColor.clear
            }

            return nil
        }

        private static func parseHexColor(_ hex: String) -> UIColor? {
            let value = String(hex.dropFirst())
            let chars = Array(value)
            func hexByte(_ a: Character, _ b: Character) -> UInt8 {
                UInt8(String([a, b]), radix: 16) ?? 0
            }

            switch chars.count {
            case 3:
                let r = hexByte(chars[0], chars[0])
                let g = hexByte(chars[1], chars[1])
                let b = hexByte(chars[2], chars[2])
                return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            case 6:
                let r = hexByte(chars[0], chars[1])
                let g = hexByte(chars[2], chars[3])
                let b = hexByte(chars[4], chars[5])
                return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            case 8:
                let r = hexByte(chars[0], chars[1])
                let g = hexByte(chars[2], chars[3])
                let b = hexByte(chars[4], chars[5])
                let a = hexByte(chars[6], chars[7])
                return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
            default:
                return nil
            }
        }

        private func handleTTSEvent(state: String, token: String) {
            guard let webView = currentWebView else { return }
            let tokenLiteral = Self.jsStringLiteral(token)
            let stateLiteral = Self.jsStringLiteral(state)
            let script = """
            window.amgiHandleTtsEvent && window.amgiHandleTtsEvent({ token: \(tokenLiteral), state: \(stateLiteral) });
            """

            webView.evaluateJavaScript(script, completionHandler: nil)
            onAudioStateChange?(state == "start" || ttsPlayer.isSpeakingNow)
        }

        private static func jsStringLiteral(_ string: String) -> String {
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            return "'\(escaped)'"
        }

        private func openLink(_ href: String) {
            let resolvedURL = URL(string: href, relativeTo: currentWebView?.url)?.absoluteURL
                ?? URL(string: href)

            guard let url = resolvedURL else { return }

            let scheme = url.scheme?.lowercased()
            let isWebLink = scheme == "http" || scheme == "https"

            if isWebLink, !openLinksExternally {
                currentWebView?.load(URLRequest(url: url))
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Allow local card document loads and same-document anchors.
            let scheme = url.scheme?.lowercased()
            if url.isFileURL || scheme == "about" || scheme == "javascript" || scheme == CardAssetPath.scheme {
                decisionHandler(.allow)
                return
            }

            // Custom app links should always go to the system.
            let isWebLink = scheme == "http" || scheme == "https"
            if !isWebLink || openLinksExternally {
                decisionHandler(.cancel)
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            } else {
                // Keep http/https inside WKWebView when external opening is disabled.
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true

            guard let pendingUpdateScript else { return }
            self.pendingUpdateScript = nil
            webView.evaluateJavaScript(pendingUpdateScript) { _, error in
                if let error {
                    print("[CardWebView] evaluateJavaScript error: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[CardWebView] Navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[CardWebView] Provisional navigation failed: \(error)")
        }
    }
}
