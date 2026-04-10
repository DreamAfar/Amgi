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
        <meta charset="UTF-8">
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
            .sound-btn {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                margin: 4px;
            }
            .sound-btn audio { display: none; }
            .replay-btn {
                background: rgba(255,255,255,0.15);
                border: 1px solid rgba(255,255,255,0.3);
                color: inherit;
                border-radius: 50%;
                width: 44px;
                height: 44px;
                font-size: 18px;
                cursor: pointer;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                -webkit-tap-highlight-color: transparent;
            }
            .replay-btn:active { background: rgba(255,255,255,0.3); }
            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a; }
                hr { border-top-color: rgba(0,0,0,0.2); }
                .replay-btn { background: rgba(0,0,0,0.08); border-color: rgba(0,0,0,0.2); }
            }
            video {
                max-width: 100%;
                height: auto;
                border-radius: 8px;
                margin: 8px 0;
            }
            .missing-media {
                display: inline-block;
                background: rgba(255,60,60,0.15);
                border: 1px dashed rgba(255,60,60,0.5);
                border-radius: 6px;
                padding: 6px 10px;
                margin: 4px;
                font-size: 13px;
                color: rgba(255,100,100,0.9);
            }
            @media (prefers-color-scheme: light) {
                .missing-media { background: rgba(255,60,60,0.08); color: rgba(200,40,40,0.8); }
            }
        </style>
        <script>
        function playSound(btn) {
            var audio = btn.previousElementSibling;
            if (audio.paused || audio.ended) {
                audio.currentTime = 0;
                audio.play();
                btn.textContent = '⏸';
                audio.onended = function() { btn.textContent = '▶'; };
            } else {
                audio.pause();
                audio.currentTime = 0;
                btn.textContent = '▶';
            }
        }
        window.onload = function() {
            var first = document.querySelector('.sound-btn audio');
            if (first) { first.play(); }
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
        };
        </script>
        </head>
        <body><div class="card">\(processedHTML)</div></body>
        </html>
        """

        // WKWebView.loadHTMLString does NOT grant file system access for local
        // resources (images, audio). We must write the HTML to a file inside
        // the media directory and use loadFileURL with allowingReadAccessTo so
        // that relative src paths (e.g. <img src="image.jpg">) resolve correctly.
        guard let mediaDir = Self.currentMediaDirectoryURL() else {
            webView.loadHTMLString(styledHTML, baseURL: nil)
            return
        }
        let htmlFile = mediaDir.appendingPathComponent("_card.html")
        do {
            try styledHTML.write(to: htmlFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(htmlFile, allowingReadAccessTo: mediaDir)
        } catch {
            webView.loadHTMLString(styledHTML, baseURL: nil)
        }
    }

    // MARK: - Helpers

    /// Converts Anki `[sound:filename.ext]` markers to a hidden `<audio>` + styled play button.
    private static func expandSoundTags(_ html: String) -> String {
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
            let replacement = "<span class=\"sound-btn\"><audio src=\"\(encoded)\" preload=\"auto\"></audio><button class=\"replay-btn\" onclick=\"playSound(this)\">▶</button></span>"
            result.replaceSubrange(matchRange, with: replacement)
        }
        return result
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
