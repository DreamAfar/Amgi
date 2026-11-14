//
//  BatchTagModel.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 26.06.2026.
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation

/// State + I/O for the browse multi-select tag sheet. Reads the selected
/// notes' tags so each tag can show whether all, some or none of the
/// selection carries it, records the edits as pending add/remove changes,
/// and applies them in one add call plus one remove call. Owns the
/// `noteClient` / `tagClient` dependencies so the view carries none.
///
/// Anki compares tags case-insensitively, so every lookup goes through a
/// lowercased key while the collection's own spelling is kept for display.
@Observable
@MainActor
final class BatchTagModel {
    /// How many of the selected notes carry a tag.
    enum Coverage: Equatable {
        case all
        case some
        case none
    }

    let noteIDs: [NoteID]

    private(set) var isLoading = true
    private(set) var isApplying = false
    var errorMessage: String?
    var query = ""

    /// Tags the selection already carries, sorted.
    private(set) var selectionTags: [String] = []
    /// Every other tag: ones typed in this sheet first, then the rest of
    /// the collection's tags, sorted.
    private(set) var otherTags: [String] = []

    /// Lowercased tag → number of selected notes carrying it.
    @ObservationIgnored private var counts: [String: Int] = [:]
    /// Lowercased tag → `true` to add to every note, `false` to remove
    /// from every note. Absent means "leave as it is".
    private var changes: [String: Bool] = [:]

    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.tagClient) private var tagClient

    init(noteIDs: Set<NoteID>) {
        self.noteIDs = noteIDs.sorted { $0.rawValue < $1.rawValue }
    }

    var hasChanges: Bool { !changes.isEmpty }
    var canApply: Bool { hasChanges && !isApplying && !isLoading }

    var visibleSelectionTags: [String] { selectionTags.filter(matchesQuery) }
    var visibleOtherTags: [String] { otherTags.filter(matchesQuery) }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let ids = noteIDs
        let noteClient = noteClient
        let tagClient = tagClient
        do {
            async let notes = noteClient.searchAll(Self.searchQuery(for: ids), nil)
            async let collectionTags = tagClient.getAllTags()
            configure(notes: try await notes, collectionTags: (try? await collectionTags) ?? [])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Splits the tags into the selection's and the rest. Split out of
    /// `load()` so tests can drive it without a backend.
    func configure(notes: [NoteRecord], collectionTags: [String]) {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for tag in collectionTags {
            spelling[tag.lowercased()] = tag
        }
        for note in notes {
            // A tag listed twice on one note still counts once.
            let keys = Set(Self.tags(in: note.tags).map { tag -> String in
                let key = tag.lowercased()
                if spelling[key] == nil { spelling[key] = tag }
                return key
            })
            for key in keys {
                counts[key, default: 0] += 1
            }
        }
        self.counts = counts
        let byName: (String, String) -> Bool = {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        selectionTags = counts.keys.compactMap { spelling[$0] }.sorted(by: byName)
        otherTags = spelling
            .filter { counts[$0.key] == nil }
            .map(\.value)
            .sorted(by: byName)
        changes = [:]
    }

    // MARK: - Editing

    func originalCoverage(of tag: String) -> Coverage {
        let count = counts[tag.lowercased()] ?? 0
        if count == 0 { return .none }
        return count >= noteIDs.count ? .all : .some
    }

    /// Coverage after the pending change, if any.
    func coverage(of tag: String) -> Coverage {
        switch changes[tag.lowercased()] {
        case true?: .all
        case false?: .none
        case nil: originalCoverage(of: tag)
        }
    }

    func isChanged(_ tag: String) -> Bool {
        changes[tag.lowercased()] != nil
    }

    /// Number of selected notes carrying the tag before any change.
    func noteCount(of tag: String) -> Int {
        counts[tag.lowercased()] ?? 0
    }

    /// Cycles a tag through the states it can reach: a partial tag goes
    /// some → all → none → some; a full or absent one flips between all
    /// and none. Landing back on the original state drops the change.
    func toggle(_ tag: String) {
        let key = tag.lowercased()
        let original = originalCoverage(of: tag)
        switch coverage(of: tag) {
        case .all:
            changes[key] = original == .none ? nil : false
        case .none:
            changes[key] = original == .none ? true : nil
        case .some:
            changes[key] = true
        }
    }

    /// Adds the typed tag(s) — Anki tags can't contain spaces, so input is
    /// split on whitespace — and marks each for adding. Tags the sheet
    /// already lists are just marked.
    func addTyped(_ input: String) {
        for tag in input.split(whereSeparator: \.isWhitespace).map(String.init) {
            let key = tag.lowercased()
            let known = (selectionTags + otherTags).first { $0.lowercased() == key }
            if known == nil {
                otherTags.insert(tag, at: 0)
            }
            if coverage(of: known ?? tag) != .all {
                toggleToAll(known ?? tag)
            }
        }
        query = ""
    }

    private func toggleToAll(_ tag: String) {
        changes[tag.lowercased()] = originalCoverage(of: tag) == .all ? nil : true
    }

    // MARK: - Applying

    /// Applies the pending changes. Returns `true` on success; on failure
    /// the changes stay so the user can retry.
    func apply() async -> Bool {
        guard canApply else { return false }
        isApplying = true
        defer { isApplying = false }
        let all = selectionTags + otherTags
        let spelled: (String) -> String = { key in
            all.first { $0.lowercased() == key } ?? key
        }
        let adds = changes.filter(\.value).keys.map(spelled).sorted()
        let removes = changes.filter { !$0.value }.keys.map(spelled).sorted()
        let ids = noteIDs
        let tagClient = tagClient
        do {
            // The backend takes space-separated tag lists, so each
            // direction is a single call.
            if !adds.isEmpty {
                try await tagClient.addTagToNotes(adds.joined(separator: " "), ids)
            }
            if !removes.isEmpty {
                try await tagClient.removeTagFromNotes(removes.joined(separator: " "), ids)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    private func matchesQuery(_ tag: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || tag.localizedCaseInsensitiveContains(trimmed)
    }

    static func tags(in field: String) -> [String] {
        field.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func searchQuery(for ids: [NoteID]) -> String {
        "nid:" + ids.map { String($0.rawValue) }.joined(separator: ",")
    }
}
