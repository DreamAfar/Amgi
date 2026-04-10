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
                Label("Suspend", systemImage: "pause.circle")
            }
            
            Button(action: performBury) {
                Label("Bury", systemImage: "books.vertical")
            }
            
            Menu {
                flagButton(1, colorName: "红色")
                flagButton(2, colorName: "橙色")
                flagButton(3, colorName: "绿色")
                flagButton(4, colorName: "蓝色")
                flagButton(5, colorName: "粉色")
                flagButton(6, colorName: "青色")
                flagButton(7, colorName: "紫色")
            } label: {
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
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = "Failed to suspend card: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func performBury() {
        do {
            try cardClient.bury(cardId)
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = "Failed to bury card: \(error.localizedDescription)"
            showError = true
        }
    }

    private func performFlag(_ value: Int32) {
        do {
            try cardClient.flag(cardId, value)
            onSuccess?()
            onActionSuccess?(false)
        } catch {
            errorMessage = "Failed to flag card: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func performUndo() {
        do {
            try cardClient.undo()
            onSuccess?()
            onActionSuccess?(true)
        } catch {
            errorMessage = "Failed to undo: \(error.localizedDescription)"
            showError = true
        }
    }

    private func flagButton(_ value: Int32, colorName: String) -> some View {
        Button(action: { performFlag(value) }) {
            Label("旗标\(value)（\(colorName)）", systemImage: "flag.fill")
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
