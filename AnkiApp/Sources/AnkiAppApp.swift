import SwiftUI
import AnkiBackend
import AnkiSync
import Dependencies
import Foundation

@main
struct AnkiAppApp: App {
    @State private var onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
    private let startupErrorMessage: String?
    @AppStorage("app_language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    private var currentLocale: Locale {
        (AppLanguage(rawValue: appLanguageRaw) ?? .system).locale
    }

    init() {
        do {
            try prepareDependencies {
                let backend = try AnkiBackend(preferredLangs: ["en"])

                let selectedUser = AppUserStore.loadSelectedUser()
                let urls = AppUserStore.collectionURLs(for: selectedUser)

                try FileManager.default.createDirectory(
                    at: urls.directory,
                    withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: urls.mediaDirectory,
                    withIntermediateDirectories: true
                )

                try backend.openCollection(
                    collectionPath: urls.collection.path,
                    mediaFolderPath: urls.mediaDirectory.path,
                    mediaDbPath: urls.mediaDB.path
                )

                // Run CheckDatabase to repair any inconsistencies after sync/migration
                _ = try? backend.call(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                )

                $0.ankiBackend = backend
            }
            startupErrorMessage = nil
        } catch {
            startupErrorMessage = "Startup failed: \(error.localizedDescription)"
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let startupErrorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text(L("app_unable_to_start"))
                            .font(.headline)
                        Text(startupErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else if onboardingCompleted {
                    ContentView()
                } else {
                    OnboardingView(isCompleted: $onboardingCompleted)
                }
            }
            .environment(\.locale, currentLocale)
            .onChange(of: appLanguageRaw) { _, newValue in
                let lang = AppLanguage(rawValue: newValue) ?? .system
                LanguageManager.shared.apply(lang)
            }
        }
    }
}
