//
//  BrowseBatchActionTests.swift
//  BrowseFeatureTests
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation
import Testing
@testable import BrowseFeature

/// Batch actions resolve the selected notes' cards once and hand them to a
/// single backend call, so a 300-note change is one operation (and one undo
/// step) rather than 300 that can half-apply.
@Suite("BrowseModel batch actions")
@MainActor
struct BrowseBatchActionTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        func record(_ call: String) { lock.lock(); _calls.append(call); lock.unlock() }
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    private func withStubs(
        _ recorder: Recorder,
        failing: Bool = false,
        _ operation: () async -> Void
    ) async {
        await withDependencies {
            $0.noteClient.search = { _, _ in [] }
            $0.cardClient.cardIDsOfNotes = { notes in
                notes.flatMap { [CardID($0.rawValue * 10), CardID($0.rawValue * 10 + 1)] }
            }
            $0.cardClient.setDeckForCards = { cards, deck in
                if failing { throw Failure() }
                recorder.record("move \(cards.count) → \(deck.rawValue)")
            }
            $0.cardClient.gradeCardsNow = { cards, rating in
                recorder.record("grade \(cards.count) \(rating)")
            }
            $0.tagClient.addTagToNotes = { tag, notes in
                recorder.record("tag \(tag) \(notes.count)")
            }
        } operation: {
            await operation()
        }
    }

    @Test("moving notes moves all their cards in one call")
    func moveIsOneCall() async {
        let recorder = Recorder()
        await withStubs(recorder) {
            let model = BrowseModel()
            await model.moveSelected([NoteID(1), NoteID(2)], to: DeckID(7))
            #expect(recorder.calls == ["move 4 → 7"])
            #expect(model.errorMessage == nil)
        }
    }

    @Test("grade now passes the rating through")
    func gradeNow() async {
        let recorder = Recorder()
        await withStubs(recorder) {
            let model = BrowseModel()
            await model.gradeSelectedNow([NoteID(3)], rating: .good)
            #expect(recorder.calls == ["grade 2 good"])
        }
    }

    @Test("marking adds Anki's marked tag")
    func mark() async {
        let recorder = Recorder()
        await withStubs(recorder) {
            let model = BrowseModel()
            await model.setMarked(true, for: [NoteID(1), NoteID(2), NoteID(3)])
            #expect(recorder.calls == ["tag marked 3"])
        }
    }

    @Test("a failed batch surfaces an error instead of failing silently")
    func failureIsReported() async {
        let recorder = Recorder()
        await withStubs(recorder, failing: true) {
            let model = BrowseModel()
            await model.moveSelected([NoteID(1)], to: DeckID(7))
            #expect(model.errorMessage?.contains("boom") == true)
        }
    }
}
