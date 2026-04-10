import SwiftUI
import WebKit
import Foundation

struct CardWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Enable media playback without user interaction
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Convert Anki [sound:filename.mp3] tags to <audio> HTML elements.
        // The Rust renderer keeps these tags literal; the client must expand them.
        let processedHTML = Self.expandSoundTags(html)

        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
            body {
                font-family: -apple-system, system-ui;
                font-size: 18px;
                line-height: 1.5;
                color: #f5f5f5;
                background: transparent;
                padding: 16px;
                margin: 0;
                text-align: center;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 80vh;
            }
            .card { max-width: 600px; width: 100%; }
            hr { border: none; border-top: 1px solid rgba(255,255,255,0.2); margin: 16px 0; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            audio {
                width: 100%;
                max-width: 400px;
                margin: 8px auto;
                display: block;
                border-radius: 8px;
            }
            video {
                max-width: 100%;
                height: auto;
                border-radius: 8px;
                margin: 8px 0;
            }
            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a; }
                hr { border-top-color: rgba(0,0,0,0.2); }
            }
        </style>
        </head>
        <body><div class="card">\(processedHTML)</div></body>
        </html>
        """
        
        // Use the current user's media directory as baseURL so relative src paths resolve.
        let baseURL = Self.currentMediaDirectoryURL()
        webView.loadHTMLString(styledHTML, baseURL: baseURL)
    }

    // MARK: - Helpers

    /// Converts Anki `[sound:filename.ext]` markers to HTML `<audio controls>` elements.
    private static func expandSoundTags(_ html: String) -> String {
        // Pattern: [sound:anything_without_closing_bracket]
        guard let regex = try? NSRegularExpression(
            pattern: #"\[sound:([^\]]+)\]"#, options: []
        ) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(
            in: html, range: range,
            withTemplate: "<audio src=\"$1\" controls></audio>"
        )
    }

    /// Returns the media directory URL for the currently selected user.
    /// Mirrors AppUserStore.collectionURLs(for:) exactly so paths always match.
    private static func currentMediaDirectoryURL() -> URL? {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "用户1"
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }

        let userFolder = sanitizedFolderName(selectedUser)
        return appSupport
            .appendingPathComponent("AnkiCollection", isDirectory: true)
            .appendingPathComponent(userFolder, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
    }

    /// Must match AppUserStore.sanitizedUserFolderName exactly (including underscore trimming).
    private static func sanitizedFolderName(_ user: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let folder = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return folder.isEmpty ? "default" : folder
    }
}
