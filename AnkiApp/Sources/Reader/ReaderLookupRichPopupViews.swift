import SwiftUI
import WebKit
import AnkiKit
import AnkiClients
import AnkiReader
import Dependencies
import UIKit

struct ReaderLookupRichEntriesView: View {
    let result: DictionaryLookupResult
    let languageHint: String?
    let popupFontSize: CGFloat
    let popupContentFontSize: CGFloat
    let popupDictionaryNameFontSize: CGFloat
    let popupKanaFontSize: CGFloat
    let popupFrequencyFontSize: CGFloat
    let collapseDictionaries: Bool
    let compactGlossaries: Bool
    let audioSourceTemplate: String
    let localAudioEnabled: Bool
    let audioAutoplay: Bool
    let audioPlaybackMode: ReaderLookupAudioPlaybackMode
    let sentence: String?
    let onAddNote: ((ReaderLookupNotePayload) -> Void)?
    let onLookupRequested: (String, String?) -> Void

    @State private var autoplayedEntryID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(result.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider()
                        .overlay(Color.amgiBorder.opacity(0.32))
                }

                ReaderLookupEntryRichView(
                    entry: entry,
                    dictionaryStyles: result.dictionaryStyles,
                    languageHint: languageHint,
                    termFontSize: popupFontSize,
                    contentFontSize: popupContentFontSize,
                    dictionaryNameFontSize: popupDictionaryNameFontSize,
                    kanaFontSize: popupKanaFontSize,
                    frequencyFontSize: popupFrequencyFontSize,
                    collapseDictionaries: collapseDictionaries,
                    compactGlossaries: compactGlossaries,
                    audioSourceTemplate: audioSourceTemplate,
                    localAudioEnabled: localAudioEnabled,
                    audioPlaybackMode: audioPlaybackMode,
                    sentence: sentence,
                    shouldAutoplay: audioAutoplay && index == 0 && autoplayedEntryID == nil,
                    onAutoplayConsumed: {
                        autoplayedEntryID = entry.id
                    },
                    onAddNote: onAddNote,
                    onLookupRequested: onLookupRequested
                )
            }
        }
        .task(id: localAudioEnabled) {
            ReaderLookupLocalAudioServer.shared.setEnabled(localAudioEnabled)
        }
    }
}

private struct ReaderLookupEntryRichView: View {
    let entry: DictionaryLookupEntry
    let dictionaryStyles: [String: String]
    let languageHint: String?
    let termFontSize: CGFloat
    let contentFontSize: CGFloat
    let dictionaryNameFontSize: CGFloat
    let kanaFontSize: CGFloat
    let frequencyFontSize: CGFloat
    let collapseDictionaries: Bool
    let compactGlossaries: Bool
    let audioSourceTemplate: String
    let localAudioEnabled: Bool
    let audioPlaybackMode: ReaderLookupAudioPlaybackMode
    let sentence: String?
    let shouldAutoplay: Bool
    let onAutoplayConsumed: () -> Void
    let onAddNote: ((ReaderLookupNotePayload) -> Void)?
    let onLookupRequested: (String, String?) -> Void

    @State private var isResolvingAudio = false

    private var groupedGlossaries: [(dictionary: String, glossaries: [DictionaryLookupGlossary])] {
        let groups = Dictionary(grouping: entry.structuredGlossaries) { glossary in
            glossary.dictionary.nilIfBlank ?? L("reader_lookup_unknown_dictionary")
        }

        return groups.keys.sorted().compactMap { key in
            guard let value = groups[key], value.isEmpty == false else {
                return nil
            }
            return (dictionary: key, glossaries: value)
        }
    }

    private var notePayload: ReaderLookupNotePayload {
        ReaderLookupNotePayload(
            term: entry.term,
            reading: entry.reading?.nilIfBlank,
            sentence: sentence,
            definitions: entry.structuredGlossaries.flatMap(\.definitions)
        )
    }

    private var frequencyBadges: [ReaderLookupBadgeItem] {
        entry.structuredFrequencies.flatMap { frequency in
            frequency.frequencies.compactMap { value in
                ReaderLookupBadgeItem(
                    title: frequency.dictionary.nilIfBlank ?? "",
                    value: value.displayValue?.nilIfBlank ?? String(value.value)
                )
            }
        }
    }

