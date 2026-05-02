public import Foundation

public enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case recent = "Recent"
    case title = "Title"

    public var id: String { rawValue }
}

public struct BookMetadata: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String?
    public let cover: String?
    public let folder: String?
    public var lastAccess: Date

    public init(
        id: UUID = UUID(),
        title: String?,
        cover: String?,
        folder: String?,
        lastAccess: Date
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.folder = folder
        self.lastAccess = lastAccess
    }
}

public struct Bookmark: Codable, Sendable {
    public let chapterIndex: Int
    public let progress: Double
    public let characterCount: Int
    public var lastModified: Date?

    public init(
        chapterIndex: Int,
        progress: Double,
        characterCount: Int,
        lastModified: Date? = nil
    ) {
        self.chapterIndex = chapterIndex
        self.progress = progress
        self.characterCount = characterCount
        self.lastModified = lastModified
    }
}

public struct BookInfo: Codable, Sendable {
    public let characterCount: Int
    public let chapterInfo: [String: ChapterInfo]

    public init(characterCount: Int, chapterInfo: [String: ChapterInfo]) {
        self.characterCount = characterCount
        self.chapterInfo = chapterInfo
    }

    public struct ChapterInfo: Codable, Sendable {
        public let spineIndex: Int?
        public let currentTotal: Int
        public let chapterCount: Int

        public init(spineIndex: Int?, currentTotal: Int, chapterCount: Int) {
            self.spineIndex = spineIndex
            self.currentTotal = currentTotal
            self.chapterCount = chapterCount
        }
    }

    public func resolveCharacterPosition(_ characterCount: Int) -> (spineIndex: Int, progress: Double)? {
        let clamped = max(0, min(characterCount, self.characterCount - 1))
        for chapter in chapterInfo.values {
            guard let spineIndex = chapter.spineIndex, chapter.chapterCount > 0 else {
                continue
            }
            let start = chapter.currentTotal
            let end = start + chapter.chapterCount
            if clamped >= start && clamped < end {
                let progress = Double(clamped - start) / Double(chapter.chapterCount)
                return (spineIndex, progress)
            }
        }
        return nil
    }
}

public struct BookShelf: Codable, Sendable {
    public let name: String
    public var bookIds: [UUID]

    public init(name: String, bookIds: [UUID]) {
        self.name = name
        self.bookIds = bookIds
    }
}

public struct ReaderEpubLibraryState: Sendable {
    public var books: [BookMetadata]
    public var shelves: [BookShelf]
    public var progressByBookID: [UUID: Double]

    public init(
        books: [BookMetadata],
        shelves: [BookShelf],
        progressByBookID: [UUID: Double]
    ) {
        self.books = books
        self.shelves = shelves
        self.progressByBookID = progressByBookID
    }

    public static let empty = ReaderEpubLibraryState(books: [], shelves: [], progressByBookID: [:])
}