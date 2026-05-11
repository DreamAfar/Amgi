import AVFoundation
import Foundation
import Network
import SQLite3
import UIKit

enum ReaderLookupAudioPlaybackMode: String, CaseIterable, Identifiable {
    case interrupt
    case duck
    case mix

    var id: String { rawValue }
}

enum ReaderLookupRemoteAudioPreset: String, CaseIterable, Identifiable, Sendable {
    case auto
    case custom
    case yomitanJapanese
    case yomitanEnglish

    var id: String { rawValue }
}

struct ReaderLookupAudioSourceDefinition: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case template
        case jpod101
        case languagePod101Japanese = "language-pod-101-japanese"
        case languagePod101English = "language-pod-101-english"
        case jisho
        case linguaLibre = "lingua-libre"
        case wiktionary
    }

    var kind: Kind
    var template: String?

    init(kind: Kind, template: String? = nil) {
        self.kind = kind
        self.template = template
    }
}

enum ReaderLookupAudioDefaults {
    static let defaultTemplate = "https://hoshi-reader.manhhaoo-do.workers.dev/?term={term}&reading={reading}"
    static let localAudioURL = "http://localhost:8765/localaudio/get/?term={term}&reading={reading}"
    static let defaultRemoteAudioPreset: ReaderLookupRemoteAudioPreset = .custom
    static let yomitanJapaneseSources: [ReaderLookupAudioSourceDefinition] = [
        .init(kind: .jpod101),
        .init(kind: .languagePod101Japanese),
        .init(kind: .jisho),
    ]
    static let yomitanEnglishSources: [ReaderLookupAudioSourceDefinition] = [
        .init(kind: .languagePod101English),
        .init(kind: .linguaLibre),
        .init(kind: .wiktionary),
    ]

    static func resolvedTemplate(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTemplate : trimmed
    }

    static func resolvedPreset(_ rawValue: String) -> ReaderLookupRemoteAudioPreset {
        ReaderLookupRemoteAudioPreset(rawValue: rawValue) ?? defaultRemoteAudioPreset
    }

    static func resolvedPlaybackMode(_ rawValue: String) -> ReaderLookupAudioPlaybackMode {
        ReaderLookupAudioPlaybackMode(rawValue: rawValue) ?? .interrupt
    }

    static func sourceDefinitions(
        remotePresetRawValue: String,
        remoteTemplate: String,
        localAudioEnabled: Bool,
        languageHint: String? = nil
    ) -> [ReaderLookupAudioSourceDefinition] {
        var sources: [ReaderLookupAudioSourceDefinition] = []
        if localAudioEnabled {
            sources.append(.init(kind: .template, template: localAudioURL))
        }

        let remoteSources: [ReaderLookupAudioSourceDefinition]
        switch resolvedPreset(remotePresetRawValue) {
        case .auto:
            switch normalizedLanguageCode(languageHint) {
            case "ja":
                remoteSources = yomitanJapaneseSources
            case "en":
                remoteSources = yomitanEnglishSources
            default:
                remoteSources = [.init(kind: .template, template: resolvedTemplate(remoteTemplate))]
            }
        case .custom:
            remoteSources = [.init(kind: .template, template: resolvedTemplate(remoteTemplate))]
        case .yomitanJapanese:
            remoteSources = yomitanJapaneseSources
        case .yomitanEnglish:
            remoteSources = yomitanEnglishSources
        }

        for source in remoteSources where sources.contains(source) == false {
            sources.append(source)
        }
        return sources
    }

    static func normalizedLanguageCode(_ languageHint: String?) -> String? {
        guard let languageHint else { return nil }
        let trimmed = languageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized.split(separator: "-").first.map(String.init)
    }
}

actor ReaderLookupWordAudioPlayer {
    static let shared = ReaderLookupWordAudioPlayer()

    private var player: AVPlayer?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?

    func play(url: URL, mode: ReaderLookupAudioPlaybackMode) {
        stopPlayback(deactivateSession: false)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: categoryOptions(for: mode))
            try session.setActive(true, options: [])
        } catch {
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.stop() }
        }

        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.stop() }
        }

        player.play()
    }

    func stop() {
        stopPlayback(deactivateSession: true)
    }

    private func stopPlayback(deactivateSession: Bool) {
        player?.pause()
        player = nil

        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }

        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }

        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func categoryOptions(for mode: ReaderLookupAudioPlaybackMode) -> AVAudioSession.CategoryOptions {
        switch mode {
        case .interrupt:
            return []
        case .duck:
            return [.mixWithOthers, .duckOthers]
        case .mix:
            return [.mixWithOthers]
        }
    }
}

