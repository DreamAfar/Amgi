import Foundation
import AnkiProto
import SwiftProtobuf

enum DeckListHeatmapCache {
    static func load() -> Anki_Stats_GraphsResponse? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey()) else {
            return nil
        }
        return try? Anki_Stats_GraphsResponse(serializedBytes: data)
    }

    static func save(_ graphs: Anki_Stats_GraphsResponse) {
        guard let data = try? graphs.serializedData() else { return }
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
}