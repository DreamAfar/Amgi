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

private func configuredSyncAuth(hostKey: String) -> Anki_Sync_SyncAuth {
    var auth = Anki_Sync_SyncAuth()
    auth.hkey = hostKey

    let syncMode = UserDefaults.standard.string(forKey: SyncPreferenceValues.modeKey) ?? "local"
    if syncMode == SyncPreferenceValues.customMode, let endpoint = KeychainHelper.loadEndpoint() {
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

/// Returns total note count, or -1 on failure (non-fatal).
private func countNotes(backend: AnkiBackend) -> Int {
    do {
        var req = Anki_Search_SearchRequest()
        req.search = "deck:*"
        let resp: Anki_Search_SearchResponse = try backend.invoke(
            service: AnkiBackend.Service.search,
            method: AnkiBackend.SearchMethod.searchNotes,
            request: req
        )
        return resp.ids.count
    } catch {
        return -1
    }
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
                    }

                    switch response.required {
                    case .noChanges:
                        logger.info("No changes needed")
                        return SyncSummary()

                    case .normalSync:
                        logger.info("Normal sync completed by backend")
                        return SyncSummary()

                    case .fullSync, .fullDownload:
                        // Need a full download — local collection is empty or incompatible
                        // The Rust backend internally closes, downloads, and reopens the collection.
                        // We do NOT close beforehand — the backend expects it open.
                        logger.info("Full download required, starting...")
                        var dlReq = Anki_Sync_FullUploadOrDownloadRequest()
                        dlReq.auth = auth
                        dlReq.upload = false
                        dlReq.serverUsn = response.serverMediaUsn

                        try syncBackend.callVoid(
                            service: AnkiBackend.Service.sync,
                            method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                            request: dlReq
                        )
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
                        var ulReq = Anki_Sync_FullUploadOrDownloadRequest()
                        ulReq.auth = auth
                        ulReq.upload = true
                        ulReq.serverUsn = response.serverMediaUsn

                        try syncBackend.callVoid(
                            service: AnkiBackend.Service.sync,
                            method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                            request: ulReq
                        )
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

                            // Count notes before sync to compute delta
                            let noteCountBefore = countNotes(backend: syncBackend)

                            var auth = configuredSyncAuth(hostKey: hostKey)
                            var req = Anki_Sync_SyncCollectionRequest()
                            req.auth = auth
                            req.syncMedia = false

                            let responseBytes: Data
                            do {
                                responseBytes = try syncBackend.call(
                                    service: AnkiBackend.Service.sync,
                                    method: AnkiBackend.SyncMethod.syncCollection,
                                    request: req
                                )
                            } catch let error as BackendError {
                                if error.isSyncAuthError { throw SyncError.authFailed }
                                throw SyncError(message: error.message)
                            }

                            let response = try Anki_Sync_SyncCollectionResponse(serializedBytes: responseBytes)
                            logger.info("syncWithProgress: required=\(response.required), serverMessage='\(response.serverMessage)'")

                            if response.hasNewEndpoint, !response.newEndpoint.isEmpty {
                                auth.endpoint = response.newEndpoint
                            }

                            switch response.required {
                            case .noChanges:
                                break

                            case .normalSync:
                                await emitter.yield(.normalSync)

                            case .fullSync, .fullDownload:
                                await emitter.yield(.fullDownloading)
                                var dlReq = Anki_Sync_FullUploadOrDownloadRequest()
                                dlReq.auth = auth
                                dlReq.upload = false
                                dlReq.serverUsn = response.serverMediaUsn
                                do {
                                    try syncBackend.callVoid(
                                        service: AnkiBackend.Service.sync,
                                        method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                                        request: dlReq
                                    )
                                } catch let error as BackendError {
                                    if error.isSyncAuthError { throw SyncError.authFailed }
                                    throw SyncError(message: error.message)
                                }
                                await emitter.yield(.checkingDatabase)
                                do {
                                    _ = try syncBackend.call(
                                        service: AnkiBackend.Service.collection,
                                        method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                                    )
                                } catch {
                                    logger.warning("CheckDatabase failed after full download: \(error)")
                                }

                            case .fullUpload:
                                await emitter.yield(.fullUploading)
                                var ulReq = Anki_Sync_FullUploadOrDownloadRequest()
                                ulReq.auth = auth
                                ulReq.upload = true
                                ulReq.serverUsn = response.serverMediaUsn
                                do {
                                    try syncBackend.callVoid(
                                        service: AnkiBackend.Service.sync,
                                        method: AnkiBackend.SyncMethod.fullUploadOrDownload,
                                        request: ulReq
                                    )
                                } catch let error as BackendError {
                                    if error.isSyncAuthError { throw SyncError.authFailed }
                                    throw SyncError(message: error.message)
                                }

                            case .UNRECOGNIZED(let v):
                                logger.warning("Unrecognized sync required value: \(v)")
                            }

                            if syncMediaEnabled() {
                                await emitter.yield(.syncingMedia)
                                let mediaAuth = configuredSyncAuth(hostKey: hostKey)
                                do {
                                    try syncBackend.callVoid(
                                        service: AnkiBackend.Service.sync,
                                        method: AnkiBackend.SyncMethod.syncMedia,
                                        request: mediaAuth
                                    )
                                } catch let error as BackendError {
                                    if error.isSyncAuthError { throw SyncError.authFailed }
                                    logger.warning("Media sync failed (non-fatal): \(error.message)")
                                }
                            }

                            UserDefaults.standard.set(
                                Date().timeIntervalSince1970,
                                forKey: SyncPreferenceValues.lastCollectionSyncKey
                            )

                            // Emit note count delta
                            let noteCountAfter = countNotes(backend: syncBackend)
                            if noteCountBefore >= 0, noteCountAfter >= 0 {
                                let added = max(0, noteCountAfter - noteCountBefore)
                                let removed = max(0, noteCountBefore - noteCountAfter)
                                await emitter.yield(.noteStats(added: added, removed: removed))
                            }

                            await emitter.yield(.completed(SyncSummary()))
                            await emitter.finish()
                        } catch {
                            await emitter.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { @Sendable _ in task.cancel() }
                }
            },
            fullSync: { direction in
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }

                let auth = configuredSyncAuth(hostKey: hostKey)

                var req = Anki_Sync_FullUploadOrDownloadRequest()
                req.auth = auth
                req.upload = (direction == .upload)

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
                } catch let error as BackendError {
                    if error.isSyncAuthError { throw SyncError.authFailed }
                    throw SyncError(message: error.message)
                }

                return MediaSyncSummary()
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
            logger.info("Login successful")
            return auth.hkey
        } catch let error as BackendError {
            logger.error("Login failed: \(error.message)")
            throw SyncError.authFailed
        }
    }
}
