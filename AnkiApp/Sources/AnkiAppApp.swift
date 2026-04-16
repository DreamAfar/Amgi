import SwiftUI
import AnkiBackend
import AnkiKit
import AnkiSync
import Dependencies
import Foundation
import OSLog
import UIKit

@main
struct AnkiAppApp: App {
    @State private var onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
    @State private var startupPhase: StartupPhase = .loading
    @AppStorage("app_language") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("app_theme") private var appThemeRaw: String = AppTheme.system.rawValue

    private enum StartupPhase {
        case loading
        case ready
        case failed(String)
    }

    private var currentLocale: Locale {
        (AppLanguage(rawValue: appLanguageRaw) ?? .system).locale
    }

    private var preferredColorScheme: ColorScheme? {
        (AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch startupPhase {
                case .loading:
                    startupLoadingView
                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text(L("app_unable_to_start"))
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                case .ready:
                    if onboardingCompleted {
                        ContentView()
                    } else {
                        OnboardingView(isCompleted: $onboardingCompleted)
                    }
                }
            }
            .task { await initializeBackend() }
            .environment(\.locale, currentLocale)
            .preferredColorScheme(preferredColorScheme)
            .onChange(of: appLanguageRaw) { _, newValue in
                let lang = AppLanguage(rawValue: newValue) ?? .system
                LanguageManager.shared.apply(lang)
            }
        }
    }

    @ViewBuilder
    private var startupLoadingView: some View {
        let cachedTree = DeckTreeCache.load()

        if onboardingCompleted, !cachedTree.isEmpty {
            StartupDeckSnapshotView(tree: cachedTree)
        } else {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 20) {
                        if let icon = UIImage(named: "AppIcon") {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        }
                        Text("Amgi")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        ProgressView()
                            .padding(.top, 4)
                    }
                }
        }
    }

    @MainActor
    private func initializeBackend() async {
        do {
            // Run all I/O off the main thread to eliminate cold-start black screen
            try await Task.detached(priority: .userInitiated) {
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

                    $0.ankiBackend = backend
                }
            }.value
            startupPhase = .ready
        } catch {
            startupPhase = .failed("Startup failed: \(error.localizedDescription)")
        }
    }
}

private struct StartupDeckSnapshotView: View {
    let tree: [DeckTreeNode]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(flattenedTree) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.node.children.isEmpty ? "rectangle.stack" : "folder")
                                .foregroundStyle(.secondary)
                            Text(item.node.name)
                                .lineLimit(1)
                            Spacer()
                            if item.node.counts.total > 0 {
                                Text("\(item.node.counts.total)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, CGFloat(item.depth) * 14)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .disabled(true)
            .overlay(alignment: .top) {
                ProgressView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
            .navigationTitle(L("deck_list_nav_title"))
        }
    }

    private var flattenedTree: [StartupDeckSnapshotItem] {
        flatten(nodes: tree, depth: 0)
    }

    private func flatten(nodes: [DeckTreeNode], depth: Int) -> [StartupDeckSnapshotItem] {
        nodes.flatMap { node in
            [StartupDeckSnapshotItem(node: node, depth: depth)] + flatten(nodes: node.children, depth: depth + 1)
        }
    }
}

private struct StartupDeckSnapshotItem: Identifiable {
    let node: DeckTreeNode
    let depth: Int

    var id: Int64 { node.id }
}
