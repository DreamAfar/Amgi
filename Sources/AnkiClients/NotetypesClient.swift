public import AnkiProto
public import Dependencies
import DependenciesMacros
public import Foundation

public struct ChangeNotetypeTarget: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let noteIDs: [Int64]
    public let sourceNotetypeID: Int64

    public init(noteIDs: [Int64], sourceNotetypeID: Int64) {
        self.noteIDs = noteIDs
        self.sourceNotetypeID = sourceNotetypeID
    }
}

public struct ChangeNotetypeMappingData: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let info: Anki_Notetypes_ChangeNotetypeInfo
    public let noteIDs: [Int64]
    public let newNotetypeName: String

    public init(
        info: Anki_Notetypes_ChangeNotetypeInfo,
        noteIDs: [Int64],
        newNotetypeName: String
    ) {
        self.info = info
        self.noteIDs = noteIDs
        self.newNotetypeName = newNotetypeName
    }
}

@DependencyClient
public struct NotetypesClient: Sendable {
    public var listAll: @Sendable () throws -> [Anki_Notetypes_NotetypeNameId]
    public var getRaw: @Sendable (_ id: Int64) throws -> Anki_Notetypes_Notetype
    public var update: @Sendable (_ notetype: Anki_Notetypes_Notetype) throws -> Void
    public var remove: @Sendable (_ id: Int64) throws -> Void
    public var resolveSingleNotetypeOfNotes: @Sendable (_ noteIDs: [Int64]) throws -> Int64
    public var prepareChangeTarget: @Sendable (_ noteIDs: [Int64]) throws -> ChangeNotetypeTarget
    public var getChangeNotetypeInfo: @Sendable (
        _ noteIDs: [Int64],
        _ sourceNotetypeID: Int64,
        _ newNotetypeID: Int64,
        _ newNotetypeName: String
    ) throws -> ChangeNotetypeMappingData
    public var changeNotetype: @Sendable (_ request: Anki_Notetypes_ChangeNotetypeRequest) throws -> Void
    public var getStockNotetypePayload: @Sendable (_ kind: Anki_Notetypes_StockNotetype.Kind) throws -> Data
    public var getLegacyNotetypePayload: @Sendable (_ id: Int64) throws -> Data
    public var addLegacyNotetype: @Sendable (_ payload: Data) throws -> Int64
}

extension NotetypesClient: TestDependencyKey {
    public static let testValue = NotetypesClient()
}

extension DependencyValues {
    public var notetypesClient: NotetypesClient {
        get { self[NotetypesClient.self] }
        set { self[NotetypesClient.self] = newValue }
    }
}