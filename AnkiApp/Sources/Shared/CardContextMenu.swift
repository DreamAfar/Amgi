import SwiftUI
import AnkiClients
import Dependencies

/// Context menu for card operations (suspend, bury, flag, undo)
@MainActor
struct CardContextMenu: View {
    let cardId: Int64
    var onSuccess: (() -> Void)?
    
    @Dependency(\.cardClient) var cardClient
    @Environment(\.dismiss) var dismiss
    
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        Menu {
            Button(action: performSuspend) {
                Label("Suspend", systemImage: "pause.circle")
            }
            
            Button(action: performBury) {
                Label("Bury", systemImage: "books.vertical")
            }
            
            Button(action: performFlag) {
                Label("Flag", systemImage: "flag.fill")
            }
            
            Button(action: performUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.headline)
        }
        .alert("Card Action Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
    }
    
    private func performSuspend() {
        do {
            try cardClient.suspend(cardId)
            dismiss()
            onSuccess?()
        } catch {
            errorMessage = "Failed to suspend card: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func performBury() {
        do {
            try cardClient.bury(cardId)
            dismiss()
            onSuccess?()
        } catch {
            errorMessage = "Failed to bury card: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func performFlag() {
        do {
            try cardClient.flag(cardId, 1)  // Flag 1 (default red flag)
            dismiss()
            onSuccess?()
        } catch {
            errorMessage = "Failed to flag card: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func performUndo() {
        do {
            try cardClient.undo()
            dismiss()
            onSuccess?()
        } catch {
            errorMessage = "Failed to undo: \(error.localizedDescription)"
            showError = true
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
