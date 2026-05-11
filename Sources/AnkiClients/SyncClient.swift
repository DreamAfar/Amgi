public import AnkiKit
public import Dependencies
import DependenciesMacros
public import Foundation

@DependencyClient
public struct SyncClient: Sendable {
    public var sync: @Sendable () async throws -> SyncSummary
    /// Streams sync progress events; final event is `.completed(SyncSummary)`.
    public var syncWithProgress: @Sendable () -> AsyncThrowingStream<SyncProgressEvent, any Error> = {
        AsyncThrowingStream { $0.finish(throwing: SyncError(message: "SyncClient.syncWithProgress unimplemented")) }
    }
    public var fullSync: @Sendable (_ direction: SyncDirection, _ serverUsn: Int32?, _ endpoint: String?) async throws -> Void
    /// Streams progress for a full upload/download, including follow-up media sync.
    public var fullSyncWithProgress: @Sendable (_ direction: SyncDirection, _ serverUsn: Int32?, _ endpoint: String?) -> AsyncThrowingStream<SyncProgressEvent, any Error> = { _, _, _ in
        AsyncThrowingStream { $0.finish(throwing: SyncError(message: "SyncClient.fullSyncWithProgress unimplemented")) }
    }
    public var syncMedia: @Sendable () async throws -> MediaSyncSummary
    /// Syncs media in batches with progress events
    public var syncMediaWithProgress: @Sendable () -> AsyncThrowingStream<SyncProgressEvent, any Error> = {
        AsyncThrowingStream { $0.finish(throwing: SyncError(message: "SyncClient.syncMediaWithProgress unimplemented")) }
    }
    public var lastSyncDate: @Sendable () -> Date? = { nil }
}

extension SyncClient: TestDependencyKey {
    public static let testValue = SyncClient()
}

extension DependencyValues {
    public var syncClient: SyncClient {
        get { self[SyncClient.self] }
        set { self[SyncClient.self] = newValue }
    }
}