    private var pitchTexts: [String] {
        entry.structuredPitches.compactMap { pitch in
            guard pitch.positions.isEmpty == false else {
                return nil
            }
            let values = pitch.positions.map(String.init).joined(separator: ", ")
            if let dictionary = pitch.dictionary.nilIfBlank {
                return "\(dictionary): \(values)"
            }
            return values
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let reading = entry.reading?.nilIfBlank,
                       reading != entry.term {
                        Text(reading)
                            .font(.system(size: max(11, kanaFontSize), weight: .medium))
                            .foregroundStyle(Color.amgiTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(entry.term)
                        .font(.system(size: max(18, termFontSize * 1.55), weight: .bold))
                        .foregroundStyle(Color.amgiTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        Task {
                            await playAudio()
                        }
                    } label: {
                        if isResolvingAudio {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: max(14, contentFontSize), weight: .medium))
                                .foregroundStyle(Color.amgiTextSecondary)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .buttonStyle(.plain)

                    if let onAddNote {
                        Button {
                            onAddNote(notePayload)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: max(14, contentFontSize), weight: .medium))
                                .foregroundStyle(Color.amgiTextSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if entry.deinflectionTrace.isEmpty == false {
                ReaderLookupTagWrap(tags: entry.deinflectionTrace.map(\.name), fontSize: max(10, contentFontSize * 0.76))
            }

            if frequencyBadges.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequencyBadges) { badge in
                            ReaderLookupFrequencyBadgeView(badge: badge, fontSize: max(11, frequencyFontSize))
                        }
                    }
                }
            }

            if pitchTexts.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pitchTexts, id: \.self) { pitch in
                        Text(pitch)
                            .font(.system(size: max(12, contentFontSize * 0.86)))
                            .foregroundStyle(Color.amgiTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if groupedGlossaries.isEmpty == false {
                ForEach(Array(groupedGlossaries.enumerated()), id: \.offset) { index, group in
                    ReaderLookupGlossaryGroupView(
                        dictionary: group.dictionary,
                        glossaries: group.glossaries,
                        dictionaryStyle: dictionaryStyles[group.dictionary] ?? "",
                        dictionaryNameFontSize: dictionaryNameFontSize,
                        collapseByDefault: collapseDictionaries && index > 0,
                        compactGlossaries: compactGlossaries,
                        onLookupRequested: onLookupRequested
                    )
                }
            } else if entry.glossaries.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.glossaries, id: \.self) { glossary in
                        Text(glossary)
                            .font(.system(size: max(13, contentFontSize)))
                            .foregroundStyle(Color.amgiTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .task(id: shouldAutoplay) {
            guard shouldAutoplay else {
                return
            }
            onAutoplayConsumed()
            await playAudio()
        }
    }

    private func playAudio() async {
        guard isResolvingAudio == false else {
            return
        }

        isResolvingAudio = true
        defer { isResolvingAudio = false }

        let resolvedReading = entry.reading?.nilIfBlank
        let url = await ReaderLookupAudioResolver.resolveAudioURL(
            term: entry.term,
            reading: resolvedReading,
            remoteTemplate: audioSourceTemplate,
            localAudioEnabled: localAudioEnabled
        )
        guard let url else {
            return
        }
        await ReaderLookupWordAudioPlayer.shared.play(url: url, mode: audioPlaybackMode)
    }
}

private struct ReaderLookupGlossaryGroupView: View {
    let dictionary: String
    let glossaries: [DictionaryLookupGlossary]
    let dictionaryStyle: String
    let dictionaryNameFontSize: CGFloat
    let collapseByDefault: Bool
    let compactGlossaries: Bool
    let onLookupRequested: (String, String?) -> Void

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ReaderLookupStructuredGlossaryWebView(
                dictionary: dictionary,
                glossaries: glossaries,
                dictionaryStyle: dictionaryStyle,
                compactGlossaries: compactGlossaries,
                onLookupRequested: onLookupRequested
            )
            .frame(maxWidth: .infinity, minHeight: 40)
        } label: {
            Text(dictionary)
                .font(.system(size: max(11, dictionaryNameFontSize), weight: .medium))
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .tint(Color.amgiTextSecondary)
        .onAppear {
            isExpanded = collapseByDefault == false
        }
    }
}

private struct ReaderLookupStructuredGlossaryWebView: UIViewRepresentable {
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    let dictionary: String
    let glossaries: [DictionaryLookupGlossary]
    let dictionaryStyle: String
    let compactGlossaries: Bool
    let onLookupRequested: (String, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            dictionary: dictionary,
            glossaries: glossaries,
            dictionaryStyle: dictionaryStyle,
            compactGlossaries: compactGlossaries,
            onLookupRequested: onLookupRequested,
            loadMediaData: { dictionary, mediaPath in
                try await dictionaryLookupClient.mediaFile(dictionary, mediaPath)
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "image")
        configuration.userContentController.add(context.coordinator, name: "openLink")
        configuration.userContentController.add(context.coordinator, name: "lookupText")

        let webView = ReaderLookupSizingWebView(frame: .zero, configuration: configuration)
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
        context.coordinator.update(
            dictionary: dictionary,
            glossaries: glossaries,
            dictionaryStyle: dictionaryStyle,
            compactGlossaries: compactGlossaries
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookupText")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
        fileprivate var html = ""
        fileprivate weak var webView: WKWebView?

        private var dictionary: String
        private var glossaries: [DictionaryLookupGlossary]
        private var dictionaryStyle: String
        private var compactGlossaries: Bool
        private let onLookupRequested: (String, String?) -> Void
        private let loadMediaData: @Sendable (String, String) async throws -> Data

        init(
            dictionary: String,
            glossaries: [DictionaryLookupGlossary],
            dictionaryStyle: String,
            compactGlossaries: Bool,
            onLookupRequested: @escaping (String, String?) -> Void,
            loadMediaData: @escaping @Sendable (String, String) async throws -> Data
        ) {
            self.dictionary = dictionary
            self.glossaries = glossaries
            self.dictionaryStyle = dictionaryStyle
            self.compactGlossaries = compactGlossaries
            self.onLookupRequested = onLookupRequested
            self.loadMediaData = loadMediaData
            super.init()
            html = Self.makeHTML(
                dictionary: dictionary,
                glossaries: glossaries,
                dictionaryStyle: dictionaryStyle,
                compactGlossaries: compactGlossaries
            )
        }

        func update(
            dictionary: String,
            glossaries: [DictionaryLookupGlossary],
            dictionaryStyle: String,
            compactGlossaries: Bool
        ) {
            let nextHTML = Self.makeHTML(
                dictionary: dictionary,
                glossaries: glossaries,
                dictionaryStyle: dictionaryStyle,
                compactGlossaries: compactGlossaries
            )

            guard nextHTML != html else {
                return
            }

            self.dictionary = dictionary
            self.glossaries = glossaries
            self.dictionaryStyle = dictionaryStyle
            self.compactGlossaries = compactGlossaries
            html = nextHTML
            webView?.loadHTMLString(nextHTML, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
                guard let number = value as? NSNumber else {
                    return
                }
                let height = CGFloat(truncating: number)
                if height > 0 {
                    webView.invalidateIntrinsicContentSize()
                    if let sizingWebView = webView as? ReaderLookupSizingWebView {
                        sizingWebView.contentHeight = height
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "lookupText" {
                guard let payload = message.body as? [String: Any],
                      let text = (payload["text"] as? String)?.nilIfBlank else {
                    return
                }
                onLookupRequested(text, payload["sentence"] as? String)
                return
            }

            guard message.name == "openLink",
                  let urlString = message.body as? String,
                  let url = URL(string: urlString) else {
                return
            }
            UIApplication.shared.open(url)
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let requestURL = urlSchemeTask.request.url,
                  let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
                  let dictionary = components.queryItems?.first(where: { $0.name == "dictionary" })?.value,
                  let mediaPath = components.queryItems?.first(where: { $0.name == "path" })?.value else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            Task {
                do {
                    let data = try await loadMediaData(dictionary, mediaPath)
                    guard data.isEmpty == false else {
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
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

        private static func makeHTML(
            dictionary: String,
            glossaries: [DictionaryLookupGlossary],
            dictionaryStyle: String,
            compactGlossaries: Bool
        ) -> String {
            let dictionaryData = (try? JSONEncoder().encode(glossaries))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let escapedDictionary = dictionary
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let escapedStyle = dictionaryStyle
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")

            return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
            <style>\(ReaderLookupStructuredContentResources.popupCSS)</style>
            <script>\(ReaderLookupStructuredContentResources.popupJS)</script>
            <style>
            body { padding: 0; }
            #content { padding: 0; }
            .glossary-content { padding: 0; }
            .glossary-inline-item + .glossary-inline-item::before { content: " | "; opacity: 0.6; }
            </style>
            </head>
            <body>
            <div id="content" data-dictionary="\(escapedDictionary)"></div>
            <script>
            (function() {
                const dictName = "\(escapedDictionary)";
                const glossaryItems = \(dictionaryData);
                window.dictionaryStyles = { [dictName]: `\(escapedStyle)` };
                window.compactGlossaries = \(compactGlossaries ? "true" : "false");

                const contentRoot = document.getElementById('content');
                const dictStyle = window.dictionaryStyles?.[dictName] ?? '';
                if (dictStyle) {
                    const style = document.createElement('style');
                    style.textContent = constructDictCss(dictStyle, dictName);
                    document.head.appendChild(style);
                }

                const compactCss = window.compactGlossaries ? `
                    #content ol, #content ul {
                        list-style: none;
                        padding-left: 0;
                        margin: 0;
                    }
                ` : '';
                if (compactCss) {
                    const compactStyle = document.createElement('style');
                    compactStyle.textContent = compactCss;
                    document.head.appendChild(compactStyle);
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

                if (glossaryItems.length > 1 && !window.compactGlossaries) {
                    const ol = el('ol');
                    let prevTags = null;
                    glossaryItems.forEach((item) => {
                        const li = el('li');
                        const parsedTags = parseTags(item.definitionTags).filter(tag => !NUMERIC_TAG.test(tag));
                        const posTags = [...new Set(parsedTags.filter(isPartOfSpeech))].sort();
                        const currentTags = JSON.stringify(posTags);
                        const filteredTags = parsedTags.filter(tag => !isPartOfSpeech(tag) || !(prevTags !== null && prevTags === currentTags));
                        const tags = createGlossaryTags(filteredTags);
                        if (tags) {
                            li.appendChild(tags);
                        }
                        const wrapper = el('div', { className: 'glossary-content' });
                        renderContent(wrapper, item.content);
                        li.appendChild(wrapper);
                        ol.appendChild(li);
                        prevTags = currentTags;
                    });
                    contentRoot.appendChild(ol);
                } else {
                    glossaryItems.forEach((item, index) => {
                        const wrapper = el('div', { className: window.compactGlossaries ? 'glossary-inline-item' : '' });
                        const tags = createGlossaryTags(parseTags(item.definitionTags).filter(tag => !NUMERIC_TAG.test(tag)));
                        if (tags) {
                            wrapper.appendChild(tags);
                        }
                        const content = el('div', { className: 'glossary-content' });
                        renderContent(content, item.content);
                        wrapper.appendChild(content);
                        if (!window.compactGlossaries && index > 0) {
                            contentRoot.appendChild(document.createElement('hr'));
                        }
                        contentRoot.appendChild(wrapper);
                    });
                }
            })();
            </script>
            </body>
            </html>
            """
        }

        private static func mimeType(for path: String) -> String {
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
}

private final class ReaderLookupSizingWebView: WKWebView {
    var contentHeight: CGFloat = 44 {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: max(44, contentHeight))
    }
}

private struct ReaderLookupTagWrap: View {
    let tags: [String]
    let fontSize: CGFloat

    var body: some View {
        FlexibleTagLayout(tags: tags, fontSize: fontSize)
    }
}

private struct FlexibleTagLayout: View {
    let tags: [String]
    let fontSize: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let rows = buildRows(maxWidth: proxy.size.width)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: fontSize))
                                .foregroundStyle(Color.amgiTextSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.amgiTextSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
        }
        .frame(minHeight: 24)
    }

    private func buildRows(maxWidth: CGFloat) -> [[String]] {
        guard maxWidth > 0 else {
            return [tags]
        }

        var rows: [[String]] = [[]]
        var currentWidth: CGFloat = 0

        for tag in tags {
            let estimatedWidth = NSString(string: tag).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width + 20
            if currentWidth + estimatedWidth > maxWidth, rows[rows.count - 1].isEmpty == false {
                rows.append([tag])
                currentWidth = estimatedWidth + 6
            } else {
                rows[rows.count - 1].append(tag)
                currentWidth += estimatedWidth + 6
            }
        }

        return rows
    }
}

private struct ReaderLookupBadgeItem: Identifiable {
    let title: String
    let value: String

    var id: String { "\(title)-\(value)" }
}

private struct ReaderLookupFrequencyBadgeView: View {
    let badge: ReaderLookupBadgeItem
    let fontSize: CGFloat

    private var horizontalPadding: CGFloat { max(6, fontSize * 0.62) }
    private var verticalPadding: CGFloat { max(3, fontSize * 0.24) }
    private var cornerRadius: CGFloat { max(6, fontSize * 0.65) }

    var body: some View {
        HStack(spacing: 0) {
            if badge.title.isEmpty == false {
                Text(badge.title)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(Color.amgiAccent)
            }

            Text(badge.value)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.amgiTextPrimary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Color(.systemBackground).opacity(0.9))
        }
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.amgiAccent.opacity(0.45), lineWidth: 1)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
