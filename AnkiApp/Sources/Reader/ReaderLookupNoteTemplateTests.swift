import XCTest
import AnkiReader
@testable import AnkiApp

final class ReaderLookupNoteTemplateTests: XCTestCase {
    func testDefinitionsByDictionaryPreservesDictionaryOrder() {
        let glossaries = [
            DictionaryLookupGlossary(dictionary: "词典A", definitions: ["A1", "A2"]),
            DictionaryLookupGlossary(dictionary: "词典B", definitions: ["B1"]),
            DictionaryLookupGlossary(dictionary: "词典A", definitions: ["A3"]),
        ]

        XCTAssertEqual(
            ReaderLookupNotePayload.definitionsByDictionary(from: glossaries),
            ["A1\nA2\nA3", "B1"]
        )
    }

    func testMakeDraftMapsDefinitionFieldsByDictionaryGroup() {
        let payload = ReaderLookupNotePayload(
            term: "単語",
            reading: "たんご",
            sentence: "例句",
            definitions: ["词典1-释义1\n词典1-释义2", "词典2-释义1", "词典3-释义1"],
            dictionaries: "词典1, 词典2, 词典3",
            frequency: nil,
            pitch: nil,
            deinflection: nil,
            matched: nil,
            source: nil,
            rules: nil
        )
        let template = ReaderLookupNoteTemplate(
            definition1Field: "Def1",
            definition2Field: "Def2",
            definition3Field: "Def3"
        )

        let draft = template.makeDraft(
            payload: payload,
            fallbackDeckID: nil,
            sourceDescription: "来源"
        )

        XCTAssertEqual(draft.fieldValues["Def1"], "词典1-释义1\n词典1-释义2")
        XCTAssertEqual(draft.fieldValues["Def2"], "词典2-释义1")
        XCTAssertEqual(draft.fieldValues["Def3"], "词典3-释义1")
    }
}
