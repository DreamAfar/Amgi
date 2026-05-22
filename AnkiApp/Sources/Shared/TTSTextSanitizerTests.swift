import XCTest
@testable import AnkiApp

final class TTSTextSanitizerTests: XCTestCase {
    func testSanitizedTextRemovesHTMLTagsAndPreservesBreaks() {
        let source = "第一行<br>第二行<p>第三行</p><div>第四行</div>"

        XCTAssertEqual(
            TTSTextSanitizer.sanitizedText(from: source),
            "第一行 第二行 第三行 第四行"
        )
    }

    func testSanitizedTextStripsRubyAndGenericTags() {
        let source = "<ruby><rb>漢</rb><rt>かん</rt></ruby>"

        XCTAssertEqual(
            TTSTextSanitizer.sanitizedText(from: source),
            "漢かん"
        )
    }

    func testSanitizedTextDecodesEscapedHTMLBeforeRemovingTags() {
        let source = "Hello &lt;br&gt; world &amp; more"

        XCTAssertEqual(
            TTSTextSanitizer.sanitizedText(from: source),
            "Hello world & more"
        )
    }

    func testSanitizedTextDoesNotTreatComparisonOperatorsAsHTML() {
        let source = "1 < 2 &amp; 3 > 1"

        XCTAssertEqual(
            TTSTextSanitizer.sanitizedText(from: source),
            "1 < 2 & 3 > 1"
        )
    }
}
