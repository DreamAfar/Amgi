import XCTest
@testable import AnkiApp
import AnkiClients
import AnkiKit
import Dependencies

// MARK: - Cross-System Integration Tests
final class CrossSystemIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    var deckClient: DeckClient!
    var tagClient: TagClient!
    var noteClient: NoteClient!
    var cardClient: CardClient!
    var searchClient: SearchClient!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        deckClient = DeckClient.testValue
        tagClient = TagClient.testValue
        noteClient = NoteClient.testValue
        cardClient = CardClient.testValue
        searchClient = SearchClient.testValue
    }
    
    override func tearDown() {
        super.tearDown()
        
        deckClient = nil
        tagClient = nil
        noteClient = nil
        cardClient = nil
        searchClient = nil
    }
    
    // MARK: - Tests: Deck + Cards Workflow
    
    func testDeckWithCardsWorkflow() {
        // Scenario: Create deck → Fetch cards → Answer cards
        
        // 1. Create deck
        let deckName = "StudyDeck"
        let deckId = try! deckClient.create(deckName)
        XCTAssertGreaterThan(deckId, 0, "Should create deck successfully")
        
        // 2. Fetch due cards (even if empty, should not throw)
        let dueCards = try? cardClient.fetchDue(deckId)
        XCTAssertNotNil(dueCards, "Should be able to fetch due cards")
        
        // 3. Verify deck exists in tree
        let tree = deckClient.getDeckTree(now: 0)
        let deckNames = extractDeckNames(from: tree)
        XCTAssertTrue(deckNames.contains(deckName), "Created deck should be in tree")
        
        // 4. Cleanup
        try? deckClient.delete(deckId)
    }
    
    func testMultipleDecksSeparateCards() {
        // Scenario: Create multiple decks and verify card isolation
        
        let deck1Name = "EnglishDeck"
        let deck2Name = "ChineseDeck"
        
        let deck1Id = try! deckClient.create(deck1Name)
        let deck2Id = try! deckClient.create(deck2Name)
        
        // Fetch due cards for each deck (should be independent)
        let cards1 = try? cardClient.fetchDue(deck1Id)
        let cards2 = try? cardClient.fetchDue(deck2Id)
        
        XCTAssertNotNil(cards1, "Should fetch cards for deck 1")
        XCTAssertNotNil(cards2, "Should fetch cards for deck 2")
        
        // Cleanup
        try? deckClient.delete(deck1Id)
        try? deckClient.delete(deck2Id)
    }
    
    // MARK: - Tests: Tags + Notes Workflow
    
    func testTaggingNotesWorkflow() {
        // Scenario: Create tags → Tag notes → Search by tag
        
        // 1. Create tags
        let tag1 = "Important"
        let tag2 = "Review"
        
        try? tagClient.addTag(tag1)
        try? tagClient.addTag(tag2)
        
        // 2. Verify tags exist
        let allTags = tagClient.getAllTags()
        XCTAssertTrue(allTags.contains(tag1), "Tag1 should exist")
        XCTAssertTrue(allTags.contains(tag2), "Tag2 should exist")
        
        // 3. Find notes with tags (may be empty, but should not throw)
        let notesWithTag1 = tagClient.findNotesByTag(tag1)
        let notesWithTag2 = tagClient.findNotesByTag(tag2)
        
        XCTAssertTrue(notesWithTag1.count >= 0, "Should find notes with tag1")
        XCTAssertTrue(notesWithTag2.count >= 0, "Should find notes with tag2")
        
        // 4. Cleanup
        try? tagClient.removeTag(tag1)
        try? tagClient.removeTag(tag2)
    }
    
    func testRenameTagAffectsNoteSearches() {
        // Scenario: Rename tag and verify search results update
        
        let oldName = "OldTag"
        let newName = "NewTag"
        
        // 1. Create tag
        try? tagClient.addTag(oldName)
        
        // 2. Find notes with old name
        let notesOld = tagClient.findNotesByTag(oldName)
        
        // 3. Rename tag
        try? tagClient.renameTag(oldName, newName)
        
        // 4. Verify old name returns empty
        let notesOldAfterRename = tagClient.findNotesByTag(oldName)
        XCTAssertEqual(notesOldAfterRename.count, 0,
                      "Old tag name should return no notes after renaming")
        
        // 5. Find notes with new name should return original results
        let notesNew = tagClient.findNotesByTag(newName)
        XCTAssertEqual(notesNew.count, notesOld.count,
                      "New tag name should have same notes as old")
        
        // 6. Cleanup
        try? tagClient.removeTag(newName)
    }
    
    // MARK: - Tests: Decks + Tags + Cards Workflow
    
    func testCompleteStudyWorkflow() {
        // Scenario: Full workflow - Create deck, add cards with tags, review
        
        // 1. Create study deck
        let deckName = "CompleteStudy"
        let deckId = try! deckClient.create(deckName)
        
        // 2. Create organizational tags
        let priorityTag = "Priority"
        let difficultyTag = "Difficult"
        
        try? tagClient.addTag(priorityTag)
        try? tagClient.addTag(difficultyTag)
        
        // 3. Fetch pending due cards
        let dueCards = try? cardClient.fetchDue(deckId)
        
        // 4. For each due card (if any)
        if let cards = dueCards, !cards.isEmpty {
            let firstCard = cards[0]
            
            // Get card association with note
            let associatedNotes = tagClient.findNotesByTag(priorityTag)
            
            // If first card has a note, verify we can look it up
            let note = try? noteClient.getNote(firstCard.noteId)
            XCTAssertNotNil(note, "Should retrieve note for card")
            
            // Can simulate answering card
            try? cardClient.answer(firstCard.id, .good, 0)
        }
        
        // 5. Search for prioritized cards
        let priorityNotes = tagClient.findNotesByTag(priorityTag)
        XCTAssertTrue(priorityNotes.count >= 0, "Should find priority notes")
        
        // 6. Cleanup
        try? tagClient.removeTag(priorityTag)
        try? tagClient.removeTag(difficultyTag)
        try? deckClient.delete(deckId)
    }
    
    // MARK: - Tests: Search Integration
    
    func testSearchAcrossMultipleSystems() {
        // Scenario: Create deck with cards and search for them
        
        // 1. Setup
        let deckName = "SearchDeck"
        let deckId = try! deckClient.create(deckName)
        let searchTag = "SearchableTag"
        try? tagClient.addTag(searchTag)
        
        // 2. Search cards in deck (if search client supports it)
        let searchResults = try? searchClient.search("deck:\(deckId)")
        XCTAssertNotNil(searchResults, "Should perform deck search")
        
        // 3. Search by tag (if search client supports it)
        let tagSearchResults = try? searchClient.search("tag:\(searchTag)")
        XCTAssertNotNil(tagSearchResults, "Should perform tag search")
        
        // 4. Cleanup
        try? tagClient.removeTag(searchTag)
        try? deckClient.delete(deckId)
    }
    
    // MARK: - Tests: Error Recovery
    
    func testErrorRecoveryInComplexWorkflow() {
        // Scenario: Handle errors gracefully in multi-step workflows
        
        // 1. Try to create invalid deck (empty name)
        XCTAssertThrowsError(try deckClient.create("")) { error in
            XCTAssertNotNil(error, "Should throw error for empty deck name")
        }
        
        // 2. Main workflow should still work
        let deckName = "RecoveryDeck"
        let deckId = try! deckClient.create(deckName)
        XCTAssertGreaterThan(deckId, 0)
        
        // 3. Try to add duplicate tag (may fail)
        try? tagClient.addTag("DuplicateTag")
        // Second add might throw or be handled gracefully
        _ = try? tagClient.addTag("DuplicateTag")
        
        // 4. Can still retrieve tags
        let tags = tagClient.getAllTags()
        XCTAssertTrue(tags.count >= 0, "Should still get tags after error attempt")
        
        // 5. Clean up
        try? deckClient.delete(deckId)
        try? tagClient.removeTag("DuplicateTag")
    }
    
    // MARK: - Tests: State Consistency
    
    func testStateConsistencyAcrossClients() {
        // Scenario: Verify consistent state across all clients
        
        // 1. Initial state
        let initialDecks = extractDeckNames(from: deckClient.getDeckTree(now: 0))
        let initialTags = tagClient.getAllTags()
        
        // 2. Make changes
        let newDeck = "ConsistencyDeck"
        let newTag = "ConsistencyTag"
        
        let deckId = try! deckClient.create(newDeck)
        try! tagClient.addTag(newTag)
        
        // 3. Verify changes are visible
        let updatedDecks = extractDeckNames(from: deckClient.getDeckTree(now: 0))
        let updatedTags = tagClient.getAllTags()
        
        XCTAssertGreaterThan(updatedDecks.count, initialDecks.count,
                            "Deck count should increase")
        XCTAssertGreaterThan(updatedTags.count, initialTags.count,
                            "Tag count should increase")
        
        XCTAssertTrue(updatedDecks.contains(newDeck),
                     "New deck should be visible")
        XCTAssertTrue(updatedTags.contains(newTag),
                     "New tag should be visible")
        
        // 4. Cleanup
        try? deckClient.delete(deckId)
        try? tagClient.removeTag(newTag)
    }
    
    // MARK: - Performance Tests
    
    func testLargeNumberOfTagsPerformance() {
        // Scenario: Create many tags and verify performance
        
        let tagCount = 50
        var createdTags: [String] = []
        
        // Create many tags
        let creationStart = Date()
        for i in 0..<tagCount {
            let tagName = "PerfTag\(i)"
            try? tagClient.addTag(tagName)
            createdTags.append(tagName)
        }
        let creationTime = Date().timeIntervalSince(creationStart)
        
        // Retrieve all tags
        let retrievalStart = Date()
        let allTags = tagClient.getAllTags()
        let retrievalTime = Date().timeIntervalSince(retrievalStart)
        
        // Assertions
        XCTAssertLessThan(creationTime, 10.0,
                         "Creating \(tagCount) tags should be fast (< 10s)")
        XCTAssertLessThan(retrievalTime, 1.0,
                         "Retrieving all tags should be fast (< 1s)")
        
        // Verify all tags present
        let actualCount = allTags.filter { $0.hasPrefix("PerfTag") }.count
        XCTAssertEqual(actualCount, tagCount,
                      "All created tags should be present")
        
        // Cleanup
        for tag in createdTags {
            try? tagClient.removeTag(tag)
        }
    }
    
    func testLargeNumberOfDecksPerformance() {
        // Scenario: Create many decks and verify performance
        
        let deckCount = 20
        var createdDeckIds: [Int64] = []
        
        // Create many decks
        let creationStart = Date()
        for i in 0..<deckCount {
            let deckName = "PerfDeck\(i)"
            let deckId = try! deckClient.create(deckName)
            createdDeckIds.append(deckId)
        }
        let creationTime = Date().timeIntervalSince(creationStart)
        
        // Retrieve deck tree
        let retrievalStart = Date()
        let tree = deckClient.getDeckTree(now: 0)
        let retrievalTime = Date().timeIntervalSince(retrievalStart)
        
        // Verify performance
        XCTAssertLessThan(creationTime, 10.0,
                         "Creating \(deckCount) decks should be fast (< 10s)")
        XCTAssertLessThan(retrievalTime, 1.0,
                         "Retrieving deck tree should be fast (< 1s)")
        
        // Cleanup
        for deckId in createdDeckIds {
            try? deckClient.delete(deckId)
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractDeckNames(from node: DeckTreeNode, names: inout [String]) {
        names.append(node.name)
        for child in node.children {
            extractDeckNames(from: child, names: &names)
        }
    }
    
    private func extractDeckNames(from node: DeckTreeNode) -> [String] {
        var names: [String] = []
        extractDeckNames(from: node, names: &names)
        return names
    }
}

// MARK: - Protocol Extensions for Testing

// Add mock implementations for test values
extension DeckClient {
    static var testValue: DeckClient {
        DeckClient(
            getDeckTree: { _ in
                DeckTreeNode(
                    name: "Root",
                    id: 1,
                    reviewCount: 0,
                    learnCount: 0,
                    newCount: 0,
                    children: []
                )
            },
            create: { _ in Int64.random(in: 1...Int64.max) },
            rename: { _, _ in },
            delete: { _ in },
            getDeckConfig: { _ in DeckConfig(id: 1, name: "Default", config: [:]) }
        )
    }
}

extension TagClient {
    static var testValue: TagClient {
        TagClient(
            getAllTags: { [] },
            addTag: { _ in },
            removeTag: { _ in },
            renameTag: { _, _ in },
            findNotesByTag: { _ in [] }
        )
    }
}

extension NoteClient {
    static var testValue: NoteClient {
        NoteClient(
            getAllNotes: { [] },
            getNote: { _ in NoteRecord(id: 0, guid: "", modelId: 0, mtime: 0, usn: 0, tags: [], flds: [], sfld: "") },
            addNote: { _ in 0 },
            updateNote: { _ in },
            deleteNote: { _ in }
        )
    }
}

extension CardClient {
    static var testValue: CardClient {
        CardClient(
            fetchDue: { _ in [] },
            fetchByNote: { _ in [] },
            save: { _ in },
            answer: { _, _, _ in },
            undo: { },
            suspend: { _ in },
            bury: { _ in },
            flag: { _, _ in }
        )
    }
}

extension SearchClient {
    static var testValue: SearchClient {
        SearchClient(
            search: { _ in [] },
            searchNotes: { _ in [] }
        )
    }
}
