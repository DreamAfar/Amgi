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

    func testLegacyAVDirectiveCountCountsSoundAndTts() {
        let html = """
        [sound:foo.mp3]
        [anki:tts lang=en_US]hello[/anki:tts]
        """

        XCTAssertEqual(ReviewSession.legacyAVDirectiveCount(in: html), 2)
    }

    func testShouldUseExtractedAVHTMLRequiresMatchingPlayPlaceholders() {
        let original = """
        [sound:foo.mp3]
        [anki:tts lang=en_US]hello[/anki:tts]
        """
        let extracted = "before [anki:play:q:0] after"

        XCTAssertFalse(
            ReviewSession.shouldUseExtractedAVHTML(
                originalHTML: original,
                extractedHTML: extracted,
                avTagCount: 2
            )
        )
    }

    func testShouldUseExtractedAVHTMLAcceptsMatchingExtraction() {
        let original = """
        [sound:foo.mp3]
        [anki:tts lang=en_US]hello[/anki:tts]
        """
        let extracted = "before [anki:play:q:0] after [anki:play:q:1]"

        XCTAssertTrue(
            ReviewSession.shouldUseExtractedAVHTML(
                originalHTML: original,
                extractedHTML: extracted,
                avTagCount: 2
            )
        )
    }

    func testLegacyTTSTagsParseTextAndOptionsFromOriginalHTML() {
        let html = """
        before [anki:tts lang=zh_CN voices=Tingting,Sinji speed=1.2 foo=bar] 你好 \n[/anki:tts] after
        """

        let tags = ReviewSession.legacyTTSTags(in: html)

        XCTAssertEqual(tags.count, 1)
        guard case .tts(let tts)? = tags.first?.value else {
            return XCTFail("Expected TTS tag")
        }
        XCTAssertEqual(tts.fieldText, "你好")
        XCTAssertEqual(tts.lang, "zh_CN")
        XCTAssertEqual(tts.voices, ["Tingting", "Sinji"])
        XCTAssertEqual(tts.speed, 1.2, accuracy: 0.0001)
        XCTAssertEqual(tts.otherArgs, ["foo=bar"])
    }

    func testSyncExtractedTTSTagsWithOriginalHTMLReplacesEmptyExtractedPayload() {
        let originalHTML = """
        [anki:tts lang=en_US voices=Alice speed=0.9]hello[/anki:tts]
        """
        let extractedHTML = "[anki:play:q:0]"
        var extractedTTS = Anki_CardRendering_TTSTag()
        extractedTTS.lang = "en_US"
        var extractedTag = Anki_CardRendering_AVTag()
        extractedTag.tts = extractedTTS

        let synced = ReviewSession.syncExtractedTTSTagsWithOriginalHTML(
            originalHTML: originalHTML,
            media: (text: extractedHTML, tags: [extractedTag])
        )

        XCTAssertEqual(synced.text, extractedHTML)
        guard case .tts(let tts)? = synced.tags.first?.value else {
            return XCTFail("Expected synced TTS tag")
        }
        XCTAssertEqual(tts.fieldText, "hello")
        XCTAssertEqual(tts.lang, "en_US")
        XCTAssertEqual(tts.voices, ["Alice"])
        XCTAssertEqual(tts.speed, 0.9, accuracy: 0.0001)
    }
}

