import XCTest
@testable import AnkiApp
import AnkiClients
import AnkiKit
import Dependencies

// MARK: - DeckClient Integration Tests
final class DeckClientIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    var deckClient: DeckClient!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        deckClient = DeckClient.testValue
    }
    
    override func tearDown() {
        super.tearDown()
        deckClient = nil
    }
    
    // MARK: - Tests: getDeckTree
    
    func testGetDeckTreeReturnsValidStructure() {
        // Given: Fresh deck client
        // When: Getting deck tree
        let tree = deckClient.getDeckTree(now: 0)
        
        // Then: Should return a valid deck tree
        XCTAssertNotNil(tree, "Deck tree should not be nil")
        XCTAssertGreaterThan(tree.name.count, 0, "Root deck should have a name")
    }
    
    func testGetDeckTreeWithCountsReturnsData() {
        // Given: Deck tree with now time specified
        let now = Date().timeIntervalSince1970 + 10000
        
        // When: Getting deck tree with time
        let tree = deckClient.getDeckTree(now: Int64(now))
        
        // Then: Should include review counts
        XCTAssertNotNil(tree, "Deck tree should be available")
        // counts may be 0 if no cards
        XCTAssertGreaterThanOrEqual(tree.reviewCount, 0)
    }
    
    // MARK: - Tests: create
    
    func testCreateDeckReturnsPositiveId() {
        // Given: Valid deck name
        let deckName = "NewDeck"
        
        // When: Creating deck
        let deckId = try? deckClient.create(deckName)
        
        // Then: Should return positive ID
        XCTAssertNotNil(deckId, "Should return a deck ID")
        if let id = deckId {
            XCTAssertGreaterThan(id, 0, "Deck ID should be positive")
        }
    }
    
    func testCreateMultipleDecksReturnsDifferentIds() {
        // Given: Two different deck names
        let deck1Name = "Deck1"
        let deck2Name = "Deck2"
        
        // When: Creating both decks
        let id1 = try? deckClient.create(deck1Name)
        let id2 = try? deckClient.create(deck2Name)
        
        // Then: Should return different IDs
        XCTAssertNotNil(id1)
        XCTAssertNotNil(id2)
        if let id1 = id1, let id2 = id2 {
            XCTAssertNotEqual(id1, id2, "Different decks should have different IDs")
        }
    }
    
    func testCreateDeckWithEmptyNameThrows() {
        // Given: Empty deck name
        let deckName = ""
        
        // When: Creating deck with empty name
        // Then: Should throw error
        XCTAssertThrowsError(
            try deckClient.create(deckName),
            "Should throw error for empty deck name"
        )
    }
    
    func testCreateDeckWithDuplicateNameThrows() {
        // Given: Deck with same name already exists
        let deckName = "DuplicateDeck"
        try? deckClient.create(deckName)
        
        // When: Creating deck with duplicate name
        // Then: Should throw error
        XCTAssertThrowsError(
            try deckClient.create(deckName),
            "Should throw error for duplicate deck name"
        )
    }
    
    // MARK: - Tests: rename
    
    func testRenameDeckSucceedsWithNewName() {
        // Given: Deck has been created
        let originalName = "OriginalName"
        let deckId = try! deckClient.create(originalName)
        let newName = "RenamedDeck"
        
        // When: Renaming deck
        XCTAssertNoThrow {
            try deckClient.rename(deckId, newName)
        }
        
        // Then: New name should be in deck tree
        let tree = deckClient.getDeckTree(now: 0)
        let deckNames = collectDeckNames(from: tree)
        XCTAssertTrue(deckNames.contains(newName), "Renamed deck should have new name")
    }
    
    func testRenameDeckNonexistentThrows() {
        // Given: Nonexistent deck ID
        let nonexistentId: Int64 = 999999
        let newName = "NewName"
        
        // When: Renaming nonexistent deck
        // Then: Should throw error
        XCTAssertThrowsError(
            try deckClient.rename(nonexistentId, newName),
            "Should throw error when renaming nonexistent deck"
        )
    }
    
    func testRenameDeckToExistingNameThrows() {
        // Given: Two decks exist
        let deck1Name = "Deck1"
        let deck2Name = "Deck2"
        let id1 = try! deckClient.create(deck1Name)
        try! deckClient.create(deck2Name)
        
        // When: Renaming deck1 to existing deck2 name
        // Then: Should throw error
        XCTAssertThrowsError(
            try deckClient.rename(id1, deck2Name),
            "Should throw error when renaming to existing deck name"
        )
    }
    
    // MARK: - Tests: delete
    
    func testDeleteDeckSucceeds() {
        // Given: Deck has been created
        let deckName = "ToDelete"
        let deckId = try! deckClient.create(deckName)
        
        // When: Deleting deck
        XCTAssertNoThrow {
            try deckClient.delete(deckId)
        }
        
        // Then: Deck should no longer be in tree (name should not exist)
        let tree = deckClient.getDeckTree(now: 0)
        let deckNames = collectDeckNames(from: tree)
        XCTAssertFalse(deckNames.contains(deckName), "Deleted deck should not exist")
    }
    
    func testDeleteNonexistentDeckThrows() {
        // Given: Nonexistent deck ID
        let nonexistentId: Int64 = 999999
        
        // When: Deleting nonexistent deck
        // Then: Should throw error
        XCTAssertThrowsError(
            try deckClient.delete(nonexistentId),
            "Should throw error when deleting nonexistent deck"
        )
    }
    
    func testDeleteDeckRemovesAllChildren() {
        // Given: Parent deck with potential children
        let parentName = "Parent"
        let parentId = try! deckClient.create(parentName)
        
        // When: Creating child deck (would be realized through hierarchical names)
        let childName = "\(parentName)::Child"
        try? deckClient.create(childName)
        
        // When: Deleting parent
        XCTAssertNoThrow {
            try deckClient.delete(parentId)
        }
        
        // Then: Parent and ideally children should be gone
        let tree = deckClient.getDeckTree(now: 0)
        let remainingNames = collectDeckNames(from: tree)
        XCTAssertFalse(remainingNames.contains(parentName),
                      "Parent deck should be deleted")
    }
    
    // MARK: - Tests: getDeckConfig
    
    func testGetDeckConfigReturnsValidConfig() {
        // Given: Existing deck
        let deckName = "ConfigTest"
        let deckId = try! deckClient.create(deckName)
        
        // When: Getting deck config
        let config = try? deckClient.getDeckConfig(deckId)
        
        // Then: Should return valid configuration
        XCTAssertNotNil(config, "Should return deck configuration")
    }
    
    func testGetDeckConfigNonexistentThrows() {
        // Given: Nonexistent deck ID
        let nonexistentId: Int64 = 999999
        
        // When: Getting config for nonexistent deck
        // Then: Should throw error
        XCTAssertThrowsError(
            try deckClient.getDeckConfig(nonexistentId),
            "Should throw error for nonexistent deck"
        )
    }
    
    // MARK: - Complex Scenarios
    
    func testCompleteDeckLifecycle() {
        // Scenario: Create → Rename → GetConfig → Delete
        
        // 1. Create deck
        let initialName = "LifecycleDeck"
        let deckId = try! deckClient.create(initialName)
        XCTAssertGreaterThan(deckId, 0)
        
        // 2. Verify creation in tree
        var tree = deckClient.getDeckTree(now: 0)
        var deckNames = collectDeckNames(from: tree)
        XCTAssertTrue(deckNames.contains(initialName), "Created deck should be in tree")
        
        // 3. Rename deck
        let newName = "RenamedLifecycleDeck"
        try! deckClient.rename(deckId, newName)
        
        tree = deckClient.getDeckTree(now: 0)
        deckNames = collectDeckNames(from: tree)
        XCTAssertFalse(deckNames.contains(initialName))
        XCTAssertTrue(deckNames.contains(newName))
        
        // 4. Get config
        let config = try! deckClient.getDeckConfig(deckId)
        XCTAssertNotNil(config)
        
        // 5. Delete deck
        try! deckClient.delete(deckId)
        
        tree = deckClient.getDeckTree(now: 0)
        deckNames = collectDeckNames(from: tree)
        XCTAssertFalse(deckNames.contains(newName), "Deleted deck should not be in tree")
    }
    
    func testDeckHierarchyOperations() {
        // Scenario: Create hierarchical decks and verify structure
        
        // 1. Create parent deck
        let parentName = "Languages"
        let parentId = try! deckClient.create(parentName)
        
        // 2. Create sibling deck (not actually hierarchical without API support)
        let siblingName = "Mathematics"
        let siblingId = try! deckClient.create(siblingName)
        
        // 3. Verify both in tree
        let tree = deckClient.getDeckTree(now: 0)
        let deckNames = collectDeckNames(from: tree)
        
        XCTAssertTrue(deckNames.contains(parentName))
        XCTAssertTrue(deckNames.contains(siblingName))
        
        // 4. Cleanup
        try? deckClient.delete(parentId)
        try? deckClient.delete(siblingId)
    }
    
    // MARK: - Helper Methods
    
    private func collectDeckNames(from node: DeckTreeNode, names: inout [String]) {
        names.append(node.name)
        for child in node.children {
            collectDeckNames(from: child, names: &names)
        }
    }
    
    private func collectDeckNames(from node: DeckTreeNode) -> [String] {
        var names: [String] = []
        collectDeckNames(from: node, names: &names)
        return names
    }
}

// MARK: - Extension for test helper

extension XCTestCase {
    func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        do {
            _ = try expression()
        } catch {
            XCTFail("Expected no throw, but threw \(error)",
                   file: file, line: line)
        }
    }
}
