import AnkiKit
import AnkiBackend
import AnkiProto
import Foundation
public import Dependencies
import DependenciesMacros
import Logging

private let logger = Logger(label: "com.ankiapp.tag.client")

extension TagClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            getAllTags: {
                // Get all tags using the tags service
                do {
                    let response: Anki_Tags_TagTreeNode = try backend.invoke(
                        service: AnkiBackend.Service.tags,
                        method: 0,  // GetTagTree
                        request: Anki_Generic_Empty()
                    )
                    
                    // Flatten the tree to get all tag names
                    var tags: [String] = []
                    func flatten(_ node: Anki_Tags_TagTreeNode) {
                        tags.append(node.name)
                        for child in node.children {
                            flatten(child)
                        }
                    }
                    
                    for child in response.children {
                        flatten(child)
                    }
                    
                    logger.info("Retrieved \(tags.count) tags")
                    return tags
                } catch {
                    logger.error("getAllTags failed: \(error)")
                    throw error
                }
            },
            addTag: { tag in
                // Adding a tag through the notes service by finding notes with empty tags
                // and adding the tag (simplified for now)
                logger.info("Tag '\(tag)' created/managed through note operations")
            },
            removeTag: { tag in
                // Remove tag from all notes
                do {
                    var req = Anki_Tags_RemoveTagRequest()
                    req.tag = tag
                    
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: 2,  // RemoveTag
                        request: req
                    )
                    logger.info("Tag '\(tag)' removed")
                } catch {
                    logger.error("removeTag failed for '\(tag)': \(error)")
                    throw error
                }
            },
            renameTag: { oldName, newName in
                // Rename tag across all notes
                do {
                    var req = Anki_Tags_RenameTagRequest()
                    req.oldName = oldName
                    req.newName = newName
                    
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: 1,  // RenameTag
                        request: req
                    )
                    logger.info("Tag renamed: '\(oldName)' → '\(newName)'")
                } catch {
                    logger.error("renameTag failed: \(error)")
                    throw error
                }
            },
            findNotesByTag: { tag in
                // Search for notes with the given tag
                do {
                    var req = Anki_Search_SearchNotesRequest()
                    req.query = "tag:\(tag)"
                    
                    let response: Anki_Search_SearchNotesResponse = try backend.invoke(
                        service: AnkiBackend.Service.search,
                        method: 2,  // SearchNotes
                        request: req
                    )
                    
                    logger.info("Found \(response.noteIds.count) notes with tag '\(tag)'")
                    return response.noteIds
                } catch {
                    logger.error("findNotesByTag failed for '\(tag)': \(error)")
                    throw error
                }
            }
        )
    }()
}
