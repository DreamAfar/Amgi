//
//  BrowseFilterChipTests.swift
//  BrowseFeatureTests
//

import AnkiClients
import AnkiKit
import Dependencies
import Testing
@testable import BrowseFeature

@Suite("BrowseModel filter chips")
@MainActor
struct BrowseFilterChipTests {
    private static let parent = DeckInfo(id: DeckID(1), name: "Japanese")
    private static let child = DeckInfo(id: DeckID(2), name: "Japanese::N5")

    @Test func tappingTheSelectedDeckClearsIt() {
        let model = BrowseModel()
        model.toggleTopLevelDeck(Self.parent)
        #expect(model.activeDeck?.id == Self.parent.id)
        model.toggleTopLevelDeck(Self.parent)
        #expect(model.activeDeck == nil)
        #expect(model.parentDeck == nil)
    }

    @Test func tappingTheParentWhileInASubdeckGoesBackToTheParent() {
        let model = BrowseModel()
        model.toggleTopLevelDeck(Self.parent)
        model.toggleChildDeck(Self.child)
        model.toggleTopLevelDeck(Self.parent)
        #expect(model.activeDeck?.id == Self.parent.id)
    }

    @Test func tappingTheSelectedSubdeckWidensToTheParent() {
        let model = BrowseModel()
        model.toggleTopLevelDeck(Self.parent)
        model.toggleChildDeck(Self.child)
        #expect(model.activeDeck?.id == Self.child.id)
        model.toggleChildDeck(Self.child)
        #expect(model.activeDeck?.id == Self.parent.id)
    }

    @Test func tagRowFollowsTheActiveDeck() async {
        let model = withDependencies {
            $0.noteClient.tagsOfNotes = { _ in ["Grammar::Verbs", "n5"] }
        } operation: {
            BrowseModel()
        }
        model.allTags = ["grammar", "grammar::verbs", "kanji", "n5"]
        model.activeTag = "kanji"
        #expect(model.visibleTags == model.allTags)

        model.toggleTopLevelDeck(Self.parent)
        await model.loadDeckTags()
        // Parent levels count, and the active tag stays so it can be cleared.
        #expect(model.visibleTags == ["grammar", "grammar::verbs", "kanji", "n5"])
        model.activeTag = nil
        #expect(model.visibleTags == ["grammar", "grammar::verbs", "n5"])

        model.toggleTopLevelDeck(Self.parent)
        await model.loadDeckTags()
        #expect(model.visibleTags == model.allTags)
    }
}
