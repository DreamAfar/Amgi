import SwiftUI
import AnkiBackend
import AnkiClients
import AnkiReader
import AnkiKit
import AnkiProto
import AnkiSync
import Dependencies
import Foundation
import OSLog
import UIKit

@main
struct AnkiAppApp: App {
    @State private var onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
    @State private var startupPhase: StartupPhase = .loading
    @StateObject private var collectionState = AppCollectionState.shared
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
                    ZStack {
                        Color.amgiBackground
                            .ignoresSafeArea()

                        VStack(spacing: AmgiSpacing.md) {
                            Label(L("app_unable_to_start"), systemImage: "exclamationmark.triangle.fill")
                                .amgiStatusText(.warning, font: .sectionHeading)
                            Text(message)
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 360)
                        .padding(.horizontal, AmgiSpacing.lg)
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
            .environmentObject(collectionState)
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
        let cachedHeatmap = DeckListHeatmapCache.load()

        if onboardingCompleted, (!cachedTree.isEmpty || cachedHeatmap != nil) {
            StartupDeckSnapshotView(tree: cachedTree, heatmapReviews: cachedHeatmap?.reviews)
        } else {
            Color.amgiBackground
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: AmgiSpacing.lg) {
                        if let icon = UIImage(named: "AppIcon") {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        }
                        Text("Amgi")
                            .amgiFont(.displayHero)
                            .foregroundStyle(Color.amgiTextPrimary)
                        ProgressView()
                            .tint(Color.amgiAccent)
                            .padding(.top, AmgiSpacing.xs)
                    }
                    .amgiCard(elevated: true)
                    .padding(.horizontal, AmgiSpacing.xl)
                }
        }
    }

    @MainActor
    private func initializeBackend() async {
        do {
            let selectedUser = AppUserStore.loadSelectedUser()
            let urls = AppUserStore.collectionURLs(for: selectedUser)

            let backend = try await Task.detached(priority: .userInitiated) {
                try AnkiBackend(preferredLangs: ["en"])
            }.value

            prepareDependencies {
                $0.ankiBackend = backend
            }

            collectionState.markOpening()

            if onboardingCompleted {
                startupPhase = .ready
                Task.detached(priority: .userInitiated) {
                    do {
                        try Self.openCollection(using: backend, urls: urls)
                        await MainActor.run {
                            AppCollectionState.shared.markReady()
                            NotificationCenter.default.post(name: AppCollectionEvents.didOpenNotification, object: nil)
                        }
                    } catch {
                        await MainActor.run {
                            AppCollectionState.shared.markFailed(error.localizedDescription)
                            if DeckTreeCache.load().isEmpty && DeckListHeatmapCache.load() == nil {
                                startupPhase = .failed("Startup failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try Self.openCollection(using: backend, urls: urls)
                }.value
                collectionState.markReady()
                startupPhase = .ready
                NotificationCenter.default.post(name: AppCollectionEvents.didOpenNotification, object: nil)
            }
        } catch {
            startupPhase = .failed("Startup failed: \(error.localizedDescription)")
        }
    }

    private nonisolated static func openCollection(
        using backend: AnkiBackend,
        urls: (directory: URL, collection: URL, mediaDirectory: URL, mediaDB: URL)
    ) throws {
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

        ReaderProgressStore.migrateLegacyMediaIfNeeded()
        try? DictionaryLookupConfigMigration.migrateLegacyMirroredConfigIfNeeded(backend: backend)
    }
}

private struct StartupDeckSnapshotView: View {
    let tree: [DeckTreeNode]
    let heatmapReviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes?

    @AppStorage(DeckListHeatmapSettings.showKey) private var showDeckListHeatmap = true
    @AppStorage(DeckListHeatmapSettings.heightKey) private var deckListHeatmapHeight = DeckListHeatmapSettings.defaultHeight

    var body: some View {
        NavigationStack {
            List {
                if showDeckListHeatmap, let heatmapReviews {
                    Section {
                        HomeHeatmapChart(reviews: heatmapReviews, preferredHeight: deckListHeatmapHeight)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                Section {
                    ForEach(flattenedTree) { item in
                        HStack(spacing: AmgiSpacing.md) {
                            Image(systemName: item.node.children.isEmpty ? "rectangle.stack" : "folder")
                                .foregroundStyle(Color.amgiTextSecondary)
                            Text(item.node.name)
                                .amgiFont(.body)
                                .foregroundStyle(Color.amgiTextPrimary)
                                .lineLimit(1)
                            Spacer()
                            if item.node.counts.total > 0 {
                                Text("\(item.node.counts.total)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                        .padding(.leading, CGFloat(item.depth) * 14)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .disabled(true)
            .overlay(alignment: .top) {
                ProgressView()
                    .tint(Color.amgiAccent)
                    .padding(.horizontal, AmgiSpacing.md)
                    .padding(.vertical, AmgiSpacing.sm)
                    .background(
                        Capsule()
                            .fill(Color.amgiSurfaceElevated)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.amgiBorder.opacity(0.28), lineWidth: 1)
                    )
                    .padding(.top, AmgiSpacing.sm)
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
