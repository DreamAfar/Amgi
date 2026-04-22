import XCTest
@testable import AnkiApp

final class RichNoteFieldEditorTests: XCTestCase {
    func testNormalizesInlineAnkiMathJaxToStoredDelimiters() {
        XCTAssertEqual(
            RichNoteFieldEditor.normalizedStoredHTML(#"<anki-mathjax> a^2 + b^2 = c^2 </anki-mathjax>"#),
            #"\( a^2 + b^2 = c^2 \)"#
        )
    }

    func testNormalizesBlockAnkiMathJaxToStoredDelimiters() {
        XCTAssertEqual(
            RichNoteFieldEditor.normalizedStoredHTML(#"<anki-mathjax block="true"><br>a^2 + b^2 = c^2<br></anki-mathjax>"#),
            #"\[a^2 + b^2 = c^2\]"#
        )
    }
}
