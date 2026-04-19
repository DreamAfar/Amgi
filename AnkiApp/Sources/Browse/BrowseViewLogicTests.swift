import XCTest
@testable import AnkiApp

final class BrowseViewLogicTests: XCTestCase {

    func testQuickFilterQueries() {
        XCTAssertEqual(BrowseQuickFilter.all.query, "")
        XCTAssertEqual(BrowseQuickFilter.addedToday.query, "added:1")
        XCTAssertEqual(BrowseQuickFilter.studiedToday.query, "rated:1")
        XCTAssertEqual(BrowseQuickFilter.newCards.query, "is:new")
        XCTAssertEqual(BrowseQuickFilter.review.query, "is:review")
        XCTAssertEqual(BrowseQuickFilter.due.query, "prop:due<=0")
        XCTAssertEqual(BrowseQuickFilter.flag1.query, "flag:1")
        XCTAssertEqual(BrowseQuickFilter.flag7.query, "flag:7")
    }

    func testQuickFilterSymbolsAreDefined() {
        for filter in BrowseQuickFilter.allCases {
            XCTAssertFalse(filter.symbol.isEmpty)
        }
    }

    func testSortFieldTitlesAndSymbolsExist() {
        for field in BrowseSortField.allCases {
            XCTAssertFalse(field.title.isEmpty)
            XCTAssertFalse(field.symbol.isEmpty)
            XCTAssertFalse(field.backendColumn.isEmpty)
        }
    }

    func testBrowseViewInit() {
        let view = BrowseView()
        XCTAssertNotNil(view)
    }
}
