import SwiftUI
import AnkiClients
import AnkiKit
import AnkiProto
import Dependencies

/// View for editing deck configuration (daily new cards, review limits, FSRS settings, etc.)
@MainActor
struct DeckConfigView: View {
    let deckId: Int64
    let onDismiss: () -> Void
    
    @Dependency(\.deckClient) var deckClient
    
    @State private var config: Anki_DeckConfig_DeckConfig?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isSaving = false
    
    // Form state
    @State private var newCardsPerDay: Int32 = 20
    @State private var reviewsPerDay: Int32 = 200
    @State private var learningStepsText: String = "1m 10m"
    @State private var relearningStepsText: String = "10m"
    @State private var fsrsEnabled: Bool = false
    @State private var fsrsWeights: String = "0.40 1.73 8.15 -0.29 -0.67 0.28 1.94 -0.07 -0.17 0.04 0.71"
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section("Daily Limits") {
                            Stepper(
                                "New cards per day: \(newCardsPerDay)",
                                value: $newCardsPerDay,
                                in: 1...1000
                            )
                            
                            Stepper(
                                "Reviews per day: \(reviewsPerDay)",
                                value: $reviewsPerDay,
                                in: 1...10000
                            )
                        }
                        
                        Section("Learning Steps") {
                            TextField("Steps (space-separated)", text: $learningStepsText)
                                .font(.monospaced(.body)())
                                .help("Use 'm' for minutes, 'd' for days (e.g., '1m 10m')")
                        }
                        
                        Section("Relearning Steps") {
                            TextField("Steps (space-separated)", text: $relearningStepsText)
                                .font(.monospaced(.body)())
                        }
                        
                        Section("FSRS") {
                            Toggle("Enable FSRS", isOn: $fsrsEnabled)
                                .help("Free Spaced Repetition Scheduler")
                            
                            if fsrsEnabled {
                                TextField("FSRS Weights", text: $fsrsWeights)
                                    .font(.monospaced(.caption)())
                                    .lineLimit(3)
                                    .help("Space-separated weights for FSRS algorithm")
                            }
                        }
                        
                        Section {
                            Button(action: saveConfig) {
                                if isSaving {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Save Configuration")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .disabled(isSaving)
                        }
                    }
                }
            }
            .navigationTitle("Deck Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .alert("Configuration Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error occurred")
            }
            .task {
                await loadConfig()
            }
        }
    }
    
    private func loadConfig() async {
        do {
            let loadedConfig = try deckClient.getDeckConfig(deckId)
            await MainActor.run {
                config = loadedConfig
                
                // Extract values from config
                if let newConfig = loadedConfig.newPerDay {
                    newCardsPerDay = newConfig
                }
                if let reviewConfig = loadedConfig.reviewsPerDay {
                    reviewsPerDay = reviewConfig
                }
                
                // FSRS settings
                fsrsEnabled = loadedConfig.useFiltered
                
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load deck configuration: \(error.localizedDescription)"
                showError = true
                isLoading = false
            }
        }
    }
    
    private func saveConfig() {
        guard var config else { return }
        
        isSaving = true
        
        // Update config with new values
        config.newPerDay = newCardsPerDay
        config.reviewsPerDay = reviewsPerDay
        config.useFiltered = fsrsEnabled
        
        do {
            try deckClient.updateDeckConfig(config)
            onDismiss()
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showError = true
            isSaving = false
        }
    }
}

#Preview {
    DeckConfigView(
        deckId: 1,
        onDismiss: { print("Dismissed") }
    )
    .preferredColorScheme(.dark)
}
