//
//  NotetypeRequests.swift
//  AnkiProtoBridge
//
//  Created by Vladimir Gusev on 08.05.2026.
//

import Foundation
public import AnkiBackend
public import AnkiKit
import AnkiProto
import SwiftProtobuf

// MARK: - getNotetypeNames

extension Request where Response == [NotetypeNameId] {
    /// Lists every notetype as `(id, name)` — the lightweight listing
    /// used by pickers and the templates browser.
    public static var notetypeNames: Self {
        .empty(
            serviceId: ServiceID.notetypes,
            methodId: NotetypesMethod.getNotetypeNames,
            decode: { bytes in
                let resp = try Anki_Notetypes_NotetypeNames(serializedBytes: bytes)
                return resp.entries.map(NotetypeNameId.init)
            }
        )
    }
}

// MARK: - getNotetype

extension Request where Response == Notetype {
    /// Fetches the full notetype (config, fields, templates) by id.
    public static func notetype(for id: NotetypeID) -> Self {
        .decoded(
            serviceId: ServiceID.notetypes,
            methodId: NotetypesMethod.getNotetype,
            encode: {
                var req = Anki_Notetypes_NotetypeId()
                req.ntid = id.rawValue
                return try req.serializedData()
            }
        )
    }
}

// MARK: - updateNotetype / removeNotetype

extension Request where Response == Void {
    /// Persists a modified notetype.
    public static func updateNotetype(_ notetype: Notetype) -> Self {
        Self(
            serviceId: ServiceID.notetypes,
            methodId: NotetypesMethod.updateNotetype,
            encode: { try notetype.toProto().serializedData() },
            decode: { _ in () }
        )
    }

    /// Removes a notetype and every card based on it.
    public static func removeNotetype(id: NotetypeID) -> Self {
        Self(
            serviceId: ServiceID.notetypes,
            methodId: NotetypesMethod.removeNotetype,
            encode: {
                var req = Anki_Notetypes_NotetypeId()
                req.ntid = id.rawValue
                return try req.serializedData()
            },
            decode: { _ in () }
        )
    }
}

// MARK: - Change notetype

extension Request where Response == ChangeNotetypeInfo {
    /// Field and template names on both sides, plus the backend's default
    /// mapping (matching names first, then position).
    public static func changeNotetypeInfo(from old: NotetypeID, to new: NotetypeID) -> Self {
        Self(
            serviceId: ServiceID.notetypes,
            methodId: NotetypesMethod.getChangeNotetypeInfo,
            encode: {
                var req = Anki_Notetypes_GetChangeNotetypeInfoRequest()
                req.oldNotetypeID = old.rawValue
                req.newNotetypeID = new.rawValue
                return try req.serializedData()
            },
            decode: { bytes in
                let info = try Anki_Notetypes_ChangeNotetypeInfo(serializedBytes: bytes)
                return ChangeNotetypeInfo(
                    oldNotetypeName: info.oldNotetypeName,
                    oldFieldNames: info.oldFieldNames,
                    oldTemplateNames: info.oldTemplateNames,
                    newFieldNames: info.newFieldNames,
                    newTemplateNames: info.newTemplateNames,
                    input: ChangeNotetypeInput(
                        noteIDs: info.input.noteIds.map(NoteID.init(rawValue:)),
                        newFields: info.input.newFields.map { $0 < 0 ? nil : Int($0) },
                        newTemplates: info.input.newTemplates.map { $0 < 0 ? nil : Int($0) },
                        oldNotetypeID: NotetypeID(rawValue: info.input.oldNotetypeID),
                        newNotetypeID: NotetypeID(rawValue: info.input.newNotetypeID),
                        currentSchema: info.input.currentSchema,
                        oldNotetypeName: info.input.oldNotetypeName,
                        isCloze: info.input.isCloze
                    )
                )
            }
        )
    }
}

extension Request where Response == Void {
    /// Moves the notes to the new notetype with the given field and card
    /// mapping. Changes the schema, so the next sync is a full one.
    public static func changeNotetype(_ input: ChangeNotetypeInput) -> Self {
        Self(
            serviceId: ServiceID.notetypes,
            methodId: NotetypesMethod.changeNotetype,
            encode: {
                var req = Anki_Notetypes_ChangeNotetypeRequest()
                req.noteIds = input.noteIDs.map(\.rawValue)
                // -1 stands for "nothing": repeated fields can't hold nulls.
                req.newFields = input.newFields.map { Int32($0 ?? -1) }
                req.newTemplates = input.newTemplates.map { Int32($0 ?? -1) }
                req.oldNotetypeID = input.oldNotetypeID.rawValue
                req.newNotetypeID = input.newNotetypeID.rawValue
                req.currentSchema = input.currentSchema
                req.oldNotetypeName = input.oldNotetypeName
                req.isCloze = input.isCloze
                return try req.serializedData()
            },
            decode: { _ in () }
        )
    }
}
