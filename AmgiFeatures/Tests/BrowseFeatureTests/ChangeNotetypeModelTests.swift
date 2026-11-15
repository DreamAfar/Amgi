//
//  ChangeNotetypeModelTests.swift
//  BrowseFeatureTests
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation
import Testing
@testable import BrowseFeature

@Suite("Change note type")
@MainActor
struct ChangeNotetypeModelTests {
    private final class Box<T>: @unchecked Sendable { var value: T; init(_ value: T) { self.value = value } }

    private static let basic = NotetypeNameId(id: NotetypeID(1), name: "Basic")
    private static let reversed = NotetypeNameId(id: NotetypeID(2), name: "Basic (and reversed card)")

    private static func info(to new: NotetypeID) -> ChangeNotetypeInfo {
        ChangeNotetypeInfo(
            oldNotetypeName: "Basic",
            oldFieldNames: ["Front", "Back"],
            oldTemplateNames: ["Card 1"],
            newFieldNames: new == reversed.id ? ["Front", "Back"] : ["Front", "Back"],
            newTemplateNames: new == reversed.id ? ["Card 1", "Card 2"] : ["Card 1"],
            input: ChangeNotetypeInput(
                noteIDs: [],
                newFields: [0, 1],
                newTemplates: new == reversed.id ? [0, nil] : [0],
                oldNotetypeID: basic.id,
                newNotetypeID: new,
                currentSchema: 42,
                oldNotetypeName: "Basic",
                isCloze: false
            )
        )
    }

    private func withStubs(
        mids: [NoteID: NotetypeID],
        saved: Box<ChangeNotetypeInput?> = Box(nil),
        _ operation: () async -> Void
    ) async {
        await withDependencies {
            $0.notetypesClient.listAll = { [Self.basic, Self.reversed] }
            $0.noteClient.fetch = { id in
                NoteRecord(id: id, guid: "g", mid: mids[id] ?? NotetypeID(1), mod: 0, flds: "", sfld: "", csum: 0)
            }
            $0.notetypesClient.changeNotetypeInfo = { _, new in Self.info(to: new) }
            $0.notetypesClient.changeNotetype = { saved.value = $0 }
        } operation: {
            await operation()
        }
    }

    @Test("notes of several note types can't be changed together")
    func mixedSelection() async {
        await withStubs(mids: [NoteID(1): NotetypeID(1), NoteID(2): NotetypeID(2)]) {
            let model = ChangeNotetypeModel(noteIDs: [NoteID(1), NoteID(2)])
            await model.load()
            #expect(model.phase == .mixed(["Basic", "Basic (and reversed card)"]))
        }
    }

    @Test("opens on the current note type with nothing to change")
    func opensUnchanged() async {
        await withStubs(mids: [:]) {
            let model = ChangeNotetypeModel(noteIDs: [NoteID(1)])
            await model.load()
            #expect(model.phase == .ready)
            #expect(model.target == Self.basic)
            #expect(!model.canSave)
        }
    }

    @Test("an old card template can feed only one new template")
    func templatesAreExclusive() async {
        await withStubs(mids: [:]) {
            let model = ChangeNotetypeModel(noteIDs: [NoteID(1)])
            await model.load()
            await model.selectTarget(Self.reversed)
            model.setTemplate(1, from: 0)
            #expect(model.newTemplates == [nil, 0])
            #expect(model.discardedTemplates.isEmpty)
        }
    }

    @Test("unmapped old fields and cards are reported as lost")
    func discarded() async {
        await withStubs(mids: [:]) {
            let model = ChangeNotetypeModel(noteIDs: [NoteID(1)])
            await model.load()
            await model.selectTarget(Self.reversed)
            model.setField(1, from: 0)
            model.setTemplate(0, from: nil)
            #expect(model.discardedFields == ["Back"])
            #expect(model.discardedTemplates == ["Card 1"])
        }
    }

    @Test("saving sends the selected notes with the chosen mapping")
    func save() async {
        let saved = Box<ChangeNotetypeInput?>(nil)
        await withStubs(mids: [:], saved: saved) {
            let model = ChangeNotetypeModel(noteIDs: [NoteID(1), NoteID(3)])
            await model.load()
            await model.selectTarget(Self.reversed)
            #expect(await model.save())
            #expect(saved.value?.noteIDs == [NoteID(1), NoteID(3)])
            #expect(saved.value?.newTemplates == [0, nil])
            #expect(saved.value?.newNotetypeID == Self.reversed.id)
            #expect(saved.value?.currentSchema == 42)
        }
    }
}
