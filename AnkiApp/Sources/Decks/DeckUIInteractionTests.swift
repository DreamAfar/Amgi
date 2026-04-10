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
