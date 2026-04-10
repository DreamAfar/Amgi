import XCTest
@testable import AnkiApp
import AnkiKit

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
}
