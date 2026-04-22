public struct DictionaryLookupEntry: Sendable, Hashable, Identifiable {
    public var term: String
    public var reading: String?
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
        glossaries: [String] = [],
        frequency: String? = nil,
        pitch: String? = nil,
        source: String? = nil
    ) {
        self.term = term
        self.reading = reading
        self.glossaries = glossaries
        self.frequency = frequency
        self.pitch = pitch
        self.source = source
    }
}

public struct DictionaryLookupResult: Sendable, Hashable {
    public var query: String
    public var entries: [DictionaryLookupEntry]
    public var isPlaceholder: Bool

    public init(
        query: String,
        entries: [DictionaryLookupEntry] = [],
        isPlaceholder: Bool = false
    ) {
        self.query = query
        self.entries = entries
        self.isPlaceholder = isPlaceholder
    }
}