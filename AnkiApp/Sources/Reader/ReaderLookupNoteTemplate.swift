import Foundation
import AnkiKit

enum ReaderLookupHandlebar: String, CaseIterable, Sendable {
    case expression = "{expression}"
    case reading = "{reading}"
    case furiganaPlain = "{furigana-plain}"
    case audio = "{audio}"
    case glossary = "{glossary}"
    case glossaryFirst = "{glossary-first}"
    case popupSelectionText = "{popup-selection-text}"
    case sentence = "{sentence}"
    case frequencies = "{frequencies}"
    case frequencyHarmonicRank = "{frequency-harmonic-rank}"
    case pitchPositions = "{pitch-accent-positions}"
    case pitchCategories = "{pitch-accent-categories}"
    case documentTitle = "{document-title}"
    case bookCover = "{book-cover}"

    static let singleGlossaryPrefix = "{single-glossary-"
}

struct ReaderLookupMiningContext: Sendable, Hashable {
    var sentence: String
    var documentTitle: String?
    var coverURL: URL?
}

struct ReaderLookupNoteTemplate: Codable, Hashable, Sendable {
    var deckID: Int64?
    var notetypeID: Int64?
    var fieldMappings: [String: String]
    var tags: String

    static let empty = Self()

    init(
        deckID: Int64? = nil,
        notetypeID: Int64? = nil,
        fieldMappings: [String: String] = [:],
        tags: String = ""
    ) {
        self.deckID = deckID
        self.notetypeID = notetypeID
        self.fieldMappings = fieldMappings
        self.tags = tags
    }

    var hasMappedFields: Bool {
        fieldMappings.isEmpty == false
    }

    var needsAudio: Bool {
        fieldMappings.values.contains(ReaderLookupHandlebar.audio.rawValue)
    }

    enum CodingKeys: String, CodingKey {
        case deckID
        case notetypeID
        case fieldMappings
        case tags

        case termField
        case readingField
        case sentenceField
        case definition1Field
        case definition2Field
        case definition3Field
        case dictionariesField
        case frequencyField
        case pitchField
        case deinflectionField
        case matchedField
        case sourceField
        case rulesField
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deckID = try container.decodeIfPresent(Int64.self, forKey: .deckID)
        notetypeID = try container.decodeIfPresent(Int64.self, forKey: .notetypeID)
        tags = try container.decodeIfPresent(String.self, forKey: .tags) ?? ""

        if let savedMappings = try container.decodeIfPresent([String: String].self, forKey: .fieldMappings) {
            fieldMappings = savedMappings
            return
        }

        var migratedMappings: [String: String] = [:]

        func migrate(_ key: CodingKeys, to handlebar: ReaderLookupHandlebar?) {
            guard let rawFieldName = try? container.decodeIfPresent(String.self, forKey: key),
                  let handlebar else {
                return
            }
            let fieldName = rawFieldName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard fieldName.isEmpty == false else {
                return
            }
            migratedMappings[fieldName] = handlebar.rawValue
        }

        migrate(.termField, to: .expression)
        migrate(.readingField, to: .reading)
        migrate(.sentenceField, to: .sentence)
        migrate(.definition1Field, to: .glossary)
        migrate(.frequencyField, to: .frequencies)
        migrate(.pitchField, to: .pitchPositions)
        migrate(.matchedField, to: .popupSelectionText)
        migrate(.sourceField, to: .documentTitle)

        fieldMappings = migratedMappings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(deckID, forKey: .deckID)
        try container.encodeIfPresent(notetypeID, forKey: .notetypeID)
        try container.encode(fieldMappings, forKey: .fieldMappings)
        try container.encode(tags, forKey: .tags)
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
        let validFieldSet = Set(validFields)
        fieldMappings = fieldMappings.filter { validFieldSet.contains($0.key) }
    }

    func makeDraft(
        content: [String: String],
        context: ReaderLookupMiningContext,
        fallbackDeckID: Int64?
    ) -> AddNoteDraft {
        var resolvedFieldValues: [String: String] = [:]
        let singleGlossaries = Self.decodeSingleGlossaries(from: content["singleGlossaries"])

        for (fieldName, mappedValue) in fieldMappings {
            let resolved = Self.handlebarValue(
                mappedValue,
                context: context,
                content: content,
                singleGlossaries: singleGlossaries
            )
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                resolvedFieldValues[fieldName] = trimmed
            }
        }

        if resolvedFieldValues.isEmpty {
            let expression = content["expression"]?.nilIfBlank ?? ""
            let resolvedSentence = Self.handlebarValue(
                ReaderLookupHandlebar.sentence.rawValue,
                context: context,
                content: content,
                singleGlossaries: singleGlossaries
            ).nilIfBlank ?? expression
            let sourceDescription = context.documentTitle?.nilIfBlank ?? expression

            resolvedFieldValues = [
                "Front": expression,
                "Text": expression,
                "Expression": expression,
                "Sentence": resolvedSentence,
                "Back": sourceDescription,
                "Source": sourceDescription,
                "Extra": sourceDescription
            ]
        }

