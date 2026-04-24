import Foundation
import AnkiKit

struct ReaderLookupNotePayload: Sendable, Hashable {
    var term: String
    var reading: String?
    var sentence: String?
    var definitions: [String]

    var normalizedDefinitions: [String] {
        definitions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ReaderLookupNoteTemplate: Codable, Hashable, Sendable {
    var deckID: Int64?
    var notetypeID: Int64?
    var termField: String
    var readingField: String
    var sentenceField: String
    var definition1Field: String
    var definition2Field: String
    var definition3Field: String

    static let empty = Self()

    init(
        deckID: Int64? = nil,
        notetypeID: Int64? = nil,
        termField: String = "",
        readingField: String = "",
        sentenceField: String = "",
        definition1Field: String = "",
        definition2Field: String = "",
        definition3Field: String = ""
    ) {
        self.deckID = deckID
        self.notetypeID = notetypeID
        self.termField = termField
        self.readingField = readingField
        self.sentenceField = sentenceField
        self.definition1Field = definition1Field
        self.definition2Field = definition2Field
        self.definition3Field = definition3Field
    }

    var hasMappedFields: Bool {
        [
            termField,
            readingField,
            sentenceField,
            definition1Field,
            definition2Field,
            definition3Field
        ]
        .contains { !$0.isEmpty }
    }

    func encodedString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    static func decode(from string: String) -> Self {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return .empty
        }
        return value
    }

    mutating func clearInvalidFields(validFields: [String]) {
        if !validFields.contains(termField) { termField = "" }
        if !validFields.contains(readingField) { readingField = "" }
        if !validFields.contains(sentenceField) { sentenceField = "" }
        if !validFields.contains(definition1Field) { definition1Field = "" }
        if !validFields.contains(definition2Field) { definition2Field = "" }
        if !validFields.contains(definition3Field) { definition3Field = "" }
    }

    func makeDraft(
        payload: ReaderLookupNotePayload,
        fallbackDeckID: Int64?,
        sourceDescription: String
    ) -> AddNoteDraft {
        var fieldValues: [String: String] = [:]
        let definitions = payload.normalizedDefinitions

        func assign(_ fieldName: String, _ value: String?) {
            guard !fieldName.isEmpty,
                  let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return
            }
            fieldValues[fieldName] = trimmed
        }

        assign(termField, payload.term)
        assign(readingField, payload.reading)
        assign(sentenceField, payload.sentence)
        assign(definition1Field, definitions[safe: 0])
        assign(definition2Field, definitions[safe: 1])
        assign(definition3Field, definitions[safe: 2])

        if fieldValues.isEmpty {
            let resolvedSentence = payload.sentence?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? payload.term
            fieldValues = [
                "Front": payload.term,
                "Text": payload.term,
                "Expression": payload.term,
                "Sentence": resolvedSentence,
                "Back": sourceDescription,
                "Source": sourceDescription,
                "Extra": sourceDescription
            ]
        }

        return AddNoteDraft(
            deckID: deckID ?? fallbackDeckID,
            notetypeID: notetypeID,
            fieldValues: fieldValues
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
