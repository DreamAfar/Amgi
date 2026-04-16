import SwiftUI
import AnkiKit
import AnkiClients
import UIKit

struct AppSyncLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

enum AppSyncState {
    case idle
    case syncing(String)
    case syncingMedia(total: Int, downloaded: Int)
    case success(SyncSummary)
    case error(String)
    case needsFullSync
    case noServer
}

@MainActor
final class AppSyncCoordinator: ObservableObject {
    static let shared = AppSyncCoordinator()

    @Published private(set) var state: AppSyncState = .idle
    @Published private(set) var logEntries: [AppSyncLogEntry] = []
    @Published private(set) var mediaProgress: (total: Int, downloaded: Int) = (0, 0)
    @Published private(set) var requiresLogin = false

    private var activeTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.beginBackgroundExecutionIfNeeded()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endBackgroundExecutionIfNeeded()
            }
        }
    }

    var isRunning: Bool {
        switch state {
        case .syncing, .syncingMedia:
            return activeTask != nil
        default:
            return false
        }
    }

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        endBackgroundExecutionIfNeeded()
        state = .idle
        logEntries.removeAll()
        mediaProgress = (0, 0)
        requiresLogin = false
    }

    func setState(_ newState: AppSyncState, clearProgress: Bool = false) {
        state = newState
        if clearProgress {
            logEntries.removeAll()
            mediaProgress = (0, 0)
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        endBackgroundExecutionIfNeeded()
        state = .idle
    }

    func startSync(syncClient: SyncClient, syncMediaEnabled: Bool) {
        guard activeTask == nil else { return }

        logEntries.removeAll()
        mediaProgress = (0, 0)
        requiresLogin = false
        state = .syncing(L("sync_preparing"))

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                for try await event in syncClient.syncWithProgress() {
                    try Task.checkCancellation()
                    await MainActor.run {
                        self.apply(event, syncMediaEnabled: syncMediaEnabled)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.state = .idle
                }
            } catch let err as SyncError where err == .authFailed {
                await MainActor.run {
                    self.state = .idle
                    self.requiresLogin = true
                }
            } catch let err as SyncError where err == .fullSyncRequired {
                await MainActor.run {
                    self.state = .needsFullSync
                }
            } catch {
                await MainActor.run {
                    if syncMediaEnabled {
                        SyncPreferences.recordMediaSyncLog(
                            L("sync_settings_media_log_failed", error.localizedDescription)
                        )
                    }
                    self.state = .error(error.localizedDescription)
                }
            }

            await MainActor.run {
                self.activeTask = nil
                self.endBackgroundExecutionIfNeeded()
            }
        }
    }

    func startFullSync(_ direction: SyncDirection, syncClient: SyncClient) {
        guard activeTask == nil else { return }

        logEntries.removeAll()
        mediaProgress = (0, 0)
        requiresLogin = false
        let message = direction == .download ? L("sync_full_downloading") : L("sync_full_uploading")
        appendLog(message)
        state = .syncing(message)

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await syncClient.fullSync(direction)
                await MainActor.run {
                    self.appendLog(L("sync_log_complete"))
                    self.state = .success(SyncSummary())
                    self.activeTask = nil
                    self.endBackgroundExecutionIfNeeded()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.state = .idle
                    self.activeTask = nil
                    self.endBackgroundExecutionIfNeeded()
                }
            } catch let err as SyncError where err == .authFailed {
                await MainActor.run {
                    self.state = .idle
                    self.requiresLogin = true
                    self.activeTask = nil
                    self.endBackgroundExecutionIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                    self.activeTask = nil
                    self.endBackgroundExecutionIfNeeded()
                }
            }
        }
    }

    func consumeLoginRequest() {
        requiresLogin = false
    }

    private func appendLog(_ message: String) {
        logEntries.append(AppSyncLogEntry(date: .now, message: message))
    }

    private func beginBackgroundExecutionIfNeeded() {
        guard activeTask != nil, backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.ankiapp.sync") { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
    }

    private func endBackgroundExecutionIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func apply(_ event: SyncProgressEvent, syncMediaEnabled: Bool) {
        switch event {
        case .mediaProgress(let total, let downloaded):
            mediaProgress = (total, downloaded)
            state = .syncingMedia(total: total, downloaded: downloaded)
            appendLog(Self.logMessage(for: event))
        case .completed(let summary):
            if syncMediaEnabled {
                SyncPreferences.recordMediaSyncLog(L("sync_settings_media_log_success"))
            }
            appendLog(Self.logMessage(for: event))
            state = .success(summary)
        default:
            let message = Self.logMessage(for: event)
            appendLog(message)
            state = .syncing(message)
        }
    }

    private static func logMessage(for event: SyncProgressEvent) -> String {
        switch event {
        case .connecting:
            return L("sync_log_connecting")
        case .normalSync:
            return L("sync_log_syncing_changes")
        case .fullDownloading:
            return L("sync_full_downloading")
        case .fullUploading:
            return L("sync_full_uploading")
        case .checkingDatabase:
            return L("sync_log_checking_db")
        case .syncingMedia:
            return L("sync_syncing_media")
        case .mediaProgress(let total, let downloaded):
            return L("sync_media_progress", downloaded, total)
        case .mediaRetry(let failed, let attempt, let delay):
            return L("sync_media_retry", failed, attempt, delay)
        case .noteStats(let added, let removed):
            if added > 0 && removed > 0 {
                return L("sync_log_notes_stats_both", added, removed)
            } else if added > 0 {
                return L("sync_log_notes_added", added)
            } else if removed > 0 {
                return L("sync_log_notes_removed", removed)
            } else {
                return L("sync_log_no_note_changes")
            }
        case .mediaStats(let checked, let added, let removed):
            return L("sync_log_media_stats", checked, added, removed)
        case .completed:
            return L("sync_log_complete")
        }
    }
}