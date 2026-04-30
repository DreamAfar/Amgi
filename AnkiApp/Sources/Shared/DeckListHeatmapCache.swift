import Foundation
import AnkiProto
import SwiftProtobuf

enum DeckListHeatmapCache {
    struct Entry: Codable {
        let responseData: Data
        let searchQuery: String
        let requestedDays: Int
        let cachedAt: Date
        let lastSyncAt: Date?
    }

    static func load() -> Anki_Stats_GraphsResponse? {
        loadEntry()?.response
    }

    static func loadCurrent() -> Anki_Stats_GraphsResponse? {
        guard
            let entry = loadEntry(),
            entry.searchQuery == currentSearchQuery(),
            entry.requestedDays == currentRequestedDays()
        else {
            return nil
        }
        return entry.response
    }

    static func loadEntry() -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey()) else {
            return nil
        }

        if let entry = try? JSONDecoder().decode(Entry.self, from: data),
           (try? Anki_Stats_GraphsResponse(serializedBytes: entry.responseData)) != nil {
            return entry
        }

        guard (try? Anki_Stats_GraphsResponse(serializedBytes: data)) != nil else {
            return nil
        }

        return Entry(
            responseData: data,
            searchQuery: currentSearchQuery(),
            requestedDays: currentRequestedDays(),
            cachedAt: .distantPast,
            lastSyncAt: nil
        )
    }

    static func save(
        _ graphs: Anki_Stats_GraphsResponse,
        searchQuery: String,
        requestedDays: Int,
        cachedAt: Date = Date(),
        lastSyncAt: Date?
    ) {
        guard let responseData = try? graphs.serializedData() else { return }
        let entry = Entry(
            responseData: responseData,
            searchQuery: searchQuery,
            requestedDays: requestedDays,
            cachedAt: cachedAt,
            lastSyncAt: lastSyncAt
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey())
    }

    private static func cacheKey() -> String {
        let selectedUser = AppUserStore.loadSelectedUser()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = selectedUser.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let profile = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let suffix = profile.isEmpty ? "default" : profile
        return "deck_list_heatmap_cache.\(suffix)"
    }

    private static func currentSearchQuery() -> String {
        let scopeRaw = UserDefaults.standard.string(forKey: DeckListHeatmapSettings.scopeKey)
            ?? DeckListHeatmapScope.allDecks.rawValue
        let scope = DeckListHeatmapScope(rawValue: scopeRaw) ?? .allDecks

        guard scope == .selectedDeck else {
            return DeckListHeatmapSettings.allDecksSearch
        }

        let selectedDeckID = UserDefaults.standard.integer(forKey: DeckListHeatmapSettings.selectedDeckIDKey)
        guard selectedDeckID > 0 else {
            return DeckListHeatmapSettings.allDecksSearch
        }

        return "did:\(selectedDeckID)"
    }

    private static func currentRequestedDays() -> Int {
        if UserDefaults.standard.object(forKey: DeckListHeatmapSettings.initialDaysKey) == nil {
            return DeckListHeatmapSettings.defaultInitialDays
        }
        return UserDefaults.standard.integer(forKey: DeckListHeatmapSettings.initialDaysKey)
    }
}

extension DeckListHeatmapCache.Entry {
    var response: Anki_Stats_GraphsResponse? {
        try? Anki_Stats_GraphsResponse(serializedBytes: responseData)
    }
}
