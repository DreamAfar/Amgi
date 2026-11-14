//
//  NoteEditingDestinationView.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 29.04.2026.
//

package import SwiftUI
package import AnkiKit
import Theme
import AnkiClients
import Dependencies

package struct NoteEditingDestinationView: View {
    let note: NoteRecord
    let embedInNavigationStack: Bool
    let onSave: () -> Void
    @State private var router = NoteEditorRouter()

    package init(note: NoteRecord, embedInNavigationStack: Bool = false, onSave: @escaping () -> Void) {
        self.note = note
        self.embedInNavigationStack = embedInNavigationStack
        self.onSave = onSave
    }

    package var body: some View {
        Group {
            if embedInNavigationStack {
                NavigationStack {
                    destinationBody
                }
            } else {
                destinationBody
            }
        }
    }

    @ViewBuilder
    private var destinationBody: some View {
        #if canImport(UIKit)
        switch router.editor {
        case .imageOcclusion:
            EditImageOcclusionNoteView(
                noteId: note.id,
                onSave: onSave,
                embedInNavigationStack: false
            )
        case .fields:
            NoteEditorView(note: note, onSave: onSave)
        case nil:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await router.resolve(note) }
        }
        #else
        NoteEditorView(note: note, onSave: onSave)
        #endif
    }
}

/// Decides which editor a note opens in from its notetype, not its text.
/// Matching "image-occlusion:" in the fields sent an ordinary note that
/// merely mentions it to the mask editor. The answer is cached per
/// notetype, so reopening notes doesn't flash a spinner.
@Observable
@MainActor
final class NoteEditorRouter {
    enum Editor { case fields, imageOcclusion }

    private(set) var editor: Editor?

    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient

    private static var cache: [NotetypeID: Editor] = [:]

    func resolve(_ note: NoteRecord) async {
        if let cached = Self.cache[note.mid] {
            editor = cached
            return
        }
        let resolved: Editor
        do {
            let notetype = try await notetypesClient.get(note.mid)
            resolved = notetype.config.originalStockKind == .imageOcclusion ? .imageOcclusion : .fields
            Self.cache[note.mid] = resolved
        } catch {
            // Can't read the notetype: fall back to the old content check
            // rather than leave the editor blank.
            resolved = note.isImageOcclusionNote ? .imageOcclusion : .fields
        }
        editor = resolved
    }
}
