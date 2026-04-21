import SwiftUI
import WebKit
import Foundation
import UIKit
import AVFoundation

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
    let autoplayEnabled: Bool
    let isAnswerSide: Bool
    let cardOrdinal: UInt32
    let replayRequestID: Int
    let typedAnswerRequestID: Int
    let replayMode: ReplayMode
    let showInlineAudioReplayButtons: Bool
    let openLinksExternally: Bool
    let prefetchHTML: String?
    let contentAlignment: ContentAlignment
    let bottomContentInset: CGFloat
    let onTypedAnswerSubmitted: ((String?) -> Void)?
    let onAudioStateChange: ((Bool) -> Void)?
    let onCardBackgroundColorChange: ((UIColor, Bool) -> Void)?

    init(
        html: String,
        autoplayEnabled: Bool = true,
        isAnswerSide: Bool = false,
        cardOrdinal: UInt32 = 0,
        replayRequestID: Int = 0,
        typedAnswerRequestID: Int = 0,
        replayMode: ReplayMode = .question,
        showInlineAudioReplayButtons: Bool = true,
        openLinksExternally: Bool = true,
        prefetchHTML: String? = nil,
        contentAlignment: ContentAlignment = .center,
        bottomContentInset: CGFloat = 0,
        onTypedAnswerSubmitted: ((String?) -> Void)? = nil,
        onAudioStateChange: ((Bool) -> Void)? = nil,
        onCardBackgroundColorChange: ((UIColor, Bool) -> Void)? = nil
    ) {
        self.html = html
        self.autoplayEnabled = autoplayEnabled
        self.isAnswerSide = isAnswerSide
        self.cardOrdinal = cardOrdinal
        self.replayRequestID = replayRequestID
        self.typedAnswerRequestID = typedAnswerRequestID
        self.replayMode = replayMode
        self.showInlineAudioReplayButtons = showInlineAudioReplayButtons
        self.openLinksExternally = openLinksExternally
        self.prefetchHTML = prefetchHTML
        self.contentAlignment = contentAlignment
        self.bottomContentInset = bottomContentInset
        self.onTypedAnswerSubmitted = onTypedAnswerSubmitted
        self.onAudioStateChange = onAudioStateChange
        self.onCardBackgroundColorChange = onCardBackgroundColorChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTypedAnswerSubmitted: onTypedAnswerSubmitted,
            onAudioStateChange: onAudioStateChange,
            onCardBackgroundColorChange: onCardBackgroundColorChange
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
        coordinator.stopTTS()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Convert Anki [sound:filename.mp3] tags to <audio> HTML elements.
        // The Rust renderer keeps these tags literal; the client must expand them.
        let isDarkMode = colorScheme == .dark
        let processedHTML = Self.deferCardScripts(in:
            Self.expandTTSTags(
                in: Self.expandSoundTags(
                    html,
                    isDarkMode: isDarkMode,
                    showReplayButtons: showInlineAudioReplayButtons
                ),
                isDarkMode: isDarkMode,
                showReplayButtons: showInlineAudioReplayButtons
            )
        )
        let hasTypedAnswerInput = !isAnswerSide && processedHTML.contains("id=\"typeans\"")
        let bodyPaddingBottom = hasTypedAnswerInput ? 148 : 16
        let cardPaddingBottom = hasTypedAnswerInput ? 96 : 0
        let alignTop = hasTypedAnswerInput || contentAlignment == .top
        let bodyClass = Self.bodyClasses(cardOrdinal: cardOrdinal, isDarkMode: isDarkMode)
        let pageSignature = "\(isDarkMode)"
        let contentSignature = "\(autoplayEnabled)|\(isAnswerSide)|\(replayMode.rawValue)|\(cardOrdinal)|\(alignTop)|\(bodyPaddingBottom)|\(cardPaddingBottom)|\(processedHTML.hashValue)|\(prefetchHTML?.hashValue ?? 0)"
        context.coordinator.openLinksExternally = openLinksExternally
        context.coordinator.currentWebView = webView
        webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light

        // Build the JS call that shows the card – passed via evaluateJavaScript so
        // HTML content never lives inside a <script> literal in the page source.
        let showCardScript = Self.showCardScript(
            processedHTML: processedHTML,
            prefetchHTML: prefetchHTML,
            isAnswerSide: isAnswerSide,
            bodyClass: bodyClass,
            autoplayEnabled: autoplayEnabled,
            replayMode: replayMode.rawValue,
            alignTop: alignTop,
            bodyPaddingBottom: bodyPaddingBottom,
            cardPaddingBottom: cardPaddingBottom
        )
        context.coordinator.stopTTS()

        if context.coordinator.lastPageSignature != pageSignature {
            context.coordinator.lastPageSignature = pageSignature
            context.coordinator.lastContentSignature = contentSignature
            context.coordinator.isPageLoaded = false
            context.coordinator.pendingUpdateScript = nil
            let htmlClass = Self.htmlClasses(isDarkMode: isDarkMode)
            let playIconHTML = Self.audioButtonIconHTML(systemName: "play.circle", alt: "Play", isDarkMode: isDarkMode)
            let pauseIconHTML = Self.audioButtonIconHTML(systemName: "pause.circle", alt: "Pause", isDarkMode: isDarkMode)
            let baseTag = CardAssetPath.mediaBaseTag()
            // Stash the show-card call so we can run it once the page finishes loading.
            context.coordinator.pendingUpdateScript = showCardScript

            let styledHTML = Self.buildFrameHTML(
                htmlClass: htmlClass,
                isDarkMode: isDarkMode,
                playIconHTML: playIconHTML,
                pauseIconHTML: pauseIconHTML,
                baseTag: baseTag
            )

            // Use cardBaseURL so that MathJax, fonts, and other resources load correctly.
            // The CardAssetScheme handler processes amgi-asset:// URLs.
            webView.loadHTMLString(styledHTML, baseURL: CardAssetPath.cardBaseURL)
        } else if context.coordinator.lastContentSignature != contentSignature {
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
        let mathJaxScriptURL = CardAssetPath.mathJaxScriptURLString

        return """
        <!DOCTYPE html>
        <html class="\(htmlClass)" data-bs-theme="\(colorScheme)">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        \(baseTag)
        <script>
        window.MathJax = {
            tex: {
                inlineMath: [["\\\\(", "\\\\)"], ["$", "$"]],
                displayMath: [["$$", "$$"], ["\\\\[", "\\\\]"]],
                processEscapes: true,
                processEnvironments: false,
                processRefs: false
            },
            startup: { typeset: false }
        };
        </script>
        <script src="\(mathJaxScriptURL)" async></script>
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
                flex: 0 0 auto; min-width: 40px; min-height: 40px;
                box-shadow: none; outline: none;
                -webkit-tap-highlight-color: transparent; appearance: none;
            }
            .replay-btn:active { opacity: 0.7; }
            .replay-btn img { width: 40px; height: 40px; display: block; }
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
                display: inline-block; background: rgba(255,60,60,0.15);
                border: 1px dashed rgba(255,60,60,0.5); border-radius: 6px;
                padding: 6px 10px; margin: 4px; font-size: 13px;
                color: \(missingMediaColor);
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
        <script>
        // ── Globals ──────────────────────────────────────────────────────────
        var PLAY_ICON_HTML = \(playIconLiteral);
        var PAUSE_ICON_HTML = \(pauseIconLiteral);
        window.__amgiAudioPlaying = false;
        window.onUpdateHook = [];
        window.onShownHook = [];
        window.__amgiUpdateQueue = Promise.resolve();
        var amgiPreloadTemplate = document.createElement('template');
        var amgiPreloadDoc = document.implementation.createHTMLDocument('');
        var amgiFontURLPattern = /url\\s*\\(\\s*(["']?)(\\S.*?)\\1\\s*\\)/g;
        var amgiCachedFonts = new Set();

        // ── Card state ──────────────────────────────────────────────────────
        window.__amgiCardState = {};

        function amgiCardState() { return window.__amgiCardState || {}; }
        function amgiAutoplayEnabled() { return !!(amgiCardState().autoplayEnabled); }
        function amgiIsAnswerSide() { return !!(amgiCardState().isAnswerSide); }
        function amgiReplayModeValue() { return amgiCardState().replayMode || 'question'; }
        function amgiPrefetchHTMLValue() { return amgiCardState().prefetchHTML || ''; }

        function amgiApplyCardState(state) {
            window.__amgiCardState = Object.assign({}, window.__amgiCardState || {}, state || {});
            var s = amgiCardState();
            var qa = document.getElementById('qa');
            document.body.className = s.bodyClass || document.body.className;
            document.body.style.setProperty('--amgi-body-padding-bottom', (s.bodyPaddingBottom || 16) + 'px');
            document.body.classList.toggle('amgi-centered', !s.alignTop);
            if (qa) qa.style.setProperty('--amgi-card-padding-bottom', (s.cardPaddingBottom || 0) + 'px');
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

        function amgiContainsInlineDollarMath(html) {
            if (!html) return false;

            var start = html.indexOf('$');
            while (start !== -1) {
                var end = html.indexOf('$', start + 1);
                if (end === -1) return false;

                var previous = start > 0 ? html.charAt(start - 1) : '';
                var next = start + 1 < html.length ? html.charAt(start + 1) : '';
                var following = end + 1 < html.length ? html.charAt(end + 1) : '';
                if (previous !== '$' && next !== '$' && following !== '$' && end > start + 1) {
                    return true;
                }

                start = html.indexOf('$', end + 1);
            }

            return false;
        }

        function amgiNeedsMathTypeset(html, container) {
            if (container && container.querySelector('math, mjx-container, script[type^="math/tex"]')) {
                return true;
            }

            if (!html) return false;
            return html.indexOf('$$') !== -1
                || html.indexOf('\\(') !== -1
                || html.indexOf('\\[') !== -1
                || html.indexOf('\\begin{') !== -1
                || html.indexOf('\\frac') !== -1
                || html.indexOf('\\sqrt') !== -1
                || html.indexOf('\\text{') !== -1
                || html.indexOf('<math') !== -1
                || html.indexOf('math/tex') !== -1
                || amgiContainsInlineDollarMath(html);
        }

        async function amgiTypesetMath(container, maxAttempts) {
            if (!window.MathJax) return false;

            var attempts = typeof maxAttempts === 'number' ? maxAttempts : 60;
            var ready = false;
            for (var i = 0; i < attempts; i++) {
                if (window.MathJax && window.MathJax.startup && window.MathJax.startup.promise) {
                    ready = true;
                    break;
                }
                await new Promise(function(resolve) { setTimeout(resolve, 50); });
            }
            if (!ready) return false;

            try {
                await window.MathJax.startup.promise;
                if (typeof window.MathJax.typesetClear === 'function') window.MathJax.typesetClear();
                if (typeof window.MathJax.typesetPromise === 'function') await window.MathJax.typesetPromise([container]);
            } catch(e) { console.error('MathJax failed', e); }

            return true;
        }

        function amgiTypesetMathWhenReady(container) {
            amgiTypesetMath(container, 60).then(function(didTypeset) {
                if (didTypeset) {
                    amgiScheduleCardThemeReport();
                }
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
        async function amgiSetInnerHTML(element, html) {
            // Pause & drain video elements first (mirrors upstream setInnerHTML)
            Array.from(element.getElementsByTagName('video')).forEach(function(v) {
                v.pause();
                while (v.firstChild) v.removeChild(v.firstChild);
                v.load();
            });
            element.innerHTML = html;
            for (var script of Array.from(element.getElementsByTagName('script'))) {
                await amgiReplaceScript(script);
            }
        }

        // ── Audio ────────────────────────────────────────────────────────────
        function setAudioButtonState(btn, state) {
            if (!btn) return;
            btn.innerHTML = state === 'pause' ? PAUSE_ICON_HTML : PLAY_ICON_HTML;
        }
        function notifyAudioState(isPlaying) {
            window.__amgiAudioPlaying = !!isPlaying;
            try { window.webkit.messageHandlers.amgiAudioState.postMessage(window.__amgiAudioPlaying); } catch(e) {}
        }
        function amgiStopTts() {
            try { window.webkit.messageHandlers.amgiStopTts.postMessage(null); } catch(e) {}
        }
        window.amgiStopTts = amgiStopTts;
        function stopAllSystemAudio() {
            amgiStopTts();
            document.querySelectorAll('.anki-sound-audio').forEach(function(a) {
                if (!a.paused) a.pause();
                a.currentTime = 0;
                setAudioButtonState(a.nextElementSibling, 'play');
                a.onended = null;
            });
            notifyAudioState(false);
        }
        function collectAudioQueue(mode) {
            var all = Array.from(document.querySelectorAll('.anki-sound-audio'));
            if (mode === 'question') return all;
            var marker = document.getElementById('answer');
            if (!marker) return all;
            var after = all.filter(function(a) {
                return !!(marker.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            return after.length > 0 ? after : all;
        }
        function splitAudioQueue() {
            var all = Array.from(document.querySelectorAll('.anki-sound-audio'));
            var marker = document.getElementById('answer');
            if (!marker) return { question: all, answer: all };
            var answer = all.filter(function(a) {
                return !!(marker.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            var question = all.filter(function(a) {
                return !(marker.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            return {
                question: question.length ? question : all,
                answer: answer.length ? answer : all
            };
        }
        function replaySequential(queue) {
            stopAllSystemAudio();
            if (!queue || !queue.length) return;
            var idx = 0;
            notifyAudioState(true);
            function playNext() {
                if (idx >= queue.length) { notifyAudioState(false); return; }
                var audio = queue[idx];
                var btn = audio.nextElementSibling;
                audio.currentTime = 0;
                audio.play().catch(function() { idx++; playNext(); });
                setAudioButtonState(btn, 'pause');
                audio.onended = function() { setAudioButtonState(btn, 'play'); idx++; playNext(); };
            }
            playNext();
        }
        function amgiReplayAll(mode) {
            if (document.querySelector('audio:not(.anki-sound-audio), video')) return;
            replaySequential(collectAudioQueue(mode));
        }
        window.amgiReplayAll = amgiReplayAll;
        function amgiPlayAudioElement(audio) {
            if (!audio) return false;
            stopAllSystemAudio(); notifyAudioState(true);
            var btn = audio.nextElementSibling;
            audio.currentTime = 0;
            audio.play().catch(function() { setAudioButtonState(btn, 'play'); notifyAudioState(false); });
            setAudioButtonState(btn, 'pause');
            audio.onended = function() { setAudioButtonState(btn, 'play'); notifyAudioState(false); };
            return false;
        }
        function playSound(btn) { return amgiPlayAudioElement(btn ? btn.previousElementSibling : null); }
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
                var queues = splitAudioQueue();
                return amgiPlayAudioElement((side === 'a' ? queues.answer : queues.question)[index]);
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
            try {
                window.webkit.messageHandlers.amgiSpeakTts.postMessage({
                    text: btn.dataset.ttsText || '',
                    lang: btn.dataset.ttsLang || '',
                    voices: btn.dataset.ttsVoices || '',
                    speed: btn.dataset.ttsSpeed || ''
                });
            } catch(e) {}
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
        window._typeAnsPress = function() {
            var e = window.event || null;
            if (e && e.key === 'Enter') { e.preventDefault(); amgiSubmitTypedAnswer(); return false; }
            return true;
        };
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
            if (!img) return;
            var canvas = document.getElementById('image-occlusion-canvas');
            if (!canvas) {
                canvas = document.createElement('canvas');
                canvas.id = 'image-occlusion-canvas';
                container.appendChild(canvas);
            }
            if (!amgiIOOneTimeSetupDone) {
                window.addEventListener('resize', function() { window.requestAnimationFrame(amgiSetupImageOcclusion); });
                amgiIOOneTimeSetupDone = true;
            }
            function waitForImg(cb) {
                if (!img || img.complete) { cb(); return; }
                var fn = function() { img.removeEventListener('load', fn); img.removeEventListener('error', fn); cb(); };
                img.addEventListener('load', fn); img.addEventListener('error', fn);
            }
            waitForImg(function() {
                window.requestAnimationFrame(function() {
                    var canvasRef = document.getElementById('image-occlusion-canvas');
                    if (!canvasRef) return;
                    var dpr = window.devicePixelRatio || 1;
                    var width = img.offsetWidth, height = img.offsetHeight;
                    if (!width || !height) return;
                    canvasRef.style.width = width + 'px'; canvasRef.style.height = height + 'px';
                    canvasRef.width = width * dpr; canvasRef.height = height * dpr;
                    function collectShapes() {
                        var shapes = [];
                        ['cloze-inactive','cloze','cloze-highlight'].forEach(function(cls) {
                            amgiExtractIOShapes('.' + cls + '[data-shape]').forEach(function(s) {
                                s._cls = cls; s._revealed = false; shapes.push(s);
                            });
                        });
                        container._amgiIOShapes = shapes;
                    }
                    function visibleShapes() {
                        return (container._amgiIOShapes || []).filter(function(s) {
                            if (s._revealed) return false;
                            if (container._amgiMasksHidden) return false;
                            if (s._cls === 'cloze-inactive') return !!s.occludeInactive;
                            return true;
                        });
                    }
                    function redraw() {
                        var ctx = canvasRef.getContext('2d');
                        if (!ctx) return;
                        ctx.setTransform(1, 0, 0, 1, 0, 0);
                        ctx.clearRect(0, 0, canvasRef.width, canvasRef.height);
                        ctx.scale(dpr, dpr);
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
            amgiApplyCardState(state || {});
            amgiPreloadResources(html || '');

            qa.style.opacity = '0';
            try { await amgiSetInnerHTML(qa, html || ''); }
            catch(e) { qa.innerHTML = '<div>Error: ' + String(e).replace(/\\n/g,'<br>') + '</div>'; }

            await amgiRunHooks(window.onUpdateHook);

            var shouldTypesetMath = amgiNeedsMathTypeset(html || '', qa);
            var didTypesetMath = false;
            if (shouldTypesetMath) {
                didTypesetMath = await amgiTypesetMath(qa, 4);
            }

            qa.style.opacity = '1';
            amgiScheduleCardThemeReport();
            if (shouldTypesetMath && !didTypesetMath) {
                amgiTypesetMathWhenReady(qa);
            }

            // Detect missing media
            document.querySelectorAll('img').forEach(function(img) {
                img.onerror = function() {
                    var hint = document.createElement('span');
                    hint.className = 'missing-media';
                    hint.textContent = '\\u26a0 ' + (img.getAttribute('src') || 'image');
                    img.replaceWith(hint);
                };
                if (img.complete && img.naturalWidth === 0 && img.src) img.onerror();
            });
            document.querySelectorAll('.sound-btn').forEach(function(span) {
                var audio = span.querySelector('audio');
                if (!audio) return;
                audio.onerror = function() {
                    var hint = document.createElement('span');
                    hint.className = 'missing-media';
                    hint.textContent = '\\u26a0 ' + (audio.getAttribute('src') || 'audio');
                    span.replaceWith(hint);
                };
            });

            var typeInput = document.getElementById('typeans');
            if (typeInput) {
                var ensureVisible = function() { window.setTimeout(amgiEnsureTypedAnswerVisible, 180); };
                typeInput.addEventListener('focus', ensureVisible);
                typeInput.addEventListener('click', ensureVisible);
                typeInput.addEventListener('input', ensureVisible);
                typeInput.focus(); ensureVisible();
            }

            amgiSetupImageOcclusion();
            await amgiRunHooks(window.onShownHook);
        }

        // ── Serial queue (mirrors upstream _queueAction) ─────────────────────
        function amgiQueueAction(action) {
            window.__amgiUpdateQueue = (window.__amgiUpdateQueue || Promise.resolve()).then(action);
        }

        // ── Public API called from Swift via evaluateJavaScript ───────────────
        function _showQuestion(html, prefetchHTML, bodyclass, autoplay, replayMode, alignTop, bodyPaddingBottom, cardPaddingBottom) {
            amgiQueueAction(function() {
                return amgiUpdateQA(
                    html,
                    {
                        isAnswerSide: false,
                        bodyClass: bodyclass,
                        autoplayEnabled: !!autoplay,
                        replayMode: replayMode || 'question',
                        alignTop: !!alignTop,
                        bodyPaddingBottom: bodyPaddingBottom || 16,
                        cardPaddingBottom: cardPaddingBottom || 0,
                        prefetchHTML: prefetchHTML || ''
                    },
                    function() {
                        window.scrollTo(0, 0);
                    },
                    function() {
                        var typeans = document.getElementById('typeans');
                        if (typeans) typeans.focus();
                        var hasTemplateManagedMedia = document.querySelector('audio:not(.anki-sound-audio), video') !== null;
                        if (amgiAutoplayEnabled() && !hasTemplateManagedMedia) amgiReplayAll(amgiReplayModeValue());
                        var ph = amgiPrefetchHTMLValue();
                        if (ph) amgiAllImagesLoaded().then(function() { return amgiPreloadResources(ph); });
                    }
                );
            });
        }

        function _showAnswer(html, bodyclass, autoplay, replayMode, alignTop, bodyPaddingBottom, cardPaddingBottom) {
            amgiQueueAction(function() {
                return amgiUpdateQA(
                    html,
                    {
                        isAnswerSide: true,
                        bodyClass: bodyclass,
                        autoplayEnabled: !!autoplay,
                        replayMode: replayMode || 'answerOnly',
                        alignTop: !!alignTop,
                        bodyPaddingBottom: bodyPaddingBottom || 16,
                        cardPaddingBottom: cardPaddingBottom || 0,
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
                        var hasTemplateManagedMedia = document.querySelector('audio:not(.anki-sound-audio), video') !== null;
                        if (amgiAutoplayEnabled() && !hasTemplateManagedMedia) amgiReplayAll(amgiReplayModeValue());
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
        isAnswerSide: Bool,
        bodyClass: String,
        autoplayEnabled: Bool,
        replayMode: String,
        alignTop: Bool,
        bodyPaddingBottom: Int,
        cardPaddingBottom: Int
    ) -> String {
        let htmlLit = jsStringLiteral(processedHTML)
        let autoplay = autoplayEnabled ? "true" : "false"
        let alignTopStr = alignTop ? "true" : "false"

        if isAnswerSide {
            return "_showAnswer(\(htmlLit),\(jsStringLiteral(bodyClass)),\(autoplay),\(jsStringLiteral(replayMode)),\(alignTopStr),\(bodyPaddingBottom),\(cardPaddingBottom)" + ");"
        } else {
            let prefetchLit = jsStringLiteral(prefetchHTML ?? "")
            return "_showQuestion(\(htmlLit),\(prefetchLit),\(jsStringLiteral(bodyClass)),\(autoplay),\(jsStringLiteral(replayMode)),\(alignTopStr),\(bodyPaddingBottom),\(cardPaddingBottom)" + ");"
        }
    }

    /// Converts Anki `[sound:filename.ext]` markers to a hidden `<audio>` + styled play button.
    private static func expandSoundTags(
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
            let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
            let replacement: String
            if showReplayButtons {
                let iconHTML = audioButtonIconHTML(systemName: "play.circle", alt: "Play", isDarkMode: isDarkMode)
                replacement = "<span class=\"sound-btn\"><audio class=\"anki-sound-audio\" src=\"\(encoded)\" preload=\"auto\"></audio><a class=\"replay-button replay-btn soundLink\" href=\"#\" draggable=\"false\" onclick=\"return playSound(this)\">\(iconHTML)</a></span>"
            } else {
                replacement = "<span class=\"sound-btn\"><audio class=\"anki-sound-audio\" src=\"\(encoded)\" preload=\"auto\"></audio></span>"
            }
            result.replaceSubrange(matchRange, with: replacement)
        }
        return result
    }

    private static func expandTTSTags(
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
                let iconHTML = audioButtonIconHTML(systemName: "speaker.wave.2.circle", alt: "Speak", isDarkMode: isDarkMode)
                replacement = "<a class=\"replay-button replay-btn tts-btn\" href=\"#\" draggable=\"false\" data-tts-text=\"\(htmlAttributeEscaped(spokenText))\" data-tts-lang=\"\(htmlAttributeEscaped(lang))\" data-tts-voices=\"\(htmlAttributeEscaped(voices))\" data-tts-speed=\"\(htmlAttributeEscaped(speed))\" onclick=\"return amgiSpeakTts(this)\">\(iconHTML)</a>"
            } else {
                replacement = ""
            }

            result.replaceSubrange(matchRange, with: replacement)
        }

        return result
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
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular, scale: .medium)
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

        return "<img src=\"data:image/png;base64,\(data.base64EncodedString())\" alt=\"\(alt)\" draggable=\"false\" style=\"width:40px;height:40px;max-width:none;display:block;flex:none;\" />"
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
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, AVSpeechSynthesizerDelegate {
        var lastPageSignature: String?
        var lastContentSignature: String?
        var lastReplayRequestID: Int = 0
        var lastTypedAnswerRequestID: Int = 0
        var isPageLoaded = false
        var pendingUpdateScript: String?
        var openLinksExternally: Bool = true
        weak var currentWebView: WKWebView?
        let onTypedAnswerSubmitted: ((String?) -> Void)?
        private let onAudioStateChange: ((Bool) -> Void)?
        private let onCardBackgroundColorChange: ((UIColor, Bool) -> Void)?
        private var lastThemePayload: String?
        private let speechSynthesizer = AVSpeechSynthesizer()

        init(
            onTypedAnswerSubmitted: ((String?) -> Void)? = nil,
            onAudioStateChange: ((Bool) -> Void)? = nil,
            onCardBackgroundColorChange: ((UIColor, Bool) -> Void)? = nil
        ) {
            self.onTypedAnswerSubmitted = onTypedAnswerSubmitted
            self.onAudioStateChange = onAudioStateChange
            self.onCardBackgroundColorChange = onCardBackgroundColorChange
            super.init()
            speechSynthesizer.delegate = self
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
                speakTTS(from: message.body)
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

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
            Task { @MainActor [weak self] in
                self?.onAudioStateChange?(true)
            }
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor [weak self] in
                self?.onAudioStateChange?(false)
            }
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            Task { @MainActor [weak self] in
                self?.onAudioStateChange?(false)
            }
        }

        func stopTTS() {
            guard speechSynthesizer.isSpeaking else { return }
            speechSynthesizer.stopSpeaking(at: .immediate)
            onAudioStateChange?(false)
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

        private func speakTTS(from body: Any) {
            guard let payload = body as? [String: Any] else { return }
            let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }

            stopTTS()

            let utterance = AVSpeechUtterance(string: text)
            let lang = ((payload["lang"] as? String) ?? "").replacingOccurrences(of: "_", with: "-")
            let preferredVoices = ((payload["voices"] as? String) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if let voice = preferredVoice(lang: lang, preferredNames: preferredVoices) {
                utterance.voice = voice
            } else if !lang.isEmpty {
                utterance.voice = AVSpeechSynthesisVoice(language: lang)
            }

            let speedMultiplier = Float((payload["speed"] as? String) ?? "") ?? 1
            let mappedRate = AVSpeechUtteranceDefaultSpeechRate * max(0.25, min(speedMultiplier, 2.0))
            utterance.rate = min(max(mappedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
            speechSynthesizer.speak(utterance)
        }

        private func preferredVoice(lang: String, preferredNames: [String]) -> AVSpeechSynthesisVoice? {
            let voices = AVSpeechSynthesisVoice.speechVoices()

            for preferredName in preferredNames {
                if let voice = voices.first(where: { $0.identifier.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                    return voice
                }
                if let voice = voices.first(where: { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                    return voice
                }
            }

            guard !lang.isEmpty else { return nil }
            return voices.first(where: { $0.language.caseInsensitiveCompare(lang) == .orderedSame })
                ?? voices.first(where: { $0.language.lowercased().hasPrefix(lang.lowercased()) })
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
