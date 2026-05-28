import EPUBKit
import Foundation
public import Dependencies

private enum ReaderEpubLibraryError: LocalizedError {
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Imported EPUB is missing a title."
        }
    }
}

private func loadEpubLibraryState() throws -> ReaderEpubLibraryState {
    let books = try BookStorage.loadAllBooks()
    let shelves = BookStorage.loadShelves() ?? []
    let progressByBookID = try loadBookProgress(for: books)
    return ReaderEpubLibraryState(
        books: books,
        shelves: shelves,
        progressByBookID: progressByBookID
    )
}

private func loadBookProgress(for books: [BookMetadata]) throws -> [UUID: Double] {
    let directory = try BookStorage.getBooksDirectory()
    var progressByBookID: [UUID: Double] = [:]

    for book in books {
        guard let folder = book.folder else {
            progressByBookID[book.id] = 0
            continue
        }

        let root = directory.appendingPathComponent(folder)
        let bookInfo = BookStorage.loadBookInfo(root: root)
        let bookmark = BookStorage.loadBookmark(root: root)

        if let total = bookInfo?.characterCount,
           total > 0,
           let current = bookmark?.characterCount {
            progressByBookID[book.id] = Double(current) / Double(total)
        } else {
            progressByBookID[book.id] = 0
        }
    }

    return progressByBookID
}

private func sanitizeFileName(_ string: String) -> String {
    string
        .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.newlines).union(.controlCharacters))
        .joined(separator: "_")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func findCoverInManifest(document: EPUBDocument) -> String? {
    if let coverItem = document.manifest.items.values.first(where: { $0.property?.contains("cover-image") == true }) {
        return coverItem.path
    }

    if let coverId = document.metadata.coverId,
       let coverItem = document.manifest.items[coverId] {
        return coverItem.path
    }

    let imageTypes: [EPUBMediaType] = [.jpeg, .png, .gif, .svg]
    if let coverItem = document.manifest.items.values.first(where: { $0.id.lowercased().contains("cover") }),
       imageTypes.contains(coverItem.mediaType) {
        return coverItem.path
    }
    if let firstImage = document.manifest.items.values.first(where: { imageTypes.contains($0.mediaType) }) {
        return firstImage.path
    }

    return nil
}

private func finalizeImport(localURL: URL, bookFolder: URL, document: EPUBDocument) throws {
    do {
        var coverURL: String?
        if let coverPath = findCoverInManifest(document: document) {
            let coverSourceURL = document.contentDirectory.appendingPathComponent(coverPath)
            let coverDestination = "Books/\(bookFolder.lastPathComponent)/\(URL(fileURLWithPath: coverPath).lastPathComponent)"
            try BookStorage.copyFile(from: coverSourceURL, to: coverDestination)
            coverURL = coverDestination
        }

        let metadata = BookMetadata(
            title: document.title,
            cover: coverURL,
            folder: bookFolder.lastPathComponent,
            lastAccess: Date()
        )

        let bookInfo = BookProcessor.process(document: document)

        try BookStorage.save(metadata, inside: bookFolder, as: FileNames.metadata)
        try BookStorage.save(bookInfo, inside: bookFolder, as: FileNames.bookinfo)
        try BookStorage.delete(at: localURL)
    } catch {
        try? BookStorage.delete(at: localURL)
        try? BookStorage.delete(at: bookFolder)
        throw error
    }
}

private func processImport(sourceURL: URL) throws {
    let tempDir = FileManager.default.temporaryDirectory
    let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")

    try FileManager.default.copyItem(at: sourceURL, to: tempURL)

    defer {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension())
    }

    let tempDocument = try BookStorage.loadEpub(tempURL)
    guard let title = tempDocument.title, !title.isEmpty else {
        throw ReaderEpubLibraryError.missingTitle
    }

    let safeTitle = sanitizeFileName(title)
    let booksDir = try BookStorage.getBooksDirectory()
    let targetFolder = booksDir.appendingPathComponent(safeTitle)
    if FileManager.default.fileExists(atPath: targetFolder.path(percentEncoded: false)) {
        return
    }

    let destinationPath = "Books/\(safeTitle).epub"
    let localURL = try BookStorage.copyFile(from: tempURL, to: destinationPath)
    let bookFolder = localURL.deletingPathExtension()
    let document = try BookStorage.loadEpub(localURL)
    try finalizeImport(localURL: localURL, bookFolder: bookFolder, document: document)
}

private func processImport(url: URL) throws {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
    try processImport(sourceURL: url)
}

private func deleteEpubBooks(_ bookIDs: [UUID]) throws {
    let state = try loadEpubLibraryState()
    for book in state.books where bookIDs.contains(book.id) {
        if let folder = book.folder {
            let bookURL = try BookStorage.getBooksDirectory().appendingPathComponent(folder)
            try BookStorage.delete(at: bookURL)
        }
    }

    var shelves = state.shelves
    for index in shelves.indices {
        shelves[index].bookIds.removeAll(where: { bookIDs.contains($0) })
    }
    try BookStorage.save(shelves, inside: try BookStorage.getBooksDirectory(), as: FileNames.shelves)
}

extension ReaderEpubLibraryClient: DependencyKey {
    public static let liveValue = ReaderEpubLibraryClient(
        loadState: {
            try loadEpubLibraryState()
        },
        importBooks: { urls in
            for url in urls {
                try processImport(url: url)
            }
            return try loadEpubLibraryState()
        },
        deleteBooks: { bookIDs in
            try deleteEpubBooks(bookIDs)
            return try loadEpubLibraryState()
        }
    )
}
