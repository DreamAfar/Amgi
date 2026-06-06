import XCTest
@testable import AnkiApp
import AnkiProto
import WebKit

final class CardWebViewTests: XCTestCase {
    func testExpandTTSTagsCreatesReplayButtonMarkup() {
        let html = #"[anki:tts lang=zh_CN voices=Tingting speed=1.2]你好[/anki:tts]"#

        let expanded = CardWebView.expandTTSTags(
            in: html,
            isDarkMode: false,
            showReplayButtons: true
        )

        XCTAssertTrue(expanded.contains("class=\"replay-button replay-btn tts-btn\""))
        XCTAssertTrue(expanded.contains("data-tts-text=\"你好\""))
        XCTAssertTrue(expanded.contains("data-tts-lang=\"zh_CN\""))
        XCTAssertTrue(expanded.contains("data-tts-voices=\"Tingting\""))
        XCTAssertTrue(expanded.contains("data-tts-speed=\"1.2\""))
    }

    func testExpandTTSTagsRemovesDirectiveWhenReplayButtonsDisabled() {
        let html = #"[anki:tts lang=zh_CN]提示[/anki:tts]"#

        let expanded = CardWebView.expandTTSTags(
            in: html,
            isDarkMode: false,
            showReplayButtons: false
        )

        XCTAssertEqual(expanded, "")
    }

    func testExpandPlayTagsBuildsStructuredAudioButtonMarkup() {
        var tag = Anki_CardRendering_AVTag()
        tag.soundOrVideo = "https://example.com/test.mp3"

        let expanded = CardWebView.expandPlayTags(
            in: #"[anki:play:q:0]"#,
            questionAVTags: [tag],
            answerAVTags: [],
            isDarkMode: false,
            showReplayButtons: true
        )

        XCTAssertTrue(expanded.contains("class=\"sound-btn soundLink\""))
        XCTAssertTrue(expanded.contains("data-av-kind=\"audio\""))
        XCTAssertTrue(expanded.contains("test.mp3"))
        XCTAssertTrue(expanded.contains("amgiPlayStructuredNode(this)"))
    }

    func testExpandPlayTagsMarksVideoResourcesAsVideo() {
        var tag = Anki_CardRendering_AVTag()
        tag.soundOrVideo = "demo.mp4"

        let expanded = CardWebView.expandPlayTags(
            in: #"[anki:play:a:0]"#,
            questionAVTags: [],
            answerAVTags: [tag],
            isDarkMode: false,
            showReplayButtons: true
        )

        XCTAssertTrue(expanded.contains("<video"))
        XCTAssertTrue(expanded.contains("class=\"amgi-inline-video\""))
        XCTAssertTrue(expanded.contains("controls"))
        XCTAssertTrue(expanded.contains("playsinline"))
        XCTAssertTrue(expanded.contains("data-av-kind=\"video\""))
        XCTAssertTrue(expanded.contains("src=\"demo.mp4\""))
    }

    func testExpandSoundTagsRendersLegacyVideoAsInlineVideo() {
        let expanded = CardWebView.expandSoundTags(
            "[sound:demo.mp4]",
            isDarkMode: false,
            showReplayButtons: true
        )

        XCTAssertTrue(expanded.contains("<video"))
        XCTAssertTrue(expanded.contains("class=\"amgi-inline-video\""))
        XCTAssertTrue(expanded.contains("data-av-kind=\"video\""))
        XCTAssertTrue(expanded.contains("src=\"demo.mp4\""))
    }

    func testExpandPlayTagsKeepsHiddenTtsMarkerWhenReplayButtonsDisabled() {
        var tts = Anki_CardRendering_TTSTag()
        tts.fieldText = "提示"
        tts.lang = "zh_CN"
        var tag = Anki_CardRendering_AVTag()
        tag.tts = tts

        let expanded = CardWebView.expandPlayTags(
            in: #"[anki:play:q:0]"#,
            questionAVTags: [tag],
            answerAVTags: [],
            isDarkMode: false,
            showReplayButtons: false
        )

        XCTAssertTrue(expanded.contains("class=\"amgi-av-tag tts-tag\""))
        XCTAssertTrue(expanded.contains("data-tts-text=\"提示\""))
    }

    func testExpandPlayTagsBuildsStructuredTtsButtonMarkup() {
        var tts = Anki_CardRendering_TTSTag()
        tts.fieldText = "提示"
        tts.lang = "zh_CN"
        var tag = Anki_CardRendering_AVTag()
        tag.tts = tts

        let expanded = CardWebView.expandPlayTags(
            in: #"[anki:play:q:0]"#,
            questionAVTags: [tag],
            answerAVTags: [],
            isDarkMode: false,
            showReplayButtons: true
        )

        XCTAssertTrue(expanded.contains("class=\"replay-button replay-btn tts-btn\""))
        XCTAssertTrue(expanded.contains("data-av-kind=\"tts\""))
        XCTAssertTrue(expanded.contains("amgiPlayStructuredNode(this)"))
    }

    func testMediaBaseTagPointsAtMediaRoot() {
        let mediaDir = URL(fileURLWithPath: "/tmp/anki-media", isDirectory: true)

        XCTAssertEqual(
            CardWebView.mediaBaseTag(for: mediaDir),
            #"<base href="file:///tmp/anki-media/">"#
        )
    }

    func testCardWrapperFileUsesHiddenFileInMediaRoot() {
        let mediaDir = URL(fileURLWithPath: "/tmp/anki-media", isDirectory: true)
        let wrapperFile = CardWebView.cardWrapperFileURL(in: mediaDir)

        XCTAssertEqual(wrapperFile.lastPathComponent, ".amgi-card-wrapper.html")
        XCTAssertEqual(wrapperFile.deletingLastPathComponent(), mediaDir)
    }

    func testMathJaxBootstrapScriptTagsIncludeConfigAndCoreScripts() {
        let tags = CardWebView.mathJaxBootstrapScriptTags()

        XCTAssertTrue(tags.contains(CardAssetPath.mathJaxConfigScriptURLString))
        XCTAssertTrue(tags.contains(CardAssetPath.mathJaxCoreScriptURLString))
        XCTAssertTrue(tags.contains("data-amgi-mathjax=\"config\""))
        XCTAssertTrue(tags.contains("data-amgi-mathjax=\"core\""))
        XCTAssertTrue(tags.contains("onload=\"this.dataset.amgiLoaded='1'\""))
    }

    func testInnerTextCompatibilityBootstrapFallsBackForDisplayNone() {
        let script = CardWebView.innerTextCompatibilityBootstrapScript()

        XCTAssertTrue(script.contains("__amgiInnerTextPatched"))
        XCTAssertTrue(script.contains("style.display === 'none'"))
        XCTAssertTrue(script.contains("return this.textContent || ''"))
    }

    @MainActor
    func testInnerTextCompatibilityBootstrapWorksInWKWebView() async throws {
        let delegate = TestNavigationDelegate()
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = delegate

        let loaded = expectation(description: "webview-loaded")
        delegate.didFinish = {
            loaded.fulfill()
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <body>
            <div id="options" style="display: none">A***B***C</div>
            <script>
            \(CardWebView.innerTextCompatibilityBootstrapScript())
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 2.0)

        let value = try await webView.evaluateJavaScript("document.getElementById('options').innerText") as? String
        XCTAssertEqual(value, "A***B***C")
    }
}

private final class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish?()
    }
}
