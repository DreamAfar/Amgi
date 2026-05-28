import AnkiBackend
import AnkiProto
public import Dependencies
import Foundation
import Logging

private let logger = Logger(label: "com.ankiapp.notetypes.client")

private enum NotetypesLegacyMethod {
    static let getStockNotetype: UInt32 = 21
    static let getNotetype: UInt32 = 6
    static let addNotetype: UInt32 = 18
}

extension NotetypesClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        func loadRawNotetype(_ id: Int64) throws -> Anki_Notetypes_Notetype {
            var request = Anki_Notetypes_NotetypeId()
            request.ntid = id
            return try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: request
            )
        }

        return Self(
            listAll: {
                let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.getNotetypeNames
                )
                return response.entries
            },
            getRaw: { id in
                try loadRawNotetype(id)
            },
            update: { notetype in
                try backend.callVoid(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.updateNotetype,
                    request: notetype
                )
                logger.info("Notetype updated: id=\(notetype.id)")
            },
            remove: { id in
                var request = Anki_Notetypes_NotetypeId()
                request.ntid = id
                try backend.callVoid(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.removeNotetype,
                    request: request
                )
                logger.info("Notetype removed: id=\(id)")
            },
            resolveSingleNotetypeOfNotes: { noteIDs in
                var request = Anki_Notes_NoteIds()
                request.noteIds = noteIDs
                let response: Anki_Notetypes_NotetypeId = try backend.invoke(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.getSingleNotetypeOfNotes,
                    request: request
                )
                return response.ntid
            },
            prepareChangeTarget: { noteIDs in
                var request = Anki_Notes_NoteIds()
                request.noteIds = noteIDs
                let response: Anki_Notetypes_NotetypeId = try backend.invoke(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.getSingleNotetypeOfNotes,
                    request: request
                )
                ChangeNotetypeTarget(
                    noteIDs: noteIDs,
                    sourceNotetypeID: response.ntid
                )
            },
            getChangeNotetypeInfo: { noteIDs, sourceNotetypeID, newNotetypeID, newNotetypeName in
                var request = Anki_Notetypes_GetChangeNotetypeInfoRequest()
                request.oldNotetypeID = sourceNotetypeID
                request.newNotetypeID = newNotetypeID
                let info: Anki_Notetypes_ChangeNotetypeInfo = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.getChangeNotetypeInfo,
                    request: request
                )
                return ChangeNotetypeMappingData(
                    info: info,
                    noteIDs: noteIDs,
                    newNotetypeName: newNotetypeName
                )
            },
            changeNotetype: { request in
                try backend.callVoid(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.changeNotetype,
                    request: request
                )
            },
            getStockNotetypePayload: { kind in
                var request = Anki_Notetypes_StockNotetype()
                request.kind = kind
                let response: Anki_Generic_Json = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: NotetypesLegacyMethod.getStockNotetype,
                    request: request
                )
                return response.json
            },
            getLegacyNotetypePayload: { id in
                var request = Anki_Notetypes_NotetypeId()
                request.ntid = id
                let response: Anki_Generic_Json = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: NotetypesLegacyMethod.getNotetype,
                    request: request
                )
                return response.json
            },
            addLegacyNotetype: { payload in
                var request = Anki_Generic_Json()
                request.json = payload
                let response: Anki_Collection_OpChangesWithId = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: NotetypesLegacyMethod.addNotetype,
                    request: request
                )
                return response.id
            }
        )
    }()
}