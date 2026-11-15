//
//  NotetypesClient+Live.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 29.04.2026.
//

import AnkiBackend
import AnkiKit
import AnkiProtoBridge
public import Dependencies
import Foundation
import Logging

private let logger = Logger(label: "com.amgiapp.notetypes.client")

extension NotetypesClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            listAll: {
                try await backend.invoke(.notetypeNames)
            },
            get: { id in
                try await backend.invoke(.notetype(for: id))
            },
            update: { notetype in
                try await backend.invoke(.updateNotetype(notetype))
                logger.info("Notetype updated: id=\(notetype.id.rawValue)")
            },
            remove: { id in
                try await backend.invoke(.removeNotetype(id: id))
                logger.info("Notetype removed: id=\(id.rawValue)")
            },
            changeNotetypeInfo: { old, new in
                try await backend.invoke(.changeNotetypeInfo(from: old, to: new))
            },
            changeNotetype: { input in
                try await backend.invoke(.changeNotetype(input))
                logger.info("Changed notetype of \(input.noteIDs.count) notes")
            }
        )
    }()
}
