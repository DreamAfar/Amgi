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
                        method: AnkiBackend.TagsMethod.tagTree,
                        request: Anki_Generic_Empty()
                    )
                    
                    // Flatten the tree to get all tag names with full paths
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
                } catch {
                    logger.error("getAllTags failed: \(error)")
                    throw error
                }
            },
            addTag: { tag in
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw BackendError(kind: .invalidInput, message: "Tag name cannot be empty")
                }

                // Use SetTagCollapsed(collapsed: false) to create/register the tag in
                // Anki's tag tree without attaching it to any note.
                var req = Anki_Tags_SetTagCollapsedRequest()
                req.name = normalized
                req.collapsed = false

                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: AnkiBackend.TagsMethod.setTagCollapsed,
                        request: req
                    )
                    logger.info("Tag '\(normalized)' created via SetTagCollapsed")
                } catch {
                    logger.error("addTag failed for '\(normalized)': \(error)")
                    throw error
                }
            },
            addTagToNotes: { tag, noteIDs in
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw BackendError(kind: .invalidInput, message: "Tag name cannot be empty")
                }
                guard !noteIDs.isEmpty else {
                    throw BackendError(kind: .invalidInput, message: "No notes selected")
                }

                var req = Anki_Tags_NoteIdsAndTagsRequest()
                req.noteIds = noteIDs
                req.tags = normalized

                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: AnkiBackend.TagsMethod.addNoteTags,
                        request: req
                    )
                    logger.info("Applied tag '\(normalized)' to \(noteIDs.count) notes")
                } catch {
                    logger.error("addTagToNotes failed for tag='\(normalized)': \(error)")
                    throw error
                }
            },
            removeTagFromNotes: { tag, noteIDs in
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    throw BackendError(kind: .invalidInput, message: "Tag name cannot be empty")
                }
                guard !noteIDs.isEmpty else {
                    throw BackendError(kind: .invalidInput, message: "No notes selected")
                }

                var req = Anki_Tags_NoteIdsAndTagsRequest()
                req.noteIds = noteIDs
                req.tags = normalized

                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: AnkiBackend.TagsMethod.removeNoteTags,
                        request: req
                    )
                    logger.info("Removed tag '\(normalized)' from \(noteIDs.count) notes")
                } catch {
                    logger.error("removeTagFromNotes failed for tag='\(normalized)': \(error)")
                    throw error
                }
            },
            removeTag: { tag in
                // Remove tag from all notes using RemoveTags
                do {
                    var req = Anki_Generic_String()
                    req.val = tag
                    
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: AnkiBackend.TagsMethod.removeTags,
                        request: req
                    )
                    logger.info("Tag '\(tag)' removed")
                } catch {
                    logger.error("removeTag failed for '\(tag)': \(error)")
                    throw error
                }
            },
            renameTag: { oldName, newName in
                // Rename tag across all notes using RenameTags
                do {
                    var req = Anki_Tags_RenameTagsRequest()
                    req.currentPrefix = oldName
                    req.newPrefix = newName
                    
                    try backend.callVoid(
                        service: AnkiBackend.Service.tags,
                        method: AnkiBackend.TagsMethod.renameTags,
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
                    var req = Anki_Search_SearchRequest()
                    req.search = "tag:\(tag)"
                    
                    let response: Anki_Search_SearchResponse = try backend.invoke(
                        service: AnkiBackend.Service.search,
                        method: AnkiBackend.SearchMethod.searchNotes,
                        request: req
                    )
                    
                    logger.info("Found \(response.ids.count) notes with tag '\(tag)'")
                    return response.ids
                } catch {
                    logger.error("findNotesByTag failed for '\(tag)': \(error)")
                    throw error
                }
            }
        )
    }()
}
