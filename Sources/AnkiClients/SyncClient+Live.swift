import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiSync
public import Dependencies
import DependenciesMacros
import Foundation
import Logging
import SwiftProtobuf

private let logger = Logger(label: "com.ankiapp.sync.client")

private enum SyncPreferenceValues {
    static let modeKeyBase = "syncMode"
    static let syncMediaKeyBase = "sync_pref_sync_media"
    static let ioTimeoutSecsKeyBase = "sync_pref_io_timeout_secs"
    static let customMode = "custom"
    static let lastCollectionSyncBase = "sync_pref_collection_last_synced_at"

    static var modeKey: String { scoped(modeKeyBase) }
    static var syncMediaKey: String { scoped(syncMediaKeyBase) }
    static var ioTimeoutSecsKey: String { scoped(ioTimeoutSecsKeyBase) }
    static var lastCollectionSyncKey: String { scoped(lastCollectionSyncBase) }

    private static func scoped(_ base: String) -> String {
        "\(base).\(currentProfileID())"
    }

    private static func currentProfileID() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = selectedUser.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let profile = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return profile.isEmpty ? "default" : profile
    }
}

private func configuredSyncAuth(hostKey: String, endpointOverride: String? = nil) -> Anki_Sync_SyncAuth {
    var auth = Anki_Sync_SyncAuth()
    auth.hkey = hostKey

    if let endpointOverride = endpointOverride?.nilIfBlank {
        auth.endpoint = endpointOverride
    } else if UserDefaults.standard.string(forKey: SyncPreferenceValues.modeKey) == SyncPreferenceValues.customMode,
              let endpoint = KeychainHelper.loadCurrentEndpoint() ?? KeychainHelper.loadEndpoint() {
        auth.endpoint = endpoint
    }

    let timeout = UserDefaults.standard.integer(forKey: SyncPreferenceValues.ioTimeoutSecsKey)
    if timeout > 0 {
        auth.ioTimeoutSecs = UInt32(timeout)
    }

    return auth
}

private func syncMediaEnabled() -> Bool {
    if UserDefaults.standard.object(forKey: SyncPreferenceValues.syncMediaKey) == nil {
        return true
    }
    return UserDefaults.standard.bool(forKey: SyncPreferenceValues.syncMediaKey)
}

