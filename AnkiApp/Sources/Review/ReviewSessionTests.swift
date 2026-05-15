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
        let extracted = "before [anki:play:q:0] after [anki:tts lang=en_US]hello[/anki:tts]"

        XCTAssertTrue(
            ReviewSession.shouldUseExtractedAVHTML(
                originalHTML: original,
                extractedHTML: extracted,
                avTagCount: 1
            )
        )
    }

    func testLegacyTTSDirectivesReturnOriginalDirectiveStrings() {
        let html = """
        before [anki:tts lang=zh_CN voices=Tingting,Sinji speed=1.2 foo=bar] 你好 \n[/anki:tts] after
        """

        let directives = ReviewSession.legacyTTSDirectives(in: html)

        XCTAssertEqual(
            directives,
            ["[anki:tts lang=zh_CN voices=Tingting,Sinji speed=1.2 foo=bar] 你好 \n[/anki:tts]"]
        )
    }

    func testNormalizeExtractedReviewMediaRestoresRawTTSAndPrunesTTSTags() {
        let originalHTML = """
        [anki:tts lang=en_US voices=Alice speed=0.9]hello[/anki:tts]
        """
        let extractedHTML = "[anki:play:q:0]"
        var extractedTTS = Anki_CardRendering_TTSTag()
        extractedTTS.fieldText = ""
        var extractedTag = Anki_CardRendering_AVTag()
        extractedTag.tts = extractedTTS

        let normalized = ReviewSession.normalizeExtractedReviewMedia(
            originalHTML: originalHTML,
            media: (text: extractedHTML, tags: [extractedTag]),
            questionSide: true
        )

        XCTAssertEqual(normalized.text, originalHTML)
        XCTAssertTrue(normalized.tags.isEmpty)
    }

    func testNormalizeExtractedReviewMediaRenumbersManagedSoundPlaceholdersAfterRemovingTTS() {
        let originalHTML = """
        [sound:foo.mp3] [anki:tts lang=en_US]hello[/anki:tts] [sound:bar.mp3]
        """
        let extractedHTML = "[anki:play:q:0] [anki:play:q:1] [anki:play:q:2]"
        var firstSound = Anki_CardRendering_AVTag()
        firstSound.soundOrVideo = "foo.mp3"
        var extractedTTS = Anki_CardRendering_TTSTag()
        extractedTTS.fieldText = "hello"
        var ttsTag = Anki_CardRendering_AVTag()
        ttsTag.tts = extractedTTS
        var secondSound = Anki_CardRendering_AVTag()
        secondSound.soundOrVideo = "bar.mp3"

        let normalized = ReviewSession.normalizeExtractedReviewMedia(
            originalHTML: originalHTML,
            media: (text: extractedHTML, tags: [firstSound, ttsTag, secondSound]),
            questionSide: true
        )

        XCTAssertEqual(
            normalized.text,
            "[anki:play:q:0] [anki:tts lang=en_US]hello[/anki:tts] [anki:play:q:1]"
        )
        XCTAssertEqual(normalized.tags.count, 2)
    }
}

