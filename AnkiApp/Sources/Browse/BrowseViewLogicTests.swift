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

    func testSortModeTitlesAndSymbolsExist() {
        for mode in BrowseSortMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
        }
    }

    func testSortBrowseNotesByModifiedDescending() {
        let notes = sampleNotes()
        let sorted = sortBrowseNotes(notes, mode: .modifiedDesc)
        XCTAssertEqual(sorted.map(\.id), [2, 3, 1])
    }

    func testSortBrowseNotesByModifiedAscending() {
        let notes = sampleNotes()
        let sorted = sortBrowseNotes(notes, mode: .modifiedAsc)
        XCTAssertEqual(sorted.map(\.id), [1, 3, 2])
    }

    func testSortBrowseNotesByCreatedDescending() {
        let notes = sampleNotes()
        let sorted = sortBrowseNotes(notes, mode: .createdDesc)
        XCTAssertEqual(sorted.map(\.id), [3, 2, 1])
    }

    func testSortBrowseNotesByCreatedAscending() {
        let notes = sampleNotes()
        let sorted = sortBrowseNotes(notes, mode: .createdAsc)
        XCTAssertEqual(sorted.map(\.id), [1, 2, 3])
    }

    func testBrowseViewInit() {
        let view = BrowseView()
        XCTAssertNotNil(view)
    }

    private func sampleNotes() -> [NoteRecord] {
        [
            NoteRecord(id: 1, guid: "a", mid: 1, mod: 100, flds: "A", sfld: "A", csum: 1),
            NoteRecord(id: 2, guid: "b", mid: 1, mod: 300, flds: "B", sfld: "B", csum: 2),
            NoteRecord(id: 3, guid: "c", mid: 1, mod: 200, flds: "C", sfld: "C", csum: 3)
        ]
    }
}
