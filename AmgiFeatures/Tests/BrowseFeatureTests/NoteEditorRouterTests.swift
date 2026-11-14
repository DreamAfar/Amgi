//
//  NoteEditorRouterTests.swift
//  BrowseFeatureTests
//

import AnkiClients
import AnkiKit
import Dependencies
import Testing
@testable import BrowseFeature

@Suite("NoteEditorRouter")
@MainActor
struct NoteEditorRouterTests {
    private struct Failure: Error {}

    private func note(mid: Int64, flds: String) -> NoteRecord {
        NoteRecord(id: NoteID(1), guid: "g", mid: NotetypeID(mid), mod: 0, flds: flds, sfld: "", csum: 0)
    }

    private func route(_ note: NoteRecord, kind: Notetype.Config.OriginalStockKind?) async -> NoteEditorRouter.Editor? {
        let router = withDependencies {
            $0.notetypesClient.get = { id in
                guard let kind else { throw Failure() }
                return Notetype(id: id, config: .init(originalStockKind: kind))
            }
        } operation: {
            NoteEditorRouter()
        }
        await router.resolve(note)
        return router.editor
    }

    // Each test uses its own notetype id: the router caches per notetype.

    @Test("an image occlusion notetype opens the mask editor")
    func imageOcclusionNotetype() async {
        let editor = await route(note(mid: 9001, flds: "{{c1::image-occlusion:rect:left=.1}}"), kind: .imageOcclusion)
        #expect(editor == .imageOcclusion)
    }

    @Test("a basic note that mentions image-occlusion: opens the field editor")
    func mentionInBasicNote() async {
        let editor = await route(note(mid: 9002, flds: "How is image-occlusion: stored?\u{1f}As cloze text"), kind: .basic)
        #expect(editor == .fields)
    }

    @Test("an unreadable notetype falls back to the field content")
    func fallbackWhenNotetypeFails() async {
        let editor = await route(note(mid: 9003, flds: "{{c1::image-occlusion:rect:left=.1}}"), kind: nil)
        #expect(editor == .imageOcclusion)
    }
}
