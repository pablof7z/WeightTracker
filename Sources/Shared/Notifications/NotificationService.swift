import Foundation
import UserNotifications

@MainActor
public final class NotificationService: ObservableObject {
    private let repository: ReadingRepository

    public init(repository: ReadingRepository) {
        self.repository = repository
    }

    public func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    public func scheduleEvaluatedTriggers() async {
        cancelAll()
        let defaults = UserDefaults.standard
        let masterEnabled = defaults.object(forKey: AppPrefKey.notifMaster) as? Bool ?? true
        guard masterEnabled, !isPaused() else { return }

        let now = Date()
        let triggers = TriggerEvaluator.evaluateTriggers(
            readings: repository.allReadings(),
            now: now,
            preferences: NotificationPreferences.fromDefaults()
        )
        for trigger in triggers {
            await schedule(trigger)
        }
    }

    private func schedule(_ trigger: ScheduledTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = trigger.title
        content.body = trigger.body
        content.sound = .default

        let unTrigger: UNNotificationTrigger
        if trigger.fireAfter <= 0 {
            unTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            unTrigger = UNTimeIntervalNotificationTrigger(timeInterval: trigger.fireAfter, repeats: false)
        }
        let request = UNNotificationRequest(identifier: trigger.id, content: content, trigger: unTrigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func isPaused() -> Bool {
        let until = UserDefaults.standard.object(forKey: AppPrefKey.notifPausedUntil) as? Date
        if let until, until > Date() { return true }
        return false
    }
}
