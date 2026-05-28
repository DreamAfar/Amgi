import AnkiBackend
import AnkiProto
public import Dependencies
import DependenciesMacros
import Foundation
import Logging

private let logger = Logger(label: "com.ankiapp.tags.service")

// MARK: - Service (read-only queries)

@DependencyClient
public struct TagService: Sendable {
    /// List all tags with full hierarchical paths (e.g. "parent::child").
    public var getAllTags: @Sendable () throws -> [String]

    /// Find note IDs that have the given tag.
    public var findNotesByTag: @Sendable (_ tag: String) throws -> [Int64]
}

// MARK: - Live Implementation

extension TagService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        return Self(
            getAllTags: {
                let response: Anki_Tags_TagTreeNode = try backend.invoke(
                    service: AnkiBackend.Service.tags,
                    method: AnkiBackend.TagsMethod.tagTree,
                    request: Anki_Generic_Empty()
                )

                var tags: [String] = []
                func flatten(_ node: Anki_Tags_TagTreeNode, parentPath: String) {
                    let fullPath = parentPath.isEmpty ? node.name : "\(parentPath)::\(node.name)"
                    tags.append(fullPath)
                    for child in node.children {
                        flatten(child, parentPath: fullPath)
                    }
                }
                for child in response.children {
                    flatten(child, parentPath: "")
                }

                logger.info("Retrieved \(tags.count) tags")
                return tags
            },

            findNotesByTag: { tag in
                var req = Anki_Search_SearchRequest()
                req.search = "tag:\(tag)"

                let response: Anki_Search_SearchResponse = try backend.invoke(
                    service: AnkiBackend.Service.search,
                    method: AnkiBackend.SearchMethod.searchNotes,
                    request: req
                )

                logger.info("Found \(response.ids.count) notes with tag '\(tag)'")
                return response.ids
            }
        )
    }()
}

// MARK: - Dependency Registration

extension TagService: TestDependencyKey {
    public static let testValue = TagService()
}

extension DependencyValues {
    public var tagService: TagService {
        get { self[TagService.self] }
        set { self[TagService.self] = newValue }
    }
}
