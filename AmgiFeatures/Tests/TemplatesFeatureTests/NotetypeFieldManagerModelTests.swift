//
//  NotetypeFieldManagerModelTests.swift
//  TemplatesFeatureTests
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation
import Testing
@testable import TemplatesFeature

@Suite("NotetypeFieldManagerModel")
@MainActor
struct NotetypeFieldManagerModelTests {

    private final class Saved: @unchecked Sendable {
        private let lock = NSLock()
        private var _notetypes: [Notetype] = []
        var notetypes: [Notetype] { lock.withLock { _notetypes } }
        func record(_ notetype: Notetype) { lock.withLock { _notetypes.append(notetype) } }
    }

    private static let basic = Notetype(
        id: NotetypeID(7),
        name: "Vocab",
        config: Notetype.Config(sortFieldIdx: 1),
        fields: [
            .init(ord: 0, name: "Word"),
            .init(ord: 1, name: "Meaning"),
            .init(ord: 2, name: "Example"),
        ]
    )

    private func makeModel(_ notetype: Notetype = basic, saved: Saved = Saved()) async -> NotetypeFieldManagerModel {
        let model = withDependencies {
            $0.notetypesClient.get = { _ in notetype }
            $0.notetypesClient.update = { saved.record($0) }
        } operation: {
            NotetypeFieldManagerModel()
        }
        await model.load(notetypeId: notetype.id)
        return model
    }

    @Test("Loads fields and the sort field")
    func load() async {
        let model = await makeModel()
        #expect(model.fields.map(\.name) == ["Word", "Meaning", "Example"])
        #expect(model.fields.firstIndex { $0.id == model.sortFieldID } == 1)
        #expect(!model.hasChanges)
    }

    @Test("Rejects empty, malformed and duplicate names")
    func validation() async {
        let model = await makeModel()
        #expect(model.validate("  ") == .empty)
        #expect(model.validate("#tag") == .invalidStart)
        #expect(model.validate("a:b") == .invalidCharacter)
        #expect(model.validate("{x}") == .invalidCharacter)
        #expect(model.validate("word") == .duplicate)
        #expect(model.validate("Reading") == nil)
        // Renaming a field to its own name, in a different case, is fine.
        let word = model.fields[0].id
        #expect(model.validate("WORD", excluding: word) == nil)
    }

    @Test("A rename keeps the ord and doesn't need a full sync")
    func rename() async {
        let saved = Saved()
        let model = await makeModel(saved: saved)
        #expect(model.rename(model.fields[1].id, to: " Definition ") == nil)
        #expect(model.hasChanges)
        #expect(!model.requiresFullSync)
        #expect(await model.save())
        let sent = try? #require(saved.notetypes.last)
        #expect(sent?.fields.map(\.name) == ["Word", "Definition", "Example"])
        #expect(sent?.fields.map(\.ord) == [0, 1, 2])
    }

    @Test("Adding a field sends it without an ord")
    func add() async {
        let saved = Saved()
        let model = await makeModel(saved: saved)
        #expect(model.addField(named: "Reading") == nil)
        #expect(model.requiresFullSync)
        #expect(await model.save())
        #expect(saved.notetypes.last?.fields.map(\.ord) == [0, 1, 2, nil])
    }

    @Test("Reordering keeps ords and moves the sort index with its field")
    func reorder() async {
        let saved = Saved()
        let model = await makeModel(saved: saved)
        // Move "Example" to the top.
        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(model.fields.map(\.name) == ["Example", "Word", "Meaning"])
        #expect(model.requiresFullSync)
        #expect(await model.save())
        let sent = saved.notetypes.last
        #expect(sent?.fields.map(\.ord) == [2, 0, 1])
        // "Meaning" was the sort field and is now third.
        #expect(sent?.config.sortFieldIdx == 2)
    }

    @Test("Moving a row down follows List.onMove offsets")
    func moveDown() async {
        let model = await makeModel()
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(model.fields.map(\.name) == ["Meaning", "Word", "Example"])
    }

    @Test("Removing the sort field falls back to the first field")
    func removeSortField() async {
        let saved = Saved()
        let model = await makeModel(saved: saved)
        model.remove(model.fields[1].id)
        #expect(model.fields.map(\.name) == ["Word", "Example"])
        #expect(model.requiresFullSync)
        #expect(await model.save())
        #expect(saved.notetypes.last?.fields.map(\.ord) == [0, 2])
        #expect(saved.notetypes.last?.config.sortFieldIdx == 0)
    }

    @Test("The last field and protected fields can't be removed")
    func removalGuards() async {
        var occlusion = Self.basic
        occlusion.fields = [.init(ord: 0, name: "Occlusion", config: .init(preventDeletion: true)), .init(ord: 1, name: "Image")]
        let model = await makeModel(occlusion)
        model.remove(model.fields[0].id)
        #expect(model.fields.count == 2)
        model.remove(model.fields[1].id)
        #expect(model.fields.map(\.name) == ["Occlusion"])
    }

    @Test("Changing the sort field needs a full sync")
    func sortFieldChange() async {
        let saved = Saved()
        let model = await makeModel(saved: saved)
        model.sortFieldID = model.fields[0].id
        #expect(model.requiresFullSync)
        #expect(await model.save())
        #expect(saved.notetypes.last?.config.sortFieldIdx == 0)
    }

    @Test("Saving without changes sends nothing")
    func noOpSave() async {
        let saved = Saved()
        let model = await makeModel(saved: saved)
        #expect(await model.save())
        #expect(saved.notetypes.isEmpty)
    }
}
