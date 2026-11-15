//
//  NoteTagListTests.swift
//  BrowseFeatureTests
//

import Testing
@testable import BrowseFeature

@Suite("NoteTagList")
struct NoteTagListTests {

    @Test func splitIgnoresExtraWhitespace() {
        #expect(NoteTagList.split("  vocab   n5\tverb ") == ["vocab", "n5", "verb"])
        #expect(NoteTagList.split("") == [])
    }

    @Test func addingSplitsAndSkipsCaseInsensitiveDuplicates() {
        let (tags, duplicate) = NoteTagList.adding("new VOCAB other new", to: ["vocab", "n5"])
        #expect(tags == ["vocab", "n5", "new", "other"])
        #expect(duplicate == 0)
    }

    @Test func addingWithoutDuplicateReportsNone() {
        #expect(NoteTagList.adding("a", to: []).duplicate == nil)
    }

    @Test func replacingEditsInPlace() {
        #expect(NoteTagList.replacing(at: 1, with: "n4", in: ["vocab", "n5", "verb"]) == ["vocab", "n4", "verb"])
    }

    @Test func replacingWithEmptyRemoves() {
        #expect(NoteTagList.replacing(at: 0, with: "  ", in: ["vocab", "n5"]) == ["n5"])
    }

    @Test func replacingWithSpacesSplitsAndDropsDuplicates() {
        let result = NoteTagList.replacing(at: 0, with: "a VERB b a", in: ["x", "verb"])
        #expect(result == ["a", "b", "verb"])
    }

    @Test func replacingKeepsOwnSpellingChange() {
        #expect(NoteTagList.replacing(at: 0, with: "Vocab", in: ["vocab"]) == ["Vocab"])
    }

    @Test func removingOutOfRangeIsANoOp() {
        #expect(NoteTagList.removing(at: 5, from: ["a"]) == ["a"])
        #expect(NoteTagList.removing(at: 0, from: ["a", "b"]) == ["b"])
    }

    @Test func suggestionsPreferPrefixAndLevelMatches() {
        let all = ["grammar", "语言::日语::N5", "n5", "sync", "vocab"]
        #expect(NoteTagList.suggestions(for: "n", from: all, excluding: []) == ["语言::日语::N5", "n5", "sync"])
        #expect(NoteTagList.suggestions(for: "N5", from: all, excluding: ["n5"]) == ["语言::日语::N5"])
        #expect(NoteTagList.suggestions(for: " ", from: all, excluding: []) == [])
    }
}
