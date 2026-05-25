import XCTest
@testable import AnkiApp
import AnkiKit

final class ReviewAINoteTemplateTests: XCTestCase {
    func testMakeDraftFormatsSelectedTextInsideSentence() {
        let template = ReviewAINoteTemplate(
            deckID: 42,
            notetypeID: 7,
            fieldMappings: [
                "Sentence": ReviewAINoteTemplateToken.sentence.rawValue,
                "Back": ReviewAINoteTemplateToken.answer.rawValue,
            ],
            tags: "ai review-ai",
            selectionFormats: [.bold, .highlight, .italic]
        )

        let draft = template.makeDraft(
            context: ReviewAIQueryContext(
                selectedText: "market",
                sentence: "He opened the market in Italy.",
                source: "Lesson 1"
            ),
            answer: "<p>解释</p>",
            fallbackDeckID: nil
        )

        XCTAssertEqual(draft.deckID, 42)
        XCTAssertEqual(draft.notetypeID, 7)
        XCTAssertEqual(
            draft.fieldValues["Sentence"],
            "He opened the <i><mark><b>market</b></mark></i> in Italy."
        )
        XCTAssertEqual(draft.fieldValues["Back"], "<p>解释</p>")
        XCTAssertEqual(draft.tags, ["ai", "review-ai"])
    }

    func testDecodeLegacyTemplateDefaultsSelectionFormatsToEmpty() {
        let legacy = """
        {"deckID":1,"notetypeID":2,"fieldMappings":{"Sentence":"{sentence}"},"tags":"ai review-ai"}
        """

        let template = try? JSONDecoder().decode(
            ReviewAINoteTemplate.self,
            from: Data(legacy.utf8)
        )

        XCTAssertEqual(template?.deckID, 1)
        XCTAssertEqual(template?.notetypeID, 2)
        XCTAssertEqual(template?.selectionFormats, [])
    }
}