//
//  BrowseModel.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 22.06.2026.
//

import AppCore
import AppShared
import AnkiClients
import AnkiBackend
import AnkiKit
import AnkiServices
import Dependencies
import Foundation
import OSLog

/// Data state + load/search/mutation logic for the Browse screen. Mirrors
/// `DeckListModel`: the View owns navigation, sheets, selection, and the
/// toolbar, while the model owns I/O, paging, and query assembly so that
/// logic is testable in isolation and the View stays a thin presentation
/// wiring layer.
@Observable
@MainActor
final class BrowseModel {
    var searchText = ""
    /// Surfaced when a batch mutation partially or wholly fails.
    var errorMessage: String?
    var allNotes: [NoteRecord] = []
    /// The loaded rows, in the backend's order for `sort`.
    var notes: [NoteRecord] = []
    var allDecks: [DeckInfo] = []
    /// The top-level parent deck selected (stays set even when drilling into subdecks).
    var parentDeck: DeckInfo?
    /// The actual deck filter applied (could be parent or a subdeck).
    var activeDeck: DeckInfo?
    var isLoading = false
    /// True when the last search threw, so the empty state can say "search
    /// failed" rather than "no results".
    private(set) var searchFailed = false
    var hasMorePages = true
    var allTags: [String] = []
    var activeTag: String?
    /// Applied by the backend's query, so it orders every match — not just
    /// the rows loaded so far, which is all a client-side sort could see.
    var sort: NoteSortOrder = .modifiedNewestFirst
    var filters = BrowseFilters()
    var notetypeNames: [NotetypeID: String] = [:]

    /// First card of each note, resolved lazily by the row context menu.
    /// Cached here rather than in per-row `@State` so a row scrolling out and
    /// back doesn't re-issue the backend lookup.
    ///
    /// `@ObservationIgnored` on purpose: rows hold the resolved value in their
    /// own `@State` and reach this only through `firstCardID(for:)`. Observed,
    /// one row's entry landing would invalidate the menu button of every other
    /// row reading the dictionary — N writes fanning out to N rows on a scroll.
    @ObservationIgnored private var firstCardIDs: [NoteID: CardID] = [:]

