//
//  ReaderFontScheme.swift
//  ReaderFeature
//

import AppShared
import Foundation
import WebKit

/// Serves the imported reader fonts to the reader web views for their
/// `@font-face` rules. Fonts are fetched cross-origin from the page, which
/// the font loader only accepts with a CORS header, so every response
/// carries one.
@MainActor
final class ReaderFontScheme: NSObject, WKURLSchemeHandler {
    /// In-flight reads by task. A stopped task must never be answered.
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let file = ReaderCustomFonts.fileURL(forRequest: url) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let key = ObjectIdentifier(urlSchemeTask)
        tasks[key] = Task { [weak self] in
            let data = try? await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: file, options: .mappedIfSafe)
            }.value
            guard let self, self.tasks[key] != nil, !Task.isCancelled else { return }
            self.tasks[key] = nil
            guard let data, let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": ReaderCustomFonts.mimeType(forFileName: file.lastPathComponent),
                    "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*",
                ]
            ) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
