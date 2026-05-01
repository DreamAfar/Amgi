import SwiftUI
import WebKit
import AnkiKit
import AnkiReader
import AnkiClients
import Dependencies
import UIKit

struct ReaderLookupPopupWebContainer: View {
    let result: DictionaryLookupResult
    let collapseDictionaries: Bool
    let compactGlossaries: Bool
    let audioSourceTemplate: String
    let localAudioEnabled: Bool
    let audioAutoplay: Bool
    let audioPlaybackMode: ReaderLookupAudioPlaybackMode
    let needsAudio: Bool
    let refreshID: Int
    let onAddNote: ([String: String]) -> Void
    let duplicateCheck: @Sendable (String) async -> Bool
    let onLookupRequested: (String, String?) -> Void
    let onTapOutside: (() -> Void)?

    var body: some View {
        ReaderLookupPopupWebView(
            result: result,
            collapseDictionaries: collapseDictionaries,
            compactGlossaries: compactGlossaries,
            audioSourceTemplate: audioSourceTemplate,
            localAudioEnabled: localAudioEnabled,
            audioAutoplay: audioAutoplay,
            audioPlaybackMode: audioPlaybackMode,
            needsAudio: needsAudio,
            refreshID: refreshID,
            onAddNote: onAddNote,
            duplicateCheck: duplicateCheck,
            onLookupRequested: onLookupRequested,
            onTapOutside: onTapOutside
        )
        .task(id: localAudioEnabled) {
            ReaderLookupLocalAudioServer.shared.setEnabled(localAudioEnabled)
        }
    }
}

