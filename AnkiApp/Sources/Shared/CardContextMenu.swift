import SwiftUI
import AnkiClients
import Dependencies

/// Context menu for card operations (suspend, bury, flag, undo)
@MainActor
struct CardContextMenu: View {
    let cardId: Int64
    let noteId: Int64? = nil
    var onSuccess: (() -> Void)?
    var onActionSuccess: ((_ shouldAdvance: Bool) -> Void)?
    var onRequestSetDueDate: ((_ cardId: Int64) -> Void)?
    
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.tagClient) var tagClient
    
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirmation = false
    @State private var isMarkedNote = false

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

            if noteId != nil {
                Button(action: performSuspendNote) {
                    Label(L("card_action_suspend_note"), systemImage: "pause.circle.fill")
                }

                Button(action: performBuryNote) {
                    Label(L("card_action_bury_note"), systemImage: "books.vertical.fill")
                }
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
                Button(action: performToggleMarkedNote) {
                    Label(
                        isMarkedNote ? L("card_action_unmark_note") : L("card_action_mark_note"),
                        systemImage: isMarkedNote ? "star.slash" : "star"
                    )
                }
            }

            if noteId != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(L("card_action_delete_note"), systemImage: "trash")
                }
            }
            
            Menu {
                // Listed in reverse so iOS bottom-anchored menus display 1→7 top–to–bottom
                flagButton(0, colorName: L("flag_none"))
                flagButton(7, colorName: L("flag_purple"))
                flagButton(6, colorName: L("flag_cyan"))
                flagButton(5, colorName: L("flag_pink"))
                flagButton(4, colorName: L("flag_blue"))
                flagButton(3, colorName: L("flag_green"))
                flagButton(2, colorName: L("flag_orange"))
                flagButton(1, colorName: L("flag_red"))
            } label: {
                Label(L("card_action_flag"), systemImage: "flag.fill")
            }
            
            Button(action: performUndo) {
                Label(L("card_action_undo"), systemImage: "arrow.uturn.backward")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.headline)
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
        .task(id: noteId) {
            await loadMarkedState()
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
            onSuccess?()
            onActionSuccess?(false)
        } catch {
            errorMessage = L("card_action_error_flag", error.localizedDescription)
            showError = true
        }
    }
    
    private func performUndo() {
        do {
            try cardClient.undo()
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = L("card_action_error_undo", error.localizedDescription)
            showError = true
        }
    }

    private func flagButton(_ value: UInt32, colorName: String) -> some View {
        let tint = flagColor(for: value)
        return Button(action: { performFlag(value) }) {
            HStack(spacing: 8) {
                Image(systemName: value == 0 ? "flag.slash.fill" : "flag.fill")
                    .foregroundStyle(tint)
                Text(colorName)
                    .foregroundStyle(tint)
            }
        }
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

    private func flagColor(for value: UInt32) -> Color {
        switch value {
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
            .font(.headline)
        
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
