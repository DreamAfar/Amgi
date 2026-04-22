import AnkiKit
import AnkiBackend
import AnkiProto
public import Dependencies
import DependenciesMacros
import Foundation

extension ReaderBookClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.noteClient) var noteClient

        func validatedDeckQuery(_ deckName: String) throws -> String {
            let trimmedDeckName = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDeckName.isEmpty else {
                throw BackendError(kind: .invalidInput, message: "Reader deck name can't be empty")
            }

            let escapedDeckName = trimmedDeckName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "deck:\"\(escapedDeckName)\""
        }

        func fetchNotetypeFieldNames(_ notetypeID: Int64) throws -> [String] {
            var request = Anki_Notetypes_NotetypeId()
            request.ntid = notetypeID
            let notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: request
            )
            return notetype.fields.map(\.name)
        }

        func decodeFieldMap(note: NoteRecord, fieldNames: [String]) -> [String: String] {
            let values = note.flds
                .split(separator: "\u{1f}", omittingEmptySubsequences: false)
                .map(String.init)

            var mapping: [String: String] = [:]
            mapping.reserveCapacity(fieldNames.count)

            for (index, fieldName) in fieldNames.enumerated() {
                mapping[fieldName] = index < values.count ? values[index] : ""
            }

            return mapping
        }

        func trimmedFieldValue(_ fieldName: String, in fieldMap: [String: String]) -> String? {
            guard let rawValue = fieldMap[fieldName] else {
                return nil
            }

            let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        }

        func contentFieldValue(_ fieldName: String, in fieldMap: [String: String]) -> String? {
            guard let rawValue = fieldMap[fieldName], !rawValue.isEmpty else {
                return nil
            }

            return rawValue
        }

        func makeChapter(
            note: NoteRecord,
            configuration: ReaderLibraryConfiguration,
            fieldNames: [String]
        ) -> ReaderChapter? {
            let fieldMap = decodeFieldMap(note: note, fieldNames: fieldNames)
            let mapping = configuration.fieldMapping

            guard let bookID = trimmedFieldValue(mapping.bookIDField, in: fieldMap),
                  let content = contentFieldValue(mapping.contentField, in: fieldMap) else {
                return nil
            }

            let bookTitle = trimmedFieldValue(mapping.bookTitleField, in: fieldMap) ?? bookID
            let chapterTitle = trimmedFieldValue(mapping.chapterTitleField, in: fieldMap) ?? bookTitle
            let chapterOrder = trimmedFieldValue(mapping.chapterOrderField, in: fieldMap)
            let language = mapping.languageField.flatMap { trimmedFieldValue($0, in: fieldMap) }

            return ReaderChapter(
                id: note.id,
                bookID: bookID,
                bookTitle: bookTitle,
                title: chapterTitle,
                order: chapterOrder,
                content: content,
                language: language
            )
        }

        func fetchNotes(for configuration: ReaderLibraryConfiguration) throws -> [NoteRecord] {
            let noteIDs = try noteClient.searchIds(validatedDeckQuery(configuration.deckName))
            guard !noteIDs.isEmpty else {
                return []
            }

            var notes: [NoteRecord] = []
            notes.reserveCapacity(noteIDs.count)

            let batchSize = 500
            var startIndex = 0
            while startIndex < noteIDs.count {
                let endIndex = min(startIndex + batchSize, noteIDs.count)
                notes.append(contentsOf: try noteClient.fetchBatch(Array(noteIDs[startIndex..<endIndex])))
                startIndex = endIndex
            }

            return notes
        }

        func parseNumericOrder(_ value: String?) -> Double? {
            guard let value else {
                return nil
            }
            return Double(value)
        }

        func chapterSort(lhs: ReaderChapter, rhs: ReaderChapter) -> Bool {
            let lhsNumericOrder = parseNumericOrder(lhs.order)
            let rhsNumericOrder = parseNumericOrder(rhs.order)

            switch (lhsNumericOrder, rhsNumericOrder) {
            case let (lhsOrder?, rhsOrder?) where lhsOrder != rhsOrder:
                return lhsOrder < rhsOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        }

        func buildBooks(from notes: [NoteRecord], configuration: ReaderLibraryConfiguration) throws -> [ReaderBook] {
            var fieldNamesByNotetypeID: [Int64: [String]] = [:]
            var chaptersByBookID: [String: [ReaderChapter]] = [:]

            for note in notes {
                let fieldNames: [String]
                if let cachedFieldNames = fieldNamesByNotetypeID[note.mid] {
                    fieldNames = cachedFieldNames
                } else {
                    let loadedFieldNames = try fetchNotetypeFieldNames(note.mid)
                    fieldNamesByNotetypeID[note.mid] = loadedFieldNames
                    fieldNames = loadedFieldNames
                }

                guard let chapter = makeChapter(
                    note: note,
                    configuration: configuration,
                    fieldNames: fieldNames
                ) else {
                    continue
                }

                chaptersByBookID[chapter.bookID, default: []].append(chapter)
            }

            return chaptersByBookID.values
                .map { chapters in
                    let sortedChapters = chapters.sorted(by: chapterSort)
                    return ReaderBook(
                        id: sortedChapters[0].bookID,
                        title: sortedChapters[0].bookTitle,
                        language: sortedChapters.compactMap(\.language).first,
                        chapters: sortedChapters
                    )
                }
                .sorted { lhs, rhs in
                    let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }
                    return lhs.id < rhs.id
                }
        }

        return Self(
            loadBooks: { configuration in
                let notes = try fetchNotes(for: configuration)
                return try buildBooks(from: notes, configuration: configuration)
            },
            loadBook: { bookID, configuration in
                try buildBooks(from: fetchNotes(for: configuration), configuration: configuration)
                    .first(where: { $0.id == bookID })
            }
        )
    }()
}