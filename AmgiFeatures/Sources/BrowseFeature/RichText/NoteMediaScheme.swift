//
//  NoteMediaScheme.swift
//  BrowseFeature
//

#if canImport(UIKit)
import AnkiClients
import Dependencies
import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the collection's media folder to the note field editor's pages,
/// so an `<img src="name.jpg">` in a field shows the image. Pages load
/// with `baseURL`, which makes a bare filename resolve to this scheme.
@MainActor
final class NoteMediaScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "amgi-note-media"
    static let baseURL = URL(string: "amgi-note-media://media/")

    /// In-flight reads, keyed by task identity. A stopped task must never
    /// be answered — WebKit raises an uncatchable exception if it is.
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    @Dependency(\.mediaClient) private var mediaClient

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let name = Self.filename(in: url),
              let folder = mediaClient.folderURL() else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let fileURL = folder.appendingPathComponent(name)
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let key = ObjectIdentifier(urlSchemeTask)
        tasks[key] = Task { [weak self] in
            let data = try? await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: fileURL, options: .mappedIfSafe)
            }.value
            guard let self, self.tasks[key] != nil, !Task.isCancelled else { return }
            self.tasks[key] = nil
            guard let data else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let response = URLResponse(
                url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    /// The media filename a request names. Media files sit flat in the
    /// folder, so only the last path component counts — a path can't reach
    /// outside it.
    nonisolated static func filename(in url: URL) -> String? {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else { return nil }
        return name
    }
}
#endif