    private let pageSize = 50

    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.collectionStore) private var store
    @ObservationIgnored @Dependency(\.deckClient) private var deckClient
    @ObservationIgnored @Dependency(\.cardClient) private var cardClient
    @ObservationIgnored @Dependency(\.tagClient) private var tagClient
    @ObservationIgnored @Dependency(\.notetypesService) private var notetypesService

    // MARK: - Derived

    /// The rows as listed. The backend already returned them in `sort`
    /// order, so this is `notes` as is — no client-side sort to redo as
    /// stubs fill in during a scroll.
    var sortedNotes: [NoteRecord] { notes }

    /// Note types by name, for the filter menu.
    var notetypeChoices: [(id: NotetypeID, name: String)] {
        notetypeNames
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var topLevelDecks: [DeckInfo] {
        allDecks.filter { !$0.name.contains("::") }
    }

    /// Direct children of the parent deck (shown as the second filter row).
    var childDecks: [DeckInfo] {
        guard let parent = parentDeck else { return [] }
        let prefix = parent.name + "::"
        return allDecks.filter { deck in
            guard deck.name.hasPrefix(prefix) else { return false }
            let remainder = deck.name.dropFirst(prefix.count)
            return !remainder.contains("::")
        }
    }

    // MARK: - Loading

    /// Everything the screen needs that isn't the note list itself. The list is
    /// driven separately by `.task(id: searchQuery)`, which also covers the
    /// first load — searching here too would issue the same query twice.
    func loadInitial() async {
        await loadDecks()
        allTags = ((try? await tagClient.getAllTags()) ?? []).sorted()
        let notetypes = notetypesService
        if let pairs = try? await backendOffload({ try notetypes.getNotetypeNames() }) {
            notetypeNames = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0.name) })
        }
    }

    func loadDecks() async {
        do {
            allDecks = try await deckClient.fetchAll()
        } catch {
            allDecks = []
        }
    }

    /// The full query the note list reflects. Drive `performSearch` from
    /// `.task(id: searchQuery)` so a change cancels the in-flight search
    /// instead of racing it.
    var searchQuery: String { buildQuery() }

    /// Everything a search depends on. Key `.task(id:)` on this so a new
    /// sort order restarts the search the same way a new query does.
    var searchKey: BrowseSearchKey { BrowseSearchKey(query: buildQuery(), sort: sort) }

    /// Runs the current query after a debounce.
    ///
    /// Both waits are cancellation points, and that is what makes this safe to
    /// re-enter: driven from `.task(id:)`, a superseded call is cancelled
    /// either during the sleep (so it never hits the backend) or before it can
    /// write results. Without those guards, typing "hello" issued five
    /// searches and the list showed whichever *returned* last.
    func performSearch(debounce: Duration = .milliseconds(250)) async {
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
        }

        isLoading = true
        let query = buildQuery()
        do {
            let results = try await noteClient.searchSorted(query, sort, nil)
            guard !Task.isCancelled else { return }
            searchFailed = false
            allNotes = results
            notes = Array(results.prefix(pageSize))
            hasMorePages = results.count > pageSize
        } catch {
            guard !Task.isCancelled else { return }
            // An empty list on failure is indistinguishable from "no matches",
            // so record the difference for the empty state to read.
            searchFailed = true
            allNotes = []
            notes = []
            hasMorePages = false
        }
        isLoading = false
    }

    func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        let loaded = notes.count
        let nextBatch = Array(allNotes.dropFirst(loaded).prefix(pageSize))
        notes.append(contentsOf: nextBatch)
        hasMorePages = notes.count < allNotes.count
    }

    /// Lazy-fetch full note details for a stub and update the arrays in place.
    ///
    /// A stub fill replaces one row's content in place; the row keeps the
    /// position the backend's ordering gave it.
    func fetchNoteDetails(id: NoteID) async {
        guard let fullNote = try? await noteClient.fetch(id) else { return }
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx] = fullNote
        }
        if let idx = allNotes.firstIndex(where: { $0.id == id }) {
            allNotes[idx] = fullNote
        }
    }

    /// Resolves (once) the first card of a note, for the row context menu.
    /// Returns the cached value when it's already known, so a row scrolling
    /// out and back doesn't re-issue the lookup.
    func firstCardID(for noteId: NoteID) async -> CardID? {
        if let cached = firstCardIDs[noteId] { return cached }
        guard let cardId = (try? await cardClient.fetchByNote(noteId))?.first?.id else {
            return nil
        }
        firstCardIDs[noteId] = cardId
        return cardId
    }

    /// Resolve a possibly-stub note to its full record before navigation.
    /// This runs from a synchronous SwiftUI `navigationDestination` closure
    /// that can't await, so it falls back to the model's already-loaded
    /// arrays (kept current by `fetchNoteDetails`) rather than an async
    /// backend fetch.
    func resolved(_ note: NoteRecord) -> NoteRecord {
        guard note.sfld == "Loading..." else { return note }
        return notes.first(where: { $0.id == note.id })
            ?? allNotes.first(where: { $0.id == note.id })
            ?? note
    }

    // MARK: - Mutations

    func delete(_ id: NoteID) async {
        await runBatch("delete", over: [id]) { try await self.noteClient.delete($0) }
        store.apply(CollectionChanges(card: true, note: true))
    }

    func suspendSelected(_ noteIDs: Set<NoteID>) async {
        let cardIDs = await collectCardIDs(for: noteIDs)
        await runBatch("suspend", over: cardIDs) { try await self.cardClient.suspend($0) }
    }

    func flagSelected(_ noteIDs: Set<NoteID>, value: UInt32) async {
        let cardIDs = await collectCardIDs(for: noteIDs)
        await runBatch("flag", over: cardIDs) { try await self.cardClient.flag($0, value) }
    }

    func deleteSelected(_ noteIDs: Set<NoteID>) async {
        await runBatch("delete", over: Array(noteIDs)) { try await self.noteClient.delete($0) }
        store.apply(CollectionChanges(card: true, note: true))
    }

    /// Applies `work` to every id, counting failures rather than discarding
    /// them. These were `try?` per item, so in a multi-select batch an
    /// arbitrary subset could fail with zero feedback — the user believed
    /// 100 notes were deleted when some were not.
    private func runBatch<ID>(
        _ verb: String,
        over ids: [ID],
        _ work: (ID) async throws -> Void
    ) async {
        var failures = 0
        var firstError: String?
        for id in ids {
            do {
                try await work(id)
            } catch {
                failures += 1
                if firstError == nil { firstError = error.localizedDescription }
                Log.browse.error("Batch \(verb) failed for one item: \(error)")
            }
        }
        if failures > 0 {
            let reason = firstError ?? String(localized: "unknown error", bundle: .module)
            errorMessage = failures == ids.count
                ? Self.batchFailureMessage(verb, failures: failures, reason: reason)
                : Self.partialBatchFailureMessage(verb, failures: failures, total: ids.count, reason: reason)
        }
        await performSearch()
    }

    // MARK: - Query

    func buildQuery() -> String {
        var parts: [String] = []
        if let deck = activeDeck {
            parts.append(DeckSearch.term(deck.name))
        }
        if let tag = activeTag {
            parts.append("tag:\"\(tag)\"")
        }
        parts.append(contentsOf: filters.searchTerms)
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }

    private func collectCardIDs(for noteIDs: Set<NoteID>) async -> [CardID] {
        var result: [CardID] = []
        result.reserveCapacity(noteIDs.count)
        let cardClient = cardClient
        for nid in noteIDs {
            if let cards = try? await cardClient.fetchByNote(nid) {
                result.append(contentsOf: cards.map(\.id))
            }
        }
        return result
    }
}

// MARK: - Batch failure messages

extension BrowseModel {
    /// One whole sentence per batch verb, so each language words it
    /// naturally instead of splicing an English verb into a template.
    static func batchFailureMessage(_ verb: String, failures: Int, reason: String) -> String {
        switch verb {
        case "delete": String(localized: "Couldn't delete \(failures) items: \(reason)", bundle: .module)
        case "suspend": String(localized: "Couldn't suspend \(failures) items: \(reason)", bundle: .module)
        case "flag": String(localized: "Couldn't flag \(failures) items: \(reason)", bundle: .module)
        default: String(localized: "Couldn't update \(failures) items: \(reason)", bundle: .module)
        }
    }

    static func partialBatchFailureMessage(_ verb: String, failures: Int, total: Int, reason: String) -> String {
        switch verb {
        case "delete": String(localized: "\(failures) of \(total) items couldn't be deleted: \(reason)", bundle: .module)
        case "suspend": String(localized: "\(failures) of \(total) items couldn't be suspended: \(reason)", bundle: .module)
        case "flag": String(localized: "\(failures) of \(total) items couldn't be flagged: \(reason)", bundle: .module)
        default: String(localized: "\(failures) of \(total) items couldn't be updated: \(reason)", bundle: .module)
        }
    }
}
