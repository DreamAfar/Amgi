import Foundation

struct ReaderSavedProgress: Codable, Equatable {
    let chapterID: Int64
    let progress: Double
    let updatedAt: Date
}

enum ReaderProgressStore {
    private static let keyPrefix = "reader.progress."

    static func load(bookID: String) -> ReaderSavedProgress? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: bookID)) else {
            return nil
        }
        return try? JSONDecoder().decode(ReaderSavedProgress.self, from: data)
    }

    static func save(bookID: String, chapterID: Int64, progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)
        let payload = ReaderSavedProgress(
            chapterID: chapterID,
            progress: clampedProgress,
            updatedAt: .now
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey(for: bookID))
    }

    private static func storageKey(for bookID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = String(bookID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })
        return keyPrefix + sanitized
    }
}