import AnkiRustLib
import AnkiProto
public import Foundation
public import SwiftProtobuf

public final class AnkiBackend: Sendable {
    private let backendPtr: Int64
    private let lock = NSLock()

    /// Stored collection paths for close/reopen after full sync.
    private nonisolated(unsafe) var collectionPath: String?
    private nonisolated(unsafe) var mediaFolderPath: String?
    private nonisolated(unsafe) var mediaDbPath: String?

    public init(preferredLangs: [String] = ["en"]) throws {
        var initMsg = Anki_Backend_BackendInit()
        initMsg.preferredLangs = preferredLangs
        initMsg.server = false

        let initBytes = try initMsg.serializedData()
        var ptr: Int64 = 0

        let result = initBytes.withUnsafeBytes { buf in
            anki_open_backend(
                buf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                buf.count,
                &ptr
            )
        }

        guard result == 0, ptr != 0 else {
            throw BackendError(kind: .ioError, message: "Failed to initialize Anki backend")
        }
        self.backendPtr = ptr
    }

    deinit {
        anki_close_backend(backendPtr)
    }

    // MARK: - Typed RPC

    public func invoke<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
        service: UInt32, method: UInt32, request: Req
    ) throws -> Resp {
        let responseBytes = try call(service: service, method: method, request: request)
        return try Resp(serializedBytes: responseBytes)
    }

    public func invoke<Resp: SwiftProtobuf.Message>(
        service: UInt32, method: UInt32
    ) throws -> Resp {
        let responseBytes = try callRaw(service: service, method: method, input: Data())
        return try Resp(serializedBytes: responseBytes)
    }

    public func call(
        service: UInt32, method: UInt32,
        request: some SwiftProtobuf.Message
    ) throws -> Data {
        let inputBytes = try request.serializedData()
        return try callRaw(service: service, method: method, input: inputBytes)
    }

    public func call(service: UInt32, method: UInt32) throws -> Data {
        try callRaw(service: service, method: method, input: Data())
    }

    public func callVoid(
        service: UInt32, method: UInt32,
        request: some SwiftProtobuf.Message
    ) throws {
        _ = try call(service: service, method: method, request: request)
    }

    public func callVoid(service: UInt32, method: UInt32) throws {
        _ = try call(service: service, method: method)
    }

    // MARK: - Collection Lifecycle

    public func openCollection(
        collectionPath: String,
        mediaFolderPath: String,
        mediaDbPath: String
    ) throws {
        // Store paths for reopen after full sync
        self.collectionPath = collectionPath
        self.mediaFolderPath = mediaFolderPath
        self.mediaDbPath = mediaDbPath

        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = collectionPath
        req.mediaFolderPath = mediaFolderPath
        req.mediaDbPath = mediaDbPath
        try callVoid(service: Service.collection, method: CollectionMethod.open, request: req)
    }

    /// Reopen the collection after a full sync (which replaces the DB file).
    /// The Rust backend internally reopens, but we call close+open at our layer
    /// to ensure consistency (same pattern as AnkiDroid).
    public func reopenAfterFullSync() throws {
        guard let path = collectionPath,
              let media = mediaFolderPath,
              let mediaDb = mediaDbPath
        else { return }

        // Close our side (Rust may already have reopened internally)
        try? closeCollection()

        // Reopen with the same paths
        try openCollection(
            collectionPath: path,
            mediaFolderPath: media,
            mediaDbPath: mediaDb
        )
    }

    public func closeCollection(downgradeToSchema11: Bool = false) throws {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgradeToSchema11
        try callVoid(service: Service.collection, method: CollectionMethod.close, request: req)
    }

    // MARK: - Collection Config

    public func getConfigJSONValue<T: Decodable>(
        for key: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T? {
        var req = Anki_Generic_String()
        req.val = key

        do {
            let response: Anki_Generic_Json = try invoke(
                service: Service.config,
                method: ConfigMethod.getConfigJson,
                request: req
            )
            return try decoder.decode(T.self, from: response.json)
        } catch let error as BackendError where error.kind == .notFoundError {
            return nil
        }
    }

    public func setConfigJSONValue<T: Encodable>(
        _ value: T,
        for key: String,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        var req = Anki_Config_SetConfigJsonRequest()
        req.key = key
        req.valueJson = try encoder.encode(value)
        req.undoable = false

        try callVoid(
            service: Service.config,
            method: ConfigMethod.setConfigJsonNoUndo,
            request: req
        )
    }

    public func removeConfigValue(for key: String) throws {
        var req = Anki_Generic_String()
        req.val = key
        try callVoid(service: Service.config, method: ConfigMethod.removeConfig, request: req)
    }

    // MARK: - Raw FFI

    private func callRaw(service: UInt32, method: UInt32, input: Data) throws -> Data {
        let shouldLock = !(service == Service.collection && method == CollectionMethod.latestProgress)
        if shouldLock {
            lock.lock()
        }
        defer {
            if shouldLock {
                lock.unlock()
            }
        }

        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0

        let status: Int32
        if input.isEmpty {
            status = anki_run_method(backendPtr, service, method, nil, 0, &outPtr, &outLen)
        } else {
            status = input.withUnsafeBytes { buf in
                anki_run_method(
                    backendPtr, service, method,
                    buf.baseAddress?.assumingMemoryBound(to: UInt8.self), buf.count,
                    &outPtr, &outLen
                )
            }
        }

        defer {
            if let outPtr { anki_free_response(outPtr, outLen) }
        }

        let responseData: Data
        if let outPtr, outLen > 0 {
            responseData = Data(bytes: outPtr, count: outLen)
        } else {
            responseData = Data()
        }

        switch status {
        case 0: return responseData
        case 1: throw BackendError(errorBytes: responseData)
        default: throw BackendError(kind: .ioError, message: "FFI error (status \(status))")
        }
    }

    // MARK: - Batch Note Fetch

    /// Fetch multiple notes in a single C FFI call instead of N separate calls.
    /// Returns serialized `Anki_Notes_Note` protobufs; missing notes are omitted.
    public func getNotesBatch(noteIds: [Int64]) throws -> [Data] {
        guard !noteIds.isEmpty else { return [] }

        // Request format: [count: u32_le][nid_0: i64_le]...
        var requestData = Data(capacity: 4 + noteIds.count * 8)
        withUnsafeBytes(of: UInt32(noteIds.count).littleEndian) { requestData.append(contentsOf: $0) }
        for nid in noteIds {
            withUnsafeBytes(of: nid.littleEndian) { requestData.append(contentsOf: $0) }
        }

        lock.lock()
        defer { lock.unlock() }

        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0

        let status = requestData.withUnsafeBytes { buf in
            anki_get_notes_batch(
                backendPtr,
                buf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                buf.count,
                &outPtr,
                &outLen
            )
        }

        defer {
            if let outPtr { anki_free_response(outPtr, outLen) }
        }

        guard status == 0, let outPtr, outLen >= 4 else {
            throw BackendError(kind: .ioError, message: "getNotesBatch failed (status \(status))")
        }

        let responseData = Data(bytes: outPtr, count: outLen)
        return Self.decodeNotesBatchResponse(responseData)
    }

    private static func decodeNotesBatchResponse(_ data: Data) -> [Data] {
        guard data.count >= 4 else { return [] }

        func readUInt32LE(_ data: Data, _ index: Int) -> UInt32 {
            UInt32(data[index])
                | (UInt32(data[index + 1]) << 8)
                | (UInt32(data[index + 2]) << 16)
                | (UInt32(data[index + 3]) << 24)
        }

        var offset = 0
        let count = Int(readUInt32LE(data, offset))
        offset += 4

        var notes: [Data] = []
        notes.reserveCapacity(count)

        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = Int(readUInt32LE(data, offset))
            offset += 4
            guard len >= 0, offset + len <= data.count else { break }
            notes.append(data.subdata(in: offset..<(offset + len)))
            offset += len
        }

        return notes
    }
}

