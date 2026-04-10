import SwiftUI
import AnkiClients
import Dependencies

/// Context menu for card operations (suspend, bury, flag, undo)
@MainActor
struct CardContextMenu: View {
    let cardId: Int64
    var onSuccess: (() -> Void)?
    var onActionSuccess: ((_ shouldAdvance: Bool) -> Void)?
    
    @Dependency(\.cardClient) var cardClient
    
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        Menu {
            Button(action: performSuspend) {
                Label(L("card_action_suspend"), systemImage: "pause.circle")
            }
            
            Button(action: performBury) {
                Label(L("card_action_bury"), systemImage: "books.vertical")
            }
            
            Menu {
                flagButton(1, colorName: L("flag_red"))
                flagButton(2, colorName: L("flag_orange"))
                flagButton(3, colorName: L("flag_green"))
                flagButton(4, colorName: L("flag_blue"))
                flagButton(5, colorName: L("flag_pink"))
                flagButton(6, colorName: L("flag_cyan"))
                flagButton(7, colorName: L("flag_purple"))
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
        Button(action: { performFlag(value) }) {
            Label(L("card_flag_label", value, colorName), systemImage: "flag.fill")
        }
    }
}


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
