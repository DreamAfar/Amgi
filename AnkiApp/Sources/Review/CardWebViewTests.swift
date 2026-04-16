import XCTest
@testable import AnkiApp

final class CardWebViewTests: XCTestCase {
    func testMediaBaseTagPointsAtMediaRoot() {
        let mediaDir = URL(fileURLWithPath: "/tmp/anki-media", isDirectory: true)

        XCTAssertEqual(
            CardWebView.mediaBaseTag(for: mediaDir),
            #"<base href="file:///tmp/anki-media/">"#
        )
    }

    func testCardWrapperFileUsesPrivateRenderCacheDirectory() {
        let mediaDir = URL(fileURLWithPath: "/tmp/anki-media", isDirectory: true)
        let wrapperDirectory = CardWebView.cardWrapperDirectoryURL(in: mediaDir)
        let wrapperFile = CardWebView.cardWrapperFileURL(in: mediaDir)

        XCTAssertEqual(wrapperDirectory.lastPathComponent, ".amgi-render-cache")
        XCTAssertEqual(wrapperFile.lastPathComponent, "card.html")
        XCTAssertEqual(wrapperFile.deletingLastPathComponent(), wrapperDirectory)
        XCTAssertEqual(wrapperDirectory.deletingLastPathComponent(), mediaDir)
    }
}