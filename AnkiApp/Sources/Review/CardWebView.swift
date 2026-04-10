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
        <body><div class="card">\(html)</div></body>
        </html>
        """
        
        // Get media directory URL as baseURL for relative URL resolution
        let mediaDirectoryURL = getMediaDirectoryURL()
        webView.loadHTMLString(styledHTML, baseURL: mediaDirectoryURL)
    }
    
    /// Get the media directory URL for the currently selected user
    private func getMediaDirectoryURL() -> URL? {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "用户1"
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        
        guard let appSupport = appSupport else { return nil }
        
        let userFolder = sanitizedUserFolderName(selectedUser)
        let mediaDirectory = appSupport
            .appendingPathComponent("AnkiCollection", isDirectory: true)
            .appendingPathComponent(userFolder, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
        
        return mediaDirectory
    }
    
    /// Sanitize user folder name (matching AppUserStore logic)
    private func sanitizedUserFolderName(_ user: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }
        
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(mapped)
    }
}
