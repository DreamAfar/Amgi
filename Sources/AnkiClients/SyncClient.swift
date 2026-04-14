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
    public var fullSync: @Sendable (_ direction: SyncDirection) async throws -> Void
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
