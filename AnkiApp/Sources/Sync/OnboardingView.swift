import SwiftUI
import AnkiSync

struct OnboardingView: View {
    @Binding var isCompleted: Bool
    @State private var showServerSetup = false
    @State private var serverURL = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome")
                .font(.largeTitle.weight(.bold))

            Text("Choose how to sync your collection")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if showServerSetup {
                    VStack(spacing: 12) {
                        TextField("Server URL", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .padding(.horizontal)

                        Button("Continue") {
                            saveAndContinue()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Back") {
                            showServerSetup = false
                        }
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        showServerSetup = true
                    } label: {
                        Label("Custom Server", systemImage: "server.rack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        UserDefaults.standard.set("local", forKey: "syncMode")
                        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                        isCompleted = true
                    } label: {
                        Label("Use Locally", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)

            Text("You can change this anytime in sync settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func saveAndContinue() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        try? KeychainHelper.saveEndpoint(url)
        UserDefaults.standard.set("custom", forKey: "syncMode")
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isCompleted = true
    }
}
