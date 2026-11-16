//
//  LookupRanking.swift
//  Reader
//
//  Created by Vladimir Gusev on 13.09.2026.
//

/// How frequency dictionaries order otherwise equal results.
public struct LookupFrequencySort: Sendable, Hashable {
    public enum Order: String, Sendable, CaseIterable {
        /// Lower numbers first, across every frequency dictionary.
        case automatic
        /// Lower numbers first: right for rank-style lists.
        case ascending
        /// Higher numbers first: right for occurrence counts.
        case descending
        /// Frequency plays no part in the order.
        case disabled
    }

    public var order: Order
    /// The one dictionary to sort by, for `ascending` and `descending`;
    /// nil uses every frequency dictionary.
    public var dictionary: String?

    public init(order: Order = .automatic, dictionary: String? = nil) {
        self.order = order
        self.dictionary = dictionary
    }

    public static let automatic = Self()
}

public enum LookupRanking {
    public static func rank(
        _ entries: [DictionaryLookupEntry],
        dictionaryOrder: [String: Int],
        frequencySort: LookupFrequencySort = .automatic
    ) -> [DictionaryLookupEntry] {
        entries.enumerated()
            .map {
                (
                    key: sortKey($0.element, dictionaryOrder: dictionaryOrder, frequencySort: frequencySort),
                    index: $0.offset,
                    entry: $0.element
                )
            }
            .sorted { lhs, rhs in
                (lhs.key.matchLength, lhs.key.dictionary, lhs.key.frequency, lhs.index)
                    < (rhs.key.matchLength, rhs.key.dictionary, rhs.key.frequency, rhs.index)
            }
            .map(\.entry)
    }

    private static func sortKey(
        _ entry: DictionaryLookupEntry,
        dictionaryOrder: [String: Int],
        frequencySort: LookupFrequencySort
    ) -> (matchLength: Int, dictionary: Int, frequency: Int) {
        (
            matchLength: -(entry.matched?.count ?? 0),
            dictionary: entry.structuredGlossaries
                .compactMap { dictionaryOrder[$0.dictionary] }
                .min() ?? .max,
            frequency: frequencyKey(entry, sort: frequencySort)
        )
    }

    /// Smaller sorts first. An entry no chosen dictionary lists goes last.
    private static func frequencyKey(_ entry: DictionaryLookupEntry, sort: LookupFrequencySort) -> Int {
        let chosen: [DictionaryLookupFrequency]
        switch sort.order {
        case .disabled:
            return 0
        case .automatic:
            chosen = entry.structuredFrequencies
        case .ascending, .descending:
            if let dictionary = sort.dictionary, !dictionary.isEmpty {
                chosen = entry.structuredFrequencies.filter { $0.dictionary == dictionary }
            } else {
                chosen = entry.structuredFrequencies
            }
        }
        let values = chosen.flatMap(\.frequencies).map(\.value)
        if sort.order == .descending {
            return values.max().map { -$0 } ?? .max
        }
        return values.min() ?? .max
    }
}
