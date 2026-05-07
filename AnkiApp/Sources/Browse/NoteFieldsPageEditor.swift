import SwiftUI
import UIKit
import WebKit

struct NoteFieldsPageEditorActionState: Equatable {
    var showsAudioButton = false
    var hasAudio = false
    var hasEditableImage = false
    var showsSourcePreview = false
    var sourcePreviewHeight: CGFloat = 96
}

struct NoteFieldsPageEditor: View {
    let fieldNames: [String]
    @Binding var fieldValues: [String]
    @Binding var fieldSourceModes: [Bool]
    let actionStates: [NoteFieldsPageEditorActionState]
    var onDraftExport: (() -> Void)? = nil
    var onInsertPhoto: ((Int) -> Void)? = nil
    var onInsertCameraPhoto: ((Int) -> Void)? = nil
    var onInsertFile: ((Int) -> Void)? = nil
    var onRecordAudio: ((Int) -> Void)? = nil
    var onPreviewAudio: ((Int) -> Void)? = nil
    var onEditImage: ((Int) -> Void)? = nil

    @State private var measuredHeight: CGFloat = 120

    var body: some View {
        NoteFieldsPageWebView(
            fieldNames: fieldNames,
            fieldValues: $fieldValues,
            fieldSourceModes: $fieldSourceModes,
            actionStates: actionStates,
            measuredHeight: $measuredHeight,
            onDraftExport: onDraftExport,
            onInsertPhoto: onInsertPhoto,
            onInsertCameraPhoto: onInsertCameraPhoto,
            onInsertFile: onInsertFile,
            onRecordAudio: onRecordAudio,
            onPreviewAudio: onPreviewAudio,
            onEditImage: onEditImage
        )
        .frame(height: max(measuredHeight, 120))
    }
}

