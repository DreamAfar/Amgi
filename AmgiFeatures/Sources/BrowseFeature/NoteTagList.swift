//
//  NoteTagList.swift
//  BrowseFeature
//

import AnkiClients
import Dependencies
import Foundation

/// Pure editing operations on a note's tag list. Notes store tags as one
/// space-separated string; the tag editor works on the split list and
/// joins it back, so nothing about storage or sync changes. Anki tags
/// can't contain spaces and compare case-insensitively, which every
/// operation here respects.
enum NoteTagList {
    static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func join(_ tags: [String]) -> String {
        tags.joined(separator: " ")
    }

    static func index(of tag: String, in tags: [String]) -> Int? {
        let key = tag.lowercased()
        return tags.firstIndex { $0.lowercased() == key }
    }

    /// Appends each whitespace-separated tag in `input` that isn't already
    /// there. Returns the new list and the index of the first tag that was
    /// skipped as a duplicate, so the editor can point at it.
    static func adding(_ input: String, to tags: [String]) -> (tags: [String], duplicate: Int?) {
        var result = tags
        var duplicate: Int?
        for tag in split(input) {
            if let existing = index(of: tag, in: result) {
                if duplicate == nil { duplicate = existing }
            } else {
                result.append(tag)
            }
        }
        return (result, duplicate)
    }

    /// Replaces the tag at `index` with the edited text: empty removes it,
    /// spaces split it into several tags in place, and any piece that
    /// duplicates another tag in the list is dropped.
    static func replacing(at index: Int, with input: String, in tags: [String]) -> [String] {
        guard tags.indices.contains(index) else { return tags }
        var others = tags
        others.remove(at: index)
        var pieces: [String] = []
        for tag in split(input)
        where self.index(of: tag, in: others) == nil && self.index(of: tag, in: pieces) == nil {
            pieces.append(tag)
        }
        var result = tags
        result.replaceSubrange(index...index, with: pieces)
        return result
    }

    static func removing(at index: Int, from tags: [String]) -> [String] {
        guard tags.indices.contains(index) else { return tags }
        var result = tags
        result.remove(at: index)
        return result
    }

    /// Collection tags matching what's being typed, best first: prefix
    /// matches on the whole tag or on any `::` level, then other substring
    /// matches. Tags already on the note are left out.
    static func suggestions(for input: String, from all: [String], excluding present: [String], limit: Int = 8) -> [String] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let taken = Set(present.map { $0.lowercased() })
        var prefix: [String] = []
        var contains: [String] = []
        for tag in all where !taken.contains(tag.lowercased()) {
            let lower = tag.lowercased()
            if lower.hasPrefix(query)
                || lower.components(separatedBy: "::").contains(where: { $0.hasPrefix(query) }) {
                prefix.append(tag)
            } else if lower.contains(query) {
                contains.append(tag)
            }
        }
        return Array((prefix + contains).prefix(limit))
    }
}

/// Loads the collection's tags once for the tag editor's suggestions, so
/// the editor view carries no `@Dependency`.
@Observable
@MainActor
final class TagSuggestionsModel {
    private(set) var allTags: [String] = []

    @ObservationIgnored @Dependency(\.tagClient) private var tagClient

    func load() async {
        guard allTags.isEmpty else { return }
        if let tags = try? await tagClient.getAllTags() {
            allTags = tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
}