        return AddNoteDraft(
            deckID: deckID ?? fallbackDeckID,
            notetypeID: notetypeID,
            fieldValues: resolvedFieldValues,
            tags: tags
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
        )
    }

    private static func decodeSingleGlossaries(from rawValue: String?) -> [String: String] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let value = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return value
    }

    private static func handlebarValue(
        _ handlebar: String,
        context: ReaderLookupMiningContext,
        content: [String: String],
        singleGlossaries: [String: String]
    ) -> String {
        if handlebar.hasPrefix(ReaderLookupHandlebar.singleGlossaryPrefix),
           handlebar.hasSuffix("}") {
            let dictionaryName = String(
                handlebar
                    .dropFirst(ReaderLookupHandlebar.singleGlossaryPrefix.count)
                    .dropLast()
            )
            return singleGlossaries[dictionaryName] ?? ""
        }

        guard let standardHandlebar = ReaderLookupHandlebar(rawValue: handlebar) else {
            return ""
        }

        switch standardHandlebar {
        case .expression:
            return content["expression"] ?? ""
        case .reading:
            return content["reading"] ?? ""
        case .furiganaPlain:
            return content["furiganaPlain"] ?? ""
        case .audio:
            return content["audio"] ?? ""
        case .glossary:
            return content["glossary"] ?? ""
        case .glossaryFirst:
            return content["glossaryFirst"] ?? ""
        case .popupSelectionText:
            return content["popupSelectionText"] ?? ""
        case .sentence:
            guard let sentence = context.sentence.nilIfBlank else {
                return ""
            }
            guard let matched = content["matched"]?.nilIfBlank else {
                return sentence
            }
            return sentence.replacingOccurrences(of: matched, with: "<b>\(matched)</b>")
        case .frequencies:
            return content["frequenciesHtml"] ?? ""
        case .frequencyHarmonicRank:
            return content["freqHarmonicRank"] ?? ""
        case .pitchPositions:
            return content["pitchPositions"] ?? ""
        case .pitchCategories:
            return content["pitchCategories"] ?? ""
        case .documentTitle:
            return context.documentTitle ?? ""
        case .bookCover:
            return content["bookCover"]?.nilIfBlank ?? context.coverURL?.absoluteString ?? ""
        }
    }
}

struct ReaderLookupNoteTemplateStore: Codable, Hashable, Sendable {
    static let defaultLanguageKey = "default"
    static let empty = Self()

    var defaultTemplate: ReaderLookupNoteTemplate
    var templatesByLanguage: [String: ReaderLookupNoteTemplate]

    init(
        defaultTemplate: ReaderLookupNoteTemplate = .empty,
        templatesByLanguage: [String: ReaderLookupNoteTemplate] = [:]
    ) {
        self.defaultTemplate = defaultTemplate
        self.templatesByLanguage = templatesByLanguage
    }

    enum CodingKeys: String, CodingKey {
        case defaultTemplate
        case templatesByLanguage
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.defaultTemplate) || container.contains(.templatesByLanguage) {
            defaultTemplate = try container.decodeIfPresent(ReaderLookupNoteTemplate.self, forKey: .defaultTemplate) ?? .empty
            templatesByLanguage = try container.decodeIfPresent([String: ReaderLookupNoteTemplate].self, forKey: .templatesByLanguage) ?? [:]
            templatesByLanguage = Dictionary(
                uniqueKeysWithValues: templatesByLanguage.map { key, value in
                    (Self.normalizedLanguageKey(key), value)
                }
            )
            return
        }

        defaultTemplate = (try? ReaderLookupNoteTemplate(from: decoder)) ?? .empty
        templatesByLanguage = [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultTemplate, forKey: .defaultTemplate)
        try container.encode(templatesByLanguage, forKey: .templatesByLanguage)
    }

    var languageKeys: [String] {
        [Self.defaultLanguageKey] + templatesByLanguage.keys.sorted()
    }

    func template(for languageHint: String?) -> ReaderLookupNoteTemplate {
        guard let languageHint = languageHint?.trimmingCharacters(in: .whitespacesAndNewlines),
              languageHint.isEmpty == false else {
            return defaultTemplate
        }

        let normalizedKey = Self.normalizedLanguageKey(languageHint)
        if let template = templatesByLanguage[normalizedKey] {
            return template
        }

        let primaryKey = normalizedKey
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? normalizedKey
        if let template = templatesByLanguage[primaryKey] {
            return template
        }

        return defaultTemplate
    }

    func template(forKey key: String) -> ReaderLookupNoteTemplate {
        let normalizedKey = Self.normalizedLanguageKey(key)
        if normalizedKey == Self.defaultLanguageKey {
            return defaultTemplate
        }
        return templatesByLanguage[normalizedKey] ?? .empty
    }

    mutating func setTemplate(_ template: ReaderLookupNoteTemplate, forKey key: String) {
        let normalizedKey = Self.normalizedLanguageKey(key)
        if normalizedKey == Self.defaultLanguageKey {
            defaultTemplate = template
            return
        }

        if template == .empty {
            templatesByLanguage.removeValue(forKey: normalizedKey)
        } else {
            templatesByLanguage[normalizedKey] = template
        }
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

    static func normalizedLanguageKey(_ rawValue: String?) -> String {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-") ?? ""
        return normalized.isEmpty ? defaultLanguageKey : normalized
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
