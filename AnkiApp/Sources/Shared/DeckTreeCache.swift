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

    static func clear(for user: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: user))
    }

    private static func cacheKey() -> String {
        cacheKey(for: AppUserStore.loadSelectedUser())
    }

    private static func cacheKey(for user: String) -> String {
        "deck_list_tree_cache.\(AppUserStore.profileID(for: user))"
    }
}
