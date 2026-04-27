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

enum ReaderLookupAudioDefaults {
    static let defaultTemplate = "https://hoshi-reader.manhhaoo-do.workers.dev/?term={term}&reading={reading}"
    static let localAudioURL = "http://localhost:8765/localaudio/get/?term={term}&reading={reading}"

    static func resolvedTemplate(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTemplate : trimmed
    }

    static func resolvedPlaybackMode(_ rawValue: String) -> ReaderLookupAudioPlaybackMode {
        ReaderLookupAudioPlaybackMode(rawValue: rawValue) ?? .interrupt
    }

    static func sourceTemplates(
        remoteTemplate: String,
        localAudioEnabled: Bool
    ) -> [String] {
        var templates: [String] = []
        if localAudioEnabled {
            templates.append(localAudioURL)
        }

        let resolvedRemote = resolvedTemplate(remoteTemplate)
        if templates.contains(resolvedRemote) == false {
            templates.append(resolvedRemote)
        }
        return templates
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

    static func resolveAudioURL(
        term: String,
        reading: String?,
        remoteTemplate: String,
        localAudioEnabled: Bool
    ) async -> URL? {
        let templates = ReaderLookupAudioDefaults.sourceTemplates(
            remoteTemplate: remoteTemplate,
            localAudioEnabled: localAudioEnabled
        )

        for template in templates {
            let target = template
                .replacingOccurrences(of: "{term}", with: term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term)
                .replacingOccurrences(of: "{reading}", with: (reading ?? term).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? (reading ?? term))

            guard let requestURL = URL(string: target) else {
                continue
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: requestURL)
                let response = try JSONDecoder().decode(AudioSourceResponse.self, from: data)
                if response.type == "audioSourceList",
                   let first = response.audioSources.first,
                   let url = URL(string: first.url) {
                    return url
                }
            } catch {
                continue
            }
        }

        return nil
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