// MARK: - Service Constants

extension AnkiBackend {
    public enum Service {
        public static let sync: UInt32 = 1
        public static let collection: UInt32 = 3
        // ConfigService/BackendConfigService sit between Decks and DeckConfig in
        // the generated descriptor ordering used by rslib.
        public static let config: UInt32 = 9
        public static let deckConfig: UInt32 = 11
        public static let cards: UInt32 = 5
        public static let decks: UInt32 = 7
        public static let scheduler: UInt32 = 13
        public static let notetypes: UInt32 = 23
        public static let notes: UInt32 = 25
        public static let cardRendering: UInt32 = 27
        public static let search: UInt32 = 29
        public static let imageOcclusion: UInt32 = 35
        public static let importExport: UInt32 = 37
        public static let media: UInt32 = 39
        public static let stats: UInt32 = 41
        public static let tags: UInt32 = 43
    }

    public enum CollectionMethod {
        public static let open: UInt32 = 0
        public static let close: UInt32 = 1
        // BackendCollectionService has 6 backend-specific methods first.
        // CollectionService.GetUndoStatus is proto index 1, so delegated index is 6 + 1 = 7.
        public static let getUndoStatus: UInt32 = 7
        public static let latestProgress: UInt32 = 4
        // BackendCollectionService has 6 backend-specific methods first.
        // CollectionService.Undo is proto index 2, so delegated index is 6 + 2 = 8.
        public static let undo: UInt32 = 8
    }

