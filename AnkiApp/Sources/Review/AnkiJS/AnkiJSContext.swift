import Foundation
import AnkiKit

@MainActor
struct AnkiJSCardInfo: Sendable, Equatable {
    let cardId: Int64
    let noteId: Int64
    let deckId: Int64
    let cardType: Int
    let left: Int
    let originalDeckId: Int64
    let originalDue: Int
    let queue: Int
    let lapses: Int
    let due: Int
    let reps: Int
    let interval: Int
    let factor: Int
    let modified: Int
    let userFlag: Int
    let isMarked: Bool
}

@MainActor
struct AnkiJSTTSPayload: Sendable, Equatable {
    let text: String
    let lang: String
    let voices: [String]
    let speed: Float
    let pitch: Float
}

@MainActor
struct AnkiJSTTSController {
    let speak: (AnkiJSTTSPayload) -> Void
    let stop: () -> Void
    let isSpeaking: () -> Bool
}

@MainActor
struct AnkiJSScrollController {
    let setHorizontalScrollbarEnabled: (Bool) -> Void
    let setVerticalScrollbarEnabled: (Bool) -> Void
}

@MainActor
struct AnkiJSContext {
    let isDisplayingAnswer: () -> Bool
    let isNightMode: () -> Bool
    let showAnswer: (_ typedAnswer: String?) -> Void
    let answerEase: (_ ease: Int, _ typedAnswer: String?) throws -> Void
    let getCounts: () -> DeckCounts
    let getETA: () -> Int
    let getNextTime: (_ ease: Int) -> String?
    let getCardInfo: () throws -> AnkiJSCardInfo
    let getDeckName: () -> String?
    let buryCard: () throws -> Void
    let buryNote: () throws -> Void
    let suspendCard: () throws -> Void
    let suspendNote: () throws -> Void
    let resetProgress: () throws -> Void
    let setCardDue: (_ days: String) throws -> Void
    let toggleMark: () throws -> Bool
    let setFlag: (_ value: UInt32) throws -> Void
    let getNoteTags: () throws -> [String]
    let setNoteTags: (_ tags: [String]) throws -> Void
    let addTagToCurrentCard: () throws -> Void
    let addTagToNote: (_ noteId: Int64?, _ tag: String) throws -> Void
    let searchCard: (_ query: String) -> Void
    let searchCardWithCallbackPayload: (_ query: String) throws -> String
    let showToast: (_ message: String, _ shortLength: Bool) -> Void
}

enum AnkiJSBridgeError: LocalizedError, Equatable {
    case invalidRequest
    case invalidContract
    case unsupportedEndpoint(String)
    case invalidArgument(String)
    case noCurrentCard
    case noCurrentNote
    case noteNotFound(Int64)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Invalid Anki JS API request."
        case .invalidContract:
            "Missing or invalid Anki JS API developer/version contract."
        case .unsupportedEndpoint(let endpoint):
            "Unsupported Anki JS API endpoint: \(endpoint)"
        case .invalidArgument(let argument):
            "Invalid Anki JS API argument: \(argument)"
        case .noCurrentCard:
            "No current review card is available."
        case .noCurrentNote:
            "No current review note is available."
        case .noteNotFound(let noteID):
            "Note \(noteID) could not be loaded."
        }
    }
}
