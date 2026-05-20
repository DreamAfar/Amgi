import Foundation

@MainActor
final class AnkiJSBridge {
    nonisolated static let apiVersion = "0.0.3"
    nonisolated static let minimumAPIVersion = "0.0.3"
    nonisolated static let messageHandlerName = "amgiAnkiJS"

    var context: AnkiJSContext

    private let ttsController: AnkiJSTTSController
    private let scrollController: AnkiJSScrollController
    private let jsEvaluator: (String) -> Void
    private var ttsLanguage = ""
    private var ttsPitch: Float = 1
    private var ttsSpeechRate: Float = 1

    init(
        context: AnkiJSContext,
        ttsController: AnkiJSTTSController,
        scrollController: AnkiJSScrollController,
        jsEvaluator: @escaping (String) -> Void = { _ in }
    ) {
        self.context = context
        self.ttsController = ttsController
        self.scrollController = scrollController
        self.jsEvaluator = jsEvaluator
    }

    func handleMessage(_ body: Any) -> (Any?, String?) {
        do {
            let request = try Request(messageBody: body)
            let responseText = try handle(request)
            return (responseText, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func handle(_ request: Request) throws -> String {
        guard request.developer.isEmpty == false, request.version.isEmpty == false else {
            return failureInteger(-1)
        }

        switch request.endpoint {
        case "init":
            return success(true)
        case "newCardCount":
            return success(context.getCounts().newCount)
        case "lrnCardCount":
            return success(context.getCounts().learnCount)
        case "revCardCount":
            return success(context.getCounts().reviewCount)
        case "eta":
            return success(context.getETA())
        case "cardMark":
            return success(try context.getCardInfo().isMarked)
        case "cardFlag":
            return success(try context.getCardInfo().userFlag)
        case "nextTime1":
            return context.getNextTime(1) ?? ""
        case "nextTime2":
            return context.getNextTime(2) ?? ""
        case "nextTime3":
            return context.getNextTime(3) ?? ""
        case "nextTime4":
            return context.getNextTime(4) ?? ""
        case "cardReps":
            return success(try context.getCardInfo().reps)
        case "cardInterval":
            return success(try context.getCardInfo().interval)
        case "cardFactor":
            return success(try context.getCardInfo().factor)
        case "cardMod":
            return success(try context.getCardInfo().modified)
        case "cardId":
            return success(try context.getCardInfo().cardId)
        case "cardNid":
            return success(try context.getCardInfo().noteId)
        case "cardType":
            return success(try context.getCardInfo().cardType)
        case "cardDid":
            return success(try context.getCardInfo().deckId)
        case "cardLeft":
            return success(try context.getCardInfo().left)
        case "cardODid":
            return success(try context.getCardInfo().originalDeckId)
        case "cardODue":
            return success(try context.getCardInfo().originalDue)
        case "cardQueue":
            return success(try context.getCardInfo().queue)
        case "cardLapses":
            return success(try context.getCardInfo().lapses)
        case "cardDue":
            return success(try context.getCardInfo().due)
        case "isInNightMode":
            return success(context.isNightMode())
        case "isDisplayingAnswer":
            return success(context.isDisplayingAnswer())
        case "deckName":
            return context.getDeckName() ?? ""
        case "ttsFieldModifierIsAvailable":
            return success(false)
        case "ttsIsSpeaking":
            return success(ttsController.isSpeaking())
        case "ttsStop":
            ttsController.stop()
            return success(true)
        case "ttsSetLanguage":
            ttsLanguage = request.stringData ?? ""
            return success(true)
        case "ttsSetPitch":
            guard let pitch = request.floatData else {
                throw AnkiJSBridgeError.invalidArgument("pitch")
            }
            ttsPitch = pitch
            return success(true)
        case "ttsSetSpeechRate":
            guard let rate = request.floatData else {
                throw AnkiJSBridgeError.invalidArgument("speechRate")
            }
            ttsSpeechRate = rate
            return success(true)
        case "ttsSpeak":
            let payload = try request.decodeJSONObject()
            guard let text = payload["text"] as? String else {
                throw AnkiJSBridgeError.invalidArgument("text")
            }
            ttsController.speak(
                .init(
                    text: text,
                    lang: ttsLanguage,
                    voices: [],
                    speed: ttsSpeechRate,
                    pitch: ttsPitch
                )
            )
            return success(true)
        case "buryCard":
            try context.buryCard()
            return success(true)
        case "buryNote":
            try context.buryNote()
            return success(true)
        case "suspendCard":
            try context.suspendCard()
            return success(true)
        case "suspendNote":
            try context.suspendNote()
            return success(true)
        case "resetProgress":
            try context.resetProgress()
            return success(true)
        case "markCard":
            _ = try context.toggleMark()
            return success(true)
        case "toggleFlag":
            let requestedFlag = (request.stringData ?? "").lowercased()
            guard let targetFlag = Self.flagValue(for: requestedFlag) else {
                throw AnkiJSBridgeError.invalidArgument("flag")
            }
            let currentFlag = try context.getCardInfo().userFlag
            let nextFlag = currentFlag == targetFlag ? 0 : targetFlag
            try context.setFlag(UInt32(nextFlag))
            return success(true)
        case "setCardDue":
            guard let dueString = request.stringData?.trimmingCharacters(in: .whitespacesAndNewlines),
                  dueString.isEmpty == false else {
                throw AnkiJSBridgeError.invalidArgument("days")
            }
            try context.setCardDue(dueString)
            return success(true)
        case "showAnswer":
            let payload = (try? request.decodeJSONObject()) ?? [:]
            context.showAnswer(payload["typedAnswer"] as? String)
            return success(true)
        case "answerEase1", "answerEase2", "answerEase3", "answerEase4":
            let payload = (try? request.decodeJSONObject()) ?? [:]
            let ease = switch request.endpoint {
            case "answerEase1": 1
            case "answerEase2": 2
            case "answerEase3": 3
            default: 4
            }
            try context.answerEase(ease, payload["typedAnswer"] as? String)
            return success(true)
        case "addTagToNote":
            let payload = try request.decodeJSONObject()
            guard let tag = payload["tag"] as? String else {
                throw AnkiJSBridgeError.invalidArgument("tag")
            }
            let noteID = Self.int64(from: payload["noteId"])
            try context.addTagToNote(noteID, tag)
            return success(true)
        case "addTagToCard":
            try context.addTagToCurrentCard()
            return success(true)
        case "setNoteTags":
            let payload = try request.decodeJSONObject()
            let tags = Self.sanitizedTags(from: payload["tags"])
            try context.setNoteTags(tags)
            return success(true)
        case "getNoteTags":
            return success(Self.serializeTags(try context.getNoteTags()))
        case "showToast":
            let payload = try request.decodeJSONObject()
            guard let text = payload["text"] as? String else {
                throw AnkiJSBridgeError.invalidArgument("text")
            }
            let shortLength = payload["shortLength"] as? Bool ?? true
            let decodedText = text.removingPercentEncoding ?? text
            context.showToast(decodedText, shortLength)
            return success(true)
        case "searchCard":
            context.searchCard(request.stringData ?? "")
            return success(true)
        case "searchCardWithCallback":
            let payload = try context.searchCardWithCallbackPayload(request.stringData ?? "")
            let script = """
            if (typeof window.ankiSearchCard === "function") {
                window.ankiSearchCard(\(Self.jsStringLiteral(payload)));
            }
            """
            jsEvaluator(script)
            return success(true)
        case "enableHorizontalScrollbar":
            guard let enabled = request.boolData else {
                throw AnkiJSBridgeError.invalidArgument("enabled")
            }
            scrollController.setHorizontalScrollbarEnabled(enabled)
            return success(true)
        case "enableVerticalScrollbar":
            guard let enabled = request.boolData else {
                throw AnkiJSBridgeError.invalidArgument("enabled")
            }
            scrollController.setVerticalScrollbarEnabled(enabled)
            return success(true)
        default:
            throw AnkiJSBridgeError.unsupportedEndpoint(request.endpoint)
        }
    }

    private func success(_ value: Bool) -> String {
        Result(success: true, value: .bool(value)).responseText()
    }

    private func success(_ value: Int) -> String {
        Result(success: true, value: .int(value)).responseText()
    }

    private func success(_ value: Int64) -> String {
        Result(success: true, value: .int64(value)).responseText()
    }

    private func success(_ value: String) -> String {
        Result(success: true, value: .string(value)).responseText()
    }

    private func failureInteger(_ value: Int) -> String {
        Result(success: false, value: .int(value)).responseText()
    }

    private static func flagValue(for flagName: String) -> Int? {
        switch flagName {
        case "none":
            0
        case "red":
            1
        case "orange":
            2
        case "green":
            3
        case "blue":
            4
        case "pink":
            5
        case "turquoise", "cyan":
            6
        case "purple":
            7
        default:
            nil
        }
    }

    private static func sanitizedTags(from rawValue: Any?) -> [String] {
        guard let values = rawValue as? [Any] else { return [] }
        return values.compactMap { value in
            guard let tag = value as? String else { return nil }
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return trimmed
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "\u{3000}", with: "_")
        }
    }

    private static func serializeTags(_ tags: [String]) -> String {
        let sortedTags = tags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter {
            $0.isEmpty == false
        }
        guard let data = try? JSONSerialization.data(withJSONObject: sortedTags, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func int64(from rawValue: Any?) -> Int64? {
        if let int64 = rawValue as? Int64 {
            return int64
        }
        if let int = rawValue as? Int {
            return Int64(int)
        }
        if let number = rawValue as? NSNumber {
            return number.int64Value
        }
        if let string = rawValue as? String {
            return Int64(string)
        }
        return nil
    }

    private static func jsStringLiteral(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "'\(escaped)'"
    }
}

extension AnkiJSBridge {
    private struct Request {
        let endpoint: String
        let developer: String
        let version: String
        let data: Any?

        init(messageBody: Any) throws {
            guard let payload = messageBody as? [String: Any],
                  let endpoint = payload["endpoint"] as? String,
                  let developer = payload["developer"] as? String,
                  let version = payload["version"] as? String else {
                throw AnkiJSBridgeError.invalidRequest
            }

            self.endpoint = endpoint
            self.developer = developer
            self.version = version
            self.data = payload["data"]
        }

        var stringData: String? {
            if let string = data as? String {
                return string
            }
            if let number = data as? NSNumber {
                return number.stringValue
            }
            if let bool = data as? Bool {
                return bool ? "true" : "false"
            }
            return nil
        }

        var boolData: Bool? {
            if let bool = data as? Bool {
                return bool
            }
            if let string = stringData?.lowercased() {
                switch string {
                case "1", "true":
                    return true
                case "0", "false":
                    return false
                default:
                    return nil
                }
            }
            return nil
        }

        var floatData: Float? {
            if let number = data as? NSNumber {
                return number.floatValue
            }
            if let string = stringData {
                return Float(string)
            }
            return nil
        }

        func decodeJSONObject() throws -> [String: Any] {
            if let dictionary = data as? [String: Any] {
                return dictionary
            }
            guard let string = stringData,
                  let jsonData = string.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw AnkiJSBridgeError.invalidArgument(endpoint)
            }
            return object
        }
    }

    private struct Result {
        let success: Bool
        let value: Value

        func responseText() -> String {
            let payload: [String: Any] = [
                "success": success,
                "value": value.rawValue,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let string = String(data: data, encoding: .utf8) else {
                return #"{"success":false,"value":-1}"#
            }
            return string
        }
    }

    private enum Value {
        case bool(Bool)
        case int(Int)
        case int64(Int64)
        case string(String)

        var rawValue: Any {
            switch self {
            case .bool(let value):
                value
            case .int(let value):
                value
            case .int64(let value):
                value
            case .string(let value):
                value
            }
        }
    }
}
