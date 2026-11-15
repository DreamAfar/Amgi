//
//  BrowseSortingTests.swift
//  BrowseFeatureTests
//
//  Created by Vladimir Gusev on 08.08.2026.
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation
import Testing
@testable import BrowseFeature

/// Sorting and filtering happen in the backend's query, so they cover every
/// match and not only the loaded rows. These tests pin that the model hands
/// the order and the filter terms to the search, restarts it when either
/// changes, and leaves the returned order alone.
@Suite("BrowseModel sorting and filtering")
@MainActor
struct BrowseSortingTests {

    private nonisolated static func note(_ id: Int64, sfld: String, mod: Int64 = 100) -> NoteRecord {
        NoteRecord(
            id: NoteID(id),
            guid: "g\(id)",
            mid: NotetypeID(1),
            mod: mod,
            tags: "",
            flds: "",
            sfld: sfld,
            csum: 0
        )
    }

    private final class Orders: @unchecked Sendable {
        private let lock = NSLock()
        private var orders: [NoteSortOrder] = []
        func record(_ order: NoteSortOrder) { lock.withLock { orders.append(order) } }
        var all: [NoteSortOrder] { lock.withLock { orders } }
    }

    @Test("the default order is most recently modified first")
    func defaultOrder() {
        #expect(BrowseModel().sort == NoteSortOrder(column: .modified, descending: true))
    }

    @Test("the search is given the chosen order")
    func searchReceivesTheOrder() async {
        let orders = Orders()
        await withDependencies {
            $0.noteClient.searchSorted = { _, order, _ in
                orders.record(order)
                return []
            }
        } operation: {
            let model = BrowseModel()
            model.sort = NoteSortOrder(column: .sortField, descending: false)
            await model.performSearch(debounce: .zero)
            #expect(orders.all == [NoteSortOrder(column: .sortField, descending: false)])
        }
    }

    @Test("the backend's order is kept as returned")
    func backendOrderIsKept() async {
        await withDependencies {
            $0.noteClient.searchSorted = { _, _, _ in
                [Self.note(1, sfld: "Zebra", mod: 1), Self.note(2, sfld: "apple", mod: 9)]
            }
        } operation: {
            let model = BrowseModel()
            await model.performSearch(debounce: .zero)
            #expect(model.sortedNotes.map(\.sfld) == ["Zebra", "apple"])
        }
    }

    @Test("changing the order or a filter changes the search key")
    func searchKeyTracksSortAndFilters() {
        let model = BrowseModel()
        let initial = model.searchKey

        model.sort.descending = false
        let resorted = model.searchKey
        #expect(resorted != initial)

        model.filters.state = .due
        #expect(model.searchKey != resorted)
    }

    @Test("a stub fill patches the row without moving it")
    func stubFillPatchesWithoutReordering() async {
        let resolved = Self.note(1, sfld: "Zebra", mod: 300)
        await withDependencies {
            $0.noteClient.fetch = { _ in resolved }
        } operation: {
            let model = BrowseModel()
            model.notes = [
                Self.note(1, sfld: "Loading...", mod: 0),
                Self.note(2, sfld: "Mango", mod: 200),
            ]
            await model.fetchNoteDetails(id: NoteID(1))
            #expect(model.sortedNotes.map(\.sfld) == ["Zebra", "Mango"])
        }
    }

    // MARK: Filters

    @Test("no filter adds no terms")
    func emptyFilters() {
        #expect(!BrowseFilters().isActive)
        #expect(BrowseFilters().searchTerms.isEmpty)
    }

    @Test("each filter contributes one search term")
    func filterTerms() {
        var filters = BrowseFilters()
        filters.state = .learning
        filters.flag = 0
        filters.notetypeID = NotetypeID(42)
        filters.recent = .againToday
        #expect(filters.isActive)
        #expect(filters.searchTerms == ["is:learn", "flag:0", "mid:42", "rated:1:1"])
    }

    @Test("filters join the deck, tag and text in the query")
    func filtersJoinTheQuery() {
        let model = BrowseModel()
        model.activeTag = "verb"
        model.filters.state = .suspended
        model.searchText = "kanji"
        #expect(model.searchQuery == "tag:\"verb\" is:suspended kanji")
    }

    @Test("sort columns use the backend's column keys")
    func columnKeys() {
        #expect(NoteSortColumn.sortField.rawValue == "noteFld")
        #expect(NoteSortColumn.created.rawValue == "noteCrt")
        #expect(NoteSortColumn.notetype.rawValue == "note")
        #expect(NoteSortColumn.cardCount.rawValue == "template")
    }
}
