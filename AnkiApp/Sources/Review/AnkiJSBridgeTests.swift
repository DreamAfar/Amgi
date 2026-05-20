import XCTest
import AnkiKit
@testable import AnkiApp

@MainActor
final class AnkiJSBridgeTests: XCTestCase {
    func testNewCardCountReturnsJSONPayload() {
        let bridge = makeBridge(
            counts: DeckCounts(newCount: 7, learnCount: 3, reviewCount: 2)
        )

        let (response, error) = bridge.handleMessage(
            request(endpoint: "newCardCount")
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":7}"#)
    }

    func testNextTimeReturnsRawString() {
        let bridge = makeBridge(nextTime: { ease in
            ease == 3 ? "4d" : nil
        })

        let (response, error) = bridge.handleMessage(
            request(endpoint: "nextTime3")
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, "4d")
    }

    func testAnswerEaseForwardsTypedAnswerPayload() {
        var capturedEase: Int?
        var capturedTypedAnswer: String?
        let bridge = makeBridge(
            answerEase: { ease, typedAnswer in
                capturedEase = ease
                capturedTypedAnswer = typedAnswer
            }
        )

        let (response, error) = bridge.handleMessage(
            request(
                endpoint: "answerEase3",
                data: #"{"typedAnswer":"typed-value"}"#
            )
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":true}"#)
        XCTAssertEqual(capturedEase, 3)
        XCTAssertEqual(capturedTypedAnswer, "typed-value")
    }

    func testToggleFlagClearsMatchingCurrentFlag() {
        var appliedFlag: UInt32?
        let bridge = makeBridge(
            cardInfo: .init(
                cardId: 1,
                noteId: 2,
                deckId: 3,
                cardType: 0,
                left: 0,
                originalDeckId: 0,
                originalDue: 0,
                queue: 0,
                lapses: 0,
                due: 0,
                reps: 0,
                interval: 0,
                factor: 0,
                modified: 0,
                userFlag: 1,
                isMarked: false
            ),
            setFlag: { value in
                appliedFlag = value
            }
        )

        let (response, error) = bridge.handleMessage(
            request(endpoint: "toggleFlag", data: "red")
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":true}"#)
        XCTAssertEqual(appliedFlag, 0)
    }

    func testSetNoteTagsSanitizesWhitespaceBeforeSaving() {
        var savedTags: [String] = []
        let bridge = makeBridge(
            setNoteTags: { tags in
                savedTags = tags
            }
        )

        let (response, error) = bridge.handleMessage(
            request(
                endpoint: "setNoteTags",
                data: #"{"tags":[" foo bar ","baz","a　b",""]}"#
            )
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":true}"#)
        XCTAssertEqual(savedTags, ["foo_bar", "baz", "a_b"])
    }

    func testShowToastDecodesPercentEscapes() {
        var capturedMessage: String?
        var capturedShortLength = false
        let bridge = makeBridge(
            showToast: { message, shortLength in
                capturedMessage = message
                capturedShortLength = shortLength
            }
        )

        let (response, error) = bridge.handleMessage(
            request(
                endpoint: "showToast",
                data: #"{"text":"hello%20world","shortLength":false}"#
            )
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":true}"#)
        XCTAssertEqual(capturedMessage, "hello world")
        XCTAssertFalse(capturedShortLength)
    }

    func testGetETAReturnsJSONPayload() {
        let bridge = makeBridge(getETA: { 9 })

        let (response, error) = bridge.handleMessage(
            request(endpoint: "eta")
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":9}"#)
    }

    func testAddTagToCardRoutesToContext() {
        var didOpenTagEditor = false
        let bridge = makeBridge(
            addTagToCurrentCard: {
                didOpenTagEditor = true
            }
        )

        let (response, error) = bridge.handleMessage(
            request(endpoint: "addTagToCard")
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":true}"#)
        XCTAssertTrue(didOpenTagEditor)
    }

    func testSearchCardWithCallbackEvaluatesJSCallback() {
        var evaluatedScript: String?
        let bridge = makeBridge(
            searchCardWithCallbackPayload: { _ in #"[{"cardId":1,"noteId":2,"fieldsData":{"Front":"hello"}}]"# },
            jsEvaluator: { script in
                evaluatedScript = script
            }
        )

        let (response, error) = bridge.handleMessage(
            request(endpoint: "searchCardWithCallback", data: "deck:test")
        )

        XCTAssertNil(error)
        XCTAssertEqual(response as? String, #"{"success":true,"value":true}"#)
        XCTAssertNotNil(evaluatedScript)
        XCTAssertTrue(evaluatedScript?.contains("window.runHook(\"ankiSearchCard\"") == true)
        XCTAssertTrue(evaluatedScript?.contains("JSON.parse") == true)
        XCTAssertTrue(evaluatedScript?.contains("Front") == true)
    }

    func testInjectedScriptContainsCompatibilityAliases() {
        let script = AnkiJSInjectedScript.source(handlerName: AnkiJSBridge.messageHandlerName)

        XCTAssertTrue(script.contains("class AnkiDroidJS"))
        XCTAssertTrue(script.contains("window.AnkiJS = AnkiDroidJS"))
        XCTAssertTrue(script.contains(AnkiJSBridge.messageHandlerName))
        XCTAssertTrue(script.contains("ankiShowToast"))
        XCTAssertTrue(script.contains("ankiAddTagToCard"))
        XCTAssertTrue(script.contains("ankiGetETA"))
        XCTAssertTrue(script.contains("ankiSearchCardWithCallback"))
        XCTAssertTrue(script.contains("function addHook"))
        XCTAssertTrue(script.contains("function runHook"))
    }

    private func request(endpoint: String, data: Any? = nil) -> [String: Any] {
        [
            "endpoint": endpoint,
            "developer": "tests@example.com",
            "version": AnkiJSBridge.apiVersion,
            "data": data ?? NSNull(),
        ]
    }

    private func makeBridge(
        counts: DeckCounts = .zero,
        nextTime: @escaping (Int) -> String? = { _ in nil },
        cardInfo: AnkiJSCardInfo = .init(
            cardId: 1,
            noteId: 2,
            deckId: 3,
            cardType: 0,
            left: 0,
            originalDeckId: 0,
            originalDue: 0,
            queue: 0,
            lapses: 0,
            due: 0,
            reps: 0,
            interval: 0,
            factor: 0,
            modified: 0,
            userFlag: 0,
            isMarked: false
        ),
        answerEase: @escaping (Int, String?) throws -> Void = { _, _ in },
        getETA: @escaping () -> Int = { 0 },
        buryNote: @escaping () throws -> Void = {},
        suspendNote: @escaping () throws -> Void = {},
        setFlag: @escaping (UInt32) throws -> Void = { _ in },
        setNoteTags: @escaping ([String]) throws -> Void = { _ in },
        addTagToCurrentCard: @escaping () throws -> Void = {},
        searchCardWithCallbackPayload: @escaping (String) throws -> String = { _ in "[]" },
        showToast: @escaping (String, Bool) -> Void = { _, _ in },
        jsEvaluator: @escaping (String) -> Void = { _ in }
    ) -> AnkiJSBridge {
        let context = AnkiJSContext(
            isDisplayingAnswer: { false },
            isNightMode: { false },
            showAnswer: { _ in },
            answerEase: answerEase,
            getCounts: { counts },
            getETA: getETA,
            getNextTime: nextTime,
            getCardInfo: { cardInfo },
            getDeckName: { "Default" },
            buryCard: {},
            buryNote: buryNote,
            suspendCard: {},
            suspendNote: suspendNote,
            resetProgress: {},
            setCardDue: { _ in },
            toggleMark: { false },
            setFlag: setFlag,
            getNoteTags: { [] },
            setNoteTags: setNoteTags,
            addTagToCurrentCard: addTagToCurrentCard,
            addTagToNote: { _, _ in },
            searchCard: { _ in },
            searchCardWithCallbackPayload: searchCardWithCallbackPayload,
            showToast: showToast
        )

        return AnkiJSBridge(
            context: context,
            ttsController: .init(
                speak: { _ in },
                stop: {},
                isSpeaking: { false }
            ),
            scrollController: .init(
                setHorizontalScrollbarEnabled: { _ in },
                setVerticalScrollbarEnabled: { _ in }
            ),
            jsEvaluator: jsEvaluator
        )
    }
}