enum ReaderLookupAudioResolver {
    private struct AudioSourceResponse: Decodable {
        struct Item: Decodable {
            var name: String
            var url: String
        }

        var type: String
        var audioSources: [Item]
    }

    private struct WikimediaSearchResponse: Decodable {
        struct Query: Decodable {
            struct SearchItem: Decodable {
                var title: String
            }

            var search: [SearchItem]
        }

        var query: Query
    }

    private struct WikimediaFileResponse: Decodable {
        struct Query: Decodable {
            struct Page: Decodable {
                struct ImageInfo: Decodable {
                    var user: String
                    var url: String
                }

                var imageinfo: [ImageInfo]?
            }

            var pages: [String: Page]
        }

        var query: Query
    }

    static func resolveAudioURL(
        term: String,
        reading: String?,
        sources: [ReaderLookupAudioSourceDefinition]
    ) async -> URL? {
        for source in sources {
            if let url = await resolveAudioURL(term: term, reading: reading, source: source) {
                return url
            }
        }
        return nil
    }

    static func resolveAudioURL(
        term: String,
        reading: String?,
        source: ReaderLookupAudioSourceDefinition
    ) async -> URL? {
        let resolvedReading = normalizedReading(reading, fallback: term)
        do {
            switch source.kind {
            case .template:
                return try await resolveTemplateAudioURL(term: term, reading: resolvedReading, template: source.template)
            case .jpod101:
                return resolveJpod101AudioURL(term: term, reading: resolvedReading)
            case .languagePod101Japanese:
                return try await resolveLanguagePod101AudioURL(term: term, reading: resolvedReading, preset: .yomitanJapanese)
            case .languagePod101English:
                return try await resolveLanguagePod101AudioURL(term: term, reading: resolvedReading, preset: .yomitanEnglish)
            case .jisho:
                return try await resolveJishoAudioURL(term: term, reading: resolvedReading)
            case .linguaLibre:
                return try await resolveLinguaLibreAudioURL(term: term, iso6393: "eng")
            case .wiktionary:
                return try await resolveWiktionaryAudioURL(term: term, iso: "en")
            }
        } catch {
            return nil
        }
    }

