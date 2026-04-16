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

    func testCardWrapperFileUsesHiddenFileInMediaRoot() {
        let mediaDir = URL(fileURLWithPath: "/tmp/anki-media", isDirectory: true)
        let wrapperFile = CardWebView.cardWrapperFileURL(in: mediaDir)

        XCTAssertEqual(wrapperFile.lastPathComponent, ".amgi-card-wrapper.html")
        XCTAssertEqual(wrapperFile.deletingLastPathComponent(), mediaDir)
    }
}