private actor SyncProgressEmitter {
    private var continuation: AsyncThrowingStream<SyncProgressEvent, any Error>.Continuation?

    init(_ continuation: AsyncThrowingStream<SyncProgressEvent, any Error>.Continuation) {
        self.continuation = continuation
    }

    func yield(_ event: SyncProgressEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }

    func finish(throwing error: any Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}

private struct NormalSyncProgressSnapshot: Equatable {
    let stage: String
    let added: String
    let removed: String
}

private struct MediaSyncProgressSnapshot: Equatable {
    let checked: String
    let added: String
    let removed: String

    var hasContent: Bool {
        checked.nilIfBlank != nil || added.nilIfBlank != nil || removed.nilIfBlank != nil
    }
}

private func latestCollectionProgress(backend: AnkiBackend) -> Anki_Collection_Progress? {
    try? backend.invoke(
        service: AnkiBackend.Service.collection,
        method: AnkiBackend.CollectionMethod.latestProgress
    )
}

private func startNormalSyncProgressPolling(
    backend: AnkiBackend,
    emitter: SyncProgressEmitter
) -> Task<Void, Never> {
    Task.detached(priority: .utility) {
        var lastSnapshot: NormalSyncProgressSnapshot?

        while !Task.isCancelled {
            if let progress = latestCollectionProgress(backend: backend),
               case .normalSync(let normalSync)? = progress.value {
                let snapshot = NormalSyncProgressSnapshot(
                    stage: normalSync.stage,
                    added: normalSync.added,
                    removed: normalSync.removed
                )
                if snapshot != lastSnapshot {
                    lastSnapshot = snapshot
                    await emitter.yield(
                        .normalSyncProgress(
                            stage: snapshot.stage,
                            added: snapshot.added,
                            removed: snapshot.removed
                        )
                    )
                }
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }
}

private func stopProgressPolling(_ task: Task<Void, Never>?) async {
    task?.cancel()
    _ = await task?.result
}

private func mediaSyncStatus(backend: AnkiBackend) throws -> Anki_Sync_MediaSyncStatusResponse {
    try backend.invoke(
        service: AnkiBackend.Service.sync,
        method: AnkiBackend.SyncMethod.mediaSyncStatus
    )
}

private func emitMediaSyncProgressIfNeeded(
    _ progress: Anki_Sync_MediaSyncProgress,
    lastSnapshot: inout MediaSyncProgressSnapshot?,
    emitter: SyncProgressEmitter?
) async {
    let snapshot = MediaSyncProgressSnapshot(
        checked: progress.checked,
        added: progress.added,
        removed: progress.removed
    )
    guard snapshot.hasContent, snapshot != lastSnapshot else {
        return
    }

    lastSnapshot = snapshot
    if let emitter {
        await emitter.yield(
            .mediaStats(
                checked: snapshot.checked,
                added: snapshot.added,
                removed: snapshot.removed
            )
        )
    }
}

private func waitForMediaSyncToComplete(
    backend: AnkiBackend,
    emitter: SyncProgressEmitter? = nil
) async throws {
    var lastSnapshot: MediaSyncProgressSnapshot?

    while true {
        try Task.checkCancellation()

        let status: Anki_Sync_MediaSyncStatusResponse
        do {
            status = try mediaSyncStatus(backend: backend)
        } catch let error as BackendError {
            if error.isSyncAuthError { throw SyncError.authFailed }
            throw SyncError(message: error.message)
        }

        if status.hasProgress {
            await emitMediaSyncProgressIfNeeded(
                status.progress,
                lastSnapshot: &lastSnapshot,
                emitter: emitter
            )
        }

        if status.active == false {
            break
        }

        try await Task.sleep(nanoseconds: 150_000_000)
    }
}

private func fullSyncRequirement(from response: Anki_Sync_SyncCollectionResponse, endpoint: String?) -> SyncFullSyncRequirement? {
    let serverUsn: Int32? = response.serverMediaUsn

    switch response.required {
    case .fullSync:
        return SyncFullSyncRequirement(
            kind: .conflict,
            serverUsn: serverUsn,
            endpoint: endpoint,
            serverMessage: response.serverMessage.nilIfBlank
        )
    case .fullDownload:
        return SyncFullSyncRequirement(
            kind: .downloadOnly,
            serverUsn: serverUsn,
            endpoint: endpoint,
            serverMessage: response.serverMessage.nilIfBlank
        )
    case .fullUpload:
        return SyncFullSyncRequirement(
            kind: .uploadOnly,
            serverUsn: serverUsn,
            endpoint: endpoint,
            serverMessage: response.serverMessage.nilIfBlank
        )
    default:
        return nil
    }
}

extension SyncClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        let syncBackend = backend

        return Self(
            sync: {
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }

                logger.info("Starting sync via Rust backend")

                var auth = configuredSyncAuth(hostKey: hostKey)

                var req = Anki_Sync_SyncCollectionRequest()
                req.auth = auth
                req.syncMedia = syncMediaEnabled()

                do {
                    let responseBytes = try syncBackend.call(
                        service: AnkiBackend.Service.sync,
                        method: AnkiBackend.SyncMethod.syncCollection,
                        request: req
                    )
                    let response = try Anki_Sync_SyncCollectionResponse(serializedBytes: responseBytes)
                    logger.info("SyncCollection response: required=\(response.required), message='\(response.serverMessage)', endpoint=\(response.newEndpoint)")

                    // Update endpoint if server redirected
                    if response.hasNewEndpoint, !response.newEndpoint.isEmpty {
                        auth.endpoint = response.newEndpoint
                        try? KeychainHelper.saveCurrentEndpoint(response.newEndpoint)
                    }

                    switch response.required {
                    case .noChanges:
                        if req.syncMedia {
                            try await waitForMediaSyncToComplete(backend: syncBackend)
                        }
                        logger.info("No changes needed")
                        return SyncSummary()

                    case .normalSync:
                        if req.syncMedia {
                            try await waitForMediaSyncToComplete(backend: syncBackend)
                        }
                        logger.info("Normal sync completed by backend")
                        return SyncSummary()

                    case .fullSync, .fullDownload:
                        // Need a full download — local collection is empty or incompatible
                        // The Rust backend internally closes, downloads, and reopens the collection.
                        // We do NOT close beforehand — the backend expects it open.
                        logger.info("Full download required, starting...")
                        let requestedServerUsn = req.syncMedia ? response.serverMediaUsn : nil
                        var dlReq = Anki_Sync_FullUploadOrDownloadRequest()
                        dlReq.auth = auth
                        dlReq.upload = false
                        if let requestedServerUsn {
                            dlReq.serverUsn = requestedServerUsn
                        }

                        try syncBackend.callVoid(
                            service: AnkiBackend.Service.sync,
                            method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                            request: dlReq
                        )
                        if requestedServerUsn != nil {
                            try await waitForMediaSyncToComplete(backend: syncBackend)
                        }
                        logger.info("Full download complete, running CheckDatabase...")

                        // Run CheckDatabase to repair any inconsistencies
                        do {
                            let checkResult = try syncBackend.call(
                                service: AnkiBackend.Service.collection,
                                method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                            )
                            logger.info("CheckDatabase completed (\(checkResult.count) bytes)")
                        } catch {
                            logger.warning("CheckDatabase failed: \(error) — continuing anyway")
                        }

                        return SyncSummary()

                    case .fullUpload:
                        logger.info("Full upload required, starting...")
                        let requestedServerUsn = req.syncMedia ? response.serverMediaUsn : nil
                        var ulReq = Anki_Sync_FullUploadOrDownloadRequest()
                        ulReq.auth = auth
                        ulReq.upload = true
                        if let requestedServerUsn {
                            ulReq.serverUsn = requestedServerUsn
                        }

                        try syncBackend.callVoid(
                            service: AnkiBackend.Service.sync,
                            method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                            request: ulReq
                        )
                        if requestedServerUsn != nil {
                            try await waitForMediaSyncToComplete(backend: syncBackend)
                        }
                        logger.info("Full upload complete")
                        return SyncSummary()

                    case .UNRECOGNIZED(let v):
                        logger.warning("Unrecognized sync required: \(v)")
                        return SyncSummary()
                    }
                } catch let error as BackendError {
                    logger.error("Sync error: \(error.message)")
                    if error.isSyncAuthError { throw SyncError.authFailed }
                    throw SyncError(message: error.message)
                }
            },
            syncWithProgress: {
                AsyncThrowingStream<SyncProgressEvent, any Error> { continuation in
                    let emitter = SyncProgressEmitter(continuation)
                    let task = Task { [syncBackend, emitter] in
                        do {
                            let hostKey = KeychainHelper.loadHostKey() ?? ""
                            guard !hostKey.isEmpty else { throw SyncError.authFailed }

                            await emitter.yield(.connecting)

                            var auth = configuredSyncAuth(hostKey: hostKey)
                            var req = Anki_Sync_SyncCollectionRequest()
                            req.auth = auth
                            req.syncMedia = syncMediaEnabled()

                            let responseBytes: Data
                            let pollTask = startNormalSyncProgressPolling(
                                backend: syncBackend,
                                emitter: emitter
                            )
                            do {
                                responseBytes = try syncBackend.call(
                                    service: AnkiBackend.Service.sync,
                                    method: AnkiBackend.SyncMethod.syncCollection,
                                    request: req
                                )
                            } catch let error as BackendError {
                                await stopProgressPolling(pollTask)
                                if error.isSyncAuthError { throw SyncError.authFailed }
                                throw SyncError(message: error.message)
                            }
                            await stopProgressPolling(pollTask)

                            let response = try Anki_Sync_SyncCollectionResponse(serializedBytes: responseBytes)
                            logger.info("syncWithProgress: required=\(response.required), serverMessage='\(response.serverMessage)'")

                            if response.hasNewEndpoint, !response.newEndpoint.isEmpty {
                                auth.endpoint = response.newEndpoint
                                try? KeychainHelper.saveCurrentEndpoint(response.newEndpoint)
                            }

                            let fullSyncEndpoint = auth.hasEndpoint ? auth.endpoint : nil
                            if let requirement = fullSyncRequirement(from: response, endpoint: fullSyncEndpoint) {
                                await emitter.yield(.fullSyncRequired(requirement))
                                await emitter.finish()
                                return
                            }

                            switch response.required {
                            case .noChanges:
                                break

                            case .normalSync:
                                await emitter.yield(.normalSync)

                            case .UNRECOGNIZED(let v):
                                logger.warning("Unrecognized sync required value: \(v)")
                            case .fullSync, .fullDownload, .fullUpload:
                                break
                            }

                            if req.syncMedia {
                                await emitter.yield(.syncingMedia)
                                try await waitForMediaSyncToComplete(
                                    backend: syncBackend,
                                    emitter: emitter
                                )
                            }

                            UserDefaults.standard.set(
                                Date().timeIntervalSince1970,
                                forKey: SyncPreferenceValues.lastCollectionSyncKey
                            )

                            await emitter.yield(.completed(SyncSummary()))
                            await emitter.finish()
                        } catch {
                            await emitter.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { @Sendable _ in task.cancel() }
                }
            },
            fullSync: { direction, serverUsn, endpoint in
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }

                let auth = configuredSyncAuth(hostKey: hostKey, endpointOverride: endpoint)
                let requestedServerUsn = syncMediaEnabled() ? serverUsn : nil

                var req = Anki_Sync_FullUploadOrDownloadRequest()
                req.auth = auth
                req.upload = (direction == .upload)
                if let requestedServerUsn {
                    req.serverUsn = requestedServerUsn
                }

                do {
                    try syncBackend.callVoid(
                        service: AnkiBackend.Service.sync,
                        method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                        request: req
                    )
                    if requestedServerUsn != nil {
                        try await waitForMediaSyncToComplete(backend: syncBackend)
                    }
                    UserDefaults.standard.set(
                        Date().timeIntervalSince1970,
                        forKey: SyncPreferenceValues.lastCollectionSyncKey
                    )
                } catch let error as BackendError {
                    if error.isSyncAuthError { throw SyncError.authFailed }
                    throw SyncError(message: error.message)
                }
            },
            fullSyncWithProgress: { direction, serverUsn, endpoint in
                AsyncThrowingStream<SyncProgressEvent, any Error> { continuation in
                    let emitter = SyncProgressEmitter(continuation)
                    let task = Task { [syncBackend, emitter] in
                        do {
                            let hostKey = KeychainHelper.loadHostKey() ?? ""
                            guard !hostKey.isEmpty else { throw SyncError.authFailed }

                            let auth = configuredSyncAuth(hostKey: hostKey, endpointOverride: endpoint)
                            let requestedServerUsn = syncMediaEnabled() ? serverUsn : nil

                            await emitter.yield(direction == .download ? .fullDownloading : .fullUploading)

                            var req = Anki_Sync_FullUploadOrDownloadRequest()
                            req.auth = auth
                            req.upload = (direction == .upload)
                            if let requestedServerUsn {
                                req.serverUsn = requestedServerUsn
                            }

                            do {
                                try syncBackend.callVoid(
                                    service: AnkiBackend.Service.sync,
                                    method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                                    request: req
                                )
                            } catch let error as BackendError {
                                if error.isSyncAuthError { throw SyncError.authFailed }
                                throw SyncError(message: error.message)
                            }

                            try Task.checkCancellation()

                            if requestedServerUsn != nil {
                                await emitter.yield(.syncingMedia)
                                try await waitForMediaSyncToComplete(
                                    backend: syncBackend,
                                    emitter: emitter
                                )
                            }

                            UserDefaults.standard.set(
                                Date().timeIntervalSince1970,
                                forKey: SyncPreferenceValues.lastCollectionSyncKey
                            )

                            await emitter.yield(.completed(SyncSummary()))
                            await emitter.finish()
                        } catch {
                            await emitter.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { @Sendable _ in task.cancel() }
                }
            },
            syncMedia: {
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }

                let auth = configuredSyncAuth(hostKey: hostKey)

                do {
                    try syncBackend.callVoid(
                        service: AnkiBackend.Service.sync,
                        method: AnkiBackend.SyncMethod.syncMedia,
                        request: auth
                    )
                    try await waitForMediaSyncToComplete(backend: syncBackend)
                } catch let error as BackendError {
                    if error.isSyncAuthError { throw SyncError.authFailed }
                    throw SyncError(message: error.message)
                }

                return MediaSyncSummary()
            },
            syncMediaWithProgress: {
                AsyncThrowingStream<SyncProgressEvent, any Error> { continuation in
                    let emitter = SyncProgressEmitter(continuation)
                    let task = Task { [syncBackend, emitter] in
                        do {
                            let hostKey = KeychainHelper.loadHostKey() ?? ""
                            guard !hostKey.isEmpty else { throw SyncError.authFailed }
                            let auth = configuredSyncAuth(hostKey: hostKey)

                            logger.info("Starting media sync via backend status monitoring")
                            await emitter.yield(.connecting)
                            await emitter.yield(.syncingMedia)

                            do {
                                try syncBackend.callVoid(
                                    service: AnkiBackend.Service.sync,
                                    method: AnkiBackend.SyncMethod.syncMedia,
                                    request: auth
                                )
                            } catch let error as BackendError {
                                if error.isSyncAuthError { throw SyncError.authFailed }
                                throw SyncError(message: error.message)
                            }

                            try await waitForMediaSyncToComplete(
                                backend: syncBackend,
                                emitter: emitter
                            )

                            await emitter.yield(.completed(SyncSummary()))
                            await emitter.finish()
                        } catch {
                            await emitter.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { @Sendable _ in task.cancel() }
                }
            },
            lastSyncDate: {
                let ts = UserDefaults.standard.double(forKey: SyncPreferenceValues.lastCollectionSyncKey)
                guard ts > 0 else { return nil }
                return Date(timeIntervalSince1970: ts)
            }
        )
    }()

    public static func login(
        username: String,
        password: String
    ) async throws -> String {
        @Dependency(\.ankiBackend) var backend

        logger.info("Logging in as \(username)")

        var req = Anki_Sync_SyncLoginRequest()
        req.username = username
        req.password = password
        let auth = configuredSyncAuth(hostKey: "")
        if auth.hasEndpoint {
            req.endpoint = auth.endpoint
        }

        do {
            let auth: Anki_Sync_SyncAuth = try backend.invoke(
                service: AnkiBackend.Service.sync,
                method: AnkiBackend.SyncMethod.syncLogin,
                request: req
            )

            try KeychainHelper.saveHostKey(auth.hkey)
            try KeychainHelper.saveUsername(username)
            if auth.hasEndpoint, !auth.endpoint.isEmpty {
                try? KeychainHelper.saveCurrentEndpoint(auth.endpoint)
            }
            logger.info("Login successful")
            return auth.hkey
        } catch let error as BackendError {
            logger.error("Login failed: \(error.message)")
            throw SyncError.authFailed
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
