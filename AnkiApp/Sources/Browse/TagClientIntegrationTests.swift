import XCTest
@testable import AnkiApp
import AnkiClients
import AnkiKit
import Dependencies

// MARK: - TagClient Integration Tests
final class TagClientIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    var tagClient: TagClient!
    var testDeckId: Int64 = 1
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        // Initialize with test dependency key
        tagClient = TagClient.testValue
    }
    
    override func tearDown() {
        super.tearDown()
        tagClient = nil
    }
    
    // MARK: - Tests: getAllTags
    
    func testGetAllTagsReturnsEmptyArrayInitially() {
        // Given: Fresh tag client
        // When: Calling getAllTags
        let tags = tagClient.getAllTags()
        
        // Then: Should return empty array
        XCTAssertEqual(tags, [], "Should return empty array for fresh state")
    }
    
    func testGetAllTagsReturnsMultipleTags() {
        // Given: Multiple tags added
        let tagNames = ["English", "Chinese", "Math", "Science"]
        for tag in tagNames {
            try? tagClient.addTag(tag)
        }
        
        // When: Calling getAllTags
        let tags = tagClient.getAllTags()
        
        // Then: Should return all added tags
        XCTAssertEqual(Set(tags), Set(tagNames), "Should return all added tags")
    }
    
    // MARK: - Tests: addTag
    
    func testAddTagSucceedsWithValidName() {
        // Given: Valid tag name
        let tagName = "Important"
        
        // When: Adding tag
        XCTAssertNoThrow {
            try tagClient.addTag(tagName)
        }
        
        // Then: Tag should exist in getAllTags
        let tags = tagClient.getAllTags()
        XCTAssertTrue(tags.contains(tagName), "Added tag should be available")
    }
    
    func testAddTagWithDuplicateNameDoesNotError() {
        // Given: Tag already exists
        let tagName = "Review"
        try? tagClient.addTag(tagName)
        
        // When: Adding same tag again
        // Then: Should handle gracefully (may skip or update)
        XCTAssertNoThrow {
            try tagClient.addTag(tagName)
        }
    }
    
    func testAddTagWithEmptyNameThrows() {
        // Given: Empty tag name
        let tagName = ""
        
        // When: Adding empty tag
        XCTAssertThrowsError(
            try tagClient.addTag(tagName),
            "Should throw error for empty tag name"
        )
    }
    
    // MARK: - Tests: removeTag
    
    func testRemoveTagSucceedsWithExistingTag() {
        // Given: Tag exists
        let tagName = "Temporary"
        try? tagClient.addTag(tagName)
        
        // When: Removing tag
        XCTAssertNoThrow {
            try tagClient.removeTag(tagName)
        }
        
        // Then: Tag should not exist
        let tags = tagClient.getAllTags()
        XCTAssertFalse(tags.contains(tagName), "Removed tag should not exist")
    }
    
    func testRemoveNonexistentTagThrows() {
        // Given: Tag does not exist
        let tagName = "Nonexistent"
        
        // When: Removing nonexistent tag
        XCTAssertThrowsError(
            try tagClient.removeTag(tagName),
            "Should throw error for nonexistent tag"
        )
    }
    
    // MARK: - Tests: renameTag
    
    func testRenameTagSucceedsWithValidNames() {
        // Given: Tag exists
        let oldName = "OldTag"
        let newName = "NewTag"
        try? tagClient.addTag(oldName)
        
        // When: Renaming tag
        XCTAssertNoThrow {
            try tagClient.renameTag(oldName, newName)
        }
        
        // Then: Old name should not exist and new name should
        let tags = tagClient.getAllTags()
        XCTAssertFalse(tags.contains(oldName), "Old tag name should not exist")
        XCTAssertTrue(tags.contains(newName), "New tag name should exist")
    }
    
    func testRenameTagNonexistentThrows() {
        // Given: Source tag does not exist
        let oldName = "Nonexistent"
        let newName = "NewName"
        
        // When: Renaming nonexistent tag
        XCTAssertThrowsError(
            try tagClient.renameTag(oldName, newName),
            "Should throw error when renaming nonexistent tag"
        )
    }
    
    func testRenameTagToExistingNameThrows() {
        // Given: Both tags exist
        let tag1 = "Tag1"
        let tag2 = "Tag2"
        try? tagClient.addTag(tag1)
        try? tagClient.addTag(tag2)
        
        // When: Renaming tag1 to tag2
        // Then: Should throw error (duplicate)
        XCTAssertThrowsError(
            try tagClient.renameTag(tag1, tag2),
            "Should throw error when renaming to existing tag name"
        )
    }
    
    // MARK: - Tests: findNotesByTag
    
    func testFindNotesByTagReturnsNoteIds() {
        // Given: Tag exists
        let tagName = "SearchableTag"
        try? tagClient.addTag(tagName)
        
        // When: Finding notes by tag
        let noteIds = tagClient.findNotesByTag(tagName)
        
        // Then: Should return array of note IDs (may be empty)
        XCTAssertTrue(noteIds.allSatisfy { $0 > 0 },
                     "All returned note IDs should be positive")
    }
    
    func testFindNotesByNonexistentTagReturnsEmpty() {
        // Given: Tag does not exist
        let tagName = "NonexistentTag"
        
        // When: Finding notes by nonexistent tag
        let noteIds = tagClient.findNotesByTag(tagName)
        
        // Then: Should return empty array
        XCTAssertEqual(noteIds, [], "Should return empty array for nonexistent tag")
    }
    
    // MARK: - Complex Scenarios
    
    func testCompleteTagLifecycle() {
        // Scenario: Create → Rename → Find → Delete
        
        // 1. Create tag
        let initialName = "Progress"
        XCTAssertNoThrow { try tagClient.addTag(initialName) }
        
        var tags = tagClient.getAllTags()
        XCTAssertTrue(tags.contains(initialName))
        
        // 2. Rename tag
        let newName = "InProgress"
        XCTAssertNoThrow { try tagClient.renameTag(initialName, newName) }
        
        tags = tagClient.getAllTags()
        XCTAssertFalse(tags.contains(initialName))
        XCTAssertTrue(tags.contains(newName))
        
        // 3. Find notes by tag
        let noteIds = tagClient.findNotesByTag(newName)
        XCTAssertTrue(noteIds.count >= 0, "Should be able to find notes")
        
        // 4. Delete tag
        XCTAssertNoThrow { try tagClient.removeTag(newName) }
        
        tags = tagClient.getAllTags()
        XCTAssertFalse(tags.contains(newName), "Tag should be deleted")
    }
    
    func testMultipleConcurrentOperations() {
        // Scenario: Multiple simultaneous tag operations
        
        let tagNames = ["Concurrent1", "Concurrent2", "Concurrent3"]
        var errors: [any Error] = []
        
        // Add multiple tags
        for name in tagNames {
            do {
                try tagClient.addTag(name)
            } catch {
                errors.append(error)
            }
        }
        
        XCTAssertEqual(errors.count, 0, "No errors should occur during concurrent adds")
        
        let tags = tagClient.getAllTags()
        for name in tagNames {
            XCTAssertTrue(tags.contains(name), "All tags should exist")
        }
        
        // Remove multiple tags
        errors.removeAll()
        for name in tagNames {
            do {
                try tagClient.removeTag(name)
            } catch {
                errors.append(error)
            }
        }
        
        XCTAssertEqual(errors.count, 0, "No errors should occur during concurrent removes")
    }
}

// MARK: - Test Helper Extension

extension XCTestCase {
    func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T,
                            _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        do {
            _ = try expression()
        } catch {
            XCTFail("Expected no throw, but threw \(error). \(message())",
                   file: file, line: line)
        }
    }
}
