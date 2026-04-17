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
        onAudioStateChange: ((Bool) -> Void)? = nil
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTypedAnswerSubmitted: onTypedAnswerSubmitted,
            onAudioStateChange: onAudioStateChange
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

        let cardStateLiteral = Self.cardStateLiteral(
            autoplayEnabled: autoplayEnabled,
            isAnswerSide: isAnswerSide,
            replayMode: replayMode.rawValue,
            bodyClass: bodyClass,
            alignTop: alignTop,
            bodyPaddingBottom: bodyPaddingBottom,
            cardPaddingBottom: cardPaddingBottom,
            prefetchHTML: prefetchHTML
        )
        let updateCardScript = Self.updateCardScript(
            html: processedHTML,
            cardStateLiteral: cardStateLiteral
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

            let styledHTML = """
        <!DOCTYPE html>
        <html class="\(htmlClass)" data-bs-theme="\(isDarkMode ? "dark" : "light")">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        \(baseTag)
        <script>
        window.MathJax = {
            tex: {
                displayMath: [["\\\\[", "\\\\]"]],
                processEscapes: false,
                processEnvironments: false,
                processRefs: false,
                packages: {
                    "[+]": ["noerrors", "mathtools"],
                    "[-]": ["textmacros"]
                }
            },
            loader: {
                load: ["[tex]/noerrors", "[tex]/mathtools"],
                paths: {
                    mathjax: "amgi-asset://assets/mathjax"
                }
            },
            startup: {
                typeset: false
            }
        };
        </script>
        <script src="\(CardAssetPath.mathJaxScriptURLString)" async></script>
        <style>
            :root {
                color-scheme: \(isDarkMode ? "dark" : "light");
            }
            html, body {
                background: transparent !important;
            }
            body {
                font-family: -apple-system, system-ui;
                font-size: 18px;
                line-height: 1.5;
                color: \(isDarkMode ? "#f5f5f5" : "#1a1a1a");
                background: transparent;
                padding: 16px 16px var(--amgi-body-padding-bottom, 16px);
                margin: 0;
                text-align: center;
                display: flex;
                align-items: var(--amgi-body-align-items, center);
                justify-content: center;
                min-height: 80vh;
            }
            .card-frame {
                max-width: 600px;
                width: 100%;
                padding-bottom: var(--amgi-card-padding-bottom, 0px);
            }
            hr { border: none; border-top: 1px solid \(isDarkMode ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.2)"); margin: 16px 0; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            .sound-btn {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                margin: 4px;
            }
            .sound-btn audio { display: none; }
            #typeans {
                width: min(100%, 280px);
                padding: 10px 12px;
                border-radius: 10px;
                border: 1px solid \(isDarkMode ? "rgba(255,255,255,0.28)" : "rgba(0,0,0,0.22)");
                background: \(isDarkMode ? "rgba(255,255,255,0.08)" : "rgba(255,255,255,0.9)");
                color: inherit;
                outline: none;
            }
            #typeans:focus {
                border-color: \(isDarkMode ? "rgba(143,184,255,0.9)" : "rgba(0,122,255,0.9)");
                box-shadow: 0 0 0 3px \(isDarkMode ? "rgba(143,184,255,0.18)" : "rgba(0,122,255,0.15)");
            }
            code#typeans {
                display: inline-block;
                white-space: pre-wrap;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                font-size: 0.95em;
                line-height: 1.5;
                padding: 10px 12px;
                border-radius: 10px;
                background: \(isDarkMode ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.05)");
            }
            .typeGood { color: \(isDarkMode ? "#7ddc6f" : "#177d1a"); }
            .typeBad { color: \(isDarkMode ? "#ff8d8d" : "#c62828"); }
            .typeMissed { color: \(isDarkMode ? "#8ab4ff" : "#1565c0"); }
            #typearrow { opacity: 0.7; }
            .replay-btn {
                background: transparent;
                border: none;
                color: inherit;
                padding: 0;
                line-height: 0;
                cursor: pointer;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                -webkit-tap-highlight-color: transparent;
                appearance: none;
            }
            .replay-btn:active { opacity: 0.7; }
            .replay-btn img {
                width: 24px;
                height: 24px;
                display: block;
            }
            video {
                max-width: 100%;
                height: auto;
                border-radius: 8px;
                margin: 8px 0;
            }
            .cloze:not([data-shape]) {
                display: inline !important;
                font-weight: 600;
                color: #1565c0;
            }
            .cloze-inactive:not([data-shape]),
            .cloze-highlight:not([data-shape]) {
                display: inline !important;
            }
            /* Image occlusion */
            .cloze[data-shape], .cloze-inactive[data-shape], .cloze-highlight[data-shape] { display: none; }
            #image-occlusion-container {
                position: relative;
                display: inline-block;
                line-height: 0;
            }
            #image-occlusion-canvas {
                position: absolute;
                top: 0;
                left: 0;
                pointer-events: auto;
                cursor: pointer;
                border-radius: 8px;
            }
            .missing-media {
                display: inline-block;
                background: rgba(255,60,60,0.15);
                border: 1px dashed rgba(255,60,60,0.5);
                border-radius: 6px;
                padding: 6px 10px;
                margin: 4px;
                font-size: 13px;
                color: \(isDarkMode ? "rgba(255,100,100,0.9)" : "rgba(200,40,40,0.8)");
            }
            .nightMode,
            .nightMode .card {
                color: #f5f5f5;
            }
            .nightMode .cloze:not([data-shape]) {
                color: #8fb8ff;
            }
            .nightMode a {
                color: #8fb8ff;
            }
        </style>
        <script>
        const AUTOPLAY_ENABLED = \(autoplayEnabled ? "true" : "false");
        const IS_ANSWER_SIDE = \(isAnswerSide ? "true" : "false");
        const DEFAULT_REPLAY_MODE = \(Self.jsStringLiteral(replayMode.rawValue));
        const PLAY_ICON_HTML = \(Self.jsStringLiteral(playIconHTML));
        const PAUSE_ICON_HTML = \(Self.jsStringLiteral(pauseIconHTML));
        const INITIAL_CARD_HTML = \(Self.jsStringLiteral(processedHTML));
        const INITIAL_CARD_STATE = \(cardStateLiteral);
        window.__amgiAudioPlaying = false;
        window.onUpdateHook = window.onUpdateHook || [];
        window.onShownHook = window.onShownHook || [];
        window.__amgiCardState = window.__amgiCardState || {};
        window.__amgiUpdateQueue = window.__amgiUpdateQueue || Promise.resolve();
        const amgiPreloadTemplate = document.createElement('template');
        const amgiPreloadDoc = document.implementation.createHTMLDocument('');
        const amgiFontURLPattern = /url\\s*\\(\\s*(["']?)(\\S.*?)\\1\\s*\\)/g;
        const amgiCachedFonts = new Set();

        function amgiCardState() {
            return window.__amgiCardState || {};
        }

        function amgiAutoplayEnabled() {
            var state = amgiCardState();
            return typeof state.autoplayEnabled === 'boolean' ? state.autoplayEnabled : AUTOPLAY_ENABLED;
        }

        function amgiIsAnswerSide() {
            var state = amgiCardState();
            return typeof state.isAnswerSide === 'boolean' ? state.isAnswerSide : IS_ANSWER_SIDE;
        }

        function amgiReplayModeValue() {
            var state = amgiCardState();
            return typeof state.replayMode === 'string' ? state.replayMode : DEFAULT_REPLAY_MODE;
        }

        function amgiPrefetchHTMLValue() {
            var state = amgiCardState();
            return typeof state.prefetchHTML === 'string' ? state.prefetchHTML : '';
        }

        function amgiApplyCardState(state) {
            window.__amgiCardState = Object.assign({}, window.__amgiCardState || {}, state || {});
            var currentState = amgiCardState();
            var qa = document.getElementById('qa');

            document.body.className = currentState.bodyClass || document.body.className;
            document.body.style.setProperty('--amgi-body-padding-bottom', String(currentState.bodyPaddingBottom || 16) + 'px');
            document.body.style.setProperty('--amgi-body-align-items', currentState.alignTop ? 'flex-start' : 'center');

            if (qa) {
                qa.style.setProperty('--amgi-card-padding-bottom', String(currentState.cardPaddingBottom || 0) + 'px');
            }
        }

        function amgiLoadPreloadResource(element) {
            return new Promise(function(resolve) {
                function finish() {
                    resolve();
                    if (element.parentNode) {
                        element.parentNode.removeChild(element);
                    }
                }
                element.addEventListener('load', finish);
                element.addEventListener('error', finish);
                document.head.appendChild(element);
            });
        }

        function amgiCreatePreloadLink(href, asType) {
            var link = document.createElement('link');
            link.rel = 'preload';
            link.href = href;
            link.as = asType;
            if (asType === 'font') {
                link.crossOrigin = '';
            }
            return link;
        }

        function amgiPreloadImage(img) {
            if (!img.getAttribute('decoding')) {
                img.decoding = 'async';
            }
            return img.complete ? Promise.resolve() : new Promise(function(resolve) {
                img.addEventListener('load', function() { resolve(); });
                img.addEventListener('error', function() { resolve(); });
            });
        }

        function amgiPreloadImages(fragment) {
            return Array.from(fragment.querySelectorAll('img[src]')).map(function(existing) {
                var img = new Image();
                img.src = new URL(existing.getAttribute('src') || '', document.baseURI).toString();
                return amgiPreloadImage(img);
            });
        }

        function amgiAllImagesLoaded() {
            return Promise.all(
                Array.from(document.getElementsByTagName('img')).map(function(img) {
                    return amgiPreloadImage(img);
                })
            );
        }

        function amgiExtractExternalStyles(fragment) {
            return Array.from(fragment.querySelectorAll('style, link')).filter(function(css) {
                return (css.tagName === 'STYLE' && (css.innerHTML || '').includes('@import'))
                    || (css.tagName === 'LINK' && css.rel === 'stylesheet');
            });
        }

        function amgiPreloadStyleSheets(fragment) {
            return amgiExtractExternalStyles(fragment).map(function(css) {
                css.media = 'print';
                return amgiLoadPreloadResource(css);
            });
        }

        function amgiExtractFontURLs(style) {
            amgiPreloadDoc.head.innerHTML = '';
            amgiPreloadDoc.head.appendChild(style);
            var urls = [];
            if (style.sheet) {
                Array.from(style.sheet.cssRules || []).forEach(function(rule) {
                    if (!(rule instanceof CSSFontFaceRule)) {
                        return;
                    }
                    var src = rule.style.getPropertyValue('src');
                    var matches = src.matchAll(amgiFontURLPattern);
                    for (const match of matches) {
                        if (match[2]) {
                            urls.push(match[2]);
                        }
                    }
                });
            }
            return urls;
        }

        function amgiPreloadFonts(fragment) {
            var fontURLs = [];
            Array.from(fragment.querySelectorAll('style')).forEach(function(style) {
                fontURLs.push.apply(fontURLs, amgiExtractFontURLs(style));
            });

            return fontURLs
                .filter(function(url) {
                    if (!url || amgiCachedFonts.has(url)) {
                        return false;
                    }
                    amgiCachedFonts.add(url);
                    return true;
                })
                .map(function(url) {
                    return amgiLoadPreloadResource(amgiCreatePreloadLink(url, 'font'));
                });
        }

        async function amgiPreloadResources(html) {
            amgiPreloadTemplate.innerHTML = html || '';
            var fragment = amgiPreloadTemplate.content;
            var styleSheets = amgiPreloadStyleSheets(fragment.cloneNode(true));
            var images = amgiPreloadImages(fragment.cloneNode(true));
            var fonts = amgiPreloadFonts(fragment.cloneNode(true));

            var timeout = 0;
            if (fonts.length) {
                timeout = 800;
            } else if (styleSheets.length) {
                timeout = 500;
            } else if (images.length) {
                timeout = 200;
            } else {
                return;
            }

            await Promise.race([
                Promise.all(styleSheets.concat(images, fonts)),
                new Promise(function(resolve) { window.setTimeout(resolve, timeout); })
            ]);
        }

        function amgiRunHooks(hooks) {
            if (!Array.isArray(hooks)) {
                return Promise.resolve([]);
            }

            var promises = [];
            hooks.forEach(function(hook) {
                try {
                    if (typeof hook === 'function') {
                        promises.push(hook());
                    }
                } catch (error) {
                    console.error('Hook failed', error);
                }
            });

            return Promise.allSettled(promises);
        }

        function amgiReplaceDeferredScript(oldScript) {
            return new Promise(function(resolve) {
                var newScript = document.createElement('script');
                var src = oldScript.getAttribute('src');
                var mustWaitForNetwork = !!src;

                oldScript.getAttributeNames().forEach(function(name) {
                    if (name === 'type' || name === 'data-amgi-card-script') {
                        return;
                    }
                    var value = oldScript.getAttribute(name);
                    if (value !== null) {
                        newScript.setAttribute(name, value);
                    }
                });

                newScript.addEventListener('load', function() { resolve(); });
                newScript.addEventListener('error', function() { resolve(); });
                newScript.appendChild(document.createTextNode(oldScript.textContent || ''));
                oldScript.replaceWith(newScript);

                if (!mustWaitForNetwork) {
                    resolve();
                }
            });
        }

        async function amgiExecuteDeferredCardScripts() {
            var scripts = Array.from(document.querySelectorAll('#qa script[type="application/x-amgi-card-script"]'));
            for (const script of scripts) {
                await amgiReplaceDeferredScript(script);
            }
        }

        function amgiAddBrowserClasses() {
            var ua = navigator.userAgent.toLowerCase();

            function addClass(name) {
                if (name) {
                    document.documentElement.classList.add(name);
                }
            }

            if (/ipad/.test(ua)) {
                addClass('ipad');
            } else if (/iphone/.test(ua)) {
                addClass('iphone');
            } else if (/android/.test(ua)) {
                addClass('android');
            }

            if (/ipad|iphone|ipod/.test(ua)) {
                addClass('ios');
            }

            if (/ipad|iphone|ipod|android/.test(ua)) {
                addClass('mobile');
            } else if (/linux/.test(ua)) {
                addClass('linux');
            } else if (/windows/.test(ua)) {
                addClass('win');
            } else if (/mac/.test(ua)) {
                addClass('mac');
            }

            if (/firefox\\//.test(ua)) {
                addClass('firefox');
            } else if (/chrome\\//.test(ua)) {
                addClass('chrome');
            } else if (/safari\\//.test(ua)) {
                addClass('safari');
            }
        }

        window.ankiPlatform = /iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) ? 'ios' : 'other';
        globalThis.ankiPlatform = window.ankiPlatform;

        function setAudioButtonState(btn, state) {
            if (!btn) {
                return;
            }
            btn.innerHTML = state === 'pause' ? PAUSE_ICON_HTML : PLAY_ICON_HTML;
        }

        function notifyAudioState(isPlaying) {
            window.__amgiAudioPlaying = !!isPlaying;
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.amgiAudioState) {
                    window.webkit.messageHandlers.amgiAudioState.postMessage(window.__amgiAudioPlaying);
                }
            } catch (e) {}
        }

        function amgiStopTts() {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.amgiStopTts) {
                    window.webkit.messageHandlers.amgiStopTts.postMessage(null);
                }
            } catch (e) {}
        }
        window.amgiStopTts = amgiStopTts;

        function stopAllSystemAudio() {
            amgiStopTts();
            document.querySelectorAll('.anki-sound-audio').forEach(function(a) {
                if (!a.paused) { a.pause(); }
                a.currentTime = 0;
                var b = a.nextElementSibling;
                setAudioButtonState(b, 'play');
                a.onended = null;
            });
            notifyAudioState(false);
        }

        function collectAudioQueue(mode) {
            var allAudio = Array.from(document.querySelectorAll('.anki-sound-audio'));
            if (mode === 'question') {
                return allAudio;
            }

            var answerMarker = document.getElementById('answer');
            if (!answerMarker) {
                return allAudio;
            }

            var afterAnswer = allAudio.filter(function(a) {
                return !!(answerMarker.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING);
            });

            if (mode === 'answerWithQuestion') {
                return afterAnswer.length > 0 ? allAudio : allAudio;
            }

            return afterAnswer.length > 0 ? afterAnswer : allAudio;
        }

        function splitAudioQueue() {
            var allAudio = Array.from(document.querySelectorAll('.anki-sound-audio'));
            var answerMarker = document.getElementById('answer');
            if (!answerMarker) {
                return {
                    question: allAudio,
                    answer: allAudio,
                };
            }

            var answer = allAudio.filter(function(a) {
                return !!(answerMarker.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING);
            });
            var question = allAudio.filter(function(a) {
                return !(answerMarker.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING);
            });

            return {
                question: question.length > 0 ? question : allAudio,
                answer: answer.length > 0 ? answer : allAudio,
            };
        }

        function replaySequential(queue) {
            stopAllSystemAudio();
            if (!queue || queue.length === 0) {
                return;
            }

            var currentIndex = 0;
            notifyAudioState(true);

            function playNext() {
                if (currentIndex >= queue.length) {
                    notifyAudioState(false);
                    return;
                }
                var audio = queue[currentIndex];
                var btn = audio.nextElementSibling;
                audio.currentTime = 0;
                audio.play().catch(function() {
                    currentIndex++;
                    playNext();
                });
                setAudioButtonState(btn, 'pause');
                audio.onended = function() {
                    setAudioButtonState(btn, 'play');
                    currentIndex++;
                    playNext();
                };
            }

            playNext();
        }

        function amgiReplayAll(mode) {
            var hasTemplateManagedMedia = document.querySelector('audio:not(.anki-sound-audio), video') !== null;
            if (hasTemplateManagedMedia) {
                return;
            }
            replaySequential(collectAudioQueue(mode));
        }
        window.amgiReplayAll = amgiReplayAll;

        function amgiPlayAudioElement(audio) {
            if (!audio) {
                return false;
            }

            stopAllSystemAudio();
            notifyAudioState(true);

            var btn = audio.nextElementSibling;
            audio.currentTime = 0;
            audio.play().catch(function() {
                setAudioButtonState(btn, 'play');
                notifyAudioState(false);
            });
            setAudioButtonState(btn, 'pause');
            audio.onended = function() {
                setAudioButtonState(btn, 'play');
                notifyAudioState(false);
            };
            return false;
        }

        function pycmd(command) {
            if (!command || typeof command !== 'string') {
                return false;
            }

            if (command === 'replay') {
                amgiReplayAll(amgiReplayModeValue());
                return false;
            }

            if (command.startsWith('play:')) {
                var parts = command.split(':');
                var side = parts[1];
                var index = parseInt(parts[2] || '0', 10);
                if (Number.isNaN(index) || index < 0) {
                    return false;
                }

                var queues = splitAudioQueue();
                var queue = side === 'a' ? queues.answer : queues.question;
                return amgiPlayAudioElement(queue[index]);
            }

            return false;
        }

        globalThis.pycmd = pycmd;
        window.pycmd = pycmd;

        function postOpenLink(rawHref) {
            if (!rawHref) {
                return;
            }

            var resolvedHref = rawHref;
            try {
                resolvedHref = new URL(rawHref, document.baseURI).toString();
            } catch (e) {}

            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.amgiOpenLink) {
                    window.webkit.messageHandlers.amgiOpenLink.postMessage(resolvedHref);
                }
            } catch (e) {}
        }

        document.addEventListener('click', function(event) {
            var anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            if (!anchor) {
                return;
            }

            var href = anchor.getAttribute('href');
            if (!href || href.startsWith('#') || href.startsWith('javascript:')) {
                return;
            }

            event.preventDefault();
            postOpenLink(anchor.href || href);
        });

        window.open = function(url) {
            postOpenLink(url);
            return null;
        };

        function playSound(btn) {
            return amgiPlayAudioElement(btn ? btn.previousElementSibling : null);
        }
        window.playSound = playSound;
        globalThis.playSound = playSound;

        function amgiSpeakTts(btn) {
            if (!btn) {
                return false;
            }

            stopAllSystemAudio();

            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.amgiSpeakTts) {
                    window.webkit.messageHandlers.amgiSpeakTts.postMessage({
                        text: btn.dataset.ttsText || '',
                        lang: btn.dataset.ttsLang || '',
                        voices: btn.dataset.ttsVoices || '',
                        speed: btn.dataset.ttsSpeed || ''
                    });
                }
            } catch (e) {}

            return false;
        }
        window.amgiSpeakTts = amgiSpeakTts;
        globalThis.amgiSpeakTts = amgiSpeakTts;

        function amgiGetTypedAnswer() {
            var input = document.getElementById('typeans');
            return input ? input.value : null;
        }
        window.amgiGetTypedAnswer = amgiGetTypedAnswer;
        window.getTypedAnswer = amgiGetTypedAnswer;
        globalThis.getTypedAnswer = amgiGetTypedAnswer;

        function amgiSubmitTypedAnswer() {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.amgiSubmitTypedAnswer) {
                    window.webkit.messageHandlers.amgiSubmitTypedAnswer.postMessage(amgiGetTypedAnswer());
                }
            } catch (e) {}
        }
        window.amgiSubmitTypedAnswer = amgiSubmitTypedAnswer;

        function amgiHandleTypeAnswerKey(event) {
            if (event && event.key === 'Enter') {
                event.preventDefault();
                amgiSubmitTypedAnswer();
                return false;
            }
            return true;
        }
        window.amgiHandleTypeAnswerKey = amgiHandleTypeAnswerKey;
        window._typeAnsPress = function() {
            return amgiHandleTypeAnswerKey(window.event || null);
        };
        globalThis._typeAnsPress = window._typeAnsPress;

        function amgiEnsureTypedAnswerVisible() {
            var input = document.getElementById('typeans');
            if (!input) {
                return;
            }
            try {
                input.scrollIntoView({ block: 'center', inline: 'nearest' });
            } catch (e) {
                input.scrollIntoView();
            }
        }
        window.amgiEnsureTypedAnswerVisible = amgiEnsureTypedAnswerVisible;

        // ── Image Occlusion ──────────────────────────────────────────────
        function amgiExtractIOShapes(selector) {
            return Array.from(document.querySelectorAll(selector)).map(function(el) {
                var pointsRaw = el.dataset.points;
                var points = null;
                if (pointsRaw) {
                    var nums = pointsRaw.trim().split(/[\\s,]+/).map(Number).filter(function(value) {
                        return !Number.isNaN(value);
                    });
                    points = [];
                    for (var i = 0; i + 1 < nums.length; i += 2) {
                        points.push({ x: nums[i], y: nums[i + 1] });
                    }
                }
                return {
                    type: el.dataset.shape,
                    left: parseFloat(el.dataset.left || '0'),
                    top: parseFloat(el.dataset.top || '0'),
                    width: parseFloat(el.dataset.width || '0'),
                    height: parseFloat(el.dataset.height || '0'),
                    rx: parseFloat(el.dataset.rx || '0'),
                    ry: parseFloat(el.dataset.ry || '0'),
                    angle: parseFloat(el.dataset.angle || '0'),
                    text: el.dataset.text || '',
                    scale: parseFloat(el.dataset.scale || '1'),
                    fontSize: parseFloat(el.dataset.fontSize || '0'),
                    fill: el.dataset.fill || '#000000',
                    occludeInactive: (el.dataset.occludeInactive || el.dataset.occludeinactive || '') === '1',
                    points: points,
                };
            });
        }

        function amgiDrawIOShape(ctx, shape, size, fill, stroke) {
            if (shape.type === 'text') {
                var fontSize = (shape.fontSize > 0 ? shape.fontSize * size.height : 40);
                var scale = shape.scale > 0 ? shape.scale : 1;
                var leftText = shape.left * size.width;
                var topText = shape.top * size.height;
                var angleText = shape.angle * Math.PI / 180;
                var padding = 5;
                ctx.save();
                ctx.font = fontSize + 'px Arial';
                ctx.textBaseline = 'top';
                ctx.scale(scale, scale);
                var lines = (shape.text || '').split('\\n');
                var baseMetrics = ctx.measureText('M');
                var fontHeight = baseMetrics.actualBoundingBoxAscent + baseMetrics.actualBoundingBoxDescent;
                var lineHeight = 1.5 * fontHeight;
                var maxWidth = 0;
                var scaledLeft = leftText / scale;
                var scaledTop = topText / scale;

                for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
                    var lineMetrics = ctx.measureText(lines[lineIndex]);
                    if (lineMetrics.width > maxWidth) {
                        maxWidth = lineMetrics.width;
                    }
                }

                if (angleText) {
                    ctx.translate(scaledLeft, scaledTop);
                    ctx.rotate(angleText);
                    ctx.translate(-scaledLeft, -scaledTop);
                }

                ctx.fillStyle = '#ffffff';
                ctx.fillRect(scaledLeft, scaledTop, maxWidth + padding, lines.length * lineHeight + padding);
                ctx.fillStyle = shape.fill || '#000000';

                for (var textIndex = 0; textIndex < lines.length; textIndex++) {
                    ctx.fillText(lines[textIndex], scaledLeft, scaledTop + textIndex * lineHeight);
                }

                ctx.restore();
                return;
            }

            if (shape.type === 'polygon' && shape.points && shape.points.length >= 2) {
                ctx.save();
                ctx.beginPath();
                ctx.moveTo(shape.points[0].x * size.width, shape.points[0].y * size.height);
                for (var polygonIndex = 1; polygonIndex < shape.points.length; polygonIndex++) {
                    ctx.lineTo(shape.points[polygonIndex].x * size.width, shape.points[polygonIndex].y * size.height);
                }
                ctx.closePath();
                ctx.fillStyle = fill;
                ctx.fill();
                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.stroke(); }
                ctx.restore();
                return;
            }

            var left = shape.left * size.width;
            var top = shape.top * size.height;
            var angle = shape.angle * Math.PI / 180;
            ctx.save();
            ctx.translate(left, top);
            ctx.rotate(angle);
            if (shape.type === 'rect') {
                var sw = shape.width * size.width;
                var sh = shape.height * size.height;
                ctx.fillStyle = fill;
                ctx.fillRect(0, 0, sw, sh);
                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.strokeRect(0, 0, sw, sh); }
            } else if (shape.type === 'ellipse') {
                var rx = shape.rx * size.width;
                var ry = shape.ry * size.height;
                ctx.beginPath();
                ctx.ellipse(rx, ry, rx, ry, 0, 0, 2 * Math.PI);
                ctx.fillStyle = fill;
                ctx.fill();
                if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.stroke(); }
            }
            ctx.restore();
        }

        function amgiDrawIOShapes(ctx, size) {
            var style = getComputedStyle(document.documentElement);
            var inactiveColor  = style.getPropertyValue('--inactive-shape-color').trim()  || '#ffeba2';
            var activeColor    = style.getPropertyValue('--active-shape-color').trim()    || '#ff8e8e';
            var highlightColor = style.getPropertyValue('--highlight-shape-color').trim() || 'rgba(255,142,142,0)';
            var border = '#212121';
            amgiExtractIOShapes('.cloze-inactive[data-shape]').forEach(function(s) { if (!s._revealed) { amgiDrawIOShape(ctx, s, size, inactiveColor, border); } });
            amgiExtractIOShapes('.cloze[data-shape]').forEach(function(s)           { if (!s._revealed) { amgiDrawIOShape(ctx, s, size, activeColor, border); } });
            amgiExtractIOShapes('.cloze-highlight[data-shape]').forEach(function(s) { if (!s._revealed) { amgiDrawIOShape(ctx, s, size, highlightColor, border); } });
        }

        // Hit-test: is canvas point (px, py) inside a shape?
        function amgiHitTestShape(shape, px, py, size) {
            if (shape.type === 'polygon' && shape.points && shape.points.length >= 3) {
                var polygonInside = false;
                for (var polygonIndex = 0, polygonPrev = shape.points.length - 1; polygonIndex < shape.points.length; polygonPrev = polygonIndex++) {
                    var polygonXi = shape.points[polygonIndex].x * size.width;
                    var polygonYi = shape.points[polygonIndex].y * size.height;
                    var polygonXj = shape.points[polygonPrev].x * size.width;
                    var polygonYj = shape.points[polygonPrev].y * size.height;
                    if (((polygonYi > py) !== (polygonYj > py)) && (px < (polygonXj - polygonXi) * (py - polygonYi) / (polygonYj - polygonYi) + polygonXi)) {
                        polygonInside = !polygonInside;
                    }
                }
                return polygonInside;
            }

            var angle = shape.angle * Math.PI / 180;
            var originX = shape.left * size.width;
            var originY = shape.top * size.height;
            // Transform to shape's local coordinate system
            var dx = px - originX, dy = py - originY;
            var lx = dx * Math.cos(-angle) - dy * Math.sin(-angle);
            var ly = dx * Math.sin(-angle) + dy * Math.cos(-angle);

            if (shape.type === 'rect') {
                var sw = shape.width * size.width, sh = shape.height * size.height;
                return lx >= 0 && lx <= sw && ly >= 0 && ly <= sh;
            } else if (shape.type === 'ellipse') {
                var rx = shape.rx * size.width, ry = shape.ry * size.height;
                var ex = lx - rx, ey = ly - ry;
                return (rx > 0 && ry > 0) ? ((ex*ex)/(rx*rx) + (ey*ey)/(ry*ry)) <= 1 : false;
            } else if (shape.type === 'text') {
                var scale = shape.scale > 0 ? shape.scale : 1;
                var fontSize = (shape.fontSize > 0 ? shape.fontSize * size.height : 40);
                var textCanvas = document.createElement('canvas');
                var textCtx = textCanvas.getContext('2d');
                if (!textCtx) {
                    return false;
                }
                textCtx.font = fontSize + 'px Arial';
                var lines = (shape.text || '').split('\\n');
                var baseMetrics = textCtx.measureText('M');
                var fontHeight = baseMetrics.actualBoundingBoxAscent + baseMetrics.actualBoundingBoxDescent;
                var lineHeight = 1.5 * fontHeight;
                var maxWidth = 0;
                for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
                    var lineMetrics = textCtx.measureText(lines[lineIndex]);
                    if (lineMetrics.width > maxWidth) {
                        maxWidth = lineMetrics.width;
                    }
                }
                var boxWidth = (maxWidth + 5) * scale;
                var boxHeight = (lines.length * lineHeight + 5) * scale;
                return lx >= 0 && lx <= boxWidth && ly >= 0 && ly <= boxHeight;
            }
            return false;
        }


        var amgiIOOneTimeSetupDone = false;

        function amgiWaitForIOImage(img, callback) {
            if (!img) {
                callback();
                return;
            }
            if (img.complete) {
                callback();
                return;
            }
            var onReady = function() {
                img.removeEventListener('load', onReady);
                img.removeEventListener('error', onReady);
                callback();
            };
            img.addEventListener('load', onReady);
            img.addEventListener('error', onReady);
        }

        function amgiSetupImageOcclusion() {
            var container = document.getElementById('image-occlusion-container');
            if (!container) {
                return;
            }

            var img = container.querySelector('img');
            if (!img) {
                return;
            }

            var canvas = document.getElementById('image-occlusion-canvas');
            if (!canvas) {
                canvas = document.createElement('canvas');
                canvas.id = 'image-occlusion-canvas';
                container.appendChild(canvas);
            }

            if (!amgiIOOneTimeSetupDone) {
                window.addEventListener('load', function() {
                    window.requestAnimationFrame(amgiSetupImageOcclusion);
                });
                window.addEventListener('resize', function() {
                    window.requestAnimationFrame(amgiSetupImageOcclusion);
                });
                window.addEventListener('keydown', function(event) {
                    var button = document.getElementById('toggle') || document.querySelector('.toggle');
                    if (button && button.style.display !== 'none' && (event.key === 'M' || event.key === 'm')) {
                        event.preventDefault();
                        button.click();
                    }
                });
                amgiIOOneTimeSetupDone = true;
            }

            amgiWaitForIOImage(img, function() {
                window.requestAnimationFrame(function() {
                    var canvasRef = document.getElementById('image-occlusion-canvas');
                    if (!canvasRef) {
                        return;
                    }

                    var dpr = window.devicePixelRatio || 1;
                    var width = img.offsetWidth;
                    var height = img.offsetHeight;
                    if (width === 0 || height === 0) {
                        return;
                    }

                    canvasRef.style.width = width + 'px';
                    canvasRef.style.height = height + 'px';
                    canvasRef.width = width * dpr;
                    canvasRef.height = height * dpr;

                    var collectShapes = function() {
                        var shapes = [];
                        ['cloze-inactive', 'cloze', 'cloze-highlight'].forEach(function(cls) {
                            amgiExtractIOShapes('.' + cls + '[data-shape]').forEach(function(shape) {
                                shape._cls = cls;
                                shape._revealed = false;
                                shapes.push(shape);
                            });
                        });
                        container._amgiIOShapes = shapes;
                    };

                    var visibleShapes = function(textOnly) {
                        return (container._amgiIOShapes || []).filter(function(shape) {
                            if (shape._revealed) {
                                return false;
                            }
                            if (textOnly && shape.type !== 'text') {
                                return false;
                            }
                            if (shape._cls === 'cloze-inactive') {
                                return !!shape.occludeInactive;
                            }
                            return true;
                        });
                    };

                    var redraw = function() {
                        var ctx = canvasRef.getContext('2d');
                        if (!ctx) {
                            return;
                        }
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

                        visibleShapes(masksHidden).forEach(function(shape) {
                            var fill = shape._cls === 'cloze-inactive' ? inactiveColor :
                                shape._cls === 'cloze' ? activeColor : highlightColor;
                            amgiDrawIOShape(ctx, shape, size, fill, border);
                        });
                    };

                    container._amgiRedrawIO = redraw;
                    collectShapes();

                    if (!canvasRef.dataset.amgiRevealBound) {
                        canvasRef.addEventListener('click', function(event) {
                            if (!amgiIsAnswerSide() || container._amgiMasksHidden) {
                                return;
                            }
                            var rect = canvasRef.getBoundingClientRect();
                            var px = event.clientX - rect.left;
                            var py = event.clientY - rect.top;
                            var size = { width: img.offsetWidth, height: img.offsetHeight };
                            var shapes = container._amgiIOShapes || [];

                            for (var index = shapes.length - 1; index >= 0; index--) {
                                var shape = shapes[index];
                                if (amgiHitTestShape(shape, px, py, size)) {
                                    shape._revealed = !shape._revealed;
                                    if (container._amgiRedrawIO) {
                                        container._amgiRedrawIO();
                                    }
                                    break;
                                }
                            }
                        });
                        canvasRef.dataset.amgiRevealBound = '1';
                    }

                    var toggleBtn = document.getElementById('toggle') || document.querySelector('.toggle');
                    var hasInactiveMasks = !!document.querySelector('[data-occludeinactive="1"], [data-occludeInactive="1"]');

                    container._amgiToggleMasks = function(event) {
                        if (event) {
                            event.preventDefault();
                            event.stopPropagation();
                        }
                        container._amgiMasksHidden = !container._amgiMasksHidden;
                        if (!container._amgiMasksHidden) {
                            (container._amgiIOShapes || []).forEach(function(shape) {
                                shape._revealed = false;
                            });
                        }
                        if (toggleBtn) {
                            toggleBtn.setAttribute('aria-pressed', container._amgiMasksHidden ? 'true' : 'false');
                        }
                        redraw();
                    };

                    if (toggleBtn) {
                        toggleBtn.type = 'button';
                        toggleBtn.setAttribute('aria-pressed', container._amgiMasksHidden ? 'true' : 'false');
                        if (!amgiIsAnswerSide() || !hasInactiveMasks) {
                            toggleBtn.style.display = 'none';
                        } else {
                            toggleBtn.style.display = '';
                            if (!toggleBtn.dataset.amgiToggleBound) {
                                toggleBtn.addEventListener('click', function(event) {
                                    if (container._amgiToggleMasks) {
                                        container._amgiToggleMasks(event);
                                    }
                                });
                                toggleBtn.dataset.amgiToggleBound = '1';
                            }
                        }
                    }

                    redraw();
                });
            });
        }
        window.amgiSetupImageOcclusion = amgiSetupImageOcclusion;

        // Compatibility shim: Anki PC-generated image occlusion templates call
        // either `anki.imageOcclusion.setup()` or the older
        // `anki.setupImageCloze()`. We provide both shims so the template's
        // try-catch succeeds instead of showing an error message.
        var anki = globalThis.anki || window.anki || {};
        globalThis.anki = anki;
        window.anki = anki;
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
        // ────────────────────────────────────────────────────────────────

        async function amgiFinalizeCardContent() {
            await amgiExecuteDeferredCardScripts();

            await amgiRunHooks(window.onUpdateHook);

            var qa = document.getElementById('qa');
            if (qa && window.MathJax && window.MathJax.startup && window.MathJax.startup.promise) {
                try {
                    await window.MathJax.startup.promise;
                    if (typeof window.MathJax.typesetClear === 'function') {
                        window.MathJax.typesetClear();
                    }
                    if (typeof window.MathJax.typesetPromise === 'function') {
                        await window.MathJax.typesetPromise([qa]);
                    }
                } catch (error) {
                    console.error('MathJax failed', error);
                }
            }

            var hasTemplateManagedMedia = document.querySelector('audio:not(.anki-sound-audio), video') !== null;

            if (amgiAutoplayEnabled() && !hasTemplateManagedMedia) {
                // Keep autoplay and replay commands on the same mode selection path.
                amgiReplayAll(amgiReplayModeValue());
            }

            // Detect missing images
            document.querySelectorAll('img').forEach(function(img) {
                img.onerror = function() {
                    var hint = document.createElement('span');
                    hint.className = 'missing-media';
                    hint.textContent = '⚠ ' + (img.getAttribute('src') || 'image');
                    img.replaceWith(hint);
                };
                if (img.complete && img.naturalWidth === 0 && img.src) { img.onerror(); }
            });
            // Detect missing audio
            document.querySelectorAll('.sound-btn').forEach(function(span) {
                var audio = span.querySelector('audio');
                if (!audio) return;
                audio.onerror = function() {
                    var hint = document.createElement('span');
                    hint.className = 'missing-media';
                    hint.textContent = '⚠ ' + (audio.getAttribute('src') || 'audio');
                    span.replaceWith(hint);
                };
            });

            var typeInput = document.getElementById('typeans');
            if (typeInput) {
                var ensureVisible = function() {
                    window.setTimeout(amgiEnsureTypedAnswerVisible, 180);
                };
                typeInput.addEventListener('focus', ensureVisible);
                typeInput.addEventListener('click', ensureVisible);
                typeInput.addEventListener('input', ensureVisible);
                typeInput.focus();
                ensureVisible();
            }

            amgiSetupImageOcclusion();
            await amgiRunHooks(window.onShownHook);

            var prefetchHTML = amgiPrefetchHTMLValue();
            if (!amgiIsAnswerSide() && prefetchHTML) {
                amgiAllImagesLoaded().then(function() {
                    return amgiPreloadResources(prefetchHTML);
                });
            }
        }

        async function amgiUpdateQAContent(html, state) {
            var qa = document.getElementById('qa');
            if (!qa) {
                return;
            }

            stopAllSystemAudio();
            window.onUpdateHook.length = 0;
            window.onShownHook.length = 0;
            amgiApplyCardState(state);
            await amgiPreloadResources(html || '');

            Array.from(qa.getElementsByTagName('video')).forEach(function(oldVideo) {
                oldVideo.pause();
                while (oldVideo.firstChild) {
                    oldVideo.removeChild(oldVideo.firstChild);
                }
                oldVideo.load();
            });

            qa.innerHTML = html || '';
            await amgiFinalizeCardContent();
        }

        window.amgiUpdateQAContent = amgiUpdateQAContent;

        function amgiQueueQAUpdate(html, state) {
            window.__amgiUpdateQueue = (window.__amgiUpdateQueue || Promise.resolve()).then(function() {
                return amgiUpdateQAContent(html, state);
            });
            return window.__amgiUpdateQueue;
        }

        window.amgiQueueQAUpdate = amgiQueueQAUpdate;

        async function amgiHandleWindowLoad() {
            if (window.__amgiWindowLoadHandled) {
                return;
            }
            window.__amgiWindowLoadHandled = true;
            await amgiQueueQAUpdate(INITIAL_CARD_HTML, INITIAL_CARD_STATE);
        }

        window.addEventListener('load', amgiHandleWindowLoad);
        if (document.readyState === 'complete') {
            amgiHandleWindowLoad();
        }
        </script>
        </head>
        <body class="\(bodyClass)"><div id="qa" class="card-frame"></div></body>
        </html>
        """

            webView.loadHTMLString(styledHTML, baseURL: CardAssetPath.cardBaseURL)
        } else if context.coordinator.lastContentSignature != contentSignature {
            context.coordinator.lastContentSignature = contentSignature
            if context.coordinator.isPageLoaded {
                webView.evaluateJavaScript(updateCardScript, completionHandler: nil)
            } else {
                context.coordinator.pendingUpdateScript = updateCardScript
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
                replacement = "<span class=\"sound-btn\"><audio class=\"anki-sound-audio\" src=\"\(encoded)\" preload=\"auto\"></audio><button type=\"button\" class=\"replay-button replay-btn soundLink\" onclick=\"return playSound(this)\">\(iconHTML)</button></span>"
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
                replacement = "<button type=\"button\" class=\"replay-button replay-btn tts-btn\" data-tts-text=\"\(htmlAttributeEscaped(spokenText))\" data-tts-lang=\"\(htmlAttributeEscaped(lang))\" data-tts-voices=\"\(htmlAttributeEscaped(voices))\" data-tts-speed=\"\(htmlAttributeEscaped(speed))\" onclick=\"return amgiSpeakTts(this)\">\(iconHTML)</button>"
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

    private static func cardStateLiteral(
        autoplayEnabled: Bool,
        isAnswerSide: Bool,
        replayMode: String,
        bodyClass: String,
        alignTop: Bool,
        bodyPaddingBottom: Int,
        cardPaddingBottom: Int,
        prefetchHTML: String?
    ) -> String {
        let state: [String: Any] = [
            "autoplayEnabled": autoplayEnabled,
            "isAnswerSide": isAnswerSide,
            "replayMode": replayMode,
            "bodyClass": bodyClass,
            "alignTop": alignTop,
            "bodyPaddingBottom": bodyPaddingBottom,
            "cardPaddingBottom": cardPaddingBottom,
            "prefetchHTML": prefetchHTML ?? "",
        ]

        guard JSONSerialization.isValidJSONObject(state),
              let data = try? JSONSerialization.data(withJSONObject: state, options: []),
              let literal = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return literal
    }

    private static func updateCardScript(html: String, cardStateLiteral: String) -> String {
        "window.amgiQueueQAUpdate && window.amgiQueueQAUpdate(\(jsStringLiteral(html)), \(cardStateLiteral));"
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

        return "<img src=\"data:image/png;base64,\(data.base64EncodedString())\" alt=\"\(alt)\" />"
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
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
        private let speechSynthesizer = AVSpeechSynthesizer()

        init(
            onTypedAnswerSubmitted: ((String?) -> Void)? = nil,
            onAudioStateChange: ((Bool) -> Void)? = nil
        ) {
            self.onTypedAnswerSubmitted = onTypedAnswerSubmitted
            self.onAudioStateChange = onAudioStateChange
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

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
            onAudioStateChange?(true)
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            onAudioStateChange?(false)
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            onAudioStateChange?(false)
        }

        func stopTTS() {
            guard speechSynthesizer.isSpeaking else { return }
            speechSynthesizer.stopSpeaking(at: .immediate)
            onAudioStateChange?(false)
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
            if url.isFileURL || scheme == "about" || scheme == "javascript" {
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
            webView.evaluateJavaScript(pendingUpdateScript, completionHandler: nil)
        }
    }
}
