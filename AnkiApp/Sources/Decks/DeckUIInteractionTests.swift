import XCTest
@testable import AnkiApp
import AnkiKit
import AnkiProto

final class DeckUIInteractionTests: XCTestCase {

    func testDeckTemplateListViewInit() {
        let view = DeckTemplateListView()
        XCTAssertNotNil(view)
    }

    func testDeckDetailViewInit() {
        let deck = DeckInfo(
            id: 1001,
            name: "Default",
            counts: .init(newCount: 1, learnCount: 2, reviewCount: 3)
        )
        let view = DeckDetailView(deck: deck)
        XCTAssertNotNil(view)
    }

    func testBrowseViewInit() {
        let view = BrowseView()
        XCTAssertNotNil(view)
    }

    func testCustomStudyRequestForNewLimitDelta() {
        let request = makeDeckCustomStudyRequest(
            deckID: 42,
            mode: .newLimit,
            amount: 12,
            cramKind: .new,
            includeTags: [],
            excludeTags: []
        )

        XCTAssertEqual(request.deckID, 42)
        XCTAssertEqual(request.value, .newLimitDelta(12))
    }

    func testCustomStudyRequestForCramSortsTags() {
        let request = makeDeckCustomStudyRequest(
            deckID: 9,
            mode: .cram,
            amount: 100,
            cramKind: .review,
            includeTags: ["b", "a"],
            excludeTags: ["z", "m"]
        )

        XCTAssertEqual(request.deckID, 9)
        XCTAssertEqual(request.cram.kind, .review)
        XCTAssertEqual(request.cram.cardLimit, 100)
        XCTAssertEqual(request.cram.tagsToInclude, ["a", "b"])
        XCTAssertEqual(request.cram.tagsToExclude, ["m", "z"])
    }

    func testCustomStudyAutoStartReviewModes() {
        XCTAssertFalse(shouldAutoStartReview(for: .newLimit))
        XCTAssertFalse(shouldAutoStartReview(for: .reviewLimit))
        XCTAssertTrue(shouldAutoStartReview(for: .forgot))
        XCTAssertTrue(shouldAutoStartReview(for: .ahead))
        XCTAssertTrue(shouldAutoStartReview(for: .preview))
        XCTAssertTrue(shouldAutoStartReview(for: .cram))
    }

    func testSortDeckTemplateEntriesByName() {
        var a = Anki_Notetypes_NotetypeNameId()
        a.id = 2
        a.name = "Basic"

        var b = Anki_Notetypes_NotetypeNameId()
        b.id = 1
        b.name = "Cloze"

        let sorted = sortDeckTemplateEntries([b, a])
        XCTAssertEqual(sorted.map(\.name), ["Basic", "Cloze"])
    }

    func testFilterDeckTemplateEntriesBySearchText() {
        var a = Anki_Notetypes_NotetypeNameId()
        a.id = 1
        a.name = "Basic"

        var b = Anki_Notetypes_NotetypeNameId()
        b.id = 2
        b.name = "Japanese Cloze"

        let filtered = filterDeckTemplateEntries([a, b], searchText: "japanese")
        XCTAssertEqual(filtered.map(\.name), ["Japanese Cloze"])
    }
}
