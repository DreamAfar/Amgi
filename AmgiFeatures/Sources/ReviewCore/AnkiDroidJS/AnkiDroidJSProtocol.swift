//
//  AnkiDroidJSProtocol.swift
//  ReviewCore
//

package import AnkiKit
import Foundation

/// A call from a card's script through the AnkiDroid-compatible API.
package struct AnkiDroidJSRequest: Equatable, Sendable {
    package let endpoint: String
    package let developer: String
    package let version: String
    /// The call's argument as text, as AnkiDroid reads it
    /// (`optString("data")`): numbers and booleans as their literal text,
    /// the JSON payloads the shim builds as that JSON string.
    package let data: String

    package init(endpoint: String, developer: String, version: String, data: String = "") {
        self.endpoint = endpoint
        self.developer = developer
        self.version = version
        self.data = data
    }

    /// From the shim's message body.
    package init?(body: Any) {
        guard let body = body as? [String: Any], let endpoint = body["endpoint"] as? String else { return nil }
        self.endpoint = endpoint
        developer = body["developer"] as? String ?? ""
        version = body["version"] as? String ?? ""
        data = Self.text(body["data"])
    }

    package static func text(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        default:
            return ""
        }
    }

    /// The argument parsed as a JSON object, for the calls whose shim
    /// method packs several arguments.
    package var jsonObject: [String: Any]? {
        guard let bytes = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }
}

/// The version and developer contact a card supplies when it creates its
/// `AnkiDroidJS`. Like AnkiDroid, only the current version is accepted, and
/// a card must name a developer to contact when the API changes.
package enum AnkiDroidJSContract {
    package static let version = "0.0.3"

    package enum Status: Equatable {
        case valid
        case missingContact
        case unsupportedVersion
    }

    package static func status(version: String, developer: String) -> Status {
        let version = version.trimmingCharacters(in: .whitespaces)
        guard !version.isEmpty, !developer.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .missingContact
        }
        return version == Self.version ? .valid : .unsupportedVersion
    }
}

/// The JSON text AnkiDroid answers every call with: `{success, value}`.
package enum AnkiDroidJSResult {
    package static func json(success: Bool, value: Any) -> String {
        let object: [String: Any] = ["success": success, "value": value]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return #"{"success":false,"value":-1}"#
        }
        return text
    }

    package static func success(_ value: Any) -> String { json(success: true, value: value) }

    package static func failure(_ value: Any = false) -> String { json(success: false, value: value) }

    /// What AnkiDroid answers an invalid contract, or a call made outside
    /// the reviewer, with.
    package static var unavailable: String { failure(-1) }
}

/// Flag names `ankiToggleFlag` takes.
package enum AnkiDroidJSFlag {
    package static let values: [String: UInt32] = [
        "none": 0, "red": 1, "orange": 2, "green": 3,
        "blue": 4, "pink": 5, "turquoise": 6, "purple": 7,
    ]

    /// The flag after toggling `name`: setting the flag the card already
    /// has clears it, and "none" always clears. Nil for an unknown name.
    package static func toggled(current: UInt32, name: String) -> UInt32? {
        guard let target = values[name] else { return nil }
        if target == 0 { return 0 }
        return current == target ? 0 : target
    }
}

/// The card fields the getters read, as AnkiDroid returns them.
package enum AnkiDroidJSCardField {
    package static func value(for endpoint: String, card: CardRecord) -> Any? {
        switch endpoint {
        case "cardId": return card.id.rawValue
        case "cardNid": return card.nid.rawValue
        case "cardDid": return card.did.rawValue
        case "cardODid": return card.odid.rawValue
        case "cardType": return Int(card.type)
        case "cardQueue": return Int(card.queue)
        case "cardDue": return Int(card.due)
        case "cardODue": return Int(card.odue)
        case "cardInterval": return Int(card.ivl)
        case "cardFactor": return Int(card.factor)
        case "cardReps": return Int(card.reps)
        case "cardLapses": return Int(card.lapses)
        case "cardLeft": return Int(card.left)
        case "cardMod": return card.mod
        default: return nil
        }
    }
}

extension AnkiDroidJSRequest {
    /// Calls that change the card, its note or its scheduling beyond
    /// answering, marking and flagging. Off unless the user allows them.
    package var changesCard: Bool {
        [
            "buryCard", "buryNote", "suspendCard", "suspendNote",
            "setCardDue", "resetProgress", "setNoteTags", "addTagToNote",
        ].contains(endpoint)
    }

    /// The rating an `answerEase<n>` call stands for.
    package var rating: Rating? {
        switch endpoint {
        case "answerEase1", "nextTime1": .again
        case "answerEase2", "nextTime2": .hard
        case "answerEase3", "nextTime3": .good
        case "answerEase4", "nextTime4": .easy
        default: nil
        }
    }
}
