import SwiftUI
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies
import UIKit

/// Context menu for card operations (suspend, bury, flag, undo)
@MainActor
struct CardContextMenu: View {
    let cardId: Int64
    let noteId: Int64?
    var onSuccess: (() -> Void)?
    var onActionSuccess: ((_ shouldAdvance: Bool) -> Void)?
    var onRequestSetDueDate: ((_ cardId: Int64) -> Void)?
    
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.ankiBackend) var backend
    
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirmation = false
    @State private var isMarkedNote = false
    @State private var currentFlag: UInt32 = 0
    @State private var canUndo = false
    @State private var isUndoing = false

    init(
        cardId: Int64,
        noteId: Int64? = nil,
        onSuccess: (() -> Void)? = nil,
        onActionSuccess: ((_ shouldAdvance: Bool) -> Void)? = nil,
        onRequestSetDueDate: ((_ cardId: Int64) -> Void)? = nil
    ) {
        self.cardId = cardId
        self.noteId = noteId
        self.onSuccess = onSuccess
        self.onActionSuccess = onActionSuccess
        self.onRequestSetDueDate = onRequestSetDueDate
    }
    
    var body: some View {
        Menu {
            Button(action: performSuspend) {
                Label(L("card_action_suspend"), systemImage: "pause.circle")
            }
            
            Button(action: performBury) {
                Label(L("card_action_bury"), systemImage: "books.vertical")
            }

            Button(action: performResetToNew) {
                Label(L("card_action_reset_to_new"), systemImage: "arrow.counterclockwise")
            }

            if let onRequestSetDueDate {
                Button {
                    onRequestSetDueDate(cardId)
                } label: {
                    Label(L("card_action_set_due_date"), systemImage: "calendar.badge.clock")
                }
            }

            if noteId != nil {
                Menu {
                    Button(action: performToggleMarkedNote) {
                        Label(
                            isMarkedNote ? L("card_action_unmark_note") : L("card_action_mark_note"),
                            systemImage: isMarkedNote ? "star.slash" : "star"
                        )
                    }

                    Button(action: performSuspendNote) {
                        Label(L("card_action_suspend_note"), systemImage: "pause.circle.fill")
                    }

                    Button(action: performBuryNote) {
                        Label(L("card_action_bury_note"), systemImage: "books.vertical.fill")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(L("card_action_delete_note"), systemImage: "trash")
                    }
                } label: {
                    Label(L("card_action_note_menu"), systemImage: "note.text")
                }
            }
            
            Menu {
                // Listed in reverse so iOS bottom-anchored menus display 1→7 top–to–bottom
                flagButton(0)
                flagButton(7)
                flagButton(6)
                flagButton(5)
                flagButton(4)
                flagButton(3)
                flagButton(2)
                flagButton(1)
            } label: {
                Label {
                    Text(L("card_action_flag"))
                } icon: {
                    Image(systemName: currentFlag == 0 ? "flag.slash.fill" : "flag.fill")
                        .foregroundStyle(flagColor(for: currentFlag))
                }
            }
            
            Button {
                Task { await performUndo() }
            } label: {
                Label(L("card_action_undo"), systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo || isUndoing)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(AmgiFont.bodyEmphasis.font)
        }
        .alert(L("card_action_error_title"), isPresented: $showError) {
            Button(L("common_ok")) { }
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
        .confirmationDialog(L("browse_delete_title"), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(L("common_delete"), role: .destructive, action: performDeleteNote)
            Button(L("common_cancel"), role: .cancel) { }
        } message: {
            Text(L("browse_delete_confirm"))
        }
        .task(id: cardId) {
            await loadMarkedState()
            await loadCurrentFlag()
            await refreshUndoAvailability()
        }
    }
    
    private func performSuspend() {
        do {
            try cardClient.suspend(cardId)
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L("card_action_error_suspend", error.localizedDescription)
            showError = true
        }
    }
    
    private func performBury() {
        do {
            try cardClient.bury(cardId)
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L("card_action_error_bury", error.localizedDescription)
            showError = true
        }
    }

    private func performSuspendNote() {
        performNoteAction(
            action: { cardId in try cardClient.suspend(cardId) },
            errorKey: "card_action_error_suspend_note"
        )
    }

    private func performBuryNote() {
        performNoteAction(
            action: { cardId in try cardClient.bury(cardId) },
            errorKey: "card_action_error_bury_note"
        )
    }

    private func performResetToNew() {
        do {
            try cardClient.resetToNew(cardId)
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L("card_action_error_reset_to_new", error.localizedDescription)
            showError = true
        }
    }

    private func performDeleteNote() {
        guard let noteId else { return }
        do {
            try noteClient.delete(noteId)
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L("card_action_error_delete_note", error.localizedDescription)
            showError = true
        }
    }

    private func performToggleMarkedNote() {
        guard let noteId else { return }
        do {
            if isMarkedNote {
                try tagClient.removeTagFromNotes(markedTag, [noteId])
            } else {
                try tagClient.addTagToNotes(markedTag, [noteId])
            }
            isMarkedNote.toggle()
            onSuccess?()
            onActionSuccess?(false)
        } catch {
            errorMessage = L("card_action_error_mark_note", error.localizedDescription)
            showError = true
        }
    }

    private func performNoteAction(
        action: (Int64) throws -> Void,
        errorKey: String
    ) {
        guard let noteId else { return }
        do {
            let cards = try cardClient.fetchByNote(noteId)
            for card in cards {
                try action(card.id)
            }
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L(errorKey, error.localizedDescription)
            showError = true
        }
    }

    private func performFlag(_ value: UInt32) {
        do {
            try cardClient.flag(cardId, value)
            currentFlag = value
            onSuccess?()
            onActionSuccess?(false)
        } catch {
            errorMessage = L("card_action_error_flag", error.localizedDescription)
            showError = true
        }
    }
    
    private func performUndo() async {
        guard !isUndoing, canUndo else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            try cardClient.undo()
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L("card_action_error_undo", error.localizedDescription)
            showError = true
            await refreshUndoAvailability()
        }
    }

    private func refreshUndoAvailability() async {
        do {
            let status: Anki_Collection_UndoStatus = try backend.invoke(
                service: AnkiBackend.Service.collection,
                method: AnkiBackend.CollectionMethod.getUndoStatus,
                request: Anki_Generic_Empty()
            )
            canUndo = !status.undo.isEmpty
        } catch {
            canUndo = false
        }
    }

    private func flagButton(_ value: UInt32) -> some View {
        let tint = flagColor(for: value)
        return Button(action: { performFlag(value) }) {
            Label {
                Text(flagDisplayName(for: value))
                    .foregroundStyle(tint)
            } icon: {
                flagMenuIcon(for: value)
            }
        }
    }

    private func flagDisplayName(for value: UInt32) -> String {
        switch value & 0b111 {
        case 1: return L("review_flag_red")
        case 2: return L("review_flag_orange")
        case 3: return L("review_flag_green")
        case 4: return L("review_flag_blue")
        case 5: return L("review_flag_pink")
        case 6: return L("review_flag_cyan")
        case 7: return L("review_flag_purple")
        default: return L("review_flag_none")
        }
    }

    private func flagMenuIcon(for value: UInt32) -> Image {
        let symbolName = value == 0 ? "flag.slash.fill" : "flag.fill"
        let tint = UIColor(flagColor(for: value))
        if let image = UIImage(systemName: symbolName)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
            return Image(uiImage: image)
        }
        return Image(systemName: symbolName)
    }

    private func loadMarkedState() async {
        guard let noteId else {
            isMarkedNote = false
            return
        }

        do {
            let note = try noteClient.fetch(noteId)
            isMarkedNote = note.map {
                $0.tags
                    .split(separator: " ")
                    .contains { $0.caseInsensitiveCompare(markedTag) == .orderedSame }
            } ?? false
        } catch {
            isMarkedNote = false
        }
    }

    private func loadCurrentFlag() async {
        do {
            var request = Anki_Cards_CardId()
            request.cid = cardId
            let card: Anki_Cards_Card = try backend.invoke(
                service: AnkiBackend.Service.cards,
                method: AnkiBackend.CardsMethod.getCard,
                request: request
            )
            currentFlag = card.flags & 0b111
        } catch {
            currentFlag = 0
        }
    }

    private func flagColor(for value: UInt32) -> Color {
        switch value & 0b111 {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .pink
        case 6: return .cyan
        case 7: return .purple
        default: return .secondary
        }
    }
}

private let markedTag = "marked"


#Preview {
    VStack(spacing: 20) {
        Text("Tap the menu button below")
            .amgiFont(.bodyEmphasis)
            .foregroundStyle(Color.amgiTextPrimary)
        
        Spacer()
        
        HStack {
            Text("Card Menu:")
            CardContextMenu(
                cardId: 12345,
                onSuccess: { print("Action succeeded") }
            )
        }
        
        Spacer()
    }
    .padding()
}
