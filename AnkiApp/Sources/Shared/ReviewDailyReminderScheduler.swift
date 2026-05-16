import Foundation
import UserNotifications
import AnkiBackend
import AnkiProto

enum ReviewDailyReminderScheduler {
    static let notificationIdentifier = "amgi.review.daily-reminder"
    static let notificationRouteDecks = "decks"
    private static let defaultHour = 20
    private static let defaultMinute = 0

    static func requestAuthorizationIfNeeded() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await notificationSettings(center: center)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        @unknown default:
            return false
        }
    }

    static func refreshIfNeeded(using backend: AnkiBackend?) async {
        guard UserDefaults.standard.bool(forKey: ReviewPreferences.Keys.dailyReminderEnabledForCurrentUser()) else {
            removePendingNotification()
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await notificationSettings(center: center)
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else {
            removePendingNotification()
            return
        }

        guard let backend else { return }

        do {
            let totalCount = try dueCardCount(using: backend)
            let request = makeRequest(totalCount: totalCount)
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            try await center.add(request)
        } catch {
            // Best-effort scheduling.
        }
    }

    static func disable() {
        removePendingNotification()
    }

    private static func dueCardCount(using backend: AnkiBackend) throws -> Int {
        var request = Anki_Decks_DeckTreeRequest()
        request.now = Int64(Date().timeIntervalSince1970)

        let tree: Anki_Decks_DeckTreeNode = try backend.invoke(
            service: AnkiBackend.Service.decks,
            method: AnkiBackend.DecksMethod.getDeckTree,
            request: request
        )

        let rootTotal = Int(tree.newCount) + Int(tree.learnCount) + Int(tree.reviewCount)
        if rootTotal > 0 {
            return rootTotal
        }

        return tree.children.reduce(into: 0) { partialResult, node in
            partialResult += Int(node.newCount) + Int(node.learnCount) + Int(node.reviewCount)
        }
    }

    private static func makeRequest(totalCount: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = L("settings_review_daily_reminder_notification_title")
        content.body = totalCount == 0
            ? L("settings_review_daily_reminder_notification_body_empty")
            : L("settings_review_daily_reminder_notification_body", totalCount)
        content.sound = .default
        content.userInfo = ["route": notificationRouteDecks]

        var dateComponents = DateComponents()
        dateComponents.hour = storedHour
        dateComponents.minute = storedMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        return UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )
    }

    private static var storedHour: Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: ReviewPreferences.Keys.dailyReminderHourForCurrentUser()) == nil {
            return defaultHour
        }
        return defaults.integer(forKey: ReviewPreferences.Keys.dailyReminderHourForCurrentUser())
    }

    private static var storedMinute: Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: ReviewPreferences.Keys.dailyReminderMinuteForCurrentUser()) == nil {
            return defaultMinute
        }
        return defaults.integer(forKey: ReviewPreferences.Keys.dailyReminderMinuteForCurrentUser())
    }

    private static func removePendingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    private static func notificationSettings(
        center: UNUserNotificationCenter
    ) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}

@MainActor
final class ReviewDailyReminderNotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = ReviewDailyReminderNotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == ReviewDailyReminderScheduler.notificationIdentifier else {
            return
        }

        let route = response.notification.request.content.userInfo["route"] as? String
        guard route == ReviewDailyReminderScheduler.notificationRouteDecks else { return }

        await MainActor.run {
            NotificationCenter.default.post(name: AppCollectionEvents.openDeckListNotification, object: nil)
        }
    }
}