private struct NoteFieldsPageWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let fieldNames: [String]
    @Binding var fieldValues: [String]
    @Binding var fieldSourceModes: [Bool]
    let actionStates: [NoteFieldsPageEditorActionState]
    @Binding var measuredHeight: CGFloat
    var onDraftExport: (() -> Void)?
    var onInsertPhoto: ((Int) -> Void)?
    var onInsertCameraPhoto: ((Int) -> Void)?
    var onInsertFile: ((Int) -> Void)?
    var onRecordAudio: ((Int) -> Void)?
    var onPreviewAudio: ((Int) -> Void)?
    var onEditImage: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fieldValues: $fieldValues,
            fieldSourceModes: $fieldSourceModes,
            measuredHeight: $measuredHeight,
            onDraftExport: onDraftExport,
            onInsertPhoto: onInsertPhoto,
            onInsertCameraPhoto: onInsertCameraPhoto,
            onInsertFile: onInsertFile,
            onRecordAudio: onRecordAudio,
            onPreviewAudio: onPreviewAudio,
            onEditImage: onEditImage
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let webView = NoteFieldsAccessoryWKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.accessoryView = makeInputToolbar(for: webView, coordinator: context.coordinator)
        context.coordinator.attach(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = htmlDocument(colorScheme: colorScheme)
        let payload = makePayload()
        if context.coordinator.lastDocument != document {
            context.coordinator.prepareForDocumentReload(document: document, payload: payload)
            webView.loadHTMLString(document, baseURL: CardAssetPath.mediaBaseURL)
            return
        }
        guard context.coordinator.isPageReady else {
            context.coordinator.pendingPayloadAfterLoad = payload
            return
        }
        context.coordinator.pushPayloadIfNeeded(payload)
    }

    private func makePayload() -> Payload {
        let normalizedValues = fieldNames.indices.map { index in
            RichNoteFieldEditor.normalizedStoredHTML(index < fieldValues.count ? fieldValues[index] : "")
        }
        let normalizedSourceModes = fieldNames.indices.map { index in
            index < fieldSourceModes.count ? fieldSourceModes[index] : false
        }
        let normalizedActionStates = fieldNames.indices.map { index in
            index < actionStates.count ? actionStates[index] : .init()
        }

        let fields = fieldNames.enumerated().map { index, name in
            FieldPayload(
                name: name,
                html: normalizedValues[index],
                isSourceMode: normalizedSourceModes[index],
                showsAudioButton: normalizedActionStates[index].showsAudioButton,
                hasAudio: normalizedActionStates[index].hasAudio,
                hasEditableImage: normalizedActionStates[index].hasEditableImage,
                showsSourcePreview: normalizedActionStates[index].showsSourcePreview,
                sourcePreviewHeight: Double(normalizedActionStates[index].sourcePreviewHeight)
            )
        }
        return Payload(fields: fields)
    }

    private func htmlDocument(colorScheme: ColorScheme) -> String {
        let textColor = colorScheme == .dark ? "#F2F4F8" : "#17212F"
        let secondaryTextColor = colorScheme == .dark ? "#A7B5C8" : "#7E8795"
        let borderColor = colorScheme == .dark ? "rgba(255,255,255,0.12)" : "rgba(23,33,47,0.10)"
        let rowBackground = colorScheme == .dark ? "#303744" : "#EEF2F7"
        let previewBackground = colorScheme == .dark ? "rgba(255,255,255,0.04)" : "rgba(23,33,47,0.03)"
        let shellBackground = colorScheme == .dark ? "#2a2a2c" : "#f3f3f3"
        let shellBorderColor = colorScheme == .dark ? "rgba(255,255,255,0.10)" : "rgba(23,33,47,0.08)"
        let actionBackground = colorScheme == .dark ? "rgba(255,255,255,0.07)" : "rgba(23,33,47,0.07)"
        let linkColor = colorScheme == .dark ? "#8FB8FF" : "#1E5BB8"
        let accentColor = colorScheme == .dark ? "#8FB8FF" : "#2C6BED"
        let selectionColor = colorScheme == .dark ? "rgba(143,184,255,0.26)" : "rgba(30,91,184,0.18)"
        let sourceTagColor = colorScheme == .dark ? "#7AD97A" : "#208A20"
        let sourceAttrNameColor = colorScheme == .dark ? "#86A8FF" : "#2048C9"
        let sourceAttrValueColor = colorScheme == .dark ? "#FF9A8A" : "#C43131"
        let sourceCommentColor = colorScheme == .dark ? "#8FA0B8" : "#7A879B"
        let mathJaxConfigScriptURL = noteFieldsJavaScriptStringLiteral(CardAssetPath.mathJaxConfigScriptURLString)
        let mathJaxCoreScriptURL = noteFieldsJavaScriptStringLiteral(CardAssetPath.mathJaxCoreScriptURLString)

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">
        \(CardAssetPath.mediaBaseTag())
        <style>
        :root {
            color-scheme: \(colorScheme == .dark ? "dark" : "light");
            --text-color: \(textColor);
            --secondary-text-color: \(secondaryTextColor);
            --border-color: \(borderColor);
            --row-background: \(rowBackground);
            --preview-background: \(previewBackground);
            --shell-background: \(shellBackground);
            --shell-border-color: \(shellBorderColor);
            --action-background: \(actionBackground);
            --link-color: \(linkColor);
            --accent-color: \(accentColor);
            --selection-color: \(selectionColor);
            --source-tag-color: \(sourceTagColor);
            --source-attr-name-color: \(sourceAttrNameColor);
            --source-attr-value-color: \(sourceAttrValueColor);
            --source-comment-color: \(sourceCommentColor);
        }
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: var(--text-color);
            font: -apple-system-body;
            overflow-wrap: anywhere;
            -webkit-text-size-adjust: 100%;
        }
        body {
            padding: 4px 0 8px;
        }
        #fields {
            display: grid;
            gap: 10px;
        }
        .field {
            padding: 0;
            display: grid;
            gap: 2px;
        }
        .field-header {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 2px 2px;
        }
        .field-name {
            flex: 1 1 auto;
            font-size: 14px;
            font-weight: 600;
            line-height: 1.2;
            color: var(--secondary-text-color);
        }
        .field-actions {
            display: flex;
            align-items: center;
            gap: 6px;
            flex: 0 0 auto;
        }
        .field-action {
            appearance: none;
            border: 1px solid transparent;
            background: var(--action-background);
            color: var(--secondary-text-color);
            width: 28px;
            height: 28px;
            padding: 0;
            margin: 0;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            border-radius: 999px;
            cursor: pointer;
            transition: background 0.15s ease, border-color 0.15s ease, color 0.15s ease;
        }
        .field-action[hidden],
        .field-action.is-hidden {
            display: none !important;
        }
        .field-action svg {
            width: 15px;
            height: 15px;
            display: block;
            fill: currentColor;
        }
        .field-action:active {
            background: rgba(127, 127, 127, 0.14);
        }
        .field-action:disabled {
            opacity: 0.35;
        }
        .field-action.is-active {
            color: var(--accent-color);
            background: rgba(44, 107, 237, 0.12);
            border-color: rgba(44, 107, 237, 0.22);
        }
        .field-editor-shell {
            padding: 6px 8px;
            border-radius: 10px;
            border: 1px solid var(--shell-border-color);
            background: var(--shell-background);
        }
        .field-preview {
            display: none;
            margin-bottom: 4px;
            padding: 6px;
            border-radius: 6px;
            background: var(--preview-background);
            border: 1px solid var(--border-color);
            overflow: auto;
        }
        .field.is-source-mode .field-preview.has-preview {
            display: block;
        }
        .field.has-math-preview .field-preview.has-preview {
            display: block;
        }
        .field-rendered,
        .field-source {
            width: 100%;
            box-sizing: border-box;
            border: none;
            outline: none;
            background: transparent;
            color: var(--text-color);
            border-radius: 0;
            overflow-wrap: anywhere;
        }
        .field-rendered {
            min-height: 13px;
            white-space: normal;
            line-height: 1.45;
            caret-color: var(--text-color);
            padding: 0;
            margin: 0;
        }
        .field-source {
            display: none;
            min-height: 13px;
            max-height: 400px;
            overflow-y: auto;
            resize: none;
            padding: 0;
            margin: 0;
            font: -apple-system-body;
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            line-height: 1.45;
            background: transparent;
            color: var(--text-color);
            white-space: pre-wrap;
        }
        .field-source-stack {
            position: relative;
            display: none;
        }
        .field-source-highlight {
            position: absolute;
            inset: 0;
            overflow: hidden;
            pointer-events: none;
            border: none;
            margin: 0;
            padding: 0;
            color: var(--text-color);
            font: -apple-system-body;
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            line-height: 1.45;
            white-space: pre-wrap;
        }
        .field-source-highlight-content {
            display: block;
            min-height: 13px;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            word-break: break-word;
            transform: translate(0, 0);
        }
        .field-source.is-syntax-highlighted {
            position: relative;
            z-index: 1;
            color: transparent;
            caret-color: var(--text-color);
            -webkit-text-fill-color: transparent;
        }
        .field-source-highlight .source-syntax-tag,
        .field-source-highlight .source-syntax-tag-punctuation {
            color: var(--source-tag-color);
        }
        .field-source-highlight .source-syntax-attr-name {
            color: var(--source-attr-name-color);
        }
        .field-source-highlight .source-syntax-attr-value {
            color: var(--source-attr-value-color);
        }
        .field-source-highlight .source-syntax-comment {
            color: var(--source-comment-color);
        }
        .field.is-source-mode .field-editor-shell {
            background: var(--shell-background);
        }
        .field.is-source-mode .field-source-stack {
            display: block;
        }
        .field.is-source-mode .field-source {
            display: block;
        }
        .field.is-source-mode .field-rendered {
            display: none;
        }
        .field-rendered:empty:before {
            content: '';
        }
        *::selection {
            background: var(--selection-color);
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
        p, div {
            margin: 0 0 0.6em 0;
        }
        p:last-child,
        div:last-child {
            margin-bottom: 0;
        }
        a {
            color: var(--link-color);
        }
        pre {
            white-space: pre-wrap;
        }
        sup, sub {
            font-size: 0.75em;
        }
        </style>
        </head>
        <body>
            <div id=\"fields\"></div>
        <script>
        const fieldsRoot = document.getElementById('fields');
        const messageHandlerName = '\(Coordinator.messageHandlerName)';
        const MATHJAX_CONFIG_SCRIPT_URL = \(mathJaxConfigScriptURL);
        const MATHJAX_CORE_SCRIPT_URL = \(mathJaxCoreScriptURL);
        const state = {
            fields: [],
            activeFieldIndex: 0,
            isSyncingFromSwift: false,
            changeTimers: new Map(),
        };
        window.__amgiNoteFieldsMathJaxPromise = null;

        function notify(type, payload) {
            const body = Object.assign({ type }, payload || {});
            window.webkit.messageHandlers[messageHandlerName].postMessage(body);
        }

        function contentHeight() {
            const root = document.documentElement;
            const body = document.body;
            return Math.max(root.scrollHeight, body.scrollHeight, fieldsRoot.scrollHeight);
        }

        let lastSentHeight = 0;
        function sendHeightIfNeeded() {
            const height = Math.ceil(contentHeight());
            if (Math.abs(height - lastSentHeight) < 1) { return; }
            lastSentHeight = height;
            notify('heightChanged', { height });
        }

        function scheduleHeightUpdate() {
            window.requestAnimationFrame(sendHeightIfNeeded);
        }

        const activeFieldLayoutState = {
            pending: false,
        };

        function scheduleActiveFieldLayoutUpdate() {
            if (activeFieldLayoutState.pending) { return; }
            activeFieldLayoutState.pending = true;
            window.requestAnimationFrame(() => {
                activeFieldLayoutState.pending = false;
                if (!isEditorFocused()) { return; }
                notify('activeFieldLayoutChanged', { index: state.activeFieldIndex });
            });
        }

        function rectPayload(rectSource) {
            if (!rectSource) { return null; }
            const rect = typeof rectSource.getBoundingClientRect === 'function'
                ? rectSource.getBoundingClientRect()
                : rectSource;
            if (!rect) { return null; }
            const viewportOffsetLeft = window.visualViewport ? window.visualViewport.offsetLeft : 0;
            const viewportOffsetTop = window.visualViewport ? window.visualViewport.offsetTop : 0;
            return {
                minX: rect.left + viewportOffsetLeft,
                minY: rect.top + viewportOffsetTop,
                maxX: rect.right + viewportOffsetLeft,
                maxY: rect.bottom + viewportOffsetTop,
                width: rect.width,
                height: rect.height,
            };
        }

        function fieldElement(index) {
            return fieldsRoot.querySelector(`.field[data-field-index="${index}"]`);
        }

        function editorShellElement(index) {
            return fieldElement(index)?.querySelector('.field-editor-shell');
        }

        function renderedElement(index) {
            return fieldElement(index)?.querySelector('.field-rendered');
        }

        function sourceElement(index) {
            return fieldElement(index)?.querySelector('.field-source');
        }

        function previewElement(index) {
            return fieldElement(index)?.querySelector('.field-preview');
        }

        function sourceHighlightElement(index) {
            return fieldElement(index)?.querySelector('.field-source-highlight-content');
        }

        function sourceSelectionIndex(textarea) {
            if (!textarea) { return 0; }
            const start = textarea.selectionStart || 0;
            const end = textarea.selectionEnd || 0;
            if (textarea.selectionDirection === 'backward') {
                return start;
            }
            return end;
        }

        function sourceCaretRect(index) {
            const source = sourceElement(index);
            if (!source) { return null; }

            const computedStyle = window.getComputedStyle(source);
            const caretIndex = Math.min(sourceSelectionIndex(source), (source.value || '').length);
            const mirror = document.createElement('div');
            const marker = document.createElement('span');
            const beforeCaret = (source.value || '').slice(0, caretIndex);
            const sourceRect = source.getBoundingClientRect();

            mirror.setAttribute('aria-hidden', 'true');
            mirror.style.position = 'fixed';
            mirror.style.left = '0';
            mirror.style.top = '0';
            mirror.style.visibility = 'hidden';
            mirror.style.pointerEvents = 'none';
            mirror.style.whiteSpace = 'pre-wrap';
            mirror.style.overflowWrap = 'anywhere';
            mirror.style.wordBreak = 'break-word';
            mirror.style.boxSizing = computedStyle.boxSizing;
            mirror.style.width = source.clientWidth + 'px';
            mirror.style.padding = computedStyle.padding;
            mirror.style.border = computedStyle.border;
            mirror.style.font = computedStyle.font;
            mirror.style.lineHeight = computedStyle.lineHeight;
            mirror.style.letterSpacing = computedStyle.letterSpacing;
            mirror.style.textTransform = computedStyle.textTransform;
            mirror.style.textIndent = computedStyle.textIndent;
            mirror.style.tabSize = computedStyle.tabSize;

            mirror.textContent = beforeCaret;
            marker.textContent = String.fromCharCode(8203);
            mirror.appendChild(marker);
            document.body.appendChild(mirror);

            const mirrorRect = mirror.getBoundingClientRect();
            const markerRect = marker.getBoundingClientRect();
            const lineHeight = Number.parseFloat(computedStyle.lineHeight || '') || markerRect.height || 24;
            mirror.remove();

            const caretLeft = sourceRect.left + (markerRect.left - mirrorRect.left) - source.scrollLeft;
            const caretTop = sourceRect.top + (markerRect.top - mirrorRect.top) - source.scrollTop;
            return {
                left: caretLeft,
                top: caretTop,
                right: caretLeft + Math.max(markerRect.width, 2),
                bottom: caretTop + Math.max(lineHeight, markerRect.height, 24),
                width: Math.max(markerRect.width, 2),
                height: Math.max(lineHeight, markerRect.height, 24),
            };
        }

        function escapeHTML(text) {
            return (text || '')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }

        function highlightHTMLTagTail(raw) {
            let index = 0;
            let result = '';
            while (index < raw.length) {
                if (/\\s/.test(raw[index])) {
                    const start = index;
                    while (index < raw.length && /\\s/.test(raw[index])) {
                        index += 1;
                    }
                    result += escapeHTML(raw.slice(start, index));
                    continue;
                }

                if (raw[index] === '/') {
                    result += '<span class="source-syntax-tag-punctuation">/</span>';
                    index += 1;
                    continue;
                }

                const nameStart = index;
                while (index < raw.length && /[^\\s=/>]/.test(raw[index])) {
                    index += 1;
                }
                const attributeName = raw.slice(nameStart, index);
                if (!attributeName) {
                    result += escapeHTML(raw[index] || '');
                    index += 1;
                    continue;
                }
                result += `<span class="source-syntax-attr-name">${escapeHTML(attributeName)}</span>`;

                const whitespaceStart = index;
                while (index < raw.length && /\\s/.test(raw[index])) {
                    index += 1;
                }
                result += escapeHTML(raw.slice(whitespaceStart, index));

                if (raw[index] !== '=') {
                    continue;
                }

                result += '<span class="source-syntax-attr-value">=</span>';
                index += 1;

                const valueWhitespaceStart = index;
                while (index < raw.length && /\\s/.test(raw[index])) {
                    index += 1;
                }
                result += escapeHTML(raw.slice(valueWhitespaceStart, index));

                if (index >= raw.length) {
                    break;
                }

                const quote = raw[index];
                if (quote === '"' || quote === "'") {
                    const valueStart = index;
                    index += 1;
                    while (index < raw.length && raw[index] !== quote) {
                        index += 1;
                    }
                    if (index < raw.length) {
                        index += 1;
                    }
                    result += `<span class="source-syntax-attr-value">${escapeHTML(raw.slice(valueStart, index))}</span>`;
                    continue;
                }

                const valueStart = index;
                while (index < raw.length && /[^\\s/>]/.test(raw[index])) {
                    index += 1;
                }
                result += `<span class="source-syntax-attr-value">${escapeHTML(raw.slice(valueStart, index))}</span>`;
            }
            return result;
        }

        function highlightHTMLToken(token) {
            if (token.startsWith('<!--')) {
                return `<span class="source-syntax-comment">${escapeHTML(token)}</span>`;
            }

            const isClosingTag = /^<\\//.test(token);
            const isSelfClosingTag = /\\/>$/.test(token);
            const inner = token.slice(
                isClosingTag ? 2 : 1,
                isSelfClosingTag ? -2 : -1
            );
            const leadingWhitespaceMatch = inner.match(/^\\s*/);
            const leadingWhitespace = leadingWhitespaceMatch ? leadingWhitespaceMatch[0] : '';
            const trimmedInner = inner.slice(leadingWhitespace.length);
            const tagNameMatch = trimmedInner.match(/^([^\\s/>]+)/);

            if (!tagNameMatch) {
                return `<span class="source-syntax-tag">${escapeHTML(token)}</span>`;
            }

            const tagName = tagNameMatch[1];
            const tail = trimmedInner.slice(tagName.length);
            return [
                '<span class="source-syntax-tag-punctuation">&lt;</span>',
                isClosingTag ? '<span class="source-syntax-tag-punctuation">/</span>' : '',
                escapeHTML(leadingWhitespace),
                `<span class="source-syntax-tag">${escapeHTML(tagName)}</span>`,
                highlightHTMLTagTail(tail),
                isSelfClosingTag ? '<span class="source-syntax-tag-punctuation">/</span>' : '',
                '<span class="source-syntax-tag-punctuation">&gt;</span>'
            ].join('');
        }

        function highlightHTMLSource(source) {
            const input = source || '';
            const tagRegex = /<!--[\\s\\S]*?-->|<\\/?[A-Za-z][^>]*?>/g;
            let result = '';
            let lastIndex = 0;
            let match = null;

            while ((match = tagRegex.exec(input)) !== null) {
                result += escapeHTML(input.slice(lastIndex, match.index));
                result += highlightHTMLToken(match[0]);
                lastIndex = match.index + match[0].length;
            }

            result += escapeHTML(input.slice(lastIndex));
            return result;
        }

        function syncSourceHighlightScroll(index) {
            const source = sourceElement(index);
            const highlight = sourceHighlightElement(index);
            if (!source || !highlight) { return; }
            highlight.style.transform = `translate(${-source.scrollLeft}px, ${-source.scrollTop}px)`;
        }

        function syncSourceHighlight(index) {
            const source = sourceElement(index);
            const highlight = sourceHighlightElement(index);
            if (!source || !highlight) { return; }
            const highlightedHTML = highlightHTMLSource(source.value || '');
            highlight.innerHTML = highlightedHTML || '<br>';
            syncSourceHighlightScroll(index);
        }

        function activeCaretRect(index) {
            if (state.fields[index]?.isSourceMode) {
                return rectPayload(
                    sourceCaretRect(index)
                    || sourceElement(index)
                    || editorShellElement(index)
                    || fieldElement(index)
                );
            }

            const selection = window.getSelection();
            if (selection && selection.rangeCount > 0 && selection.anchorNode) {
                const range = selection.getRangeAt(0).cloneRange();
                range.collapse(false);
                const clientRect = Array.from(range.getClientRects()).find(rect => rect.width > 0 || rect.height > 0)
                    || range.getBoundingClientRect();
                if (clientRect && (clientRect.width > 0 || clientRect.height > 0)) {
                    return rectPayload(clientRect);
                }

                const anchorElement = selection.anchorNode.nodeType === Node.ELEMENT_NODE
                    ? selection.anchorNode
                    : selection.anchorNode.parentElement;
                if (anchorElement) {
                    return rectPayload(anchorElement);
                }
            }

            return rectPayload(renderedElement(index) || editorShellElement(index) || fieldElement(index));
        }

        function activeFieldContainerRect(index) {
            return rectPayload(editorShellElement(index) || fieldElement(index));
        }

        function activeFieldSnapshot(index) {
            const fieldRect = activeFieldContainerRect(index);
            const focusRect = activeCaretRect(index) || fieldRect;
            if (!fieldRect || !focusRect) {
                return null;
            }
            return {
                fieldMinX: fieldRect.minX,
                fieldMinY: fieldRect.minY,
                fieldMaxX: fieldRect.maxX,
                fieldMaxY: fieldRect.maxY,
                fieldWidth: fieldRect.width,
                fieldHeight: fieldRect.height,
                focusMinX: focusRect.minX,
                focusMinY: focusRect.minY,
                focusMaxX: focusRect.maxX,
                focusMaxY: focusRect.maxY,
                focusWidth: focusRect.width,
                focusHeight: focusRect.height,
            };
        }

        function hasEmbeddedMedia(html) {
            const lowercased = (html || '').toLowerCase();
            return lowercased.includes('<img')
                || lowercased.includes('<svg')
                || lowercased.includes('<video')
                || lowercased.includes('<audio');
        }

        function trimMathPreviewText(text) {
            return (text || '')
                .replace(/<br[ ]*\\/?>/gi, '\\n')
                .replace(/^\\n*/, '')
                .replace(/\\n*$/, '');
        }

        function normalizeMathPreviewMarkup(html) {
            return (html || '').replace(
                /<anki-mathjax(?:[^>]*?block="(.*?)")?[^>]*?>([\\s\\S]*?)<\\/anki-mathjax>/gi,
                function(_match, block, text) {
                    const trimmed = trimMathPreviewText(text);
                    return (typeof block === 'string' && block !== 'false')
                        ? '\\[' + trimmed + '\\]'
                        : '\\(' + trimmed + '\\)';
                }
            );
        }

        function containsMathPreviewMarkup(html) {
            const source = normalizeMathPreviewMarkup(html);
            return source.includes('\\(') || source.includes('\\[');
        }

        function hasPreviewContent(html) {
            return hasEmbeddedMedia(html) || containsMathPreviewMarkup(html);
        }

        function loadMathJaxScript(kind, src) {
            return new Promise(function(resolve) {
                const existing = document.querySelector('script[data-amgi-note-fields-mathjax="' + kind + '"]');
                if (existing) {
                    if (existing.dataset.amgiLoaded === '1') {
                        resolve();
                        return;
                    }
                    existing.addEventListener('load', function() {
                        existing.dataset.amgiLoaded = '1';
                        resolve();
                    }, { once: true });
                    existing.addEventListener('error', function() {
                        resolve();
                    }, { once: true });
                    return;
                }

                const script = document.createElement('script');
                script.src = src;
                script.async = false;
                script.setAttribute('data-amgi-note-fields-mathjax', kind);
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

        async function waitForMathJax(timeout) {
            const deadline = Date.now() + (timeout || 0);
            while (Date.now() <= deadline) {
                const mathJax = window.MathJax;
                if (mathJax
                    && mathJax.startup
                    && mathJax.startup.promise
                    && typeof mathJax.typesetPromise === 'function') {
                    try {
                        await mathJax.startup.promise;
                    } catch (error) {
                        console.error('NoteFields MathJax startup failed', error);
                        return null;
                    }
                    return mathJax;
                }
                await new Promise(function(resolve) { window.setTimeout(resolve, 25); });
            }
            return null;
        }

        async function ensureMathJaxReady(timeout) {
            const readyMathJax = await waitForMathJax(0);
            if (readyMathJax) {
                return readyMathJax;
            }

            if (!window.__amgiNoteFieldsMathJaxPromise) {
                window.__amgiNoteFieldsMathJaxPromise = (async function() {
                    await loadMathJaxScript('config', MATHJAX_CONFIG_SCRIPT_URL);
                    await loadMathJaxScript('core', MATHJAX_CORE_SCRIPT_URL);
                    return await waitForMathJax(timeout || 1500);
                })().catch(function(error) {
                    console.error('NoteFields MathJax load failed', error);
                    window.__amgiNoteFieldsMathJaxPromise = null;
                    return null;
                });
            }

            return await window.__amgiNoteFieldsMathJaxPromise;
        }

        async function renderPreviewContent(preview, html) {
            if (!preview) { return; }
            const normalizedHTML = normalizeMathPreviewMarkup(html || '');
            const renderToken = String(Date.now()) + ':' + Math.random().toString(36).slice(2);
            preview.dataset.previewRenderToken = renderToken;
            preview.innerHTML = normalizedHTML;

            if (!containsMathPreviewMarkup(normalizedHTML)) {
                scheduleHeightUpdate();
                return;
            }

            const mathJax = await ensureMathJaxReady(1500);
            if (!mathJax || preview.dataset.previewRenderToken !== renderToken) {
                return;
            }

            try {
                await mathJax.typesetPromise([preview]);
                scheduleHeightUpdate();
            } catch (error) {
                console.error('NoteFields MathJax typeset failed', error);
            }
        }

        function focusElement(element) {
            if (!element) { return; }
            try {
                element.focus({ preventScroll: true });
            } catch (error) {
                element.focus();
            }
        }

        function setActiveField(index) {
            state.activeFieldIndex = index;
            notify('activeFieldChanged', { index });
        }

        function debounceFieldChanged(index) {
            const existing = state.changeTimers.get(index);
            if (existing) {
                clearTimeout(existing);
            }
            const timer = setTimeout(() => {
                state.changeTimers.delete(index);
                sendFieldChanged(index);
            }, 180);
            state.changeTimers.set(index, timer);
        }

        function sendFieldChanged(index) {
            if (state.isSyncingFromSwift) { return; }
            notify('fieldChanged', {
                index,
                html: state.fields[index]?.html || '',
            });
        }

        function sendSourceModeChanged(index) {
            if (state.isSyncingFromSwift) { return; }
            notify('sourceModeChanged', {
                index,
                isSourceMode: !!state.fields[index]?.isSourceMode,
            });
        }

        function flushPendingChanges() {
            for (const timer of state.changeTimers.values()) {
                clearTimeout(timer);
            }
            state.changeTimers.clear();
            const fields = state.fields.map(field => ({
                html: field.html || '',
                isSourceMode: !!field.isSourceMode,
            }));
            notify('flushDraft', {
                fields,
                activeFieldIndex: state.activeFieldIndex,
            });
            return fields;
        }

        function plainTextSelection(selection) {
            return selection ? selection.toString() || '' : '';
        }

        function wrapSourceSelection(textarea, prefix, suffix) {
            const start = textarea.selectionStart || 0;
            const end = textarea.selectionEnd || 0;
            const value = textarea.value || '';
            const selected = value.slice(start, end);
            const replacement = `${prefix}${selected}${suffix}`;
            textarea.value = value.slice(0, start) + replacement + value.slice(end);
            const cursor = selected.length > 0 ? start + replacement.length : start + prefix.length;
            textarea.selectionStart = cursor;
            textarea.selectionEnd = cursor;
            return textarea.value;
        }

        function execDocumentCommand(command, value) {
            try {
                return document.execCommand(command, false, value ?? null);
            } catch (error) {
                return false;
            }
        }

        function insertHTMLAtSelection(html) {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) { return false; }
            const range = selection.getRangeAt(0);
            replaceSelectionHTML(range, html);
            selection.removeAllRanges();
            selection.addRange(range);
            return true;
        }

        function wrapCurrentSelectionWithHTML(prefix, suffix) {
            const selection = window.getSelection();
            const selectedText = plainTextSelection(selection);
            return insertHTMLAtSelection(`${prefix}${selectedText}${suffix}`);
        }

        function applySpanStyleToSelection(styleValue) {
            return wrapCurrentSelectionWithHTML(`<span style="${styleValue}">`, '</span>');
        }

        function selectionTextAsListHTML(ordered) {
            const selection = window.getSelection();
            const text = plainTextSelection(selection);
            const lines = (text || '')
                .split(/\\n+/)
                .map(line => line.trim())
                .filter(line => line.length > 0);
            const tagName = ordered ? 'ol' : 'ul';
            const items = (lines.length > 0 ? lines : ['']).map(line => `<li>${line}</li>`).join('');
            return `<${tagName}>${items}</${tagName}>`;
        }

        function fallbackExecRenderedCommand(command, value) {
            const wrappers = {
                bold: ['<b>', '</b>'],
                italic: ['<i>', '</i>'],
                underline: ['<u>', '</u>'],
                strikeThrough: ['<s>', '</s>'],
                superscript: ['<sup>', '</sup>'],
                subscript: ['<sub>', '</sub>'],
                justifyLeft: ['<div style="text-align: left;">', '</div>'],
                justifyCenter: ['<div style="text-align: center;">', '</div>'],
                justifyRight: ['<div style="text-align: right;">', '</div>'],
            };
            if (command === 'foreColor' && value) {
                return applySpanStyleToSelection(`color: ${value};`);
            }
            if (command === 'hiliteColor' && value) {
                return applySpanStyleToSelection(`background-color: ${value};`);
            }
            if (command === 'insertOrderedList') {
                return insertHTMLAtSelection(selectionTextAsListHTML(true));
            }
            if (command === 'insertUnorderedList') {
                return insertHTMLAtSelection(selectionTextAsListHTML(false));
            }
            if (wrappers[command]) {
                return wrapCurrentSelectionWithHTML(wrappers[command][0], wrappers[command][1]);
            }
            return false;
        }

        function execSourceCommand(command, value) {
            const index = state.activeFieldIndex;
            const textarea = sourceElement(index);
            if (!textarea) { return; }
            const wrappers = {
                bold: ['<b>', '</b>'],
                italic: ['<i>', '</i>'],
                underline: ['<u>', '</u>'],
                strikeThrough: ['<s>', '</s>'],
                superscript: ['<sup>', '</sup>'],
                subscript: ['<sub>', '</sub>'],
                justifyLeft: ['<div style="text-align: left;">', '</div>'],
                justifyCenter: ['<div style="text-align: center;">', '</div>'],
                justifyRight: ['<div style="text-align: right;">', '</div>'],
            };
            if (command === 'foreColor') {
                state.fields[index].html = wrapSourceSelection(textarea, `<span style="color: ${value};">`, '</span>');
            } else if (command === 'hiliteColor') {
                state.fields[index].html = wrapSourceSelection(textarea, `<span style="background-color: ${value};">`, '</span>');
            } else if (command === 'insertOrderedList' || command === 'insertUnorderedList') {
                const start = textarea.selectionStart || 0;
                const end = textarea.selectionEnd || 0;
                const sourceValue = textarea.value || '';
                const selected = sourceValue.slice(start, end);
                const lines = selected
                    .split(/\\n+/)
                    .map(line => line.trim())
                    .filter(line => line.length > 0);
                const tagName = command === 'insertOrderedList' ? 'ol' : 'ul';
                const items = (lines.length > 0 ? lines : ['']).map(line => `<li>${line}</li>`).join('');
                const replacement = `<${tagName}>${items}</${tagName}>`;
                textarea.value = sourceValue.slice(0, start) + replacement + sourceValue.slice(end);
                textarea.selectionStart = start + replacement.length;
                textarea.selectionEnd = textarea.selectionStart;
                state.fields[index].html = textarea.value;
            } else if (wrappers[command]) {
                state.fields[index].html = wrapSourceSelection(textarea, wrappers[command][0], wrappers[command][1]);
            } else if (command === 'undo' || command === 'redo') {
                textarea.focus();
                document.execCommand(command, false, null);
                state.fields[index].html = textarea.value;
            } else {
                return;
            }
            syncFieldUI(index);
            debounceFieldChanged(index);
            scheduleHeightUpdate();
        }

        function focusRendered(index) {
            const editor = renderedElement(index);
            if (!editor) { return; }
            focusElement(editor);
        }

        function focusActiveField() {
            const index = state.activeFieldIndex;
            if (state.fields[index]?.isSourceMode) {
                focusElement(sourceElement(index));
            } else {
                focusRendered(index);
            }
        }

        function blurActiveField() {
            sourceElement(state.activeFieldIndex)?.blur();
            renderedElement(state.activeFieldIndex)?.blur();
        }

        function isEditorFocused() {
            const activeElement = document.activeElement;
            if (activeElement?.classList?.contains('field-source')) {
                return true;
            }
            if (activeElement?.classList?.contains('field-rendered')) {
                return true;
            }
            const activeField = fieldElement(state.activeFieldIndex);
            const selection = window.getSelection();
            return !!activeField
                && !!selection
                && selection.rangeCount > 0
                && activeField.contains(selection.anchorNode);
        }

        function activeSelectionHasRange() {
            const index = state.activeFieldIndex;
            if (state.fields[index]?.isSourceMode) {
                const textarea = sourceElement(index);
                return !!textarea && textarea.selectionStart !== textarea.selectionEnd;
            }
            const editor = renderedElement(index);
            const selection = window.getSelection();
            return !!editor
                && !!selection
                && selection.rangeCount > 0
                && selection.isCollapsed === false
                && editor.contains(selection.anchorNode)
                && editor.contains(selection.focusNode);
        }

        function replaceSelectionHTML(range, html) {
            range.deleteContents();
            const fragment = range.createContextualFragment(html);
            range.insertNode(fragment);
        }

        function unwrapNode(node) {
            const parent = node.parentNode;
            if (!parent) { return; }
            while (node.firstChild) {
                parent.insertBefore(node.firstChild, node);
            }
            parent.removeChild(node);
        }

        function clearSpecificHTMLFormatting(html, kind) {
            const container = document.createElement('div');
            container.innerHTML = html || '';
            const inlineTagKinds = {
                bold: ['B', 'STRONG'],
                italic: ['I', 'EM'],
                underline: ['U'],
                strikethrough: ['S', 'STRIKE', 'DEL'],
                superscript: ['SUP'],
                subscriptText: ['SUB'],
            };

            function stripStyleValue(styleValue, propertyName) {
                return styleValue
                    .split(';')
                    .map(part => part.trim())
                    .filter(part => part.length > 0 && part.toLowerCase().startsWith(propertyName) === false)
                    .join('; ');
            }

            if (kind === 'all') {
                const elements = Array.from(container.querySelectorAll('*'));
                for (const element of elements) {
                    element.removeAttribute('style');
                    element.removeAttribute('class');
                }
                for (let index = elements.length - 1; index >= 0; index -= 1) {
                    const element = elements[index];
                    if (['B', 'STRONG', 'I', 'EM', 'U', 'S', 'STRIKE', 'DEL', 'SPAN', 'FONT', 'MARK', 'SUB', 'SUP'].includes(element.tagName)) {
                        unwrapNode(element);
                    }
                }
                return container.innerHTML;
            }

            if (inlineTagKinds[kind]) {
                const elements = Array.from(container.querySelectorAll('*'));
                for (let index = elements.length - 1; index >= 0; index -= 1) {
                    const element = elements[index];
                    if (inlineTagKinds[kind].includes(element.tagName)) {
                        unwrapNode(element);
                    }
                }
            }

            if (kind === 'foregroundColor' || kind === 'backgroundColor') {
                const propertyName = kind === 'foregroundColor' ? 'color' : 'background-color';
                const elements = Array.from(container.querySelectorAll('[style]'));
                for (const element of elements) {
                    const nextStyle = stripStyleValue(element.getAttribute('style') || '', propertyName);
                    if (nextStyle.length > 0) {
                        element.setAttribute('style', nextStyle);
                    } else {
                        element.removeAttribute('style');
                    }
                    if (element.tagName === 'SPAN' && element.attributes.length === 0) {
                        unwrapNode(element);
                    }
                }
            }

            return container.innerHTML;
        }

        function clearRenderedFormatting(kind) {
            const index = state.activeFieldIndex;
            const editor = renderedElement(index);
            if (!editor) { return; }
            const selection = window.getSelection();
            const canOperateSelection = !!selection
                && selection.rangeCount > 0
                && editor.contains(selection.anchorNode)
                && editor.contains(selection.focusNode)
                && selection.isCollapsed === false;

            if (canOperateSelection) {
                const range = selection.getRangeAt(0);
                const container = document.createElement('div');
                container.appendChild(range.extractContents());
                const sanitized = clearSpecificHTMLFormatting(container.innerHTML, kind);
                replaceSelectionHTML(range, sanitized);
                selection.removeAllRanges();
            } else {
                editor.innerHTML = clearSpecificHTMLFormatting(editor.innerHTML, kind);
            }

            state.fields[index].html = editor.innerHTML;
            syncFieldUI(index);
            sendFieldChanged(index);
            scheduleHeightUpdate();
        }

        function clearFormatting(kind) {
            const index = state.activeFieldIndex;
            if (state.fields[index]?.isSourceMode) {
                state.fields[index].html = clearSpecificHTMLFormatting(state.fields[index]?.html || '', kind);
                syncFieldUI(index);
                sendFieldChanged(index);
                scheduleHeightUpdate();
                return;
            }
            clearRenderedFormatting(kind);
        }

        function wrapSelection(prefix, suffix) {
            const index = state.activeFieldIndex;
            if (state.fields[index]?.isSourceMode) {
                const textarea = sourceElement(index);
                if (!textarea) { return; }
                state.fields[index].html = wrapSourceSelection(textarea, prefix, suffix);
                syncFieldUI(index);
                debounceFieldChanged(index);
                scheduleHeightUpdate();
                return;
            }

            focusRendered(index);
            const selection = window.getSelection();
            const selectedText = plainTextSelection(selection);
            if (!execDocumentCommand('insertHTML', `${prefix}${selectedText}${suffix}`)) {
                wrapCurrentSelectionWithHTML(prefix, suffix);
            }
            const editor = renderedElement(index);
            state.fields[index].html = editor ? editor.innerHTML : state.fields[index].html;
            syncFieldUI(index);
            debounceFieldChanged(index);
            scheduleHeightUpdate();
        }

        function nextClozeOrdinal() {
            let maxOrdinal = 0;
            for (const field of state.fields) {
                const matches = (field.html || '').matchAll(/\\{\\{c(\\d+)::/g);
                for (const match of matches) {
                    const ordinal = Number(match[1] || '0');
                    if (ordinal > maxOrdinal) {
                        maxOrdinal = ordinal;
                    }
                }
            }
            return maxOrdinal + 1;
        }

        function wrapSelectionInCloze() {
            const ordinal = nextClozeOrdinal();
            wrapSelection(`{{c${ordinal}::`, '}}');
        }

        function execCommand(command, value) {
            const index = state.activeFieldIndex;
            if (state.fields[index]?.isSourceMode) {
                execSourceCommand(command, value);
                return;
            }
            focusRendered(index);
            if (command === 'foreColor' || command === 'hiliteColor') {
                execDocumentCommand('styleWithCSS', true);
            }
            const didExecute = execDocumentCommand(command, value ?? null);
            if (!didExecute) {
                fallbackExecRenderedCommand(command, value ?? null);
            }
            const editor = renderedElement(index);
            state.fields[index].html = editor ? editor.innerHTML : state.fields[index].html;
            syncFieldUI(index);
            debounceFieldChanged(index);
            scheduleHeightUpdate();
        }

        function updatePreview(index) {
            const preview = previewElement(index);
            if (!preview) { return; }
            const field = state.fields[index];
            const html = field.html || '';
            const section = fieldElement(index);
            const hasMathPreview = containsMathPreviewMarkup(html);
            const shouldShow = !!field.showsSourcePreview && hasPreviewContent(html);
            preview.classList.toggle('has-preview', shouldShow);
            section?.classList.toggle('has-math-preview', hasMathPreview);
            preview.style.minHeight = `${field.sourcePreviewHeight || 96}px`;
            if (!shouldShow) {
                preview.dataset.previewRenderToken = '';
                preview.innerHTML = '';
                return;
            }
            renderPreviewContent(preview, html);
        }

        function updateActionState(index) {
            const field = state.fields[index];
            const section = fieldElement(index);
            if (!section) { return; }
            const audioButton = section.querySelector('.field-action[data-role="audio"]');
            const imageButton = section.querySelector('.field-action[data-role="image"]');
            const sourceButton = section.querySelector('.field-action[data-role="source"]');
            if (audioButton) {
                const shouldShowAudio = !!field.showsAudioButton;
                audioButton.hidden = !shouldShowAudio;
                audioButton.classList.toggle('is-hidden', !shouldShowAudio);
                audioButton.disabled = !field.hasAudio;
            }
            if (imageButton) {
                const shouldShowImage = !!field.hasEditableImage;
                imageButton.hidden = !shouldShowImage;
                imageButton.classList.toggle('is-hidden', !shouldShowImage);
                imageButton.disabled = !shouldShowImage;
            }
            if (sourceButton) {
                sourceButton.classList.toggle('is-active', !!field.isSourceMode);
            }
        }

        function syncFieldUI(index) {
            const field = state.fields[index];
            const section = fieldElement(index);
            if (!field || !section) { return; }
            const rendered = renderedElement(index);
            const source = sourceElement(index);
            if (rendered && rendered.innerHTML !== (field.html || '')) {
                rendered.innerHTML = field.html || '';
            }
            if (source && source.value !== (field.html || '')) {
                source.value = field.html || '';
            }
            section.classList.toggle('is-source-mode', !!field.isSourceMode);
            editorShellElement(index)?.classList.toggle('is-source-mode', !!field.isSourceMode);
            if (source) {
                autosizeTextarea(source);
                syncSourceHighlight(index);
            }
            updatePreview(index);
            updateActionState(index);
        }

        function autosizeTextarea(textarea) {
            if (!textarea) { return; }
            textarea.style.height = 'auto';
            textarea.style.height = textarea.scrollHeight + 'px';
        }

        function bindFieldSection(section, index) {
            const rendered = section.querySelector('.field-rendered');
            const source = section.querySelector('.field-source');
            const sourceButton = section.querySelector('.field-action[data-role="source"]');
            const audioButton = section.querySelector('.field-action[data-role="audio"]');
            const imageButton = section.querySelector('.field-action[data-role="image"]');

            rendered.addEventListener('focus', () => setActiveField(index));
            rendered.addEventListener('click', () => setActiveField(index));
            rendered.addEventListener('input', () => {
                state.fields[index].html = rendered.innerHTML;
                updatePreview(index);
                debounceFieldChanged(index);
                scheduleHeightUpdate();
            });
            rendered.addEventListener('blur', () => {
                state.fields[index].html = rendered.innerHTML;
                sendFieldChanged(index);
            });

            source.addEventListener('focus', () => setActiveField(index));
            source.addEventListener('click', () => setActiveField(index));
            source.addEventListener('input', () => {
                state.fields[index].html = source.value;
                autosizeTextarea(source);
                syncSourceHighlight(index);
                updatePreview(index);
                debounceFieldChanged(index);
                scheduleHeightUpdate();
            });
            source.addEventListener('scroll', () => {
                syncSourceHighlightScroll(index);
            });
            source.addEventListener('blur', () => {
                state.fields[index].html = source.value;
                sendFieldChanged(index);
            });

            sourceButton.addEventListener('click', () => {
                const next = !state.fields[index].isSourceMode;
                state.fields[index].isSourceMode = next;
                syncFieldUI(index);
                sendSourceModeChanged(index);
                setActiveField(index);
                if (next) {
                    autosizeTextarea(source);
                    focusElement(source);
                } else {
                    focusElement(rendered);
                }
                scheduleHeightUpdate();
            });

            audioButton?.addEventListener('click', () => {
                setActiveField(index);
                notify('requestPreviewAudio', { index });
            });

            imageButton?.addEventListener('click', () => {
                setActiveField(index);
                notify('requestEditImage', { index });
            });
        }

        function iconMarkup(kind) {
            const icons = {
                source: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8.8 6.6a1 1 0 0 1 0 1.4L5.8 11l3 3a1 1 0 1 1-1.4 1.4l-3.7-3.7a1 1 0 0 1 0-1.4l3.7-3.7a1 1 0 0 1 1.4 0Zm6.4 0a1 1 0 0 1 1.4 0l3.7 3.7a1 1 0 0 1 0 1.4l-3.7 3.7a1 1 0 0 1-1.4-1.4l3-3-3-3a1 1 0 0 1 0-1.4Z"/></svg>',
                audio: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.6 4.7a1 1 0 0 1 1.7.7v13.2a1 1 0 0 1-1.7.7l-4.1-4.1H7.3a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2h3.2l4.1-4.1Zm4.1 3.1a1 1 0 0 1 1.4 0 6 6 0 0 1 0 8.5 1 1 0 0 1-1.4-1.4 4 4 0 0 0 0-5.7 1 1 0 0 1 0-1.4Z"/></svg>',
                image: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4.8h8.2a1 1 0 0 1 .7.3l3 3a1 1 0 0 1 .3.7V19a2.2 2.2 0 0 1-2.2 2.2H6A2.2 2.2 0 0 1 3.8 19V7A2.2 2.2 0 0 1 6 4.8Zm1.8 4.1a1.7 1.7 0 1 0 0 3.4 1.7 1.7 0 0 0 0-3.4Zm8.4 8.7-2.6-3.1a1 1 0 0 0-1.5 0l-1.6 1.9-1-1.1a1 1 0 0 0-1.5 0l-2.4 2.8h10.6Z"/></svg>',
            };
            return icons[kind] || '';
        }

        function makeFieldSection(field, index) {
            const section = document.createElement('section');
            section.className = 'field';
            section.dataset.fieldIndex = String(index);

            const header = document.createElement('div');
            header.className = 'field-header';

            const title = document.createElement('div');
            title.className = 'field-name';
            title.textContent = field.name;
            header.appendChild(title);

            const actions = document.createElement('div');
            actions.className = 'field-actions';

            const sourceButton = document.createElement('button');
            sourceButton.type = 'button';
            sourceButton.className = 'field-action';
            sourceButton.dataset.role = 'source';
            sourceButton.innerHTML = iconMarkup('source');
            sourceButton.setAttribute('aria-label', 'Source');
            actions.appendChild(sourceButton);

            const audioButton = document.createElement('button');
            audioButton.type = 'button';
            audioButton.className = 'field-action';
            audioButton.dataset.role = 'audio';
            audioButton.innerHTML = iconMarkup('audio');
            audioButton.setAttribute('aria-label', 'Audio');
            actions.appendChild(audioButton);

            const imageButton = document.createElement('button');
            imageButton.type = 'button';
            imageButton.className = 'field-action';
            imageButton.dataset.role = 'image';
            imageButton.innerHTML = iconMarkup('image');
            imageButton.setAttribute('aria-label', 'Image');
            actions.appendChild(imageButton);

            header.appendChild(actions);
            section.appendChild(header);

            const preview = document.createElement('div');
            preview.className = 'field-preview';
            section.appendChild(preview);

            const shell = document.createElement('div');
            shell.className = 'field-editor-shell';

            const rendered = document.createElement('div');
            rendered.className = 'field-rendered';
            rendered.contentEditable = 'true';
            rendered.spellcheck = false;
            rendered.autocapitalize = 'off';
            rendered.autocomplete = 'off';
            rendered.autocorrect = 'off';
            shell.appendChild(rendered);

            const sourceStack = document.createElement('div');
            sourceStack.className = 'field-source-stack';

            const sourceHighlight = document.createElement('pre');
            sourceHighlight.className = 'field-source-highlight';
            sourceHighlight.setAttribute('aria-hidden', 'true');

            const sourceHighlightContent = document.createElement('code');
            sourceHighlightContent.className = 'field-source-highlight-content';
            sourceHighlight.appendChild(sourceHighlightContent);
            sourceStack.appendChild(sourceHighlight);

            const source = document.createElement('textarea');
            source.className = 'field-source is-syntax-highlighted';
            source.spellcheck = false;
            source.autocapitalize = 'off';
            source.autocomplete = 'off';
            source.autocorrect = 'off';
            sourceStack.appendChild(source);
            shell.appendChild(sourceStack);

            section.appendChild(shell);

            bindFieldSection(section, index);
            return section;
        }

        function rebuildFields(payload) {
            state.fields = payload.fields.map(field => Object.assign({}, field));
            fieldsRoot.replaceChildren();
            state.fields.forEach((field, index) => {
                const section = makeFieldSection(field, index);
                fieldsRoot.appendChild(section);
                syncFieldUI(index);
            });
            scheduleHeightUpdate();
        }

        function applyPayload(payload) {
            if (!payload || !Array.isArray(payload.fields)) { return; }
            const shouldRebuild = payload.fields.length !== state.fields.length
                || payload.fields.some((field, index) => !state.fields[index] || state.fields[index].name !== field.name);
            if (shouldRebuild) {
                rebuildFields(payload);
                return;
            }

            state.isSyncingFromSwift = true;
            payload.fields.forEach((field, index) => {
                state.fields[index] = Object.assign({}, field);
                syncFieldUI(index);
            });
            state.isSyncingFromSwift = false;
            scheduleHeightUpdate();
        }

        window.amgiNoteFieldsEditor = {
            bootstrap(payload) {
                state.isSyncingFromSwift = true;
                rebuildFields(payload);
                state.isSyncingFromSwift = false;
                scheduleHeightUpdate();
            },
            syncPayload(payload) {
                applyPayload(payload);
            },
            exec(command, value) {
                execCommand(command, value);
            },
            wrapSelection(prefix, suffix) {
                wrapSelection(prefix, suffix);
            },
            wrapSelectionInCloze() {
                wrapSelectionInCloze();
            },
            clearFormatting(kind) {
                clearFormatting(kind);
            },
            hasSelection() {
                return activeSelectionHasRange();
            },
            exportState() {
                return flushPendingChanges();
            },
            activeFieldSnapshot() {
                return activeFieldSnapshot(state.activeFieldIndex);
            },
            activeFieldRect() {
                return activeCaretRect(state.activeFieldIndex);
            },
            isEditorFocused() {
                return isEditorFocused();
            },
            focus() {
                focusActiveField();
            },
            blur() {
                blurActiveField();
            }
        };

        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState !== 'visible') {
                flushPendingChanges();
            }
        });
        window.addEventListener('load', scheduleHeightUpdate);
        window.addEventListener('pageshow', scheduleHeightUpdate);
        document.addEventListener('click', event => {
            if (!(event.target instanceof Element)) { return; }
            const link = event.target.closest('a[href]');
            if (!link) { return; }
            event.preventDefault();
        });

        document.addEventListener('selectionchange', () => {
            scheduleActiveFieldLayoutUpdate();
        });

        if (window.visualViewport) {
            window.visualViewport.addEventListener('resize', scheduleActiveFieldLayoutUpdate);
            window.visualViewport.addEventListener('scroll', scheduleActiveFieldLayoutUpdate);
        }

        if (window.ResizeObserver) {
            const resizeObserver = new ResizeObserver(scheduleHeightUpdate);
            resizeObserver.observe(fieldsRoot);
            resizeObserver.observe(document.body);
        }

        document.addEventListener('load', event => {
            const tagName = event.target?.tagName;
            if (tagName === 'IMG' || tagName === 'AUDIO' || tagName === 'VIDEO') {
                scheduleHeightUpdate();
            }
        }, true);

        notify('ready');
        scheduleHeightUpdate();
        </script>
        </body>
        </html>
        """
    }

    private func makeInputToolbar(for webView: WKWebView, coordinator: Coordinator) -> UIView {
        let container = NoteFieldsToolbarContainerView(frame: CGRect(x: 0, y: 0, width: 0, height: 68))
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
            makeMenuButton(systemName: "textformat.superscript", title: L("rich_text_action_superscript"), tintColor: .systemBlue) {
                showInlineMenu(
                    key: "baseline",
                    views: [
                        makePaletteActionButton(title: L("rich_text_action_superscript"), tintColor: .systemBlue) {
                            coordinator.exec("superscript")
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(title: L("rich_text_action_subscript"), tintColor: .systemBlue) {
                            coordinator.exec("subscript")
                            dismissInlineMenu()
                        }
                    ]
                )
            },
            makeTextFormatButton(label: "[...]", title: "Cloze") {
                dismissInlineMenu()
                coordinator.wrapSelectionInCloze()
            },
            makeMenuButton(systemName: "paintbrush", title: L("rich_text_action_color"), tintColor: .systemBlue) {
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
            makeMenuButton(systemName: "eraser.line.dashed", title: L("rich_text_action_clear_format"), tintColor: .systemBlue) {
                showInlineMenu(
                    key: "clear-format",
                    views: makeClearFormattingPaletteViews(
                        coordinator: coordinator,
                        dismissMenu: dismissInlineMenu
                    )
                )
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
                        makePaletteActionButton(
                            title: L("rich_text_action_align_left"),
                            systemName: "align.horizontal.left",
                            tintColor: .systemBlue
                        ) {
                            coordinator.exec("justifyLeft")
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(
                            title: L("rich_text_action_align_center"),
                            systemName: "align.horizontal.center",
                            tintColor: .systemBlue
                        ) {
                            coordinator.exec("justifyCenter")
                            dismissInlineMenu()
                        },
                        makePaletteActionButton(
                            title: L("rich_text_action_align_right"),
                            systemName: "align.horizontal.right",
                            tintColor: .systemBlue
                        ) {
                            coordinator.exec("justifyRight")
                            dismissInlineMenu()
                        }
                    ]
                )
            },
            makeMenuButton(systemName: "function", title: L("rich_text_action_mathjax"), tintColor: .systemBlue) {
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
                            coordinator.triggerInsertPhoto()
                        },
                        makePaletteActionButton(title: L("note_editor_media_import_camera"), tintColor: .systemBlue) {
                            dismissInlineMenu()
                            coordinator.blur()
                            coordinator.triggerInsertCameraPhoto()
                        },
                        makePaletteActionButton(title: L("note_editor_media_import_file"), tintColor: .systemBlue) {
                            dismissInlineMenu()
                            coordinator.blur()
                            coordinator.triggerInsertFile()
                        }
                    ]
                )
            },
            makeFormatButton(systemName: "mic.fill", title: L("rich_text_action_record_audio")) {
                dismissInlineMenu()
                coordinator.blur()
                coordinator.triggerRecordAudio()
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

    private func makeClearFormattingPaletteViews(
        coordinator: Coordinator,
        dismissMenu: @escaping () -> Void
    ) -> [UIView] {
        [
            makePaletteActionButton(
                title: L("rich_text_action_bold"),
                systemName: "bold",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.bold)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_italic"),
                systemName: "italic",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.italic)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_underline"),
                systemName: "underline",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.underline)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_strikethrough"),
                systemName: "strikethrough",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.strikethrough)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_superscript"),
                systemName: "textformat.superscript",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.superscript)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_subscript"),
                systemName: "textformat.subscript",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.subscriptText)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_color"),
                systemName: "paintbrush",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.foregroundColor)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_action_highlight"),
                systemName: "highlighter",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.backgroundColor)
                dismissMenu()
            },
            makePaletteActionButton(
                title: L("rich_text_clear_all_confirm"),
                systemName: "eraser.line.dashed",
                tintColor: .systemRed,
                badgeSystemName: "xmark.circle.fill"
            ) {
                coordinator.clearFormatting(.all)
                dismissMenu()
            }
        ]
    }

    private func makeSymbolButton(systemName: String, title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .label
        configuration.image = UIImage(systemName: systemName)
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
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .systemBlue
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeTextFormatButton(label: String, title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.lineBreakMode = .byClipping
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .systemBlue
        configuration.attributedTitle = AttributedString(
            label,
            attributes: AttributeContainer([
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
            ])
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeMenuButton(systemName: String, title: String, tintColor: UIColor, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8
        button.accessibilityLabel = title
        var configuration = UIButton.Configuration.plain()
        configuration.buttonSize = .small
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = tintColor
        configuration.image = UIImage(systemName: systemName)
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
        badgeSystemName: String? = nil,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = tintColor
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 16
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = tintColor
        if let title {
            button.accessibilityLabel = title
        }
        if let systemName {
            configuration.image = UIImage(systemName: systemName)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        }
        if let title, systemName == nil {
            configuration.title = title
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        }
        button.configuration = configuration
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        if let badgeSystemName {
            let badge = UIImageView(image: UIImage(systemName: badgeSystemName))
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.tintColor = tintColor
            badge.backgroundColor = .systemBackground
            badge.layer.cornerRadius = 6
            badge.clipsToBounds = true
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(equalToConstant: 12),
                badge.heightAnchor.constraint(equalToConstant: 12),
                badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
                badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1)
            ])
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    fileprivate struct Payload: Encodable, Equatable {
        let fields: [FieldPayload]
    }

    fileprivate struct FieldPayload: Encodable, Equatable {
        let name: String
        let html: String
        let isSourceMode: Bool
        let showsAudioButton: Bool
        let hasAudio: Bool
        let hasEditableImage: Bool
        let showsSourcePreview: Bool
        let sourcePreviewHeight: Double
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        enum ClearFormattingKind: String {
            case bold
            case italic
            case underline
            case strikethrough
            case superscript
            case subscriptText
            case foregroundColor
            case backgroundColor
            case all
        }

        static let messageHandlerName = "amgiNoteFieldsChanged"

        private enum ActiveFieldAlignmentTarget {
            case field
            case focus
        }

        private struct ActiveFieldSnapshot {
            let fieldRect: CGRect
            let focusRect: CGRect
        }

        private struct KeyboardAnimation {
            let endFrameInScreen: CGRect
            let duration: TimeInterval
            let options: UIView.AnimationOptions

            init?(notification: Notification) {
                guard let userInfo = notification.userInfo,
                      let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
                else { return nil }

                if let isLocal = userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber,
                   isLocal.boolValue == false {
                    return nil
                }

                let animationCurve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
                    ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)

                endFrameInScreen = frameValue.cgRectValue
                duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
                options = UIView.AnimationOptions(rawValue: animationCurve << 16)
                    .union([.beginFromCurrentState, .allowUserInteraction])
            }
        }

        @Binding var fieldValues: [String]
        @Binding var fieldSourceModes: [Bool]
        @Binding var measuredHeight: CGFloat
        weak var webView: WKWebView?
        var lastDocument = ""
        var lastPayloadJSON = ""
        var isPageReady = false
        fileprivate var pendingPayloadAfterLoad: Payload?
        var activeFieldIndex = 0
        private let onInsertPhoto: ((Int) -> Void)?
        private let onInsertCameraPhoto: ((Int) -> Void)?
        private let onInsertFile: ((Int) -> Void)?
        private let onRecordAudio: ((Int) -> Void)?
        private let onPreviewAudio: ((Int) -> Void)?
        private let onEditImage: ((Int) -> Void)?
        private let onDraftExport: (() -> Void)?
        private var colorSelectionHandler: ((UIColor) -> Void)?
        private var hasRegisteredLifecycleObservers = false
        private var keyboardEndFrameInScreen: CGRect = .null
        private var pendingVisibilityAdjustmentWorkItem: DispatchWorkItem?
        private var isKeyboardFrameTransitioning = false
        // Keyboard animation to use when scrolling the host view to reveal the active field.
        // Set during WillChangeFrame so the scroll runs in sync with the keyboard animation.
        private var pendingRevealAnimation: KeyboardAnimation?
        private weak var trackedHostScrollView: UIScrollView?
        private var trackedHostContentInset: UIEdgeInsets = .zero
        private var trackedHostVerticalIndicatorInsets: UIEdgeInsets = .zero
        private var lastHostScrollInteractionTime: TimeInterval = 0

        init(
            fieldValues: Binding<[String]>,
            fieldSourceModes: Binding<[Bool]>,
            measuredHeight: Binding<CGFloat>,
            onDraftExport: (() -> Void)?,
            onInsertPhoto: ((Int) -> Void)?,
            onInsertCameraPhoto: ((Int) -> Void)?,
            onInsertFile: ((Int) -> Void)?,
            onRecordAudio: ((Int) -> Void)?,
            onPreviewAudio: ((Int) -> Void)?,
            onEditImage: ((Int) -> Void)?
        ) {
            self._fieldValues = fieldValues
            self._fieldSourceModes = fieldSourceModes
            self._measuredHeight = measuredHeight
            self.onDraftExport = onDraftExport
            self.onInsertPhoto = onInsertPhoto
            self.onInsertCameraPhoto = onInsertCameraPhoto
            self.onInsertFile = onInsertFile
            self.onRecordAudio = onRecordAudio
            self.onPreviewAudio = onPreviewAudio
            self.onEditImage = onEditImage
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            registerLifecycleObservers()
        }

        func prepareForDocumentReload(document: String, payload: Payload) {
            lastDocument = document
            lastPayloadJSON = ""
            isPageReady = false
            pendingPayloadAfterLoad = payload
        }

        fileprivate func pushPayloadIfNeeded(_ payload: Payload, force: Bool = false) {
            guard isPageReady else {
                pendingPayloadAfterLoad = payload
                return
            }
            guard let payloadJSON = Self.javaScriptObjectLiteral(from: payload) else { return }
            guard force || payloadJSON != lastPayloadJSON else { return }
            lastPayloadJSON = payloadJSON
            let functionName = force ? "bootstrap" : "syncPayload"
            let script = "window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.\(functionName)(\(payloadJSON));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func exec(_ command: String, value: String? = nil) {
            let resolvedValue = value.map(noteFieldsJavaScriptStringLiteral) ?? "null"
            let script = "window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.exec('\(command)', \(resolvedValue));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func wrapSelection(prefix: String, suffix: String) {
            let script = "window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.wrapSelection(\(noteFieldsJavaScriptStringLiteral(prefix)), \(noteFieldsJavaScriptStringLiteral(suffix)));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func wrapSelectionInCloze() {
            webView?.evaluateJavaScript(
                "window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.wrapSelectionInCloze();",
                completionHandler: nil
            )
        }

        func blur() {
            webView?.evaluateJavaScript("window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.blur();", completionHandler: nil)
        }

        func focus() {
            webView?.evaluateJavaScript("window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.focus();", completionHandler: nil)
        }

        func clearFormatting(_ kind: ClearFormattingKind) {
            if kind == .all {
                webView?.evaluateJavaScript("window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.hasSelection();") { [weak self] result, _ in
                    guard let self else { return }
                    if (result as? Bool) == true {
                        self.performClearFormatting(kind)
                    } else {
                        self.presentClearAllFormattingConfirmation()
                    }
                }
                return
            }
            performClearFormatting(kind)
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

        func triggerInsertPhoto() {
            onInsertPhoto?(activeFieldIndex)
        }

        func triggerInsertCameraPhoto() {
            onInsertCameraPhoto?(activeFieldIndex)
        }

        func triggerInsertFile() {
            onInsertFile?(activeFieldIndex)
        }

        func triggerRecordAudio() {
            onRecordAudio?(activeFieldIndex)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if isPageReady, let pendingPayloadAfterLoad {
                pushPayloadIfNeeded(pendingPayloadAfterLoad, force: true)
                self.pendingPayloadAfterLoad = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            switch type {
            case "ready":
                isPageReady = true
                if let pendingPayloadAfterLoad {
                    pushPayloadIfNeeded(pendingPayloadAfterLoad, force: true)
                    self.pendingPayloadAfterLoad = nil
                }
            case "heightChanged":
                if let height = body["height"] as? Double {
                    measuredHeight = max(CGFloat(height), 120)
                }
            case "activeFieldChanged":
                if let index = body["index"] as? Int {
                    activeFieldIndex = max(0, index)
                }
                if isKeyboardVisibleForCurrentEditor(), isKeyboardFrameTransitioning == false {
                    scheduleActiveFieldVisibilityAdjustment(target: .focus, delay: 0.01)
                }
            case "activeFieldLayoutChanged":
                if let index = body["index"] as? Int {
                    activeFieldIndex = max(0, index)
                }
                if isKeyboardVisibleForCurrentEditor(),
                   isKeyboardFrameTransitioning == false,
                   shouldScheduleLayoutDrivenVisibilityAdjustment() {
                    scheduleActiveFieldVisibilityAdjustment(target: .focus, delay: 0.01)
                }
            case "fieldChanged":
                guard let index = body["index"] as? Int,
                      let html = body["html"] as? String,
                      fieldValues.indices.contains(index)
                else { return }
                fieldValues[index] = RichNoteFieldEditor.normalizedStoredHTML(html)
            case "sourceModeChanged":
                guard let index = body["index"] as? Int,
                      let isSourceMode = body["isSourceMode"] as? Bool,
                      fieldSourceModes.indices.contains(index)
                else { return }
                fieldSourceModes[index] = isSourceMode
            case "flushDraft":
                applyExportedState(body["fields"] as? [[String: Any]])
                if let index = body["activeFieldIndex"] as? Int {
                    activeFieldIndex = max(0, index)
                }
                onDraftExport?()
            case "requestPreviewAudio":
                if let index = body["index"] as? Int {
                    onPreviewAudio?(index)
                }
            case "requestEditImage":
                if let index = body["index"] as? Int {
                    onEditImage?(index)
                }
            default:
                break
            }
        }

        @objc private func handleLifecycleNotification(_ notification: Notification) {
            pendingVisibilityAdjustmentWorkItem?.cancel()
            isKeyboardFrameTransitioning = false
            keyboardEndFrameInScreen = .null
            pendingRevealAnimation = nil
            restoreTrackedHostScrollInsetsIfNeeded()
            clampTrackedHostScrollOffsetIfNeeded()
            flushPendingEditingState()
        }

        @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
            captureHostScrollBaselineIfNeeded(force: keyboardEndFrameInScreen.isNull)
            guard let animation = KeyboardAnimation(notification: notification) else { return }

            isKeyboardFrameTransitioning = true
            keyboardEndFrameInScreen = animation.endFrameInScreen
            syncHostScrollViewInsetsIfNeeded(animation: animation)
            // Store the animation so the upcoming scroll reveal runs in sync with the
            // keyboard slide-up animation instead of jumping after it completes.
            pendingRevealAnimation = animation
            // Schedule early (during the keyboard animation window) so the host scroll
            // view animates together with the keyboard appearance.
            scheduleActiveFieldVisibilityAdjustment(target: .focus, delay: 0.03)
        }

        @objc private func handleKeyboardDidChangeFrameNotification(_ notification: Notification) {
            guard let animation = KeyboardAnimation(notification: notification) else { return }

            keyboardEndFrameInScreen = animation.endFrameInScreen
            syncHostScrollViewInsetsIfNeeded()
            isKeyboardFrameTransitioning = false
            // Keyboard animation is done; any remaining adjustment should be instant.
            pendingRevealAnimation = nil

            guard isKeyboardVisibleForCurrentEditor() else {
                pendingVisibilityAdjustmentWorkItem?.cancel()
                return
            }

            // Safety-net: re-schedule without animation in case WillChangeFrame's early
            // adjustment missed the field (e.g. JS wasn't ready yet).
            let delay = min(max(animation.duration * 0.1, 0.01), 0.05)
            scheduleActiveFieldVisibilityAdjustment(target: .focus, delay: delay)
        }

        @objc private func handleKeyboardDidHideNotification(_ notification: Notification) {
            keyboardEndFrameInScreen = .null
            pendingVisibilityAdjustmentWorkItem?.cancel()
            isKeyboardFrameTransitioning = false
            pendingRevealAnimation = nil
            restoreTrackedHostScrollInsetsIfNeeded()
        }

        private func performClearFormatting(_ kind: ClearFormattingKind) {
            webView?.evaluateJavaScript(
                "window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.clearFormatting('\(kind.rawValue)');",
                completionHandler: nil
            )
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
                    self?.performClearFormatting(.all)
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

        private func registerLifecycleObservers() {
            guard hasRegisteredLifecycleObservers == false else { return }
            hasRegisteredLifecycleObservers = true
            let notificationCenter = NotificationCenter.default
            let observers: [(NSNotification.Name, Selector)] = [
                (UIApplication.willResignActiveNotification, #selector(handleLifecycleNotification)),
                (UIApplication.didEnterBackgroundNotification, #selector(handleLifecycleNotification)),
                (UIApplication.userDidTakeScreenshotNotification, #selector(handleLifecycleNotification)),
                (UIResponder.keyboardWillChangeFrameNotification, #selector(handleKeyboardWillChangeFrameNotification)),
                (UIResponder.keyboardDidChangeFrameNotification, #selector(handleKeyboardDidChangeFrameNotification)),
                (UIResponder.keyboardDidHideNotification, #selector(handleKeyboardDidHideNotification))
            ]
            observers.forEach { name, selector in
                notificationCenter.addObserver(
                    self,
                    selector: selector,
                    name: name,
                    object: nil
                )
            }
        }

        private func flushPendingEditingState() {
            webView?.evaluateJavaScript(
                "window.amgiNoteFieldsEditor && window.amgiNoteFieldsEditor.exportState();"
            ) { [weak self] result, _ in
                guard let self, let fields = result as? [[String: Any]] else { return }
                self.applyExportedState(fields)
                self.onDraftExport?()
            }
        }

        private func applyExportedState(_ fields: [[String: Any]]?) {
            guard let fields else { return }
            let normalizedValues = fields.enumerated().map { index, field in
                if let html = field["html"] as? String {
                    return RichNoteFieldEditor.normalizedStoredHTML(html)
                }
                return index < fieldValues.count ? fieldValues[index] : ""
            }
            if normalizedValues.count == fieldValues.count {
                fieldValues = normalizedValues
            } else if normalizedValues.isEmpty == false {
                fieldValues = normalizedValues
            }

            let normalizedSourceModes = fields.enumerated().map { index, field in
                if let isSourceMode = field["isSourceMode"] as? Bool {
                    return isSourceMode
                }
                return index < fieldSourceModes.count ? fieldSourceModes[index] : false
            }
            if normalizedSourceModes.count == fieldSourceModes.count {
                fieldSourceModes = normalizedSourceModes
            } else if normalizedSourceModes.isEmpty == false {
                fieldSourceModes = normalizedSourceModes
            }
        }

        private func scheduleActiveFieldVisibilityAdjustment(
            target: ActiveFieldAlignmentTarget,
            delay: TimeInterval = 0.05
        ) {
            pendingVisibilityAdjustmentWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.adjustActiveFieldVisibilityIfNeeded(target: target)
            }
            pendingVisibilityAdjustmentWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func shouldScheduleLayoutDrivenVisibilityAdjustment() -> Bool {
            if isHostScrollUserInteractionInProgress() {
                pendingVisibilityAdjustmentWorkItem?.cancel()
                return false
            }

            // Ignore layout-driven reveal attempts immediately after the user scrolls
            // the list, otherwise the focused field can snap back into view.
            let cooldown: TimeInterval = 0.4
            return Date.timeIntervalSinceReferenceDate - lastHostScrollInteractionTime >= cooldown
        }

        private func adjustActiveFieldVisibilityIfNeeded(target: ActiveFieldAlignmentTarget) {
            // Keep keyboard avoidance from snapping the list back while the user is scrolling it.
            guard isHostScrollUserInteractionInProgress() == false else { return }
            guard isPageReady, let webView else { return }
            let script = """
            (() => {
                const editor = window.amgiNoteFieldsEditor;
                if (!editor || !editor.isEditorFocused()) {
                    return null;
                }
                return editor.activeFieldSnapshot();
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                guard let payload = result as? [String: Any],
                      let fieldRect = Self.rect(from: payload, prefix: "field"),
                      let focusRect = Self.rect(from: payload, prefix: "focus"),
                      let normalizedFieldRect = Self.normalizedRect(fieldRect),
                      let normalizedFocusRect = Self.normalizedRect(focusRect)
                else { return }
                self.applyVisibilityAdjustment(
                    snapshot: ActiveFieldSnapshot(
                        fieldRect: normalizedFieldRect,
                        focusRect: normalizedFocusRect
                    ),
                    target: target
                )
            }
        }

        private func applyVisibilityAdjustment(
            snapshot: ActiveFieldSnapshot,
            target: ActiveFieldAlignmentTarget
        ) {
            guard let context = hostScrollContext(), let webView else { return }
            let hostScrollView = context.scrollView

            syncHostScrollViewInsetsIfNeeded(using: context)

            guard context.keyboardOverlap > 0,
                  let fieldRectInHost = Self.normalizedRect(webView.convert(snapshot.fieldRect, to: hostScrollView)),
                  let focusRectInHost = Self.normalizedRect(webView.convert(snapshot.focusRect, to: hostScrollView))
            else { return }

            let targetRectInHost = alignmentRect(
                fieldRectInHost: fieldRectInHost,
                focusRectInHost: focusRectInHost,
                target: target
            )
            revealTargetRectIfNeeded(targetRectInHost, in: hostScrollView)
        }

        private func isKeyboardVisibleForCurrentEditor() -> Bool {
            guard let context = hostScrollContext() else { return false }
            return context.keyboardOverlap > 1
        }

        private struct HostScrollContext {
            let scrollView: UIScrollView
            let keyboardOverlap: CGFloat
        }

        private func hostScrollContext() -> HostScrollContext? {
            guard let webView,
                  let hostScrollView = enclosingHostScrollView(for: webView),
                  let window = webView.window
            else { return nil }

            let keyboardFrameInWindow = keyboardEndFrameInScreen.isNull
                ? CGRect(x: 0, y: window.bounds.maxY, width: window.bounds.width, height: 0)
                : window.convert(keyboardEndFrameInScreen, from: nil)
            let visibleKeyboardFrame = keyboardFrameInWindow.intersection(window.bounds)
            let hostFrameInWindow = hostScrollView.convert(hostScrollView.bounds, to: window)
            let keyboardOverlap = hostFrameInWindow.intersection(visibleKeyboardFrame).height
            let bottomInset = keyboardOverlap > 1 ? keyboardOverlap : 0

            return HostScrollContext(
                scrollView: hostScrollView,
                keyboardOverlap: bottomInset
            )
        }

        private func syncHostScrollViewInsetsIfNeeded(animation: KeyboardAnimation? = nil) {
            guard let context = hostScrollContext() else { return }
            syncHostScrollViewInsetsIfNeeded(using: context, animation: animation)
        }

        private func syncHostScrollViewInsetsIfNeeded(
            using context: HostScrollContext,
            animation: KeyboardAnimation? = nil
        ) {
            let hostScrollView = context.scrollView
            if trackedHostScrollView !== hostScrollView {
                captureHostScrollBaselineIfNeeded(force: true)
            }

            var contentInset = trackedHostContentInset
            contentInset.bottom += context.keyboardOverlap

            var verticalIndicatorInsets = trackedHostVerticalIndicatorInsets
            verticalIndicatorInsets.bottom += context.keyboardOverlap

            applyTrackedHostScrollInsets(
                to: hostScrollView,
                contentInset: contentInset,
                verticalIndicatorInsets: verticalIndicatorInsets,
                animation: animation
            )
        }

        private func captureHostScrollBaselineIfNeeded(force: Bool = false) {
            guard let webView,
                  let hostScrollView = enclosingHostScrollView(for: webView)
            else { return }
            guard force || trackedHostScrollView !== hostScrollView else { return }

            trackedHostScrollView = hostScrollView
            trackedHostContentInset = hostScrollView.contentInset
            if #available(iOS 13.0, *) {
                trackedHostVerticalIndicatorInsets = hostScrollView.verticalScrollIndicatorInsets
            } else {
                trackedHostVerticalIndicatorInsets = hostScrollView.scrollIndicatorInsets
            }
        }

        private func restoreTrackedHostScrollInsetsIfNeeded(animation: KeyboardAnimation? = nil) {
            guard let hostScrollView = trackedHostScrollView else { return }
            applyTrackedHostScrollInsets(
                to: hostScrollView,
                contentInset: trackedHostContentInset,
                verticalIndicatorInsets: trackedHostVerticalIndicatorInsets,
                animation: animation
            )
        }

        private func applyTrackedHostScrollInsets(
            to scrollView: UIScrollView,
            contentInset: UIEdgeInsets,
            verticalIndicatorInsets: UIEdgeInsets,
            animation: KeyboardAnimation?
        ) {
            let applyInsets = {
                scrollView.contentInset = contentInset
                if #available(iOS 13.0, *) {
                    scrollView.verticalScrollIndicatorInsets = verticalIndicatorInsets
                } else {
                    scrollView.scrollIndicatorInsets = verticalIndicatorInsets
                }
            }

            if let animation, animation.duration > 0.01 {
                UIView.animate(withDuration: animation.duration, delay: 0, options: animation.options) {
                    applyInsets()
                }
            } else {
                applyInsets()
            }
        }

        private func clampTrackedHostScrollOffsetIfNeeded() {
            guard let hostScrollView = trackedHostScrollView else { return }

            let minOffsetY = -hostScrollView.adjustedContentInset.top
            let maxOffsetY = max(
                minOffsetY,
                hostScrollView.contentSize.height - hostScrollView.bounds.height + hostScrollView.adjustedContentInset.bottom
            )
            let clampedOffsetY = min(max(hostScrollView.contentOffset.y, minOffsetY), maxOffsetY)
            guard abs(clampedOffsetY - hostScrollView.contentOffset.y) > 1 else { return }

            hostScrollView.setContentOffset(
                CGPoint(x: hostScrollView.contentOffset.x, y: clampedOffsetY),
                animated: false
            )
        }

        private func isHostScrollUserInteractionInProgress() -> Bool {
            guard let hostScrollView = trackedHostScrollView ?? webView.flatMap(enclosingHostScrollView(for:)) else {
                return false
            }
            let isInteracting = hostScrollView.isTracking || hostScrollView.isDragging || hostScrollView.isDecelerating
            if isInteracting {
                lastHostScrollInteractionTime = Date.timeIntervalSinceReferenceDate
            }
            return isInteracting
        }

        private func alignmentRect(
            fieldRectInHost: CGRect,
            focusRectInHost: CGRect,
            target: ActiveFieldAlignmentTarget
        ) -> CGRect {
            let expandedFieldRect = fieldRectInHost.insetBy(dx: 0, dy: -6)
            switch target {
            case .field:
                return expandedFieldRect
            case .focus:
                let desiredHeight = max(44, focusRectInHost.height + 16)
                let focusTargetRect = CGRect(
                    x: expandedFieldRect.minX,
                    y: focusRectInHost.midY - (desiredHeight / 2),
                    width: max(expandedFieldRect.width, 1),
                    height: desiredHeight
                )
                let clippedFocusTargetRect = focusTargetRect.intersection(expandedFieldRect)
                return clippedFocusTargetRect.isNull ? expandedFieldRect : clippedFocusTargetRect
            }
        }

        private func revealTargetRectIfNeeded(_ targetRect: CGRect, in hostScrollView: UIScrollView) {
            let visibleRect = CGRect(
                x: hostScrollView.contentOffset.x + hostScrollView.adjustedContentInset.left,
                y: hostScrollView.contentOffset.y + hostScrollView.adjustedContentInset.top,
                width: hostScrollView.bounds.width - hostScrollView.adjustedContentInset.left - hostScrollView.adjustedContentInset.right,
                height: hostScrollView.bounds.height - hostScrollView.adjustedContentInset.top - hostScrollView.adjustedContentInset.bottom
            ).insetBy(dx: 0, dy: 6)

            guard visibleRect.height > 0 else { return }

            if targetRect.height > visibleRect.height {
                let visibleIntersection = targetRect.intersection(visibleRect)
                let minimumVisibleHeight = min(max(visibleRect.height * 0.5, 44), 120)
                if visibleIntersection.isNull == false, visibleIntersection.height >= minimumVisibleHeight {
                    return
                }
            } else if visibleRect.contains(targetRect) {
                return
            }

            let deltaY: CGFloat
            if targetRect.minY < visibleRect.minY {
                deltaY = targetRect.minY - visibleRect.minY
            } else if targetRect.maxY > visibleRect.maxY {
                deltaY = targetRect.maxY - visibleRect.maxY
            } else {
                return
            }

            let minOffsetY = -hostScrollView.adjustedContentInset.top
            let maxOffsetY = max(
                minOffsetY,
                hostScrollView.contentSize.height - hostScrollView.bounds.height + hostScrollView.adjustedContentInset.bottom
            )
            let targetOffsetY = min(max(hostScrollView.contentOffset.y + deltaY, minOffsetY), maxOffsetY)
            guard abs(targetOffsetY - hostScrollView.contentOffset.y) > 1 else { return }

            let revealAnim = pendingRevealAnimation
            pendingRevealAnimation = nil
            if let anim = revealAnim, anim.duration > 0.05 {
                UIView.animate(withDuration: anim.duration, delay: 0, options: anim.options) {
                    hostScrollView.setContentOffset(
                        CGPoint(x: hostScrollView.contentOffset.x, y: targetOffsetY),
                        animated: false
                    )
                }
            } else {
                hostScrollView.setContentOffset(
                    CGPoint(x: hostScrollView.contentOffset.x, y: targetOffsetY),
                    animated: false
                )
            }
        }

        private func enclosingHostScrollView(for webView: WKWebView) -> UIScrollView? {
            var current = webView.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView,
                   scrollView !== webView.scrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }

        private static func rect(from payload: [String: Any], prefix: String) -> CGRect? {
            guard let minY = payload["\(prefix)MinY"] as? Double,
                  let maxY = payload["\(prefix)MaxY"] as? Double
            else { return nil }

            let minX = (payload["\(prefix)MinX"] as? Double) ?? 0
            let width = (payload["\(prefix)Width"] as? Double) ?? 0
            return CGRect(
                x: minX,
                y: minY,
                width: max(width, 0),
                height: max(0, maxY - minY)
            )
        }

        private static func normalizedRect(_ rect: CGRect) -> CGRect? {
            guard rect.minX.isFinite,
                  rect.minY.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite
            else { return nil }

            return CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(rect.width, 1),
                height: max(rect.height, 1)
            )
        }

        private static func javaScriptObjectLiteral<T: Encodable>(from value: T) -> String? {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(value),
                  let string = String(data: data, encoding: .utf8)
            else { return nil }
            return string
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

extension NoteFieldsPageWebView.Coordinator: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        colorSelectionHandler?(viewController.selectedColor)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        colorSelectionHandler = nil
        focus()
    }
}

