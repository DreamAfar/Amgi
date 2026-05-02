public import EPUBKit
import Foundation
import Observation

public enum ReaderEpubNavigationAction: Sendable {
    case loadChapter(URL, progress: Double, fragment: String?)
    case restoreProgress(Double)
    case jumpToFragment(String)
}

public enum ReaderEpubSessionError: LocalizedError {
    case missingFolder

    public var errorDescription: String? {
        switch self {
        case .missingFolder:
            return "Book folder is missing."
        }
    }
}

@Observable
@MainActor
public final class ReaderEpubSession {
    public let bookID: UUID
    public let rootURL: URL
    public let document: EPUBDocument

    public var index: Int = 0
    public var currentProgress: Double = 0
    public var bookInfo: BookInfo

    public init(book: BookMetadata) throws {
        guard let folder = book.folder else {
            throw ReaderEpubSessionError.missingFolder
        }

        let booksFolder = try BookStorage.getBooksDirectory()
        let rootURL = booksFolder.appendingPathComponent(folder)
        let document = try BookStorage.loadEpub(rootURL)
        let bookmark = BookStorage.loadBookmark(root: rootURL)
        let bookInfo = BookStorage.loadBookInfo(root: rootURL) ?? BookInfo(characterCount: 0, chapterInfo: [:])

        self.bookID = book.id
        self.rootURL = rootURL
        self.document = document
        self.bookInfo = bookInfo

        if let bookmark {
            self.index = bookmark.chapterIndex
            self.currentProgress = bookmark.progress
        }

        var updatedBook = book
        updatedBook.lastAccess = Date()
        try? BookStorage.save(updatedBook, inside: rootURL, as: FileNames.metadata)
    }

    public var coverURL: URL? {
        BookStorage.loadMetadata(root: rootURL)?.coverURL
    }

    public var currentCharacter: Int {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else {
            return 0
        }

        return chapterInfo.currentTotal + Int(Double(chapterInfo.chapterCount) * currentProgress)
    }

    public func initialAction() -> ReaderEpubNavigationAction? {
        guard let url = currentChapterURL() else {
            return nil
        }
        return .loadChapter(url, progress: currentProgress, fragment: nil)
    }

    public func saveBookmark(progress: Double) {
        currentProgress = progress
        persistBookmark(progress: progress)
    }

    public func actionForJumpToCharacter(_ characterCount: Int) -> ReaderEpubNavigationAction? {
        guard let result = bookInfo.resolveCharacterPosition(characterCount) else {
            return nil
        }

        if result.spineIndex == index {
            persistBookmark(progress: result.progress)
            return .restoreProgress(result.progress)
        }

        return updateChapter(index: result.spineIndex, progress: result.progress, fragment: nil)
    }

    public func actionForJumpToChapter(index: Int, fragment: String? = nil) -> ReaderEpubNavigationAction? {
        updateChapter(index: index, progress: 0, fragment: fragment)
    }

    public func actionForInternalLink(_ url: URL) -> ReaderEpubNavigationAction? {
        guard let destination = resolveSpineDestination(for: url) else {
            return nil
        }

        if destination.spineIndex == index {
            if let fragment = destination.fragment {
                return .jumpToFragment(fragment)
            }

            persistBookmark(progress: 0)
            return .restoreProgress(0)
        }

        return updateChapter(index: destination.spineIndex, progress: 0, fragment: destination.fragment)
    }

    public func syncProgressAfterInternalJump(_ progress: Double) {
        persistBookmark(progress: progress)
    }

    public func actionForNextChapter() -> ReaderEpubNavigationAction? {
        guard index < document.spine.items.count - 1 else {
            return nil
        }
        return updateChapter(index: index + 1, progress: 0, fragment: nil)
    }

    public func actionForPreviousChapter() -> ReaderEpubNavigationAction? {
        guard index > 0 else {
            return nil
        }
        return updateChapter(index: index - 1, progress: 1, fragment: nil)
    }

    private func currentChapterURL() -> URL? {
        guard document.spine.items.indices.contains(index) else {
            return nil
        }

        let item = document.spine.items[index]
        guard let manifestItem = document.manifest.items[item.idref] else {
            return nil
        }
        return document.contentDirectory.appendingPathComponent(manifestItem.path)
    }

    private func updateChapter(index: Int, progress: Double, fragment: String?) -> ReaderEpubNavigationAction? {
        self.index = index
        persistBookmark(progress: progress)

        guard let url = currentChapterURL() else {
            return nil
        }
        return .loadChapter(url, progress: progress, fragment: fragment)
    }

    private func persistBookmark(progress: Double) {
        currentProgress = progress
        let bookmark = Bookmark(
            chapterIndex: index,
            progress: progress,
            characterCount: currentCharacter,
            lastModified: Date()
        )
        try? BookStorage.save(bookmark, inside: rootURL, as: FileNames.bookmark)
    }

    private func resolveSpineDestination(for url: URL) -> (spineIndex: Int, fragment: String?)? {
        let targetPath = normalizedFilePath(url)

        for (spineIndex, spineItem) in document.spine.items.enumerated() {
            guard let manifestItem = document.manifest.items[spineItem.idref] else {
                continue
            }
            let chapterPath = normalizedFilePath(document.contentDirectory.appendingPathComponent(manifestItem.path))
            if chapterPath == targetPath {
                return (spineIndex, normalizeFragment(url.fragment))
            }
        }

        return nil
    }

    private func normalizedFilePath(_ url: URL) -> String {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath().path
        return normalized.removingPercentEncoding ?? normalized
    }

    private func normalizeFragment(_ fragment: String?) -> String? {
        guard let fragment, !fragment.isEmpty else {
            return nil
        }
        return fragment.removingPercentEncoding ?? fragment
    }
}