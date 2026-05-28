public import EPUBKit
public import Foundation
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
    public var statisticsEnabled: Bool
    public var isTracking = false
    public var isPaused = false
    public var stats: [ReaderStatistics]
    public var sessionStatistics: ReaderStatistics
    public var todaysStatistics: ReaderStatistics
    public var allTimeStatistics: ReaderStatistics

    private var statisticsLoaded = false
    private var lastStatisticsTimestamp: Date = .now
    private var lastStatisticsCharacterCount = 0

    public init(book: BookMetadata, enableStatistics: Bool = false, autostartStatistics: Bool = false) throws {
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
        self.statisticsEnabled = false

        let statisticsTitle = document.title ?? book.title ?? ""
        let currentDateKey = Self.formattedDate(date: .now)
        let emptyStatistics = ReaderStatistics.empty(title: statisticsTitle, dateKey: currentDateKey)
        self.stats = []
        self.sessionStatistics = emptyStatistics
        self.todaysStatistics = emptyStatistics
        self.allTimeStatistics = emptyStatistics

        if let bookmark {
            self.index = bookmark.chapterIndex
            self.currentProgress = bookmark.progress
        }

        var updatedBook = book
        updatedBook.lastAccess = Date()
        try? BookStorage.save(updatedBook, inside: rootURL, as: FileNames.metadata)

        configureStatistics(enabled: enableStatistics, autostart: autostartStatistics)
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

    public var currentChapterCount: Int {
        guard document.spine.items.indices.contains(index),
              let manifestItem = document.manifest.items[document.spine.items[index].idref],
              let chapterInfo = bookInfo.chapterInfo[manifestItem.path] else {
            return 0
        }

        return chapterInfo.currentTotal + chapterInfo.chapterCount
    }

    public func configureStatistics(enabled: Bool, autostart: Bool = false) {
        statisticsEnabled = enabled

        guard enabled else {
            stopTracking()
            return
        }

        loadStatisticsIfNeeded()

        if autostart && isTracking == false {
            startTracking()
        }
    }

    public func startTracking() {
        guard statisticsEnabled else {
            return
        }
        loadStatisticsIfNeeded()
        isTracking = true
        isPaused = false
        resetTrackingBaseline()
    }

    public func stopTracking() {
        guard isTracking else {
            return
        }
        flushStatistics()
        isTracking = false
        isPaused = false
    }

    public func pauseTracking() {
        guard isTracking else {
            return
        }
        flushStatistics()
        isPaused = true
    }

    public func resumeTracking() {
        guard isTracking else {
            return
        }
        isPaused = false
        resetTrackingBaseline()
    }

    public func updateStatistics() {
        guard statisticsEnabled, isTracking, isPaused == false else {
            return
        }

        let now = Date.now
        let timeDiff = now.timeIntervalSince(lastStatisticsTimestamp)
        let characterDiff = currentCharacter - lastStatisticsCharacterCount
        let finalCharacterDiff = characterDiff < 0 && abs(characterDiff) > sessionStatistics.charactersRead
            ? -sessionStatistics.charactersRead
            : characterDiff
        let lastStatisticModified = Int(now.timeIntervalSince1970 * 1000)

        guard timeDiff > 0 else {
            return
        }

        updateStatistics(
            &sessionStatistics,
            timeDiff: timeDiff,
            characterDiff: finalCharacterDiff,
            lastStatisticModified: lastStatisticModified
        )
        updateStatistics(
            &todaysStatistics,
            timeDiff: timeDiff,
            characterDiff: finalCharacterDiff,
            lastStatisticModified: lastStatisticModified
        )
        updateStatistics(
            &allTimeStatistics,
            timeDiff: timeDiff,
            characterDiff: finalCharacterDiff,
            lastStatisticModified: lastStatisticModified
        )

        lastStatisticsTimestamp = now
        lastStatisticsCharacterCount = currentCharacter
    }

    public func syncProgress(_ progress: Double, persistBookmark shouldPersistBookmark: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        currentProgress = clampedProgress

        if shouldPersistBookmark {
            persistBookmark(progress: clampedProgress)
        }
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
        flushStatistics()
    }

    public func actionForJumpToCharacter(_ characterCount: Int) -> ReaderEpubNavigationAction? {
        guard let result = bookInfo.resolveCharacterPosition(characterCount) else {
            return nil
        }

        flushStatistics()

        if result.spineIndex == index {
            persistBookmark(progress: result.progress)
            resetTrackingBaseline()
            return .restoreProgress(result.progress)
        }

        let action = updateChapter(index: result.spineIndex, progress: result.progress, fragment: nil)
        resetTrackingBaseline()
        return action
    }

    public func actionForJumpToChapter(index: Int, fragment: String? = nil) -> ReaderEpubNavigationAction? {
        flushStatistics()
        let action = updateChapter(index: index, progress: 0, fragment: fragment)
        resetTrackingBaseline()
        return action
    }

    public func actionForInternalLink(_ url: URL) -> ReaderEpubNavigationAction? {
        guard let destination = resolveSpineDestination(for: url) else {
            return nil
        }

        flushStatistics()

        if destination.spineIndex == index {
            if let fragment = destination.fragment {
                return .jumpToFragment(fragment)
            }

            persistBookmark(progress: 0)
            resetTrackingBaseline()
            return .restoreProgress(0)
        }

        let action = updateChapter(index: destination.spineIndex, progress: 0, fragment: destination.fragment)
        resetTrackingBaseline()
        return action
    }

    public func syncProgressAfterInternalJump(_ progress: Double) {
        persistBookmark(progress: progress)
        resetTrackingBaseline()
    }

    public func actionForNextChapter() -> ReaderEpubNavigationAction? {
        guard index < document.spine.items.count - 1 else {
            return nil
        }
        let action = updateChapter(index: index + 1, progress: 0, fragment: nil)
        flushStatistics()
        return action
    }

    public func actionForPreviousChapter() -> ReaderEpubNavigationAction? {
        guard index > 0 else {
            return nil
        }
        let action = updateChapter(index: index - 1, progress: 1, fragment: nil)
        flushStatistics()
        return action
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

    private func loadStatisticsIfNeeded() {
        guard statisticsLoaded == false else {
            return
        }

        stats = BookStorage.loadStatistics(root: rootURL) ?? []
        let currentDateKey = Self.formattedDate(date: .now)
        todaysStatistics = stats.first(where: { $0.dateKey == currentDateKey }) ?? ReaderStatistics.empty(
            title: statisticsTitle,
            dateKey: currentDateKey
        )
        allTimeStatistics = ReaderStatistics.empty(title: statisticsTitle, dateKey: currentDateKey)

        for statistic in stats {
            allTimeStatistics.readingTime += statistic.readingTime
            allTimeStatistics.charactersRead += statistic.charactersRead
            allTimeStatistics.lastReadingSpeed = allTimeStatistics.readingTime > 0
                ? Int((Double(allTimeStatistics.charactersRead) / allTimeStatistics.readingTime) * 3600.0)
                : 0
            allTimeStatistics.maxReadingSpeed = max(allTimeStatistics.maxReadingSpeed, statistic.maxReadingSpeed)
            allTimeStatistics.minReadingSpeed = allTimeStatistics.minReadingSpeed != 0
                ? min(allTimeStatistics.minReadingSpeed, statistic.minReadingSpeed)
                : statistic.minReadingSpeed
            allTimeStatistics.altMinReadingSpeed = allTimeStatistics.altMinReadingSpeed != 0
                ? min(allTimeStatistics.altMinReadingSpeed, statistic.altMinReadingSpeed)
                : statistic.altMinReadingSpeed
            allTimeStatistics.lastStatisticModified = max(allTimeStatistics.lastStatisticModified, statistic.lastStatisticModified)
        }

        statisticsLoaded = true
    }

    private var statisticsTitle: String {
        document.title ?? BookStorage.loadMetadata(root: rootURL)?.title ?? ""
    }

    private func updateStatistics(
        _ statistics: inout ReaderStatistics,
        timeDiff: Double,
        characterDiff: Int,
        lastStatisticModified: Int
    ) {
        statistics.readingTime += timeDiff
        statistics.charactersRead = max(statistics.charactersRead + characterDiff, 0)
        statistics.lastReadingSpeed = statistics.readingTime > 0
            ? Int((Double(statistics.charactersRead) / statistics.readingTime) * 3600.0)
            : 0
        statistics.maxReadingSpeed = max(statistics.maxReadingSpeed, statistics.lastReadingSpeed)
        statistics.minReadingSpeed = statistics.minReadingSpeed != 0
            ? min(statistics.minReadingSpeed, statistics.lastReadingSpeed)
            : statistics.lastReadingSpeed
        if characterDiff != 0 {
            statistics.altMinReadingSpeed = statistics.altMinReadingSpeed != 0
                ? min(statistics.altMinReadingSpeed, statistics.lastReadingSpeed)
                : statistics.lastReadingSpeed
        }
        statistics.lastStatisticModified = lastStatisticModified
    }

    private func saveStatistics() {
        guard statisticsEnabled else {
            return
        }

        if let index = stats.firstIndex(where: { $0.dateKey == todaysStatistics.dateKey }) {
            stats[index] = todaysStatistics
        } else {
            stats.append(todaysStatistics)
        }

        try? BookStorage.save(stats, inside: rootURL, as: FileNames.statistics)
    }

    private func flushStatistics() {
        guard statisticsEnabled, isTracking else {
            return
        }
        updateStatistics()
        saveStatistics()
    }

    private func resetTrackingBaseline() {
        lastStatisticsCharacterCount = currentCharacter
        lastStatisticsTimestamp = .now
    }

    private static func formattedDate(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
