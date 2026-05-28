import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiServices
import Foundation
public import Dependencies
import DependenciesMacros
import Logging

private let logger = Logger(label: "com.ankiapp.tag.client")

extension TagClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.tagService) var tags

        return Self(
            // MARK: Delegated to TagService (read-only)
            getAllTags:     { try tags.getAllTags() },

            // MARK: Write operations (stay in Client)
            clearUnusedTags: {
                do {
                    let response: Anki_Collection_OpChangesWithCount = try backend.invoke(
                        service: AnkiBackend.Service.tags,
                        method: AnkiBackend.TagsMethod.clearUnusedTags,
                        request: Anki_Generic_Empty()
                    )

                    let removedCount = Int(response.count)
                    logger.info("Cleared \(removedCount) unused tags")
                    return removedCount
                } catch {
                    logger.error("clearUnusedTags failed: \(error)")
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
            findNotesByTag: { try tags.findNotesByTag($0) }
        )
    }()
}