private struct ReaderLookupPopupWebView: UIViewRepresentable {
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    let result: DictionaryLookupResult
    let collapseDictionaries: Bool
    let compactGlossaries: Bool
    let audioSourceTemplate: String
    let localAudioEnabled: Bool
    let audioAutoplay: Bool
    let audioPlaybackMode: ReaderLookupAudioPlaybackMode
    let needsAudio: Bool
    let refreshID: Int
    let onAddNote: ([String: String]) -> Void
    let duplicateCheck: @Sendable (String) async -> Bool
    let onLookupRequested: (String, String?) -> Void
    let onTapOutside: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            result: result,
            collapseDictionaries: collapseDictionaries,
            compactGlossaries: compactGlossaries,
            audioSourceTemplate: audioSourceTemplate,
            localAudioEnabled: localAudioEnabled,
            audioAutoplay: audioAutoplay,
            audioPlaybackMode: audioPlaybackMode,
            needsAudio: needsAudio,
            onAddNote: onAddNote,
            duplicateCheck: duplicateCheck,
            onLookupRequested: onLookupRequested,
            onTapOutside: onTapOutside,
            loadMediaData: { dictionary, mediaPath in
                try await dictionaryLookupClient.mediaFile(dictionary, mediaPath)
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "openLink")
        configuration.userContentController.add(context.coordinator, name: "lookupText")
        configuration.userContentController.add(context.coordinator, name: "tapOutside")
        configuration.userContentController.add(context.coordinator, name: "playWordAudio")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "mineEntry")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "duplicateCheck")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "getEntry")
        configuration.setURLSchemeHandler(AudioHandler(), forURLScheme: "audio")
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "image")
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(context.coordinator.html, baseURL: nil)
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            result: result,
            collapseDictionaries: collapseDictionaries,
            compactGlossaries: compactGlossaries,
            audioSourceTemplate: audioSourceTemplate,
            localAudioEnabled: localAudioEnabled,
            audioAutoplay: audioAutoplay,
            audioPlaybackMode: audioPlaybackMode,
            needsAudio: needsAudio,
            onAddNote: onAddNote,
            duplicateCheck: duplicateCheck,
            onLookupRequested: onLookupRequested,
            onTapOutside: onTapOutside
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        Task {
            await ReaderLookupWordAudioPlayer.shared.stop()
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookupText")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapOutside")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playWordAudio")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mineEntry", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "duplicateCheck", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "getEntry", contentWorld: .page)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKURLSchemeHandler {
        fileprivate var html: String
        fileprivate weak var webView: WKWebView?

        private var result: DictionaryLookupResult
        private var lookupEntries: [[String: Any]]
        private var collapseDictionaries: Bool
        private var compactGlossaries: Bool
        private var audioSourceTemplate: String
        private var localAudioEnabled: Bool
        private var audioAutoplay: Bool
        private var audioPlaybackMode: ReaderLookupAudioPlaybackMode
        private var needsAudio: Bool
        private var onAddNote: ([String: String]) -> Void
        private var duplicateCheck: @Sendable (String) async -> Bool
        private var onLookupRequested: (String, String?) -> Void
        private var onTapOutside: (() -> Void)?
        private let loadMediaData: @Sendable (String, String) async throws -> Data

        init(
            result: DictionaryLookupResult,
            collapseDictionaries: Bool,
            compactGlossaries: Bool,
            audioSourceTemplate: String,
            localAudioEnabled: Bool,
            audioAutoplay: Bool,
            audioPlaybackMode: ReaderLookupAudioPlaybackMode,
            needsAudio: Bool,
            onAddNote: @escaping ([String: String]) -> Void,
            duplicateCheck: @escaping @Sendable (String) async -> Bool,
            onLookupRequested: @escaping (String, String?) -> Void,
            onTapOutside: (() -> Void)?,
            loadMediaData: @escaping @Sendable (String, String) async throws -> Data
        ) {
            self.result = result
            self.lookupEntries = Self.makeLookupEntries(from: result.entries)
            self.collapseDictionaries = collapseDictionaries
            self.compactGlossaries = compactGlossaries
            self.audioSourceTemplate = audioSourceTemplate
            self.localAudioEnabled = localAudioEnabled
            self.audioAutoplay = audioAutoplay
            self.audioPlaybackMode = audioPlaybackMode
            self.needsAudio = needsAudio
            self.onAddNote = onAddNote
            self.duplicateCheck = duplicateCheck
            self.onLookupRequested = onLookupRequested
            self.onTapOutside = onTapOutside
            self.loadMediaData = loadMediaData
            self.html = Self.makeHTML(
                collapseDictionaries: collapseDictionaries,
                compactGlossaries: compactGlossaries,
                audioSourceTemplate: audioSourceTemplate,
                localAudioEnabled: localAudioEnabled,
                audioAutoplay: audioAutoplay,
                audioPlaybackMode: audioPlaybackMode,
                needsAudio: needsAudio
            )
            super.init()
        }

        func update(
            result: DictionaryLookupResult,
            collapseDictionaries: Bool,
            compactGlossaries: Bool,
            audioSourceTemplate: String,
            localAudioEnabled: Bool,
            audioAutoplay: Bool,
            audioPlaybackMode: ReaderLookupAudioPlaybackMode,
            needsAudio: Bool,
            onAddNote: @escaping ([String: String]) -> Void,
            duplicateCheck: @escaping @Sendable (String) async -> Bool,
            onLookupRequested: @escaping (String, String?) -> Void,
            onTapOutside: (() -> Void)?
        ) {
            self.result = result
            self.lookupEntries = Self.makeLookupEntries(from: result.entries)
            self.collapseDictionaries = collapseDictionaries
            self.compactGlossaries = compactGlossaries
            self.audioSourceTemplate = audioSourceTemplate
            self.localAudioEnabled = localAudioEnabled
            self.audioAutoplay = audioAutoplay
            self.audioPlaybackMode = audioPlaybackMode
            self.needsAudio = needsAudio
            self.onAddNote = onAddNote
            self.duplicateCheck = duplicateCheck
            self.onLookupRequested = onLookupRequested
            self.onTapOutside = onTapOutside

            let nextHTML = Self.makeHTML(
                collapseDictionaries: collapseDictionaries,
                compactGlossaries: compactGlossaries,
                audioSourceTemplate: audioSourceTemplate,
                localAudioEnabled: localAudioEnabled,
                audioAutoplay: audioAutoplay,
                audioPlaybackMode: audioPlaybackMode,
                needsAudio: needsAudio
            )

            if nextHTML != html {
                html = nextHTML
                webView?.loadHTMLString(nextHTML, baseURL: nil)
                return
            }

            webView?.callAsyncJavaScript(
                """
                window.dictionaryStyles = dictionaryStyles;
                window.entryCount = entryCount;
                document.getElementById('entries-container').innerHTML = '';
                window.renderPopup();
                """,
                arguments: [
                    "dictionaryStyles": result.dictionaryStyles,
                    "entryCount": lookupEntries.count,
                ],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.callAsyncJavaScript(
                """
                window.dictionaryStyles = dictionaryStyles;
                window.entryCount = entryCount;
                window.renderPopup();
                """,
                arguments: [
                    "dictionaryStyles": result.dictionaryStyles,
                    "entryCount": lookupEntries.count,
                ],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "openLink":
                guard let urlString = message.body as? String,
                      let url = URL(string: urlString) else {
                    return
                }
                UIApplication.shared.open(url)
            case "lookupText":
                guard let payload = message.body as? [String: Any],
                      let text = payload["text"] as? String else {
                    return
                }
                onLookupRequested(text, payload["sentence"] as? String)
            case "tapOutside":
                onTapOutside?()
            case "playWordAudio":
                guard let content = message.body as? [String: Any],
                      let urlString = content["url"] as? String,
                      let url = URL(string: urlString) else {
                    return
                }
                let requestedMode = (content["mode"] as? String).flatMap(ReaderLookupAudioPlaybackMode.init) ?? .interrupt
                Task(priority: .userInitiated) {
                    await ReaderLookupWordAudioPlayer.shared.play(url: url, mode: requestedMode)
                }
            default:
                return
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
            switch message.name {
            case "mineEntry":
                guard let content = message.body as? [String: String] else {
                    return (false, nil)
                }
                onAddNote(content)
                return (false, nil)
            case "duplicateCheck":
                guard let word = message.body as? String else {
                    return (false, nil)
                }
                return (await duplicateCheck(word), nil)
            case "getEntry":
                guard let index = message.body as? Int,
                      lookupEntries.indices.contains(index) else {
                    return (nil, nil)
                }
                return (lookupEntries[index], nil)
            default:
                return (nil, nil)
            }
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
            collapseDictionaries: Bool,
            compactGlossaries: Bool,
            audioSourceTemplate: String,
            localAudioEnabled: Bool,
            audioAutoplay: Bool,
            audioPlaybackMode: ReaderLookupAudioPlaybackMode,
            needsAudio: Bool
        ) -> String {
            let audioSources = ReaderLookupAudioDefaults.sourceTemplates(
                remoteTemplate: audioSourceTemplate,
                localAudioEnabled: localAudioEnabled
            )
            let audioSourcesJSON = (try? JSONEncoder().encode(audioSources))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>\(ReaderLookupStructuredContentResources.popupCSS)</style>
                <script>\(ReaderLookupStructuredContentResources.popupJS)</script>
            </head>
            <body>
                <script>
                    window.collapseDictionaries = \(collapseDictionaries);
                    window.compactGlossaries = \(compactGlossaries);
                    window.audioSources = \(audioSourcesJSON);
                    window.audioEnableAutoplay = \(audioAutoplay);
                    window.audioPlaybackMode = "\(audioPlaybackMode.rawValue)";
                    window.needsAudio = \(needsAudio);
                    window.allowDupes = false;
                    window.compactGlossariesAnki = \(compactGlossaries);
                    window.customCSS = "";
                    window.swipeThreshold = 0;
                </script>
                <div id="entries-container"></div>
                <div class="overlay">
                    <div class="overlay-close" onclick="closeOverlay()">×</div>
                    <div class="overlay-content"></div>
                </div>
            </body>
            </html>
            """
        }

        private static func makeLookupEntries(from entries: [DictionaryLookupEntry]) -> [[String: Any]] {
            let payload = entries.map(PopupEntryPayload.init)
            guard let data = try? JSONEncoder().encode(payload),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return json
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

private final class AudioHandler: NSObject, WKURLSchemeHandler {
    private var tasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url,
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let targetURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let targetURL = URL(string: targetURLString) else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        let taskID = ObjectIdentifier(task)
        tasks.insert(taskID)

        Task {
            do {
                let request = URLRequest(url: targetURL, timeoutInterval: 1.2)
                let (data, _) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    guard self.tasks.contains(taskID) else {
                        return
                    }

                    let response = HTTPURLResponse(
                        url: requestURL,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Access-Control-Allow-Origin": "*",
                            "Content-Type": "application/json"
                        ]
                    )!
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                }
            } catch {
                await MainActor.run {
                    guard self.tasks.contains(taskID) else {
                        return
                    }
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        tasks.remove(ObjectIdentifier(task))
    }
}

private struct PopupEntryPayload: Codable {
    struct DeinflectionTrace: Codable {
        var name: String
        var description: String
    }

    struct GlossaryPayload: Codable {
        var dictionary: String
        var content: String
        var definitionTags: String
        var termTags: String
    }

    struct FrequencyValuePayload: Codable {
        var value: Int
        var displayValue: String
    }

    struct FrequencyPayload: Codable {
        var dictionary: String
        var frequencies: [FrequencyValuePayload]
    }

    struct PitchPayload: Codable {
        var dictionary: String
        var pitchPositions: [Int]
    }

    var expression: String
    var reading: String
    var matched: String
    var deinflectionTrace: [DeinflectionTrace]
    var glossaries: [GlossaryPayload]
    var frequencies: [FrequencyPayload]
    var pitches: [PitchPayload]
    var rules: [String]

    init(entry: DictionaryLookupEntry) {
        expression = entry.term
        reading = entry.reading ?? ""
        matched = entry.matched ?? ""
        deinflectionTrace = entry.deinflectionTrace.map {
            DeinflectionTrace(name: $0.name, description: $0.description ?? "")
        }
        glossaries = entry.structuredGlossaries.map {
            GlossaryPayload(
                dictionary: $0.dictionary,
                content: $0.content,
                definitionTags: $0.definitionTags ?? "",
                termTags: $0.termTags ?? ""
            )
        }
        frequencies = entry.structuredFrequencies.map {
            FrequencyPayload(
                dictionary: $0.dictionary,
                frequencies: $0.frequencies.map {
                    FrequencyValuePayload(
                        value: $0.value,
                        displayValue: $0.displayValue ?? ""
                    )
                }
            )
        }
        pitches = entry.structuredPitches.map {
            PitchPayload(dictionary: $0.dictionary, pitchPositions: $0.positions)
        }
        rules = entry.rules
    }
}

actor ReaderLookupDuplicateCache {
    static let shared = ReaderLookupDuplicateCache()

    private var wordsByNotetypeID: [Int64: Set<String>] = [:]

    func contains(
        word: String,
        notetypeID: Int64,
        loader: @Sendable () async throws -> [String]
    ) async -> Bool {
        if let cached = wordsByNotetypeID[notetypeID] {
            return cached.contains(word)
        }

        do {
            let loadedWords = try await loader()
            let normalizedWords = Set(
                loadedWords.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { $0.isEmpty == false }
            )
            wordsByNotetypeID[notetypeID] = normalizedWords
            return normalizedWords.contains(word)
        } catch {
            return false
        }
    }

    func invalidate(notetypeID: Int64?) {
        if let notetypeID {
            wordsByNotetypeID.removeValue(forKey: notetypeID)
        } else {
            wordsByNotetypeID.removeAll()
        }
    }
}
