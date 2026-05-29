import SwiftUI
import BackgroundTasks
import AnkiBackend
import AnkiClients
import AmgiReader
import AnkiKit
import AnkiProto
import AnkiSync
import AmgiTheme
import Dependencies
import Foundation
import OSLog
import UIKit
import UserNotifications

@main
struct AnkiAppApp: App {
    @UIApplicationDelegateAdaptor(AppBackgroundSyncAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette
    @State private var onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
    @State private var startupPhase: StartupPhase = .loading
    @State private var pendingImportURL: URL?
    @State private var themeManager = ThemeManager.shared
    @StateObject private var collectionState = AppCollectionState.shared
    @AppStorage("app_language") private var appLanguageRaw: String = AppLanguage.system.rawValue
    private let periodicBackupTimer = Timer.publish(
        every: CollectionBackupManager.periodicCheckInterval,
        on: .main,
        in: .common
    ).autoconnect()

    init() {
        let appDefaults = UserDefaults.amgiAppGroup

        if appDefaults.string(forKey: "theme.appearance") == nil,
           let legacyTheme = UserDefaults.standard.string(forKey: "app_theme"),
           Appearance(rawValue: legacyTheme) != nil {
            appDefaults.set(legacyTheme, forKey: "theme.appearance")
        }

        ThemeManager.shared.appearance = appDefaults.string(forKey: "theme.appearance")
            .flatMap(Appearance.init(rawValue:)) ?? .system
        ThemeManager.shared.theme = appDefaults.string(forKey: "theme.selection")
            .flatMap(Theme.init(rawValue:)) ?? .vivid

        ReaderPreferences.migrateLegacyDefaultsIfNeeded(for: AppUserStore.loadSelectedUser())
    }

    private enum StartupPhase {
        case loading
        case ready
        case failed(String)
    }

    private var currentLocale: Locale {
        (AppLanguage(rawValue: appLanguageRaw) ?? .system).locale
    }

    private var preferredBackendLangs: [String] {
        (AppLanguage(rawValue: appLanguageRaw) ?? .system).preferredBackendLangs
    }

    private var preferredColorScheme: ColorScheme? {
        themeManager.appearance.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch startupPhase {
                case .loading:
                    startupLoadingView
                case .failed(let message):
                    ZStack {
                        palette.background
                            .ignoresSafeArea()

                        VStack(spacing: AmgiSpacing.md) {
                            Label(L("app_unable_to_start"), systemImage: "exclamationmark.triangle.fill")
                                .amgiStatusText(.warning, font: .sectionHeading)
                            Text(message)
                                .amgiFont(.caption)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 360)
                        .padding(.horizontal, AmgiSpacing.lg)
                    }
                case .ready:
                    if onboardingCompleted {
                        ContentView(incomingImportURL: $pendingImportURL)
                    } else {
                        OnboardingView(isCompleted: $onboardingCompleted)
                    }
                }
            }
            .task { await initializeBackend() }
            .environmentObject(collectionState)
            .environment(\.locale, currentLocale)
            .themedRoot(manager: themeManager)
            .tint(palette.textPrimary)
            .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didOpenNotification)) { _ in
                Task {
                    await syncDailyReminderIfNeeded()
                    await runAutomaticBackupIfNeeded()
                }
                AppBackgroundSyncManager.scheduleBackgroundTasks()
            }
            .onReceive(periodicBackupTimer) { _ in
                Task { await runAutomaticBackupIfNeeded() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    Task { await runAutomaticBackupIfNeeded() }
                    Task { await writeWidgetSnapshot() }
                    AppBackgroundSyncManager.scheduleBackgroundTasks()
                case .background:
                    Task { await syncDailyReminderIfNeeded() }
                    AppBackgroundSyncManager.scheduleBackgroundTasks()
                default:
                    break
                }
            }
            .onChange(of: appLanguageRaw) { _, newValue in
                let lang = AppLanguage(rawValue: newValue) ?? .system
                LanguageManager.shared.apply(lang)
            }
            .onOpenURL { url in
                pendingImportURL = url
            }
        }
    }

    @ViewBuilder
    private var startupLoadingView: some View {
        let cachedTree = DeckTreeCache.load()
        let cachedHeatmapReviews = DeckListHeatmapCache.loadCurrent()?.reviews

        if onboardingCompleted, !cachedTree.isEmpty {
            StartupDeckSnapshotView(tree: cachedTree, heatmapReviews: cachedHeatmapReviews)
        } else {
            palette.background
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
                            .foregroundStyle(palette.textPrimary)
                        ProgressView()
                            .tint(palette.accent)
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
            UNUserNotificationCenter.current().delegate = ReviewDailyReminderNotificationDelegate.shared
            let selectedUser = AppUserStore.loadSelectedUser()
            let preferredBackendLangs = self.preferredBackendLangs

            let backend = try await AppBackendRuntime.shared.prepareBackend(
                preferredLangs: preferredBackendLangs
            )

            prepareDependencies {
                $0.ankiBackend = backend
            }

            collectionState.markOpening()

            if onboardingCompleted {
                startupPhase = .ready
                Task.detached(priority: .userInitiated) {
                    do {
                        _ = try await AppBackendRuntime.shared.ensureCollectionOpen(
                            preferredLangs: preferredBackendLangs,
                            username: selectedUser
                        )
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
                _ = try await AppBackendRuntime.shared.ensureCollectionOpen(
                    preferredLangs: preferredBackendLangs,
                    username: selectedUser
                )
                collectionState.markReady()
                startupPhase = .ready
                NotificationCenter.default.post(name: AppCollectionEvents.didOpenNotification, object: nil)
            }
        } catch {
            startupPhase = .failed("Startup failed: \(error.localizedDescription)")
        }
    }

    private func syncDailyReminderIfNeeded() async {
        guard collectionState.isReady else { return }
        @Dependency(\.ankiBackend) var backend
        await ReviewDailyReminderScheduler.refreshIfNeeded(using: backend)
    }

    private func runAutomaticBackupIfNeeded() async {
        guard collectionState.isReady, scenePhase == .active else { return }
        @Dependency(\.ankiBackend) var backend
        await CollectionBackupManager.runAutomaticBackupIfNeeded(
            backend: backend,
            username: AppUserStore.loadSelectedUser()
        )
    }
}

private struct StartupDeckSnapshotView: View {
    @Environment(\.palette) private var palette

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
                                .foregroundStyle(palette.textSecondary)
                            Text(item.node.name)
                                .amgiFont(.body)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if item.node.counts.total > 0 {
                                Text("\(item.node.counts.total)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .padding(.leading, CGFloat(item.depth) * 14)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .disabled(true)
            .overlay(alignment: .top) {
                ProgressView()
                    .tint(palette.accent)
                    .padding(.horizontal, AmgiSpacing.md)
                    .padding(.vertical, AmgiSpacing.sm)
                    .background(
                        Capsule()
                            .fill(palette.surfaceElevated)
                    )
                    .overlay(
                        Capsule()
                            .stroke(palette.border.opacity(0.28), lineWidth: 1)
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
