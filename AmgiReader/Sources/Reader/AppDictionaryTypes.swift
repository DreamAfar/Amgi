//
//  AppDictionaryTypes.swift
//  Reader
//
//  Created by Vladimir Gusev on 28.04.2026.
//

import Foundation

public enum AppDictionaryKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case term
    case frequency
    case pitch
    case kanji

    public var id: String { rawValue }
}

public struct AppDictionaryIndex: Codable, Hashable, Sendable {
    public var title: String
    public var format: Int
    public var revision: String
    public var isUpdatable: Bool
    public var indexURL: String
    public var downloadURL: String

    public init(
        title: String,
        format: Int = 0,
        revision: String = "",
        isUpdatable: Bool = false,
        indexURL: String = "",
        downloadURL: String = ""
    ) {
        self.title = title
        self.format = format
        self.revision = revision
        self.isUpdatable = isUpdatable
        self.indexURL = indexURL
        self.downloadURL = downloadURL
    }

    enum CodingKeys: String, CodingKey {
        case title
        case format
        case revision
        case isUpdatable
        case indexURL = "indexUrl"
        case downloadURL = "downloadUrl"
    }

    private enum SummaryKeys: String, CodingKey {
        case version
    }

    /// Reads both shapes of a stored `index.json`. The engine used to write
    /// the dictionary's own index with every key present; it now writes an
    /// import summary, where the format number is `version` and the update
    /// keys are left out when the dictionary has none. A strict decode of
    /// that would fail — and a dictionary whose index doesn't decode is
    /// treated as broken.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        revision = try container.decodeIfPresent(String.self, forKey: .revision) ?? ""
        isUpdatable = try container.decodeIfPresent(Bool.self, forKey: .isUpdatable) ?? false
        indexURL = try container.decodeIfPresent(String.self, forKey: .indexURL) ?? ""
        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL) ?? ""
        if let format = try container.decodeIfPresent(Int.self, forKey: .format) {
            self.format = format
        } else {
            let summary = try decoder.container(keyedBy: SummaryKeys.self)
            format = try summary.decodeIfPresent(Int.self, forKey: .version) ?? 0
        }
    }
}

public struct AppDictionaryInfo: Identifiable, Codable, Hashable, Sendable {
    public var fileName: String
    public var index: AppDictionaryIndex
    public var isEnabled: Bool
    public var order: Int
    /// True for a dictionary imported by an older engine, whose files the
    /// current one no longer reads. It stays listed so it can be deleted
    /// and imported again, but lookups skip it.
    public var needsReimport: Bool

    public var id: String { fileName }

    public var title: String {
        index.title.isEmpty ? fileName : index.title
    }

    public init(
        fileName: String,
        index: AppDictionaryIndex,
        isEnabled: Bool = true,
        order: Int = 0,
        needsReimport: Bool = false
    ) {
        self.fileName = fileName
        self.index = index
        self.isEnabled = isEnabled
        self.order = order
        self.needsReimport = needsReimport
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        index = try container.decode(AppDictionaryIndex.self, forKey: .index)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        order = try container.decode(Int.self, forKey: .order)
        needsReimport = try container.decodeIfPresent(Bool.self, forKey: .needsReimport) ?? false
    }
}

public struct AppDictionaryConfig: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var fileName: String
        public var isEnabled: Bool
        public var order: Int

        public init(fileName: String, isEnabled: Bool, order: Int) {
            self.fileName = fileName
            self.isEnabled = isEnabled
            self.order = order
        }
    }

    public var termDictionaries: [Entry]
    public var frequencyDictionaries: [Entry]
    public var pitchDictionaries: [Entry]
    public var kanjiDictionaries: [Entry]

    public init(
        termDictionaries: [Entry] = [],
        frequencyDictionaries: [Entry] = [],
        pitchDictionaries: [Entry] = [],
        kanjiDictionaries: [Entry] = []
    ) {
        self.termDictionaries = termDictionaries
        self.frequencyDictionaries = frequencyDictionaries
        self.pitchDictionaries = pitchDictionaries
        self.kanjiDictionaries = kanjiDictionaries
    }

    /// Configs saved before kanji dictionaries existed have no entry for
    /// them, on this device or in the synced copy.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termDictionaries = try container.decodeIfPresent([Entry].self, forKey: .termDictionaries) ?? []
        frequencyDictionaries = try container.decodeIfPresent([Entry].self, forKey: .frequencyDictionaries) ?? []
        pitchDictionaries = try container.decodeIfPresent([Entry].self, forKey: .pitchDictionaries) ?? []
        kanjiDictionaries = try container.decodeIfPresent([Entry].self, forKey: .kanjiDictionaries) ?? []
    }
}

public struct AppDictionaryLibraryState: Codable, Hashable, Sendable {
    public var termDictionaries: [AppDictionaryInfo]
    public var frequencyDictionaries: [AppDictionaryInfo]
    public var pitchDictionaries: [AppDictionaryInfo]
    public var kanjiDictionaries: [AppDictionaryInfo]

    public init(
        termDictionaries: [AppDictionaryInfo] = [],
        frequencyDictionaries: [AppDictionaryInfo] = [],
        pitchDictionaries: [AppDictionaryInfo] = [],
        kanjiDictionaries: [AppDictionaryInfo] = []
    ) {
        self.termDictionaries = termDictionaries
        self.frequencyDictionaries = frequencyDictionaries
        self.pitchDictionaries = pitchDictionaries
        self.kanjiDictionaries = kanjiDictionaries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termDictionaries = try container.decodeIfPresent([AppDictionaryInfo].self, forKey: .termDictionaries) ?? []
        frequencyDictionaries = try container.decodeIfPresent([AppDictionaryInfo].self, forKey: .frequencyDictionaries) ?? []
        pitchDictionaries = try container.decodeIfPresent([AppDictionaryInfo].self, forKey: .pitchDictionaries) ?? []
        kanjiDictionaries = try container.decodeIfPresent([AppDictionaryInfo].self, forKey: .kanjiDictionaries) ?? []
    }

    public static let empty = Self()

    public var isEmpty: Bool {
        termDictionaries.isEmpty && frequencyDictionaries.isEmpty
            && pitchDictionaries.isEmpty && kanjiDictionaries.isEmpty
    }

    public func dictionaries(of kind: AppDictionaryKind) -> [AppDictionaryInfo] {
        switch kind {
        case .term: termDictionaries
        case .frequency: frequencyDictionaries
        case .pitch: pitchDictionaries
        case .kanji: kanjiDictionaries
        }
    }

    /// Whether any dictionary has to be imported again before it works.
    public var needsReimport: Bool {
        AppDictionaryKind.allCases.contains { dictionaries(of: $0).contains(where: \.needsReimport) }
    }
}
