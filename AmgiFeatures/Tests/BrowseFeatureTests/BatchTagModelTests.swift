//
//  BatchTagModelTests.swift
//  BrowseFeatureTests
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation
import Testing
@testable import BrowseFeature

@Suite("BatchTagModel")
@MainActor
struct BatchTagModelTests {

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _adds: [(String, [NoteID])] = []
        private var _removes: [(String, [NoteID])] = []
        var adds: [(String, [NoteID])] { lock.withLock { _adds } }
        var removes: [(String, [NoteID])] { lock.withLock { _removes } }
        func add(_ tag: String, _ ids: [NoteID]) { lock.withLock { _adds.append((tag, ids)) } }
        func remove(_ tag: String, _ ids: [NoteID]) { lock.withLock { _removes.append((tag, ids)) } }
    }

    private static func note(_ id: Int64, tags: String) -> NoteRecord {
        NoteRecord(id: NoteID(id), guid: "\(id)", mid: NotetypeID(1), mod: 0,
                   tags: tags, flds: "", sfld: "", csum: 0)
    }

    private static let notes = [
        note(1, tags: " vocab n5 "),
        note(2, tags: " Vocab verb "),
        note(3, tags: " vocab "),
    ]

    private func makeModel(calls: Calls = Calls(), failing: Bool = false) -> BatchTagModel {
        withDependencies {
            $0.noteClient.searchAll = { _, _ in Self.notes }
            $0.tagClient.getAllTags = { ["vocab", "n5", "verb", "grammar"] }
            $0.tagClient.addTagToNotes = { tag, ids in
                if failing { throw CocoaError(.fileWriteUnknown) }
                calls.add(tag, ids)
            }
            $0.tagClient.removeTagFromNotes = { tag, ids in
                if failing { throw CocoaError(.fileWriteUnknown) }
                calls.remove(tag, ids)
            }
        } operation: {
            BatchTagModel(noteIDs: [NoteID(1), NoteID(2), NoteID(3)])
        }
    }

    @Test func splitsSelectionTagsFromTheRest() async {
        let model = makeModel()
        await model.load()
        #expect(model.selectionTags == ["n5", "verb", "vocab"])
        #expect(model.otherTags == ["grammar"])
    }

    @Test func coverageIsCaseInsensitive() async {
        let model = makeModel()
        await model.load()
        #expect(model.coverage(of: "vocab") == .all)
        #expect(model.coverage(of: "n5") == .some)
        #expect(model.noteCount(of: "n5") == 1)
        #expect(model.coverage(of: "grammar") == .none)
    }

    @Test func partialTagCyclesThroughAllNoneAndBack() async {
        let model = makeModel()
        await model.load()
        model.toggle("n5")
        #expect(model.coverage(of: "n5") == .all)
        model.toggle("n5")
        #expect(model.coverage(of: "n5") == .none)
        model.toggle("n5")
        #expect(model.coverage(of: "n5") == .some)
        #expect(!model.hasChanges)
    }

    @Test func fullAndAbsentTagsFlip() async {
        let model = makeModel()
        await model.load()
        model.toggle("vocab")
        model.toggle("grammar")
        #expect(model.coverage(of: "vocab") == .none)
        #expect(model.coverage(of: "grammar") == .all)
        model.toggle("vocab")
        model.toggle("grammar")
        #expect(!model.hasChanges)
    }

    @Test func typedTagsAreSplitAndMarkedForAdding() async {
        let model = makeModel()
        await model.load()
        model.addTyped("new-one  VERB")
        #expect(model.otherTags.first == "new-one")
        #expect(model.coverage(of: "new-one") == .all)
        #expect(model.coverage(of: "verb") == .all)
        #expect(model.selectionTags.filter { $0.lowercased() == "verb" }.count == 1)
    }

    @Test func applySendsOneAddAndOneRemoveCall() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        await model.load()
        model.toggle("grammar")
        model.toggle("n5")
        model.toggle("vocab")
        let ok = await model.apply()
        #expect(ok)
        #expect(calls.adds.map(\.0) == ["grammar n5"])
        #expect(calls.removes.map(\.0) == ["vocab"])
        #expect(calls.adds.first?.1 == [NoteID(1), NoteID(2), NoteID(3)])
    }

    @Test func failureKeepsChangesAndReportsError() async {
        let model = makeModel(failing: true)
        await model.load()
        model.toggle("grammar")
        let ok = await model.apply()
        #expect(!ok)
        #expect(model.errorMessage != nil)
        #expect(model.hasChanges)
    }

    @Test func searchQueryListsEveryNote() {
        #expect(BatchTagModel.searchQuery(for: [NoteID(4), NoteID(9)]) == "nid:4,9")
    }
}
