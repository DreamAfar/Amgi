import SwiftUI
import AnkiSync
import AmgiTheme

struct OnboardingView: View {
    @Binding var isCompleted: Bool
    @Environment(\.palette) private var palette
    @State private var showServerSetup = false
    @State private var serverURL = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 64))
                .foregroundStyle(palette.accent)

            Text(L("onboarding_welcome"))
                .amgiFont(.displayHero)
                .foregroundStyle(palette.textPrimary)

            Text(L("onboarding_subtitle"))
                .amgiFont(.body)
                .foregroundStyle(palette.textSecondary)

            VStack(spacing: 12) {
                if showServerSetup {
                    VStack(spacing: 12) {
                        TextField(L("onboarding_server_url_placeholder"), text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .padding(.horizontal)

                        Button(L("onboarding_btn_continue")) {
                            saveAndContinue()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(L("onboarding_btn_back")) {
                            showServerSetup = false
                        }
                        .foregroundStyle(palette.textSecondary)
                    }
                } else {
                    Button {
                        showServerSetup = true
                    } label: {
                        Label(L("onboarding_btn_custom_server"), systemImage: "server.rack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .controlSize(.large)

                    Button {
                        UserDefaults.standard.set(
                            SyncPreferences.Mode.local.rawValue,
                            forKey: SyncPreferences.Keys.modeForCurrentUser()
                        )
                        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                        isCompleted = true
                    } label: {
                        Label(L("onboarding_btn_use_local"), systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)

            Text(L("onboarding_footer"))
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)

            Spacer()
        }
        .background(palette.background)
    }

    private func saveAndContinue() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        try? KeychainHelper.saveEndpoint(url)
        UserDefaults.standard.set(
            SyncPreferences.Mode.custom.rawValue,
            forKey: SyncPreferences.Keys.modeForCurrentUser()
        )
        AppSyncAuthEvents.clearCredentials()
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isCompleted = true
    }
}
