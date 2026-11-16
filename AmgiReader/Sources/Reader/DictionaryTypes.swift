//
//  DictionaryTypes.swift
//  Reader
//
//  Created by Vladimir Gusev on 28.04.2026.
//

public struct DictionaryLookupDeinflectionStep: Sendable, Hashable, Codable {
    public var name: String
    public var description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

public struct DictionaryLookupGlossary: Sendable, Hashable, Codable {
    public var dictionary: String
    public var content: String
    public var definitions: [String]
    public var definitionTags: String?
    public var termTags: String?

    public init(
        dictionary: String,
        content: String = "",
        definitions: [String] = [],
        definitionTags: String? = nil,
        termTags: String? = nil
    ) {
        self.dictionary = dictionary
        self.content = content
        self.definitions = definitions
        self.definitionTags = definitionTags
        self.termTags = termTags
    }
}

public struct DictionaryLookupFrequencyValue: Sendable, Hashable, Codable {
    public var value: Int
    public var displayValue: String?

    public init(value: Int, displayValue: String? = nil) {
        self.value = value
        self.displayValue = displayValue
    }
}

public struct DictionaryLookupFrequency: Sendable, Hashable, Codable {
    public var dictionary: String
    public var frequencies: [DictionaryLookupFrequencyValue]

    public init(dictionary: String, frequencies: [DictionaryLookupFrequencyValue] = []) {
        self.dictionary = dictionary
        self.frequencies = frequencies
    }
}

public struct DictionaryLookupPitch: Sendable, Hashable, Codable {
    public var dictionary: String
    /// Downstep positions, for accents given as a number.
    public var positions: [Int]
    /// Accents given as a pattern of highs and lows, such as `LHHL`.
    public var patterns: [String]
    /// IPA transcriptions, from dictionaries that carry those instead.
    public var transcriptions: [String]

    public init(
        dictionary: String,
        positions: [Int] = [],
        patterns: [String] = [],
        transcriptions: [String] = []
    ) {
        self.dictionary = dictionary
        self.positions = positions
        self.patterns = patterns
        self.transcriptions = transcriptions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dictionary = try container.decode(String.self, forKey: .dictionary)
        positions = try container.decodeIfPresent([Int].self, forKey: .positions) ?? []
        patterns = try container.decodeIfPresent([String].self, forKey: .patterns) ?? []
        transcriptions = try container.decodeIfPresent([String].self, forKey: .transcriptions) ?? []
    }

    /// Everything this dictionary gives for the word, in reading order.
    public var displayValues: [String] {
        positions.map(String.init) + patterns + transcriptions
    }
}

/// One character's entries from the kanji dictionaries.
public struct DictionaryLookupKanji: Sendable, Hashable, Identifiable, Codable {
    public struct Entry: Sendable, Hashable, Codable {
        public var dictionary: String
        public var onyomi: [String]
        public var kunyomi: [String]
        public var meanings: [String]

        public init(dictionary: String, onyomi: [String] = [], kunyomi: [String] = [], meanings: [String] = []) {
            self.dictionary = dictionary
            self.onyomi = onyomi
            self.kunyomi = kunyomi
            self.meanings = meanings
        }
    }

    public var character: String
    public var entries: [Entry]

    public var id: String { character }

    public init(character: String, entries: [Entry] = []) {
        self.character = character
        self.entries = entries
    }
}

public struct DictionaryLookupEntry: Sendable, Hashable, Identifiable, Codable {
    public var term: String
    public var reading: String?
    public var matched: String?
    public var rules: [String]
    public var deinflectionTrace: [DictionaryLookupDeinflectionStep]
    public var structuredGlossaries: [DictionaryLookupGlossary]
    public var structuredFrequencies: [DictionaryLookupFrequency]
    public var structuredPitches: [DictionaryLookupPitch]
    public var glossaries: [String]
    public var frequency: String?
    public var pitch: String?
    public var source: String?

    public var id: String {
        [term, reading ?? "", source ?? ""].joined(separator: "|")
    }

    public init(
        term: String,
        reading: String? = nil,
        matched: String? = nil,
        rules: [String] = [],
        deinflectionTrace: [DictionaryLookupDeinflectionStep] = [],
        structuredGlossaries: [DictionaryLookupGlossary] = [],
        structuredFrequencies: [DictionaryLookupFrequency] = [],
        structuredPitches: [DictionaryLookupPitch] = [],
        glossaries: [String] = [],
        frequency: String? = nil,
        pitch: String? = nil,
        source: String? = nil
    ) {
        self.term = term
        self.reading = reading
        self.matched = matched
        self.rules = rules
        self.deinflectionTrace = deinflectionTrace
        self.structuredGlossaries = structuredGlossaries
        self.structuredFrequencies = structuredFrequencies
        self.structuredPitches = structuredPitches
        self.glossaries = glossaries
        self.frequency = frequency
        self.pitch = pitch
        self.source = source
    }
}

public struct DictionaryLookupResult: Sendable, Hashable, Codable {
    public var query: String
    public var entries: [DictionaryLookupEntry]
    public var isPlaceholder: Bool
    public var dictionaryStyles: [String: String]
    /// The kanji of the best match, looked up in the kanji dictionaries.
    public var kanji: [DictionaryLookupKanji]
    /// True when nothing could be searched because every dictionary was
    /// imported by an older engine and has to be imported again.
    public var needsReimport: Bool

    public init(
        query: String,
        entries: [DictionaryLookupEntry] = [],
        isPlaceholder: Bool = false,
        dictionaryStyles: [String: String] = [:],
        kanji: [DictionaryLookupKanji] = [],
        needsReimport: Bool = false
    ) {
        self.query = query
        self.entries = entries
        self.isPlaceholder = isPlaceholder
        self.dictionaryStyles = dictionaryStyles
        self.kanji = kanji
        self.needsReimport = needsReimport
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        entries = try container.decodeIfPresent([DictionaryLookupEntry].self, forKey: .entries) ?? []
        isPlaceholder = try container.decodeIfPresent(Bool.self, forKey: .isPlaceholder) ?? false
        dictionaryStyles = try container.decodeIfPresent([String: String].self, forKey: .dictionaryStyles) ?? [:]
        kanji = try container.decodeIfPresent([DictionaryLookupKanji].self, forKey: .kanji) ?? []
        needsReimport = try container.decodeIfPresent(Bool.self, forKey: .needsReimport) ?? false
    }

    /// Whether there is anything to show: a word or a kanji.
    public var hasContent: Bool { !entries.isEmpty || !kanji.isEmpty }
}