private final class NoteFieldsToolbarContainerView: UIView {
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

private final class NoteFieldsAccessoryWKWebView: WKWebView {
    var accessoryView: UIView?

    override var inputAccessoryView: UIView? {
        accessoryView
    }

    // Unique context pointer so we can distinguish our own KVO observation
    // from WKWebView's internal observations of the same key path.
    private static var contentOffsetKVOContext = 0

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        // iOS WebKit programmatically sets scrollView.contentOffset when focusing a
        // contenteditable element, even when isScrollEnabled = false.  This displaces
        // rendered content and corrupts the coordinate calculations used for host-scroll
        // keyboard-avoidance.  KVO-reset the offset to .zero whenever internal scroll
        // is disabled so that all scrolling is handled exclusively by the host UIScrollView.
        scrollView.addObserver(
            self,
            forKeyPath: "contentOffset",
            options: .new,
            context: &Self.contentOffsetKVOContext
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        scrollView.removeObserver(self, forKeyPath: "contentOffset", context: &Self.contentOffsetKVOContext)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &Self.contentOffsetKVOContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        guard !scrollView.isScrollEnabled, scrollView.contentOffset != .zero else { return }
        scrollView.contentOffset = .zero
    }
}

private func noteFieldsJavaScriptStringLiteral(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let json = String(data: data, encoding: .utf8),
          json.count >= 2
    else {
        return "\"\""
    }
    return String(json.dropFirst().dropLast())
}
