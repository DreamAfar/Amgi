public import Foundation
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct ReaderEpubLibraryClient: Sendable {
    public var loadState: @Sendable () throws -> ReaderEpubLibraryState
    public var importBooks: @Sendable (_ urls: [URL]) throws -> ReaderEpubLibraryState
    public var deleteBooks: @Sendable (_ bookIDs: [UUID]) throws -> ReaderEpubLibraryState
}

extension ReaderEpubLibraryClient: TestDependencyKey {
    public static let testValue = ReaderEpubLibraryClient(
        loadState: { .empty },
        importBooks: { _ in .empty },
        deleteBooks: { _ in .empty }
    )
}

extension DependencyValues {
    public var readerEpubLibraryClient: ReaderEpubLibraryClient {
        get { self[ReaderEpubLibraryClient.self] }
        set { self[ReaderEpubLibraryClient.self] = newValue }
    }
}