    public enum CheckDatabaseMethod {
        // Delegated via BackendCollectionService (service=3); 6 backend-specific
        // methods precede delegated CollectionService methods, so CheckDatabase
        // (CollectionService method 0) is at index 6.
        public static let checkDatabase: UInt32 = 6
    }

    public enum SyncMethod {
        public static let syncMedia: UInt32 = 0
        public static let syncLogin: UInt32 = 3
        public static let syncStatus: UInt32 = 4
        public static let syncCollection: UInt32 = 5
        public static let fullUploadOrDownload: UInt32 = 6
    }

    public enum ConfigMethod {
        public static let getConfigJson: UInt32 = 0
        public static let setConfigJson: UInt32 = 1
        public static let setConfigJsonNoUndo: UInt32 = 2
        public static let removeConfig: UInt32 = 3
    }

    // Method indices from BackendSchedulerService (service 13) dispatch table.
    // Backend-level has 3 extra methods at start (computeFsrsParams, benchmark, exportDataset)
    // so Collection-level indices are offset by +3.
    public enum SchedulerMethod {
        public static let getQueuedCards: UInt32 = 3
        public static let answerCard: UInt32 = 4
        public static let schedTimingToday: UInt32 = 5
        public static let countsForDeckToday: UInt32 = 10
        public static let congratsInfo: UInt32 = 11
        // RestoreBuriedAndSuspendedCards = proto index 9 + offset 3 = 12
        public static let restoreBuriedAndSuspendedCards: UInt32 = 12
        public static let buryOrSuspendCards: UInt32 = 14
        // ScheduleCardsAsNew = proto index 14 + offset 3 = 17
        public static let scheduleCardsAsNew: UInt32 = 17
        // SetDueDate = proto index 16 + offset 3 = 19
        public static let setDueDate: UInt32 = 19
        // ComputeFsrsParams = proto index 27 + offset 3 = 30
        public static let computeFsrsParams: UInt32 = 30
        // SimulateFsrsReview = proto index 30 + offset 3 = 33
        public static let simulateFsrsReview: UInt32 = 33
        // SimulateFsrsWorkload = proto index 31 + offset 3 = 34
        public static let simulateFsrsWorkload: UInt32 = 34
    }

    public enum NotesMethod {
        public static let newNote: UInt32 = 0
        public static let addNote: UInt32 = 1
        public static let updateNotes: UInt32 = 5
        public static let getNote: UInt32 = 6
        public static let removeNotes: UInt32 = 7
    }

    public enum DecksMethod {
        public static let newDeck: UInt32 = 0
        public static let addDeck: UInt32 = 1
        public static let addDeckLegacy: UInt32 = 2
        public static let addOrUpdateDeckLegacy: UInt32 = 3
        public static let deckTree: UInt32 = 4
        public static let deckTreeLegacy: UInt32 = 5
        public static let getAllDecksLegacy: UInt32 = 6
        public static let getDeckIdByName: UInt32 = 7
        public static let getDeck: UInt32 = 8
        public static let updateDeck: UInt32 = 9
        public static let updateDeckLegacy: UInt32 = 10
        public static let setDeckCollapsed: UInt32 = 11
        public static let getDeckLegacy: UInt32 = 12
        public static let getDeckNames: UInt32 = 13
        public static let getDeckAndChildNames: UInt32 = 14
        public static let newDeckLegacy: UInt32 = 15
        public static let removeDecks: UInt32 = 16
        public static let reparentDecks: UInt32 = 17
        public static let renameDeck: UInt32 = 18
        public static let getOrCreateFilteredDeck: UInt32 = 19
        public static let addOrUpdateFilteredDeck: UInt32 = 20
        public static let filteredDeckOrderLabels: UInt32 = 21
        public static let setCurrentDeck: UInt32 = 22
        public static let getCurrentDeck: UInt32 = 23

