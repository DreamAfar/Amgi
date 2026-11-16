//
//  AnkiDroidJSProtocolTests.swift
//  ReviewCoreTests
//

import AnkiKit
import Foundation
import Testing
@testable import ReviewCore

@Suite("AnkiDroid JS API protocol")
struct AnkiDroidJSProtocolTests {

    @Test func requestReadsTheShimBody() {
        let request = AnkiDroidJSRequest(body: [
            "endpoint": "toggleFlag", "developer": "dev@example.com", "version": "0.0.3", "data": "red",
        ])
        #expect(request == AnkiDroidJSRequest(endpoint: "toggleFlag", developer: "dev@example.com", version: "0.0.3", data: "red"))
        #expect(AnkiDroidJSRequest(body: ["developer": "x"]) == nil)
        #expect(AnkiDroidJSRequest(body: "nope") == nil)
    }

    @Test func dataBecomesTextLikeAnkiDroidsOptString() {
        #expect(AnkiDroidJSRequest.text(NSNumber(value: 5)) == "5")
        #expect(AnkiDroidJSRequest.text(NSNumber(value: 1.5)) == "1.5")
        #expect(AnkiDroidJSRequest.text(NSNumber(value: true)) == "true")
        #expect(AnkiDroidJSRequest.text("red") == "red")
        #expect(AnkiDroidJSRequest.text(NSNull()) == "")
        #expect(AnkiDroidJSRequest.text(nil) == "")
    }

    @Test func jsonPayloadsParse() {
        let request = AnkiDroidJSRequest(endpoint: "showToast", developer: "d", version: "0.0.3", data: #"{"text":"hi","shortLength":false}"#)
        #expect(request.jsonObject?["text"] as? String == "hi")
        #expect(request.jsonObject?["shortLength"] as? Bool == false)
    }

    @Test func onlyTheCurrentVersionWithAContactIsValid() {
        #expect(AnkiDroidJSContract.status(version: "0.0.3", developer: "dev") == .valid)
        #expect(AnkiDroidJSContract.status(version: "0.0.3", developer: " ") == .missingContact)
        #expect(AnkiDroidJSContract.status(version: "", developer: "dev") == .missingContact)
        #expect(AnkiDroidJSContract.status(version: "0.0.2", developer: "dev") == .unsupportedVersion)
        #expect(AnkiDroidJSContract.status(version: "0.0.4", developer: "dev") == .unsupportedVersion)
    }

    @Test func resultsAreAnkiDroidsJSON() {
        #expect(AnkiDroidJSResult.success(5) == #"{"success":true,"value":5}"#)
        #expect(AnkiDroidJSResult.success(true) == #"{"success":true,"value":true}"#)
        #expect(AnkiDroidJSResult.success("10m") == #"{"success":true,"value":"10m"}"#)
        #expect(AnkiDroidJSResult.success(Int64(1_707_102_058_557)) == #"{"success":true,"value":1707102058557}"#)
        #expect(AnkiDroidJSResult.unavailable == #"{"success":false,"value":-1}"#)
        #expect(AnkiDroidJSResult.failure() == #"{"success":false,"value":false}"#)
    }

    @Test func flagsToggleLikeTheReviewer() {
        #expect(AnkiDroidJSFlag.toggled(current: 0, name: "red") == 1)
        #expect(AnkiDroidJSFlag.toggled(current: 1, name: "red") == 0)
        #expect(AnkiDroidJSFlag.toggled(current: 1, name: "purple") == 7)
        #expect(AnkiDroidJSFlag.toggled(current: 4, name: "none") == 0)
        #expect(AnkiDroidJSFlag.toggled(current: 0, name: "magenta") == nil)
    }

    @Test func cardFieldsMatchTheCard() {
        let card = CardRecord(
            id: CardID(11), nid: NoteID(22), did: DeckID(33), ord: 0, mod: 44,
            type: 2, queue: 2, due: 100, ivl: 7, factor: 2500, reps: 9, lapses: 1, left: 0,
            odue: 0, odid: DeckID(0), flags: 3
        )
        #expect(AnkiDroidJSCardField.value(for: "cardId", card: card) as? Int64 == 11)
        #expect(AnkiDroidJSCardField.value(for: "cardNid", card: card) as? Int64 == 22)
        #expect(AnkiDroidJSCardField.value(for: "cardDid", card: card) as? Int64 == 33)
        #expect(AnkiDroidJSCardField.value(for: "cardInterval", card: card) as? Int == 7)
        #expect(AnkiDroidJSCardField.value(for: "cardFactor", card: card) as? Int == 2500)
        #expect(AnkiDroidJSCardField.value(for: "cardMod", card: card) as? Int64 == 44)
        #expect(AnkiDroidJSCardField.value(for: "cardFlag", card: card) == nil)
    }

    @Test func cardChangingCallsAreFlagged() {
        func request(_ endpoint: String) -> AnkiDroidJSRequest {
            AnkiDroidJSRequest(endpoint: endpoint, developer: "d", version: "0.0.3")
        }
        #expect(request("suspendCard").changesCard)
        #expect(request("setCardDue").changesCard)
        #expect(request("setNoteTags").changesCard)
        #expect(!request("answerEase3").changesCard)
        #expect(!request("markCard").changesCard)
        #expect(!request("toggleFlag").changesCard)
        #expect(request("answerEase1").rating == .again)
        #expect(request("nextTime4").rating == .easy)
        #expect(request("cardReps").rating == nil)
    }
}

struct AnkiDroidJSSearchAnswerTests {
    @Test func carriesTheCardsBesideTheUsualAnswer() throws {
        let text = AnkiDroidJSResult.search(results: [
            ["cardId": Int64(1_700_000_000_001), "noteId": Int64(1_700_000_000_000), "fieldsData": ["Front": "犬", "Back": "dog"]],
        ])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["success"] as? Bool == true)
        #expect(object["value"] as? Bool == true)
        let results = try #require(object["results"] as? [[String: Any]])
        #expect(results.count == 1)
        #expect((results[0]["cardId"] as? NSNumber)?.int64Value == 1_700_000_000_001)
        #expect(results[0]["fieldsData"] as? [String: String] == ["Front": "犬", "Back": "dog"])
    }

    @Test func anEmptySearchStillAnswers() {
        #expect(AnkiDroidJSResult.search(results: []) == #"{"results":[],"success":true,"value":true}"#)
    }
}
