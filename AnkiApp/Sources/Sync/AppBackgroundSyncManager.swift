import BackgroundTasks
import AnkiClients
import AnkiKit
import AnkiSync
import Dependencies
import Foundation
import OSLog
import UIKit

private let backgroundSyncLogger = Logger(subsystem: "amgi", category: "background-sync")

struct AppPendingSyncAlert: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fullSyncRequired
        case fullDownloadRequired
        case fullUploadRequired
        case conflict
    }

    var kind: Kind
    var serverMessage: String?

    init(kind: Kind, serverMessage: String? = nil) {
        self.kind = kind
        let trimmed = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serverMessage = trimmed?.isEmpty == false ? trimmed : nil
    }

    init(status: SyncStatus) {
        self.init(kind: .fullSyncRequired)
    }

    init(requirement: SyncFullSyncRequirement) {
        let kind: Kind
        switch requirement.kind {
        case .conflict:
            kind = .conflict
        case .downloadOnly:
            kind = .fullDownloadRequired
        case .uploadOnly:
            kind = .fullUploadRequired
        }
        self.init(kind: kind, serverMessage: requirement.serverMessage)
    }
}

final class AppBackgroundSyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppBackgroundSyncManager.registerBackgroundTasks()
        return true
    }
}

private final class BackgroundTaskCompletionBox: @unchecked Sendable {
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    func setCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

enum AppBackgroundSyncManager {
    static let appRefreshIdentifier = "com.ankiapp.AnkiApp.sync-refresh"
    static let processingIdentifier = "com.ankiapp.AnkiApp.sync-processing"

    private static let pendingAlertDefaultsKey = "amgi.sync.pending-alert"
    private static let refreshLeadTime: TimeInterval = 15 * 60
    private static let processingLeadTime: TimeInterval = 2 * 60

    private enum BackgroundSyncOutcome {
        case noAction
        case completed
        case needsUserAttention(AppPendingSyncAlert)
    }

    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: appRefreshIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleAppRefresh(task)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleProcessing(task)
        }
    }

    static func scheduleBackgroundTasks() {
        guard isBackgroundSyncEnabled() else {
            cancelScheduledTasks()
            return
        }

        scheduleAppRefresh()
        scheduleProcessing()
    }

    static func consumePendingAlert() -> AppPendingSyncAlert? {
        defer {
            UserDefaults.standard.removeObject(forKey: pendingAlertDefaultsKey)
        }

        guard let data = UserDefaults.standard.data(forKey: pendingAlertDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppPendingSyncAlert.self, from: data)
    }

    static func automaticForegroundAlert(for status: SyncStatus) -> AppPendingSyncAlert? {
        guard status.requiresFullSync else {
            return nil
        }
        return AppPendingSyncAlert(status: status)
    }

    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let completion = BackgroundTaskCompletionBox(task: task)

        let workTask = Task {
            let success = await performBackgroundStatusCheck()
            completion.setCompleted(success: success)
        }

        task.expirationHandler = {
            workTask.cancel()
        }
    }

    private static func handleProcessing(_ task: BGProcessingTask) {
        scheduleProcessing(after: refreshLeadTime)

        let completion = BackgroundTaskCompletionBox(task: task)

        let workTask = Task {
            let success = await performBackgroundSyncAttempt()
            completion.setCompleted(success: success)
        }

        task.expirationHandler = {
            workTask.cancel()
        }
    }

    private static func performBackgroundStatusCheck() async -> Bool {
        guard isBackgroundSyncEnabled() else {
            return true
        }

        guard KeychainHelper.loadHostKey() != nil else {
            clearPendingAlert()
            return true
        }

        do {
            let status = try await withBackgroundSyncClient { syncClient in
                try await syncClient.syncStatus()
            }

            if status.requiresFullSync {
                storePendingAlert(AppPendingSyncAlert(status: status))
                return true
            }

            scheduleProcessing(after: processingLeadTime)
            return true
        } catch is CancellationError {
            return false
        } catch {
            backgroundSyncLogger.error("Background sync status check failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func performBackgroundSyncAttempt() async -> Bool {
        guard isBackgroundSyncEnabled() else {
            return true
        }

        guard KeychainHelper.loadHostKey() != nil else {
            clearPendingAlert()
            return true
        }

        do {
            let outcome = try await withBackgroundSyncClient { syncClient in
                try await performSafeSync(using: syncClient)
            }

            switch outcome {
            case .noAction, .completed:
                clearPendingAlert()
                return true
            case .needsUserAttention(let alert):
                storePendingAlert(alert)
                return true
            }
        } catch is CancellationError {
            return false
        } catch {
            backgroundSyncLogger.error("Background sync attempt failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func performSafeSync(using syncClient: SyncClient) async throws -> BackgroundSyncOutcome {
        for try await event in syncClient.syncWithProgress() {
            switch event {
            case .fullSyncRequired(let requirement):
                return .needsUserAttention(AppPendingSyncAlert(requirement: requirement))
            case .completed:
                return .completed
            default:
                continue
            }
        }

        return .noAction
    }

    private static func withBackgroundSyncClient<T>(
        operation: @escaping @Sendable (SyncClient) async throws -> T
    ) async throws -> T {
        let username = AppUserStore.loadSelectedUser()
        let preferredLangs = AppCollectionBootstrap.preferredBackendLangsFromDefaults()
        let backend = try await AppBackendRuntime.shared.ensureCollectionOpen(
            preferredLangs: preferredLangs,
            username: username
        )

        return try await withDependencies {
            $0.ankiBackend = backend
        } operation: {
            @Dependency(\.syncClient) var syncClient
            return try await operation(syncClient)
        }
    }

    private static func scheduleAppRefresh(after interval: TimeInterval = refreshLeadTime) {
        guard isBackgroundSyncEnabled(), KeychainHelper.loadHostKey() != nil else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            backgroundSyncLogger.error("Failed to schedule app refresh: \(error.localizedDescription)")
        }
    }

    private static func scheduleProcessing(after interval: TimeInterval = processingLeadTime) {
        guard isBackgroundSyncEnabled(), KeychainHelper.loadHostKey() != nil else {
            return
        }

        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            backgroundSyncLogger.error("Failed to schedule processing task: \(error.localizedDescription)")
        }
    }

    private static func storePendingAlert(_ alert: AppPendingSyncAlert) {
        if let data = try? JSONEncoder().encode(alert) {
            UserDefaults.standard.set(data, forKey: pendingAlertDefaultsKey)
        }
    }

    private static func isBackgroundSyncEnabled() -> Bool {
        let key = SyncPreferences.Keys.backgroundSyncEnabledForCurrentUser()
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func cancelScheduledTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: appRefreshIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
    }

    private static func clearPendingAlert() {
        UserDefaults.standard.removeObject(forKey: pendingAlertDefaultsKey)
    }
}