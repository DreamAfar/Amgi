import XCTest
@testable import AnkiApp

final class ReaderLookupNoteTemplateTests: XCTestCase {
    func testMakeDraftMapsConfiguredHandlebars() {
        let template = ReaderLookupNoteTemplate(
            deckID: 42,
            notetypeID: 24,
            fieldMappings: [
                "Expression": ReaderLookupHandlebar.expression.rawValue,
                "Meaning": ReaderLookupHandlebar.glossary.rawValue,
                "Sentence": ReaderLookupHandlebar.sentence.rawValue,
                "Pitch": ReaderLookupHandlebar.pitchPositions.rawValue,
            ],
            tags: "reader mined"
        )

        let draft = template.makeDraft(
            content: [
                "expression": "単語",
                "matched": "単語",
                "glossary": "<ul><li>释义</li></ul>",
                "pitchPositions": "<span>[1]</span>",
            ],
            context: ReaderLookupMiningContext(
                sentence: "単語を覚える。",
                documentTitle: "标题",
                coverURL: nil
            ),
            fallbackDeckID: 100
        )

        XCTAssertEqual(draft.deckID, 42)
        XCTAssertEqual(draft.notetypeID, 24)
        XCTAssertEqual(draft.fieldValues["Expression"], "単語")
        XCTAssertEqual(draft.fieldValues["Meaning"], "<ul><li>释义</li></ul>")
        XCTAssertEqual(draft.fieldValues["Sentence"], "<b>単語</b>を覚える。")
        XCTAssertEqual(draft.fieldValues["Pitch"], "<span>[1]</span>")
        XCTAssertEqual(draft.tags, ["reader", "mined"])
    }

    func testDecodeMigratesLegacyTemplateShape() {
        let legacy = """
        {"deckID":1,"notetypeID":2,"termField":"Front","readingField":"Back","definition1Field":"Meaning","sourceField":"Source"}
        """

        let template = ReaderLookupNoteTemplate.decode(from: legacy)

        XCTAssertEqual(template.deckID, 1)
        XCTAssertEqual(template.notetypeID, 2)
        XCTAssertEqual(template.fieldMappings["Front"], ReaderLookupHandlebar.expression.rawValue)
        XCTAssertEqual(template.fieldMappings["Back"], ReaderLookupHandlebar.reading.rawValue)
        XCTAssertEqual(template.fieldMappings["Meaning"], ReaderLookupHandlebar.glossary.rawValue)
        XCTAssertEqual(template.fieldMappings["Source"], ReaderLookupHandlebar.documentTitle.rawValue)
    }

    func testMakeDraftSupportsSingleGlossaryAndStoredBookCoverMarkup() {
        let template = ReaderLookupNoteTemplate(
            fieldMappings: [
                "Dictionary": "{single-glossary-大辞泉}",
                "Cover": ReaderLookupHandlebar.bookCover.rawValue,
            ]
        )

        let draft = template.makeDraft(
            content: [
                "singleGlossaries": #"{"大辞泉":"<p>词典释义</p>"}"#,
                "bookCover": #"<img src="reader-cover.png">"#,
            ],
            context: ReaderLookupMiningContext(
                sentence: "",
                documentTitle: nil,
                coverURL: URL(string: "file:///unused-cover.png")
            ),
            fallbackDeckID: nil
        )

        XCTAssertEqual(draft.fieldValues["Dictionary"], "<p>词典释义</p>")
        XCTAssertEqual(draft.fieldValues["Cover"], #"<img src="reader-cover.png">"#)
    }
}
