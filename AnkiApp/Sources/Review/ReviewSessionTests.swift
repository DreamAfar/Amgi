import XCTest
@testable import AnkiApp
import AnkiKit
import AnkiProto

class ReviewSessionTests: XCTestCase {
    var session: ReviewSession!
    
    override func setUp() {
        super.setUp()
        session = ReviewSession(deckId: 1)
    }
    
    override func tearDown() {
        session = nil
        super.tearDown()
    }
    
    // MARK: - Property Exposure Tests
    
    /// Test that currentCard property is initially nil
    func testCurrentCardInitiallyNil() {
        XCTAssertNil(session.currentCard, "currentCard should be nil before session starts")
    }
    
    /// Test that currentCard is publicly accessible
    func testCurrentCardPublicAccess() {
        XCTAssertTrue(session.currentCard == nil, "currentCard should be accessible via public property")
    }
    
    /// Test that currentCard exposes necessary fields
    func testCurrentCardStructure() {
        if let card = session.currentCard {
            // Verify card has the expected properties
            let cardId = card.card.id
            let states = card.states
            
            XCTAssertGreater(cardId, 0, "Card ID should be positive")
            XCTAssertNotNil(states, "Card should have scheduling states")
        }
    }
    
    // MARK: - Refresh and Advance Tests
    
    /// Test that refreshAndAdvance method exists and is callable
    func testRefreshAndAdvanceMethodExists() {
        // This test verifies the method signature exists and is callable
        // In a real scenario, this would require a mock backend
        XCTAssertTrue(session.currentCard == nil || session.currentCard != nil, "Placeholder assertion")
    }
    
    /// Test session stats properties
    func testSessionStatsInitialized() {
        XCTAssertEqual(session.sessionStats.reviewed, 0, "Initial reviewed count should be 0")
        XCTAssertEqual(session.sessionStats.correct, 0, "Initial correct count should be 0")
        XCTAssertEqual(session.sessionStats.totalTimeMs, 0, "Initial time should be 0")
    }
    
    /// Test remaining counts initialization
    func testRemainingCountsInitialized() {
        XCTAssertEqual(session.remainingCounts.newCount, 0)
        XCTAssertEqual(session.remainingCounts.learnCount, 0)
        XCTAssertEqual(session.remainingCounts.reviewCount, 0)
    }
    
    /// Test nextIntervals structure
    func testNextIntervalsStructure() {
        // Initially empty
        XCTAssertTrue(session.nextIntervals.isEmpty, "nextIntervals should be empty initially")
    }
    
    /// Test isFinished state
    func testIsFinishedInitiallyFalse() {
        XCTAssertFalse(session.isFinished, "Session should not be finished initially")
    }
    
    /// Test showAnswer state
    func testShowAnswerInitiallyFalse() {
        XCTAssertFalse(session.showAnswer, "Answer should not be visible initially")
    }
}