        // Backward-compatible aliases
        public static let getDeckTree: UInt32 = deckTree
        public static let removeBrushedTags: UInt32 = filteredDeckOrderLabels
    }

    public enum DeckConfigMethod {
        public static let getDeckConfig: UInt32 = 1
        public static let getDeckConfigsForUpdate: UInt32 = 6
        public static let updateDeckConfigs: UInt32 = 7
        public static let getIgnoredBeforeCount: UInt32 = 8
        public static let getRetentionWorkload: UInt32 = 9
    }

    public enum SearchMethod {
        public static let searchCards: UInt32 = 1
        public static let searchNotes: UInt32 = 2
    }

    public enum CardsMethod {
        public static let getCard: UInt32 = 0
        public static let updateCards: UInt32 = 1
        public static let removeCards: UInt32 = 2
        public static let setDeck: UInt32 = 3
        public static let setFlag: UInt32 = 4
        public static let getCardByOrdinal: UInt32 = 5
    }

    // BackendCardRenderingService (27) has 3 backend-specific methods before delegated CardRenderingService methods.
    public enum CardRenderingMethod {
        public static let extractLatex: UInt32 = 4
        public static let getEmptyCards: UInt32 = 5
        public static let renderExistingCard: UInt32 = 6
        public static let renderUncommittedCard: UInt32 = 7
        public static let compareAnswer: UInt32 = 15
        public static let extractClozeForTyping: UInt32 = 16
    }

    public enum NotetypesMethod {
        public static let updateNotetype: UInt32 = 1
        public static let getNotetype: UInt32 = 6
        public static let getNotetypeNames: UInt32 = 8
        public static let getNotetypeNamesAndCounts: UInt32 = 9
        public static let removeNotetype: UInt32 = 11
        // GetChangeNotetypeInfo = proto index 14
        public static let getChangeNotetypeInfo: UInt32 = 14
        // ChangeNotetype = proto index 15
        public static let changeNotetype: UInt32 = 15
    }

    public enum ImportExportMethod {
        public static let importCollectionPackage: UInt32 = 0
        public static let exportCollectionPackage: UInt32 = 1
        public static let importAnkiPackage: UInt32 = 2
        // ExportAnkiPackage = ImportExportService method 2 + offset 2 backend methods = 4
        public static let exportAnkiPackage: UInt32 = 4
    }

    public enum StatsMethod {
        public static let cardStats: UInt32 = 0
        public static let graphs: UInt32 = 2
    }

    // BackendMediaService (39) has no backend-specific methods;
    // all MediaService methods are delegated with offset 0.
    public enum MediaMethod {
        public static let checkMedia: UInt32 = 0
        public static let addMediaFile: UInt32 = 1
        public static let trashMediaFiles: UInt32 = 2
        public static let emptyTrash: UInt32 = 3
        public static let restoreTrash: UInt32 = 4
    }

    public enum TagsMethod {
        public static let clearUnusedTags: UInt32 = 0
        public static let allTags: UInt32 = 1
        public static let removeTags: UInt32 = 2
        public static let setTagCollapsed: UInt32 = 3
        public static let tagTree: UInt32 = 4
        public static let reparentTags: UInt32 = 5
        public static let renameTags: UInt32 = 6
        public static let addNoteTags: UInt32 = 7
        public static let removeNoteTags: UInt32 = 8
        public static let findAndReplaceTag: UInt32 = 9
        public static let completeTag: UInt32 = 10

        // Backward-compatible aliases
        public static let getTagTree: UInt32 = tagTree
    }

    public enum ImageOcclusionMethod {
        // BackendImageOcclusionService (service 35) — all delegated from ImageOcclusionService.
        // Method order in ImageOcclusionService:
        //   0=GetImageForOcclusion, 1=GetImageOcclusionNote, 2=GetImageOcclusionFields,
        //   3=AddImageOcclusionNotetype, 4=AddImageOcclusionNote, 5=UpdateImageOcclusionNote
        public static let getImageForOcclusion: UInt32 = 0
        public static let getImageOcclusionNote: UInt32 = 1
        public static let getImageOcclusionFields: UInt32 = 2
        public static let addImageOcclusionNotetype: UInt32 = 3
        public static let addImageOcclusionNote: UInt32 = 4
        public static let updateImageOcclusionNote: UInt32 = 5
    }
}