    private static func resolveTemplateAudioURL(
        term: String,
        reading: String,
        template: String?
    ) async throws -> URL? {
        guard let template, template.isEmpty == false else {
            return nil
        }

        let target = template
            .replacingOccurrences(of: "{term}", with: term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term)
            .replacingOccurrences(of: "{reading}", with: reading.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reading)

        guard let requestURL = URL(string: target) else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: requestURL)
        let response = try JSONDecoder().decode(AudioSourceResponse.self, from: data)
        guard response.type == "audioSourceList",
              let first = response.audioSources.first else {
            return nil
        }
        return URL(string: first.url)
    }

    private static func resolveJpod101AudioURL(term: String, reading: String) -> URL? {
        var resolvedTerm = term
        var resolvedReading = reading
        if reading == term, isStringEntirelyKana(term) {
            resolvedTerm = ""
            resolvedReading = term
        }

        var components = URLComponents(string: "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php")
        var queryItems: [URLQueryItem] = []
        if resolvedTerm.isEmpty == false {
            queryItems.append(URLQueryItem(name: "kanji", value: resolvedTerm))
        }
        if resolvedReading.isEmpty == false {
            queryItems.append(URLQueryItem(name: "kana", value: resolvedReading))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private static func resolveLanguagePod101AudioURL(
        term: String,
        reading: String,
        preset: ReaderLookupRemoteAudioPreset
    ) async throws -> URL? {
        let language: String
        let podOrClass: String
        switch preset {
        case .yomitanJapanese:
            language = "Japanese"
            podOrClass = "pod"
        case .yomitanEnglish:
            language = "English"
            podOrClass = "class"
        case .custom:
            return nil
        }

        guard let fetchURL = URL(string: "https://www.\(language.lowercased())\(podOrClass)101.com/learningcenter/reference/dictionary_post") else {
            return nil
        }

        var request = URLRequest(url: fetchURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "post": "dictionary_reference",
            "match_type": "exact",
            "search_query": term,
            "vulgar": "true",
        ]
        request.httpBody = body
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let responseURL = (response as? HTTPURLResponse)?.url ?? response.url else {
            return nil
        }
        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        let snippets = matchedAudioSnippets(in: html)
        for snippet in snippets {
            let normalizedURL = URL(string: snippet.url, relativeTo: responseURL)?.absoluteURL
            switch preset {
            case .yomitanJapanese:
                if snippet.context.contains("dc-vocab_kana"),
                   snippet.context.contains(reading) {
                    return normalizedURL
                }
            case .yomitanEnglish:
                if let vocab = extractLanguagePod101Vocab(from: snippet.context),
                   normalizedLookupText(vocab) == normalizedLookupText(term) {
                    return normalizedURL
                }
            case .custom:
                break
            }
        }
        switch preset {
        case .yomitanJapanese:
            return snippets.first.flatMap { URL(string: $0.url, relativeTo: responseURL)?.absoluteURL }
        case .yomitanEnglish, .custom:
            return nil
        }
    }

    private static func resolveJishoAudioURL(term: String, reading: String) async throws -> URL? {
        let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
        guard let fetchURL = URL(string: "https://jisho.org/search/\(encodedTerm)") else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: fetchURL)
        guard let responseURL = (response as? HTTPURLResponse)?.url ?? response.url,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        let marker = "audio_\(term):\(reading)"
        guard let markerRange = html.range(of: marker) else {
            return nil
        }

        let snippetStart = html.distance(from: html.startIndex, to: markerRange.lowerBound)
        let startOffset = max(0, snippetStart - 200)
        let endOffset = min(html.count, snippetStart + 600)
        let snippetRange = html.index(html.startIndex, offsetBy: startOffset)..<html.index(html.startIndex, offsetBy: endOffset)
        let snippet = String(html[snippetRange])
        guard let sourceURL = firstCapturedGroup(in: snippet, pattern: #"<source[^>]+src=["']([^"']+)["']"#, options: [.caseInsensitive]) else {
            return nil
        }
        return URL(string: sourceURL, relativeTo: responseURL)?.absoluteURL
    }

    private static func resolveLinguaLibreAudioURL(term: String, iso6393: String) async throws -> URL? {
        let searchCategory = #"incategory:"Lingua_Libre_pronunciation-\#(iso6393)""#
        let searchString = "-\(term).wav"
        let searchQuery = "intitle:/\(searchString)/i+\(searchCategory)"
        guard let fetchURL = commonsSearchURL(searchQuery: searchQuery) else {
            return nil
        }

        return try await resolveWikimediaCommonsAudioURL(
            fetchURL: fetchURL,
            validate: { title, user in
                title.range(
                    of: #"^File:LL-Q\d+\s+\(\#(iso6393)\)-\#(NSRegularExpression.escapedPattern(for: user))-\#(NSRegularExpression.escapedPattern(for: term))\.wav$"#,
                    options: .regularExpression
                ) != nil
            }
        )
    }

    private static func resolveWiktionaryAudioURL(term: String, iso: String) async throws -> URL? {
        let searchString = "\(iso)(-[a-zA-Z]{2})?-\(term)[0123456789]*.ogg"
        guard let fetchURL = commonsSearchURL(searchQuery: "intitle:/\(searchString)/i") else {
            return nil
        }

        return try await resolveWikimediaCommonsAudioURL(
            fetchURL: fetchURL,
            validate: { title, _ in
                title.range(
                    of: #"^File:\#(iso)(-\w\w)?-\#(NSRegularExpression.escapedPattern(for: term))\d*\.ogg$"#,
                    options: .regularExpression
                ) != nil
            }
        )
    }

    private static func resolveWikimediaCommonsAudioURL(
        fetchURL: URL,
        validate: (String, String) -> Bool
    ) async throws -> URL? {
        let (data, _) = try await URLSession.shared.data(from: fetchURL)
        let response = try JSONDecoder().decode(WikimediaSearchResponse.self, from: data)

        for item in response.query.search {
            guard let fileInfoURL = commonsFileInfoURL(title: item.title) else {
                continue
            }
            let (fileData, _) = try await URLSession.shared.data(from: fileInfoURL)
            let fileResponse = try JSONDecoder().decode(WikimediaFileResponse.self, from: fileData)
            for page in fileResponse.query.pages.values {
                guard let imageInfo = page.imageinfo?.first,
                      validate(item.title, imageInfo.user) else {
                    continue
                }
                if let url = URL(string: imageInfo.url) {
                    return url
                }
            }
        }
        return nil
    }

    private static func commonsSearchURL(searchQuery: String) -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: searchQuery),
            URLQueryItem(name: "srnamespace", value: "6"),
            URLQueryItem(name: "origin", value: "*"),
        ]
        return components?.url
    }

    private static func commonsFileInfoURL(title: String) -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "user|url"),
            URLQueryItem(name: "origin", value: "*"),
        ]
        return components?.url
    }

    private static func normalizedReading(_ reading: String?, fallback term: String) -> String {
        let trimmed = reading?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? term : trimmed
    }

    private static func firstCapturedGroup(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func extractLanguagePod101Vocab(from snippet: String) -> String? {
        guard let rawValue = firstCapturedGroup(
            in: snippet,
            pattern: #"<[^>]*class=["'][^"']*\bdc-vocab\b[^"']*["'][^>]*>([\s\S]*?)</[^>]+>"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        return normalizedHTMLText(rawValue)
    }

    private static func normalizedHTMLText(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return decoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedLookupText(_ text: String) -> String {
        normalizedHTMLText(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func matchedAudioSnippets(in html: String) -> [(url: String, context: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<audio\b[\s\S]*?<source[^>]+src=["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let urlRange = Range(match.range(at: 1), in: html),
                  let contextRange = Range(match.range(at: 0), in: html) else {
                return nil
            }

            let lowerDistance = html.distance(from: html.startIndex, to: contextRange.lowerBound)
            let upperDistance = html.distance(from: html.startIndex, to: contextRange.upperBound)
            let snippetStart = max(0, lowerDistance - 500)
            let snippetEnd = min(html.count, upperDistance + 250)
            let snippetRange = html.index(html.startIndex, offsetBy: snippetStart)..<html.index(html.startIndex, offsetBy: snippetEnd)
            return (String(html[urlRange]), String(html[snippetRange]))
        }
    }

    private static func isStringEntirelyKana(_ text: String) -> Bool {
        guard text.isEmpty == false else {
            return false
        }

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
                continue
            case 0x30FC:
                continue
            default:
                return false
            }
        }
        return true
    }
}

@MainActor
final class ReaderLookupLocalAudioServer {
    static let shared = ReaderLookupLocalAudioServer()

    private static let port: UInt16 = 8765
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let defaultSources = ["nhk16", "daijisen", "shinmeikai8", "jpod", "jpod_alternate", "taas", "ozk5", "forvo", "forvo_ext", "forvo_ext2"]
    private static let emptyAudioResponse = Data(#"{"type":"audioSourceList","audioSources":[]}"#.utf8)

    private var listener: NWListener?
    private var enabled = false

    private init() {}

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else {
            if enabled {
                startServerIfNeeded()
            }
            return
        }

        self.enabled = enabled
        if enabled {
            startServerIfNeeded()
        } else {
            stopServer()
        }
    }

    private func startServerIfNeeded() {
        guard listener == nil else {
            return
        }

        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let listener = try? NWListener(using: .tcp, on: port) else {
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .failed = state {
                    self.listener = nil
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func stopServer() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            Task { @MainActor in
                self?.respond(to: connection, requestData: data ?? Data())
            }
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) {
        let request = parseRequest(from: requestData)
        if request.path == "/localaudio/get/" {
            sendAudioSources(for: request, to: connection)
        } else if request.path.hasPrefix("/localaudio/") {
            sendAudioFile(path: request.path, to: connection)
        } else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
        }
    }

    private func sendAudioSources(for request: Request, to connection: NWConnection) {
        let term = request.query["term"] ?? ""
        let rawReading = request.query["reading"] ?? ""
        let reading = katakanaToHiragana(rawReading)

        guard let dbURL = localAudioDatabaseURL() else {
            send(Self.emptyAudioResponse, status: "200 OK", contentType: "application/json", to: connection)
            return
        }

        var db: OpaquePointer?
        sqlite3_open(dbURL.path(percentEncoded: false), &db)
        defer { sqlite3_close(db) }

        let sortOrder = "CASE source " + Self.defaultSources.indices.map { "WHEN ? THEN \($0) " }.joined() + "ELSE 999 END"
        let sql: String
        if reading.isEmpty {
            sql = """
                SELECT source, file FROM entries
                WHERE expression = ? AND file LIKE '%.mp3'
                ORDER BY \(sortOrder)
                LIMIT 1;
                """
        } else {
            sql = """
                SELECT source, file FROM entries
                WHERE (expression = ? OR reading = ?) AND file LIKE '%.mp3'
                ORDER BY CASE WHEN reading = ? THEN 0 ELSE 1 END, \(sortOrder)
                LIMIT 1;
                """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            send(Self.emptyAudioResponse, status: "200 OK", contentType: "application/json", to: connection)
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, term, -1, Self.sqliteTransient)
        var bindIndex = 2
        if reading.isEmpty == false {
            sqlite3_bind_text(stmt, 2, reading, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, reading, -1, Self.sqliteTransient)
            bindIndex = 4
        }
        for (index, source) in Self.defaultSources.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + bindIndex), source, -1, Self.sqliteTransient)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let sourceBytes = sqlite3_column_text(stmt, 0),
              let fileBytes = sqlite3_column_text(stmt, 1) else {
            send(Self.emptyAudioResponse, status: "200 OK", contentType: "application/json", to: connection)
            return
        }

        let source = String(cString: sourceBytes)
        let file = String(cString: fileBytes)
        let encodedFile = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        let url = "http://localhost:\(Self.port)/localaudio/\(source)/\(encodedFile)"
        let response: [String: Any] = ["type": "audioSourceList", "audioSources": [["name": source, "url": url]]]
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Self.emptyAudioResponse
        send(data, status: "200 OK", contentType: "application/json", to: connection)
    }

    private func sendAudioFile(path: String, to connection: NWConnection) {
        let prefix = "/localaudio/"
        let tail = String(path.dropFirst(prefix.count))
        let parts = tail.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }

        let source = String(parts[0])
        let file = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        guard let dbURL = localAudioDatabaseURL() else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }

        var db: OpaquePointer?
        sqlite3_open(dbURL.path(percentEncoded: false), &db)
        defer { sqlite3_close(db) }

        let sql = "SELECT data FROM android WHERE source = ? AND file = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, source, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, file, -1, Self.sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(stmt, 0) else {
            send(Data(), status: "404 Not Found", contentType: "text/plain; charset=utf-8", to: connection)
            return
        }

        let count = Int(sqlite3_column_bytes(stmt, 0))
        let audioData = Data(bytes: bytes, count: count)
        send(audioData, status: "200 OK", contentType: "audio/mpeg", to: connection)
    }

    private func localAudioDatabaseURL() -> URL? {
        let selectedUser = AppUserStore.loadSelectedUser()
        let urls = AppUserStore.collectionURLs(for: selectedUser)
        let candidates = [
            urls.mediaDirectory.appendingPathComponent("Audio/android.db"),
            urls.directory.appendingPathComponent("Audio/android.db")
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
    }

    private func katakanaToHiragana(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> UnicodeScalar in
            let value = scalar.value
            if value >= 0x30A1 && value <= 0x30F6 {
                return UnicodeScalar(value - 0x60) ?? scalar
            }
            return scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func parseRequest(from requestData: Data) -> Request {
        guard let request = String(data: requestData, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            return Request(path: "/", query: [:])
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return Request(path: "/", query: [:])
        }

        let target = String(parts[1])
        let components = URLComponents(string: "http://localhost\(target)")
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return Request(path: components?.path ?? "/", query: query)
    }

    private func send(_ body: Data, status: String, contentType: String, to connection: NWConnection) {
        let header =
            "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct Request {
        let path: String
        let query: [String: String]
    }
}
