import Foundation
import AnkiKit

enum DeckTreeCache {
    static func load() -> [DeckTreeNode] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey()) else {
            return []
        }
        return (try? JSONDecoder().decode([DeckTreeNode].self, from: data)) ?? []
    }

    static func save(_ tree: [DeckTreeNode]) {
        guard let data = try? JSONEncoder().encode(tree) else { return }
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
        return "deck_list_tree_cache.\(suffix)"
    }
}